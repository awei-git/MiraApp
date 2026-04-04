import Foundation
import HealthKit
import MiraBridge
import Observation

/// Reads health data directly from HealthKit (vitals, trends)
/// and from bridge summary (notes, reports, alerts).
@Observable
final class HealthDataProvider {
    // Latest values (value + date)
    var weight: HealthMetric?
    var sleepHours: HealthMetric?
    var steps: HealthMetric?
    var heartRate: HealthMetric?
    var bodyFat: HealthMetric?
    var hrv: HealthMetric?
    var bloodOxygen: HealthMetric?
    // Oura extras
    var stressHigh: HealthMetric?
    var recoveryHigh: HealthMetric?
    var readinessScore: HealthMetric?
    var activityScore: HealthMetric?
    var activeMinutes: HealthMetric?
    var sleepScore: HealthMetric?

    // Trends (30 days)
    var weightTrend: [(date: Date, value: Double)] = []
    var sleepTrend: [(date: Date, value: Double)] = []
    var hrvTrend: [(date: Date, value: Double)] = []
    var bodyFatTrend: [(date: Date, value: Double)] = []
    var bloodOxygenTrend: [(date: Date, value: Double)] = []
    var heartRateTrend: [(date: Date, value: Double)] = []

    // Notes from bridge
    var notes: [HealthNote] = []

    var isLoading = false
    var debugLog: String = ""

    struct HealthMetric {
        let value: Double
        let date: Date
    }

    private let store = HKHealthStore()

    /// True after user has tapped "connect" at least once, or we have data from HealthKit.
    var isAuthorized: Bool {
        UserDefaults.standard.bool(forKey: "healthkit_authorized")
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.bodyMassIndex),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.vo2Max),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.appleExerciseTime),
            HKWorkoutType.workoutType(),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.bodyTemperature),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            UserDefaults.standard.set(true, forKey: "healthkit_authorized")
            return true
        } catch {
            return false
        }
    }

    func refresh(config: BridgeConfig) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isLoading = true

        Task {
            let since30d = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            let since7d = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            let since24h = Calendar.current.date(byAdding: .hour, value: -24, to: Date())!

            // Latest values — use 7d window so data shows even if not measured today
            async let w = queryLastMetric(.bodyMass, unit: .gramUnit(with: .kilo), since: since7d)
            async let s = querySleepMetric(since: since24h)
            async let st = queryCumulativeMetric(.stepCount, unit: .count(), since: since24h)
            async let hr = queryLastMetric(.restingHeartRate, unit: HKUnit(from: "count/min"), since: since7d)
            async let bf = queryLastMetric(.bodyFatPercentage, unit: .percent(), since: since7d, multiply: 100)
            async let h = queryLastMetric(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: since7d)
            async let ox = queryLastMetric(.oxygenSaturation, unit: .percent(), since: since7d, multiply: 100)

            // Trends (30 days)
            async let wt = queryTrend(.bodyMass, unit: .gramUnit(with: .kilo), since: since30d)
            async let slt = querySleepTrend(since: since30d)
            async let ht = queryTrend(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: since30d)
            async let bft = queryTrend(.bodyFatPercentage, unit: .percent(), since: since30d, multiply: 100)

            let (wVal, sVal, stVal, hrVal, bfVal, hVal, oxVal) = await (w, s, st, hr, bf, h, ox)
            let (wtVal, sltVal, htVal, bftVal) = await (wt, slt, ht, bft)

            await MainActor.run {
                // Only overwrite if HealthKit has data (don't clobber bridge values)
                if wVal != nil { self.weight = wVal }
                if sVal != nil { self.sleepHours = sVal }
                if stVal != nil { self.steps = stVal }
                if hrVal != nil { self.heartRate = hrVal }
                if bfVal != nil { self.bodyFat = bfVal }
                if hVal != nil { self.hrv = hVal }
                if oxVal != nil { self.bloodOxygen = oxVal }

                if !wtVal.isEmpty { self.weightTrend = wtVal }
                if !sltVal.isEmpty { self.sleepTrend = sltVal }
                if !htVal.isEmpty { self.hrvTrend = htVal }
                if !bftVal.isEmpty { self.bodyFatTrend = bftVal }

                self.isLoading = false
            }
        }

        // Also load data from bridge summary (Oura API data, agent notes)
        loadBridgeSummary(config: config)
    }

    // MARK: - HealthKit Queries

    private func queryLastMetric(_ type: HKQuantityTypeIdentifier, unit: HKUnit,
                                  since: Date, multiply: Double = 1) async -> HealthMetric? {
        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate,
                                       limit: 1, sortDescriptors: [sort]) { _, results, _ in
                guard let sample = results?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let val = sample.quantity.doubleValue(for: unit) * multiply
                continuation.resume(returning: HealthMetric(value: val, date: sample.startDate))
            }
            store.execute(query)
        }
    }

    private func queryCumulativeMetric(_ type: HKQuantityTypeIdentifier, unit: HKUnit,
                                        since: Date) async -> HealthMetric? {
        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType,
                                           quantitySamplePredicate: predicate,
                                           options: .cumulativeSum) { _, stats, _ in
                guard let val = stats?.sumQuantity()?.doubleValue(for: unit), val > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: HealthMetric(value: val, date: since))
            }
            store.execute(query)
        }
    }

    private func querySleepMetric(since: Date) async -> HealthMetric? {
        let hours = await querySleepHoursRaw(since: since)
        guard let h = hours, h > 0 else { return nil }
        return HealthMetric(value: h, date: since)
    }

    private func querySleepHoursRaw(since: Date) async -> Double? {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                       limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                var total: TimeInterval = 0
                for s in samples where asleepValues.contains(s.value) {
                    total += s.endDate.timeIntervalSince(s.startDate)
                }
                let hours = total / 3600.0
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            store.execute(query)
        }
    }

    private func queryTrend(_ type: HKQuantityTypeIdentifier, unit: HKUnit,
                            since: Date, multiply: Double = 1) async -> [(date: Date, value: Double)] {
        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate,
                                       limit: 100, sortDescriptors: [sort]) { _, results, _ in
                let points = (results as? [HKQuantitySample])?.map { sample in
                    (date: sample.startDate, value: sample.quantity.doubleValue(for: unit) * multiply)
                } ?? []
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    private func querySleepTrend(since: Date) async -> [(date: Date, value: Double)] {
        // Group sleep by night (date of wake-up)
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                       limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                // Group by calendar day of end date
                var byDay: [Date: TimeInterval] = [:]
                let cal = Calendar.current
                for s in samples where asleepValues.contains(s.value) {
                    let day = cal.startOfDay(for: s.endDate)
                    byDay[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
                }
                let points = byDay.map { (date: $0.key, value: $0.value / 3600.0) }
                    .sorted { $0.date < $1.date }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    // MARK: - Bridge summary (Oura API data + agent notes)

    private func loadBridgeSummary(config: BridgeConfig) {
        guard let bridgeURL = config.bridgeURL,
              let profileId = config.profile?.id else {
            debugLog = "no bridgeURL or profileId"
            return
        }
        let url = bridgeURL.appending(path: "users/\(profileId)/health/health_summary.json")
        debugLog = "path: \(url.path())\n"

        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path())
        debugLog += "exists: \(exists)\n"

        // Trigger iCloud download
        try? fm.startDownloadingUbiquitousItem(at: url)
        let healthDir = bridgeURL.appending(path: "users/\(profileId)/health")
        try? fm.startDownloadingUbiquitousItem(at: healthDir)

        // Check iCloud download status
        if let vals = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
            debugLog += "iCloud status: \(vals.ubiquitousItemDownloadingStatus?.rawValue ?? "nil")\n"
        }

        guard let data = try? Data(contentsOf: url) else {
            debugLog += "read FAILED — retrying in 3s...\n"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self else { return }
                // Re-check
                let retryExists = fm.fileExists(atPath: url.path())
                self.debugLog += "retry exists: \(retryExists)\n"
                if let vals = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
                    self.debugLog += "retry iCloud: \(vals.ubiquitousItemDownloadingStatus?.rawValue ?? "nil")\n"
                }
                guard let data = try? Data(contentsOf: url) else {
                    self.debugLog += "retry read FAILED"
                    return
                }
                self.debugLog += "retry OK (\(data.count) bytes)"
                self.parseBridgeSummary(data: data)
            }
            return
        }
        debugLog += "read OK (\(data.count) bytes)"
        parseBridgeSummary(data: data)

    }

    private func parseBridgeSummary(data: Data) {
        let json: BridgeSummary
        do {
            json = try JSONDecoder().decode(BridgeSummary.self, from: data)
        } catch {
            debugLog += "\nDECODE ERROR: \(error)"
            return
        }

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        func parseDate(_ s: String) -> Date {
            isoFull.date(from: s) ?? isoBasic.date(from: s) ?? Date()
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.debugLog += "\nkeys: \(json.latest.keys.sorted().joined(separator: ", "))"

            func assignIfNewer(_ current: inout HealthMetric?, _ incoming: HealthMetric) {
                guard current == nil || incoming.date >= current!.date else { return }
                current = incoming
            }

            for (key, val) in json.latest {
                let metric = HealthMetric(value: val.value, date: parseDate(val.date))
                switch key {
                case "weight":          assignIfNewer(&self.weight, metric)
                case "sleep_hours":     assignIfNewer(&self.sleepHours, metric)
                case "steps":           assignIfNewer(&self.steps, metric)
                case "heart_rate":      assignIfNewer(&self.heartRate, metric)
                case "body_fat":        assignIfNewer(&self.bodyFat, metric)
                case "hrv":             assignIfNewer(&self.hrv, metric)
                case "blood_oxygen":    assignIfNewer(&self.bloodOxygen, metric)
                case "stress_high":     assignIfNewer(&self.stressHigh, metric)
                case "recovery_high":   assignIfNewer(&self.recoveryHigh, metric)
                case "readiness_score": assignIfNewer(&self.readinessScore, metric)
                case "activity_score":  assignIfNewer(&self.activityScore, metric)
                case "active_minutes":  assignIfNewer(&self.activeMinutes, metric)
                case "sleep_score":     assignIfNewer(&self.sleepScore, metric)
                default: break
                }
            }
            self.debugLog += "\nhr=\(self.heartRate?.value ?? -1) hrv=\(self.hrv?.value ?? -1) o2=\(self.bloodOxygen?.value ?? -1)"

            func bridgeTrend(_ key: String) -> [(date: Date, value: Double)] {
                (json.trends[key] ?? []).map { p in
                    (date: parseDate(p.date), value: p.value)
                }
            }
            if self.weightTrend.count < 2, let bt = json.trends["weight"], bt.count >= 2 {
                self.weightTrend = bridgeTrend("weight")
            }
            if self.sleepTrend.count < 2, let bt = json.trends["sleep_hours"], bt.count >= 2 {
                self.sleepTrend = bridgeTrend("sleep_hours")
            }
            if self.hrvTrend.count < 2, let bt = json.trends["hrv"], bt.count >= 2 {
                self.hrvTrend = bridgeTrend("hrv")
            }
            if self.bodyFatTrend.count < 2, let bt = json.trends["body_fat"], bt.count >= 2 {
                self.bodyFatTrend = bridgeTrend("body_fat")
            }
            if self.bloodOxygenTrend.count < 2, let bt = json.trends["blood_oxygen"], bt.count >= 2 {
                self.bloodOxygenTrend = bridgeTrend("blood_oxygen")
            }
            if self.heartRateTrend.count < 2, let bt = json.trends["heart_rate"], bt.count >= 2 {
                self.heartRateTrend = bridgeTrend("heart_rate")
            }

            self.notes = json.notes
        }
    }
}

// MARK: - Bridge summary models

private struct BridgeSummary: Codable {
    let latest: [String: BridgeMetric]
    let trends: [String: [BridgeTrendPoint]]
    let notes: [HealthNote]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = (try? container.decode([String: BridgeMetric].self, forKey: .latest)) ?? [:]
        trends = (try? container.decode([String: [BridgeTrendPoint]].self, forKey: .trends)) ?? [:]
        notes = (try? container.decode([HealthNote].self, forKey: .notes)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case latest, trends, notes
    }
}

private struct BridgeMetric: Codable {
    let value: Double
    let date: String
    let unit: String?
}

private struct BridgeTrendPoint: Codable {
    let value: Double
    let date: String
}

struct HealthNote: Codable, Identifiable {
    let date: String
    let category: String
    let content: String
    var id: String { "\(date)_\(content.prefix(20))" }
}
