import SwiftUI
import Charts
import HealthKit
import MiraBridge

// MARK: - Health Tab (root)

struct HealthView: View {
    @Environment(BridgeConfig.self) private var config
    @Environment(ItemStore.self) private var store
    @Environment(CommandWriter.self) private var commands
    @Environment(HealthDataProvider.self) private var healthData
    @State private var showInput = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                waListBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !healthData.isAuthorized {
                            HealthKitConnectBanner {
                                Task {
                                    let ok = await healthData.requestAuthorization()
                                    if ok { healthData.refresh(config: config) }
                                }
                            }
                        }

                        HealthAlertBanner()
                        HealthInsightCard()
                        HealthDashboard(data: healthData)
                        HealthTrendCharts(data: healthData)

                        if !healthData.notes.isEmpty {
                            HealthNotesSection(notes: healthData.notes)
                        }

                        HealthFeedSection()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 90)
                }

                Button { showInput = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(waListBg)
                        .frame(width: 52, height: 52)
                        .background(waAccent)
                        .clipShape(Circle())
                }
                .padding(.trailing, 18)
                .padding(.bottom, 14)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("health")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(waTextPri)
                        .tracking(0.3)
                }
            }
            .navigationDestination(for: String.self) { id in
                ItemDetailView(itemId: id)
            }
            .sheet(isPresented: $showInput) {
                HealthInputSheet(commands: commands)
            }
            .onAppear {
                // Provider is pre-warmed at app launch / scene-active; only refresh
                // if it never loaded (cold path) so opening the tab is instant.
                if !healthData.hasLoadedOnce {
                    healthData.refresh(config: config)
                }
            }
            .refreshable { healthData.refresh(config: config) }
        }
    }
}

// MARK: - HealthKit Connect Banner

struct HealthKitConnectBanner: View {
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("connect apple health")
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(waTextDim)
                    .tracking(0.5)
                Text("自动同步体重、睡眠、步数、心率")
                    .font(.system(size: 14))
                    .foregroundStyle(waTextSec)
            }
            Spacer()
            Button(action: onConnect) {
                Text("connect")
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(waListBg)
                    .tracking(0.5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(waAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(waCardBg)
    }
}

// MARK: - Dashboard Cards (reads from health_summary.json)

struct HealthDashboard: View {
    @Bindable var data: HealthDataProvider

    private func fmt(_ metric: HealthDataProvider.HealthMetric?, decimals: Int = 1) -> String? {
        guard let m = metric else { return nil }
        if m.value > 100 && m.value == m.value.rounded() { return String(format: "%.0f", m.value) }
        return String(format: "%.\(decimals)f", m.value)
    }

    private func dateLabel(_ metric: HealthDataProvider.HealthMetric?) -> String? {
        guard let m = metric else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(m.date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "今天 " + f.string(from: m.date)
        } else if cal.isDateInYesterday(m.date) {
            return "昨天"
        } else {
            let f = DateFormatter()
            f.dateFormat = "M/d"
            return f.string(from: m.date)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if data.isLoading && data.weight == nil {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.7).tint(waTextDim)
                    Text("loading")
                        .font(.system(size: 12).monospaced())
                        .foregroundStyle(waTextDim)
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(waCardBg)
            } else {
                metricSection("vitals", rows: [
                    [
                        MetricSpec("sleep", fmt(data.sleepHours), "h", warn: data.sleepHours.map { $0.value < 6 } ?? false),
                        MetricSpec("hrv", fmt(data.hrv, decimals: 0), "ms"),
                        MetricSpec("rhr", fmt(data.heartRate, decimals: 0), "bpm"),
                    ],
                    [
                        MetricSpec("spo2", fmt(data.bloodOxygen, decimals: 0), "%", warn: data.bloodOxygen.map { $0.value < 95 } ?? false),
                        MetricSpec("breath", fmt(data.respiratoryRate, decimals: 1), "/min"),
                        MetricSpec("weight", fmt(data.weight), "kg"),
                    ],
                ])

                metricSection("oura scores", rows: [
                    [
                        MetricSpec("readiness", fmt(data.readinessScore, decimals: 0), "/100", warn: data.readinessScore.map { $0.value < 65 } ?? false),
                        MetricSpec("sleep score", fmt(data.sleepScore, decimals: 0), "/100", warn: data.sleepScore.map { $0.value < 70 } ?? false),
                        MetricSpec("activity", fmt(data.activityScore, decimals: 0), "/100"),
                    ],
                    [
                        MetricSpec("temp dev.", fmt(data.temperatureDeviation, decimals: 0), "/100",
                                   warn: data.temperatureDeviation.map { $0.value < 50 } ?? false,
                                   alert: data.temperatureDeviation.map { $0.value < 30 } ?? false),
                        MetricSpec("resilience", resilienceLabel(data.resilienceLevel?.value), "",
                                   warn: data.resilienceLevel.map { $0.value <= 1 } ?? false),
                        MetricSpec("body fat", fmt(data.bodyFat), "%"),
                    ],
                ])

                metricSection("today", rows: [
                    [
                        MetricSpec("steps", fmt(data.steps, decimals: 0), ""),
                        MetricSpec("active", fmt(data.activeMinutes, decimals: 0), "min"),
                        MetricSpec("kcal", fmt(data.activeCalories, decimals: 0), ""),
                    ],
                    [
                        MetricSpec("stress", fmt(data.stressHigh, decimals: 0), "min"),
                        MetricSpec("recovery", fmt(data.recoveryHigh, decimals: 0), "min"),
                        MetricSpec("sleep recov.", fmt(data.sleepRecovery, decimals: 0), ""),
                    ],
                ])
            }
        }
    }

    @ViewBuilder
    private func metricSection(_ title: String, rows: [[MetricSpec]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11).monospaced())
                .foregroundStyle(waTextDim)
                .tracking(1.2)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { cIdx, m in
                            MetricCell(spec: m)
                            if cIdx < row.count - 1 {
                                Rectangle().fill(waBorder).frame(width: 0.5)
                            }
                        }
                    }
                    if rIdx < rows.count - 1 {
                        Rectangle().fill(waBorder).frame(height: 0.5)
                    }
                }
            }
            .background(waCardBg)
        }
    }

    private func resilienceLabel(_ raw: Double?) -> String? {
        guard let v = raw else { return nil }
        switch Int(v.rounded()) {
        case 1: return "limited"
        case 2: return "adequate"
        case 3: return "solid"
        case 4: return "strong"
        case 5: return "exceptional"
        default: return String(format: "%.0f", v)
        }
    }
}

struct MetricSpec {
    let label: String
    let value: String?
    let unit: String
    let warn: Bool
    let alert: Bool
    init(_ label: String, _ value: String?, _ unit: String, warn: Bool = false, alert: Bool = false) {
        self.label = label
        self.value = value
        self.unit = unit
        self.warn = warn
        self.alert = alert
    }
}

struct MetricCell: View {
    let spec: MetricSpec

    private var valueColor: Color {
        if spec.alert { return waStatusAlert }
        if spec.warn { return waStatusWarn }
        return waTextPri
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spec.label)
                .font(.system(size: 11).monospaced())
                .foregroundStyle(waTextDim)
                .tracking(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(spec.value ?? "—")
                    .font(.system(size: 22, weight: .light).monospacedDigit())
                    .foregroundStyle(valueColor)
                if let _ = spec.value, !spec.unit.isEmpty {
                    Text(spec.unit)
                        .font(.system(size: 11))
                        .foregroundStyle(waTextDim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}


// MARK: - Health Alert Banner

struct HealthAlertBanner: View {
    @Environment(ItemStore.self) private var store

    // Show all unread alerts from the last 3 days, freshest first.
    // A single critical alert (e.g. Oura "major issue") can otherwise be hidden
    // behind a more recent info-level item — surface them all.
    private var alerts: [MiraItem] {
        let cutoff = Date().addingTimeInterval(-3 * 24 * 3600)
        return store.items.filter {
            $0.tags.contains("health") && $0.tags.contains("alert") &&
            $0.status != .archived && $0.date >= cutoff
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        if !alerts.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(alerts.prefix(3).enumerated()), id: \.element.id) { idx, alert in
                    NavigationLink(value: alert.id) {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Circle().fill(waStatusAlert).frame(width: 6, height: 6)
                                    Text("alert")
                                        .font(.system(size: 11).monospaced())
                                        .foregroundStyle(waStatusAlert)
                                        .tracking(1.0)
                                }
                                Text(alert.lastMessagePreview)
                                    .font(.system(size: 14))
                                    .foregroundStyle(waTextPri)
                                    .lineLimit(4)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Text(relativeDate(alert.date))
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(waTextDim)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(waCardHi)
                    }
                    .buttonStyle(.plain)
                    if idx < alerts.prefix(3).count - 1 {
                        Rectangle().fill(waBorder).frame(height: 0.5)
                    }
                }
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInYesterday(date) { return "yesterday" }
        let f = DateFormatter(); f.dateFormat = "M/d"
        return f.string(from: date)
    }
}

// MARK: - Daily Health Insight Card

struct HealthInsightCard: View {
    @Environment(ItemStore.self) private var store

    private var insight: MiraItem? {
        store.items.filter {
            $0.tags.contains("health") && $0.tags.contains("insight") && $0.status != .archived
        }
        .sorted { $0.date > $1.date }
        .first
    }

    var body: some View {
        if let item = insight {
            NavigationLink(value: item.id) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("today's reading")
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(waTextDim)
                        .tracking(1.2)
                    Text(item.lastMessagePreview)
                        .font(.system(size: 14))
                        .foregroundStyle(waTextPri)
                        .lineLimit(8)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(waCardHi)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Trend Charts (from health_summary.json trends)

struct HealthTrendCharts: View {
    let data: HealthDataProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("trends · 30d")
                .font(.system(size: 11).monospaced())
                .foregroundStyle(waTextDim)
                .tracking(1.2)
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 12)
            VStack(spacing: 0) {
                let pairs: [(String, String, [(date: Date, value: Double)])] = [
                    ("sleep", "h", data.sleepTrend),
                    ("hrv", "ms", data.hrvTrend),
                    ("readiness", "", data.readinessTrend),
                    ("sleep score", "", data.sleepScoreTrend),
                    ("rhr", "bpm", data.heartRateTrend),
                    ("spo2", "%", data.bloodOxygenTrend),
                    ("weight", "kg", data.weightTrend),
                    ("body fat", "%", data.bodyFatTrend),
                ].filter { $0.2.count >= 2 }
                ForEach(Array(pairs.enumerated()), id: \.offset) { idx, pair in
                    MiniTrendChart(title: pair.0, unit: pair.1, data: pair.2)
                    if idx < pairs.count - 1 {
                        Rectangle().fill(waBorder).frame(height: 0.5)
                    }
                }
            }
            .background(waCardBg)
        }
    }
}

struct MiniTrendChart: View {
    let title: String
    let unit: String
    let data: [(date: Date, value: Double)]

    private var latest: Double { data.last?.value ?? 0 }
    private var avg: Double {
        guard !data.isEmpty else { return 0 }
        return data.map(\.value).reduce(0, +) / Double(data.count)
    }

    private var yRange: ClosedRange<Double> {
        let values = data.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let span = hi - lo
        let padding = max(span * 0.15, 0.5)
        return (lo - padding)...(hi + padding)
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
                    .tracking(0.5)
                Text(String(format: "%.1f%@", latest, unit))
                    .font(.system(size: 18, weight: .light).monospacedDigit())
                    .foregroundStyle(waTextPri)
                Text(String(format: "avg %.1f", avg))
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(waTextDim)
            }
            .frame(width: 90, alignment: .leading)

            Chart(data, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(waAccent)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            .chartYScale(domain: yRange)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 50)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

// MARK: - Health Notes Section

struct HealthNotesSection: View {
    let notes: [HealthNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("recent notes")
                .font(.system(size: 11).monospaced())
                .foregroundStyle(waTextDim)
                .tracking(1.2)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                let preview = Array(notes.prefix(5))
                ForEach(Array(preview.enumerated()), id: \.element.id) { idx, note in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.category.lowercased())
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(waTextDim)
                                .tracking(0.5)
                            Text(note.content)
                                .font(.system(size: 14))
                                .foregroundStyle(waTextPri)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Text(note.date)
                            .font(.system(size: 11).monospaced())
                            .foregroundStyle(waTextDim)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    if idx < preview.count - 1 {
                        Rectangle().fill(waBorder).frame(height: 0.5)
                    }
                }
            }
            .background(waCardBg)
        }
    }
}

// MARK: - Health Feed Section

struct HealthFeedSection: View {
    @Environment(ItemStore.self) private var store

    private var healthItems: [MiraItem] {
        store.items.filter { $0.tags.contains("health") && $0.status != .archived }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        if !healthItems.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("activity")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(waTextDim)
                    .tracking(1.2)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    let recent = Array(healthItems.prefix(10))
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, item in
                        NavigationLink(value: item.id) {
                            HealthItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                        if idx < recent.count - 1 {
                            Rectangle().fill(waBorder).frame(height: 0.5).padding(.leading, 18)
                        }
                    }
                }
                .background(waCardBg)
            }
        }
    }
}

// MARK: - Health Item Row

struct HealthItemRow: View {
    let item: MiraItem

    private var spec: (label: String, color: Color, icon: String) {
        if item.tags.contains("alert") || item.title.contains("提醒") {
            return ("alert", colorAlert, "exclamationmark.triangle.fill")
        }
        if item.tags.contains("symptom") {
            return ("symptom", colorHealth, "stethoscope")
        }
        if item.tags.contains("report") || item.title.contains("周报") {
            return ("report", colorAnalysis, "chart.bar.doc.horizontal")
        }
        if item.tags.contains("insight") {
            return ("insight", colorWriting, "brain.head.profile")
        }
        return ("log", colorHealth, "heart.text.clipboard")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(spec.color)
                    .frame(width: 38, height: 38)
                Image(systemName: spec.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(waListBg)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(spec.label)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(spec.color)
                    .tracking(0.8)
                Text(item.title)
                    .font(.system(size: 15))
                    .foregroundStyle(waTextPri)
                    .lineLimit(1)
                Text(item.lastMessagePreview)
                    .font(.system(size: 12))
                    .foregroundStyle(waTextSec)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Text(formatTime(item.date))
                .font(.system(size: 11).monospaced())
                .foregroundStyle(waTextDim)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            ZStack {
                waCardBg
                spec.color.opacity(0.10)
            }
        )
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d"
        return f.string(from: date)
    }
}

// MARK: - Health Input Sheet

struct HealthInputSheet: View {
    let commands: CommandWriter
    @Environment(BridgeConfig.self) private var config
    @Environment(\.dismiss) private var dismiss

    @State private var inputType = 0  // 0=症状 1=数据 2=体检
    @State private var metricType = "blood_pressure"
    @State private var metricValue = ""
    @State private var bpSystolic = ""
    @State private var bpDiastolic = ""
    @State private var symptomText = ""
    @State private var selectedPerson = "self"
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var checkupImages: [UIImage] = []
    @State private var checkupNote = ""
    @State private var isUploading = false

    // Only metrics that can't be auto-collected
    private let metricTypes = [
        ("blood_pressure", "血压", "heart"),
        ("blood_sugar", "血糖 (mmol/L)", "drop"),
        ("temperature", "体温 (°C)", "thermometer.medium"),
    ]

    private var familyMembers: [(id: String, label: String)] {
        var members: [(String, String)] = [("self", "自己")]
        for p in config.profiles where p.id != config.profile?.id {
            members.append((p.id, p.displayName))
        }
        members.append(contentsOf: [("dad", "爸爸"), ("mom", "妈妈")])
        return members
    }

    private var isBP: Bool { metricType == "blood_pressure" }

    var body: some View {
        NavigationStack {
            Form {
                Section("为谁记录") {
                    Picker("家庭成员", selection: $selectedPerson) {
                        ForEach(familyMembers, id: \.id) { Text($0.label).tag($0.id) }
                    }.pickerStyle(.menu)
                }
                Picker("类型", selection: $inputType) {
                    Text("症状/感受").tag(0); Text("血压/血糖").tag(1); Text("体检报告").tag(2)
                }.pickerStyle(.segmented).listRowBackground(Color.clear)

                if inputType == 0 {
                    Section("今天感觉怎么样？") {
                        TextField("比如：感冒、头疼、喉咙痛、精力不好、胃不舒服...",
                                  text: $symptomText, axis: .vertical)
                            .lineLimit(3...8)
                    }
                } else if inputType == 1 {
                    Section("手动记录") {
                        Picker("指标", selection: $metricType) {
                            ForEach(metricTypes, id: \.0) { Label($0.1, systemImage: $0.2).tag($0.0) }
                        }
                        if isBP {
                            HStack {
                                TextField("收缩压", text: $bpSystolic).keyboardType(.numberPad)
                                Text("/").foregroundStyle(waTextSec)
                                TextField("舒张压", text: $bpDiastolic).keyboardType(.numberPad)
                                Text("mmHg").font(.caption).foregroundStyle(waTextSec)
                            }
                        } else {
                            TextField("数值", text: $metricValue).keyboardType(.decimalPad)
                        }
                    }
                } else {
                    Section("上传体检报告") {
                        HStack(spacing: 12) {
                            Button { showCamera = true } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "camera.fill")
                                        .font(.title2)
                                    Text("拍照")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(hex: 0x1F2C34))
                                .cornerRadius(10)
                            }
                            Button { showPhotoPicker = true } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.title2)
                                    Text("相册")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(hex: 0x1F2C34))
                                .cornerRadius(10)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(waAccent)

                        if !checkupImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(checkupImages.indices, id: \.self) { i in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: checkupImages[i])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 80, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            Button {
                                                checkupImages.remove(at: i)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.white, .red)
                                            }
                                            .offset(x: 4, y: -4)
                                        }
                                    }
                                }
                            }
                            Text("\(checkupImages.count) 张照片")
                                .font(.caption)
                                .foregroundStyle(waTextSec)
                        }
                    }
                    Section("备注（可选）") {
                        TextField("体检日期、医院、注意事项...", text: $checkupNote, axis: .vertical)
                            .lineLimit(2...4)
                    }
                    if isUploading {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("上传中...").font(.caption).foregroundStyle(waTextSec)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(waListBg)
            .navigationTitle("记录健康数据").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { submit(); dismiss() }.disabled(!isValid)
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(images: $checkupImages)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture(images: $checkupImages)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var isValid: Bool {
        switch inputType {
        case 0: return !symptomText.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return isBP ? (Int(bpSystolic) != nil && Int(bpDiastolic) != nil) : Double(metricValue) != nil
        case 2: return !checkupImages.isEmpty
        default: return false
        }
    }

    private var personPrefix: String {
        selectedPerson == "self" ? "" :
            (familyMembers.first { $0.id == selectedPerson }?.label ?? selectedPerson) + "的"
    }

    private func submit() {
        let person = selectedPerson == "self" ? "" : " (person: \(selectedPerson))"
        switch inputType {
        case 0:
            commands.createRequest(
                title: "\(personPrefix)症状: \(symptomText.prefix(30))",
                content: "\(symptomText)\(person)", quick: true, tags: ["health", "symptom"])
        case 1:
            if isBP {
                commands.createRequest(
                    title: "记录\(personPrefix)血压 \(bpSystolic)/\(bpDiastolic)mmHg",
                    content: "记录血压 收缩压\(bpSystolic) 舒张压\(bpDiastolic)\(person)",
                    quick: true, tags: ["health", "metric"])
            } else {
                let label = metricTypes.first { $0.0 == metricType }?.1 ?? metricType
                commands.createRequest(
                    title: "记录\(personPrefix)\(label) \(metricValue)",
                    content: "记录 \(metricType) \(metricValue)\(person)",
                    quick: true, tags: ["health", "metric"])
            }
        case 2:
            uploadCheckup(person: person)
        default: break
        }
    }

    private func uploadCheckup(person: String) {
        guard let bridgeURL = config.bridgeURL,
              let profileId = config.profile?.id else { return }
        isUploading = true

        let checkupDir = bridgeURL
            .appending(path: "users/\(profileId)/health/checkups")
        try? FileManager.default.createDirectory(at: checkupDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        // Save images as JPEGs
        var filenames: [String] = []
        for (i, img) in checkupImages.enumerated() {
            let name = "checkup_\(timestamp)_\(i).jpg"
            if let data = img.jpegData(compressionQuality: 0.85) {
                let fileURL = checkupDir.appending(path: name)
                try? data.write(to: fileURL)
                filenames.append(name)
            }
        }

        // Send request to agent to parse
        let note = checkupNote.isEmpty ? "" : "\n备注: \(checkupNote)"
        commands.createRequest(
            title: "\(personPrefix)体检报告 (\(filenames.count)张)",
            content: "体检报告上传: \(filenames.joined(separator: ", "))\(note)\(person)\n路径: users/\(profileId)/health/checkups/",
            quick: false, tags: ["health", "checkup"])

        isUploading = false
    }
}

// MARK: - Photo Picker (PHPicker)

import PhotosUI

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 10
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            for result in results {
                result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage {
                        DispatchQueue.main.async { self.parent.images.append(img) }
                    }
                }
            }
        }
    }
}

// MARK: - Camera Capture

struct CameraCapture: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.images.append(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
