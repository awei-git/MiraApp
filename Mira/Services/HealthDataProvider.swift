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
    var temperatureDeviation: HealthMetric?
    var sleepRecovery: HealthMetric?
    var daytimeRecovery: HealthMetric?
    var resilienceLevel: HealthMetric?
    var respiratoryRate: HealthMetric?
    var activeCalories: HealthMetric?
    var restingHRLowest: HealthMetric?

    // Trends (30 days)
    var weightTrend: [(date: Date, value: Double)] = []
    var sleepTrend: [(date: Date, value: Double)] = []
    var hrvTrend: [(date: Date, value: Double)] = []
    var bodyFatTrend: [(date: Date, value: Double)] = []
    var bloodOxygenTrend: [(date: Date, value: Double)] = []
    var heartRateTrend: [(date: Date, value: Double)] = []
    var sleepScoreTrend: [(date: Date, value: Double)] = []
    var readinessTrend: [(date: Date, value: Double)] = []

    // Notes from bridge
    var notes: [HealthNote] = []

    var isLoading = false
    var hasLoadedOnce = false
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

        // Load bridge first (Oura is source of truth for sleep/readiness/etc.)
        // Run on background queue so iCloud reads don't block UI.
        Task.detached(priority: .userInitiated) { [weak self] in
            self?.loadBridgeSummary(config: config)
        }

        Task {
            let since30d = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            let since7d = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            let since24h = Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
            // Sleep window must cover last night even at late evening — use 36h.
            let since36h = Calendar.current.date(byAdding: .hour, value: -36, to: Date())!

            // Latest values — use 7d window so data shows even if not measured today
            async let w = queryLastMetric(.bodyMass, unit: .gramUnit(with: .kilo), since: since7d)
            async let s = querySleepMetric(since: since36h)
            async let st = queryCumulativeMetric(.stepCount, unit: .count(), since: since24h)
            async let hr = queryLastMetric(.restingHeartRate, unit: HKUnit(from: "count/min"), since: since7d)
            async let bf = queryLastMetric(.bodyFatPercentage, unit: .percent(), since: since7d, multiply: 100)
            async let h = queryLastMetric(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: since7d)
            async let ox = queryLastMetric(.oxygenSaturation, unit: .percent(), since: since7d, multiply: 100)
            async let rr = queryLastMetric(.respiratoryRate, unit: HKUnit(from: "count/min"), since: since7d)

            // Trends (30 days)
            async let wt = queryTrend(.bodyMass, unit: .gramUnit(with: .kilo), since: since30d)
            async let slt = querySleepTrend(since: since30d)
            async let ht = queryTrend(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: since30d)
            async let bft = queryTrend(.bodyFatPercentage, unit: .percent(), since: since30d, multiply: 100)

            let (wVal, sVal, stVal, hrVal, bfVal, hVal, oxVal, rrVal) = await (w, s, st, hr, bf, h, ox, rr)
            let (wtVal, sltVal, htVal, bftVal) = await (wt, slt, ht, bft)

            await MainActor.run {
                // HealthKit fills only fields the bridge doesn't already cover, EXCEPT
                // for sleep — bridge (Oura) is authoritative; HealthKit is fallback only.
                if wVal != nil { self.weight = wVal }
                if let sV = sVal, self.sleepHours == nil { self.sleepHours = sV }  // bridge wins
                if stVal != nil { self.steps = stVal }
                if hrVal != nil { self.heartRate = hrVal }
                if bfVal != nil { self.bodyFat = bfVal }
                if hVal != nil { self.hrv = hVal }
                if oxVal != nil { self.bloodOxygen = oxVal }
                if let rrV = rrVal, self.respiratoryRate == nil { self.respiratoryRate = rrV }

                if !wtVal.isEmpty { self.weightTrend = wtVal }
                if !sltVal.isEmpty && self.sleepTrend.count < 2 { self.sleepTrend = sltVal }
                if !htVal.isEmpty { self.hrvTrend = htVal }
                if !bftVal.isEmpty { self.bodyFatTrend = bftVal }

                self.isLoading = false
                self.hasLoadedOnce = true
            }
        }
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
                // Group samples by source (Oura vs Apple Watch vs etc.) and pick the
                // source with the largest total — avoids double-counting when multiple
                // wearables write overlapping sleep data, and prevents undercounting
                // when one source only logged a fragment.
                var bySource: [String: [(Date, Date)]] = [:]
                for s in samples where asleepValues.contains(s.value) {
                    let key = s.sourceRevision.source.bundleIdentifier
                    bySource[key, default: []].append((s.startDate, s.endDate))
                }
                func mergedTotal(_ intervals: [(Date, Date)]) -> TimeInterval {
                    let sorted = intervals.sorted { $0.0 < $1.0 }
                    var total: TimeInterval = 0
                    var curStart: Date? = nil
                    var curEnd: Date? = nil
                    for (s, e) in sorted {
                        if let cs = curStart, let ce = curEnd, s <= ce {
                            curEnd = max(ce, e)
                            _ = cs  // keep
                        } else {
                            if let cs = curStart, let ce = curEnd {
                                total += ce.timeIntervalSince(cs)
                            }
                            curStart = s
                            curEnd = e
                        }
                    }
                    if let cs = curStart, let ce = curEnd {
                        total += ce.timeIntervalSince(cs)
                    }
                    return total
                }
                let best = bySource.values.map(mergedTotal).max() ?? 0
                let hours = best / 3600.0
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
            Task { @MainActor in self.debugLog = "no bridgeURL or profileId" }
            return
        }
        let url = bridgeURL.appending(path: "users/\(profileId)/health/health_summary.json")
        let fm = FileManager.default

        // Trigger iCloud download
        try? fm.startDownloadingUbiquitousItem(at: url)
        let healthDir = bridgeURL.appending(path: "users/\(profileId)/health")
        try? fm.startDownloadingUbiquitousItem(at: healthDir)

        // Try up to 3 times with backoff, off the main thread.
        Task.detached { [weak self] in
            for delay in [0, 800, 2500] {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                }
                if let data = try? Data(contentsOf: url) {
                    self?.parseBridgeSummary(data: data, url: url)
                    return
                }
            }
            await MainActor.run {
                self?.debugLog = "bridge read failed (no health_summary.json after retries)"
            }
        }
    }

    private func parseBridgeSummary(data: Data, url: URL) {
        let json: BridgeSummary
        do {
            json = try JSONDecoder().decode(BridgeSummary.self, from: data)
        } catch {
            Task { @MainActor in self.debugLog = "DECODE ERROR: \(error)" }
            return
        }

        Task { @MainActor [weak self] in
            let isoFull = ISO8601DateFormatter()
            isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]

            func parseDate(_ s: String) -> Date {
                isoFull.date(from: s) ?? isoBasic.date(from: s) ?? Date()
            }
            guard let self else { return }

            // Bridge (Oura) is authoritative for sleep, readiness, and Oura-only fields.
            // For metrics also tracked by HealthKit, prefer the most recent.
            func assignIfNewer(_ current: inout HealthMetric?, _ incoming: HealthMetric) {
                guard current == nil || incoming.date >= current!.date else { return }
                current = incoming
            }
            func bridgeWins(_ current: inout HealthMetric?, _ incoming: HealthMetric) {
                current = incoming
            }

            for (key, val) in json.latest {
                let metric = HealthMetric(value: val.value, date: parseDate(val.date))
                switch key {
                case "weight":                 assignIfNewer(&self.weight, metric)
                case "sleep_hours":            bridgeWins(&self.sleepHours, metric)
                case "steps":                  assignIfNewer(&self.steps, metric)
                case "heart_rate":             assignIfNewer(&self.heartRate, metric)
                case "body_fat":               assignIfNewer(&self.bodyFat, metric)
                case "hrv":                    bridgeWins(&self.hrv, metric)
                case "blood_oxygen":           assignIfNewer(&self.bloodOxygen, metric)
                case "stress_high":            bridgeWins(&self.stressHigh, metric)
                case "recovery_high":          bridgeWins(&self.recoveryHigh, metric)
                case "readiness_score":        bridgeWins(&self.readinessScore, metric)
                case "activity_score":         bridgeWins(&self.activityScore, metric)
                case "active_minutes":         bridgeWins(&self.activeMinutes, metric)
                case "sleep_score":            bridgeWins(&self.sleepScore, metric)
                case "temperature_deviation":  bridgeWins(&self.temperatureDeviation, metric)
                case "sleep_recovery":         bridgeWins(&self.sleepRecovery, metric)
                case "daytime_recovery":       bridgeWins(&self.daytimeRecovery, metric)
                case "resilience_level":       bridgeWins(&self.resilienceLevel, metric)
                case "respiratory_rate":       bridgeWins(&self.respiratoryRate, metric)
                case "active_calories":        bridgeWins(&self.activeCalories, metric)
                case "resting_hr_lowest":      bridgeWins(&self.restingHRLowest, metric)
                default: break
                }
            }

            func bridgeTrend(_ key: String) -> [(date: Date, value: Double)] {
                (json.trends[key] ?? []).map { p in
                    (date: parseDate(p.date), value: p.value)
                }
            }
            if self.weightTrend.count < 2, let bt = json.trends["weight"], bt.count >= 2 {
                self.weightTrend = bridgeTrend("weight")
            }
            // Sleep trend: bridge wins (Oura has full nightly totals)
            if let bt = json.trends["sleep_hours"], bt.count >= 2 {
                self.sleepTrend = bridgeTrend("sleep_hours")
            }
            if let bt = json.trends["hrv"], bt.count >= 2 {
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
            if let bt = json.trends["sleep_score"], bt.count >= 2 {
                self.sleepScoreTrend = bridgeTrend("sleep_score")
            }
            if let bt = json.trends["readiness_score"], bt.count >= 2 {
                self.readinessTrend = bridgeTrend("readiness_score")
            }

            self.notes = json.notes
            self.hasLoadedOnce = true
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
