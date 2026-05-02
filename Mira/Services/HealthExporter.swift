import Foundation
import HealthKit
import MiraBridge

/// Exports Apple Health data to the iCloud bridge for the health agent to consume.
/// Runs on background refresh — writes JSON to bridge/users/{id}/health/
final class HealthExporter {
    static let shared = HealthExporter()

    private let store = HKHealthStore()
    private var authorized = false
    private var lastExportAt: Date?
    private var exportInFlight = false

    private init() {}

    // MARK: - Authorization

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        let readTypes: Set<HKObjectType> = [
            // Basics (already had)
            HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            // Renpho scale
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.bodyMassIndex),
            HKQuantityType(.leanBodyMass),
            // Apple Fitness
            HKQuantityType(.vo2Max),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.appleExerciseTime),
            HKWorkoutType.workoutType(),
            // Oura Ring
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.bodyTemperature),
        ]

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorized = true
            return true
        } catch {
            #if DEBUG
            print("[HealthExporter] authorization failed: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Export

    /// Export recent HealthKit data. API is primary; iCloud JSON remains a fallback.
    func export(config: BridgeConfig, force: Bool = false) async {
        let personId = config.profile?.id ?? "ang"
        if exportInFlight {
            return
        }
        if !force, let lastExportAt, Date().timeIntervalSince(lastExportAt) < 30 * 60 {
            return
        }
        exportInFlight = true
        defer { exportInFlight = false }
        guard let export = await buildExport(personId: personId) else { return }
        if await postToAPI(config: config, export: export, personId: personId) {
            lastExportAt = Date()
            return
        }
        if let bridgeURL = config.bridgeURL {
            writeToBridge(bridgeURL: bridgeURL, personId: personId, export: export)
            lastExportAt = Date()
        }
    }

    /// Export recent HealthKit data to a JSON file at the given bridge URL.
    func exportToBridge(bridgeURL: URL, personId: String) async {
        guard let export = await buildExport(personId: personId) else { return }
        writeToBridge(bridgeURL: bridgeURL, personId: personId, export: export)
    }

    private func buildExport(personId: String) async -> [String: Any]? {
        if !authorized {
            let ok = await requestAuthorization()
            guard ok else { return nil }
        }

        var metrics: [[String: Any]] = []
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        let since = Calendar.current.date(byAdding: .hour, value: -72, to: Date())!
        let workoutSince = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        // Weight (last reading)
        if let weight = await queryLastSample(.bodyMass, since: since) {
            metrics.append([
                "type": "weight",
                "value": weight.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                "unit": "kg",
                "date": ISO8601DateFormatter.shared.string(from: weight.startDate),
            ])
        }

        // Steps (total today)
        let steps = await queryCumulativeStat(.stepCount, since: todayStart)
        if steps > 0 {
            metrics.append([
                "type": "steps",
                "value": steps,
                "unit": "count",
                "date": ISO8601DateFormatter.shared.string(from: todayStart),
            ])
        }

        // Resting heart rate
        if let rhr = await queryLastSample(.restingHeartRate, since: since) {
            metrics.append([
                "type": "heart_rate",
                "value": rhr.quantity.doubleValue(for: HKUnit(from: "count/min")),
                "unit": "bpm",
                "date": ISO8601DateFormatter.shared.string(from: rhr.startDate),
            ])
        }

        // Active energy
        let energy = await queryCumulativeStat(.activeEnergyBurned, since: todayStart)
        if energy > 0 {
            metrics.append([
                "type": "active_energy",
                "value": energy,
                "unit": "kcal",
                "date": ISO8601DateFormatter.shared.string(from: todayStart),
            ])
        }

        // --- Renpho scale ---
        if let bf = await queryLastSample(.bodyFatPercentage, since: since) {
            metrics.append([
                "type": "body_fat",
                "value": bf.quantity.doubleValue(for: .percent()) * 100,
                "unit": "%",
                "date": ISO8601DateFormatter.shared.string(from: bf.startDate),
            ])
        }
        if let bmi = await queryLastSample(.bodyMassIndex, since: since) {
            metrics.append([
                "type": "bmi",
                "value": bmi.quantity.doubleValue(for: .count()),
                "unit": "",
                "date": ISO8601DateFormatter.shared.string(from: bmi.startDate),
            ])
        }
        if let lbm = await queryLastSample(.leanBodyMass, since: since) {
            metrics.append([
                "type": "lean_body_mass",
                "value": lbm.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                "unit": "kg",
                "date": ISO8601DateFormatter.shared.string(from: lbm.startDate),
            ])
        }

        // --- Apple Fitness ---
        if let vo2 = await queryLastSample(.vo2Max, since: since) {
            metrics.append([
                "type": "vo2_max",
                "value": vo2.quantity.doubleValue(for: HKUnit(from: "ml/kg*min")),
                "unit": "mL/kg·min",
                "date": ISO8601DateFormatter.shared.string(from: vo2.startDate),
            ])
        }
        if let spo2 = await queryLastSample(.oxygenSaturation, since: since) {
            metrics.append([
                "type": "blood_oxygen",
                "value": spo2.quantity.doubleValue(for: .percent()) * 100,
                "unit": "%",
                "date": ISO8601DateFormatter.shared.string(from: spo2.startDate),
            ])
        }
        let exerciseMin = await queryCumulativeStat(.appleExerciseTime, since: todayStart)
        if exerciseMin > 0 {
            metrics.append([
                "type": "exercise_minutes",
                "value": exerciseMin,
                "unit": "min",
                "date": ISO8601DateFormatter.shared.string(from: todayStart),
            ])
        }

        // Workouts (Apple Fitness / any workout app)
        let workouts = await queryWorkouts(since: workoutSince)
        for w in workouts {
            metrics.append(w)
        }

        // --- Oura Ring ---
        if let hrv = await queryLastSample(.heartRateVariabilitySDNN, since: since) {
            metrics.append([
                "type": "hrv",
                "value": hrv.quantity.doubleValue(for: .secondUnit(with: .milli)),
                "unit": "ms",
                "date": ISO8601DateFormatter.shared.string(from: hrv.startDate),
            ])
        }
        if let rr = await queryLastSample(.respiratoryRate, since: since) {
            metrics.append([
                "type": "respiratory_rate",
                "value": rr.quantity.doubleValue(for: HKUnit(from: "count/min")),
                "unit": "brpm",
                "date": ISO8601DateFormatter.shared.string(from: rr.startDate),
            ])
        }
        if let temp = await queryLastSample(.bodyTemperature, since: since) {
            metrics.append([
                "type": "body_temperature",
                "value": temp.quantity.doubleValue(for: .degreeCelsius()),
                "unit": "°C",
                "date": ISO8601DateFormatter.shared.string(from: temp.startDate),
            ])
        }

        guard !metrics.isEmpty else { return nil }

        return [
            "export_date": ISO8601DateFormatter.shared.string(from: Date()),
            "person_id": personId,
            "metrics": metrics,
        ]
    }

    private func writeToBridge(bridgeURL: URL, personId: String, export: [String: Any]) {
        // Write to bridge
        let healthDir = bridgeURL.appending(path: "users/\(personId)/health")
        try? FileManager.default.createDirectory(at: healthDir, withIntermediateDirectories: true)
        let fileURL = healthDir.appending(path: "apple_health_export.json")

        do {
            let data = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
            #if DEBUG
            let count = (export["metrics"] as? [[String: Any]])?.count ?? 0
            print("[HealthExporter] wrote \(count) metrics to bridge")
            #endif
        } catch {
            #if DEBUG
            print("[HealthExporter] write failed: \(error)")
            #endif
        }
    }

    private func postToAPI(config: BridgeConfig, export: [String: Any], personId: String) async -> Bool {
        guard JSONSerialization.isValidJSONObject(export),
              let body = try? JSONSerialization.data(withJSONObject: export, options: []) else {
            return false
        }
        config.startServerDiscovery()
        let base = config.serverURL ?? BridgeConfig.defaultServerURL
        let url = base.appending(path: "api/\(personId)/health/export")
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (_, response) = try await MiraPinnedURLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(code)
        } catch {
            return false
        }
    }

    // MARK: - HealthKit Queries

    private func queryLastSample(_ type: HKQuantityTypeIdentifier, since: Date) async -> HKQuantitySample? {
        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate,
                                       limit: 1, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: results?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
    }

    private func queryCumulativeStat(_ type: HKQuantityTypeIdentifier, since: Date) async -> Double {
        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate,
                                           options: .cumulativeSum) { _, stats, _ in
                let unit: HKUnit
                switch type {
                case .stepCount:
                    unit = .count()
                case .appleExerciseTime:
                    unit = .minute()
                default:
                    unit = .kilocalorie()
                }
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func queryWorkouts(since: Date) async -> [[String: Any]] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                       limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                guard let workouts = results as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }
                let mapped: [[String: Any]] = workouts.map { w in
                    let activityName = Self.workoutName(w.workoutActivityType)
                    let duration = w.duration / 60.0 // minutes
                    let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                        .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                        .sumQuantity()?.doubleValue(for: .meter()) ?? 0
                    return [
                        "type": "workout",
                        "value": duration,
                        "unit": "min",
                        "date": ISO8601DateFormatter.shared.string(from: w.startDate),
                        "activity": activityName,
                        "calories": energy,
                        "distance": distance,
                    ] as [String: Any]
                }
                continuation.resume(returning: mapped)
            }
            self.store.execute(query)
        }
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "跑步"
        case .soccer: return "足球"
        case .walking: return "步行"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .hiking: return "徒步"
        case .yoga: return "瑜伽"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "力量训练"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "椭圆机"
        case .rowing: return "划船"
        case .dance: return "舞蹈"
        case .cooldown: return "放松"
        case .coreTraining: return "核心训练"
        case .pilates: return "普拉提"
        default: return "运动"
        }
    }

    private func querySleepHours(since: Date) async -> Double {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                       limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }
                // Sum asleep stages (not inBed)
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                var totalSeconds: TimeInterval = 0
                for sample in samples {
                    if asleepValues.contains(sample.value) {
                        totalSeconds += sample.endDate.timeIntervalSince(sample.startDate)
                    }
                }
                continuation.resume(returning: totalSeconds / 3600.0)
            }
            store.execute(query)
        }
    }
}

// Shared formatter
extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
