import SwiftUI
import Charts
import HealthKit
import MiraBridge

// MARK: - Health Tab (root)

struct HealthView: View {
    @Environment(BridgeConfig.self) private var config
    @Environment(ItemStore.self) private var store
    @Environment(CommandWriter.self) private var commands
    @State private var showInput = false
    @State private var healthData = HealthDataProvider()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                waListBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        if !healthData.isAuthorized {
                            HealthKitConnectBanner {
                                Task {
                                    let ok = await healthData.requestAuthorization()
                                    if ok { healthData.refresh(config: config) }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }

                        // Health alerts — top priority
                        HealthAlertBanner()
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        // Daily insight from GPT
                        HealthInsightCard()
                            .padding(.horizontal, 16)

                        // Dashboard cards — direct from HealthKit
                        HealthDashboard(data: healthData)
                            .padding(.horizontal, 16)
                            .padding(.top, healthData.isAuthorized ? 4 : 0)

                        // Trend charts — direct from HealthKit
                        HealthTrendCharts(data: healthData)
                            .padding(.horizontal, 16)

                        // Recent notes (from agent via bridge)
                        if !healthData.notes.isEmpty {
                            HealthNotesSection(notes: healthData.notes)
                                .padding(.horizontal, 16)
                        }

                        // Health feed from bridge
                        HealthFeedSection()
                    }
                    .padding(.bottom, 80)
                }

                Button { showInput = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(hex: 0x22C55E))
                        .background(Circle().fill(waListBg).frame(width: 44, height: 44))
                }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
            .navigationTitle("Health")
            .navigationDestination(for: String.self) { id in
                ItemDetailView(itemId: id)
            }
            .sheet(isPresented: $showInput) {
                HealthInputSheet(commands: commands)
            }
            .onAppear { healthData.refresh(config: config) }
            .refreshable { healthData.refresh(config: config) }
        }
    }
}

// MARK: - HealthKit Connect Banner

struct HealthKitConnectBanner: View {
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.circle")
                .font(.title2)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("连接 Apple Health")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(waTextPri)
                Text("自动同步体重、睡眠、步数、心率")
                    .font(.caption)
                    .foregroundStyle(waTextSec)
            }
            Spacer()
            Button("连接", action: onConnect)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.red, in: Capsule())
        }
        .padding(14)
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 12))
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
        VStack(spacing: 10) {
            if data.isLoading && data.weight == nil {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("读取 Apple Health...")
                        .font(.caption)
                        .foregroundStyle(waTextSec)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(waCardBg, in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DashCard(icon: "scalemass", label: "体重", value: fmt(data.weight), unit: "kg", dateLabel: dateLabel(data.weight), color: Color(hex: 0x4A9EFF))
                    DashCard(icon: "moon.zzz", label: "睡眠", value: fmt(data.sleepHours), unit: "h", dateLabel: dateLabel(data.sleepHours), color: Color(hex: 0xA78BFA))
                    DashCard(icon: "figure.walk", label: "步数", value: fmt(data.steps, decimals: 0), unit: "", dateLabel: dateLabel(data.steps), color: Color(hex: 0x22C55E))
                    DashCard(icon: "heart", label: "心率", value: fmt(data.heartRate, decimals: 0), unit: "bpm", dateLabel: dateLabel(data.heartRate), color: Color(hex: 0xEF4444))
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DashCard(icon: "percent", label: "体脂", value: fmt(data.bodyFat), unit: "%", dateLabel: dateLabel(data.bodyFat), color: Color(hex: 0xE8A838))
                    DashCard(icon: "waveform.path.ecg", label: "HRV", value: fmt(data.hrv, decimals: 0), unit: "ms", dateLabel: dateLabel(data.hrv), color: Color(hex: 0x818CF8))
                    DashCard(icon: "lungs", label: "血氧", value: fmt(data.bloodOxygen, decimals: 0), unit: "%", dateLabel: dateLabel(data.bloodOxygen), color: Color(hex: 0x38BDF8))
                }
                // Oura scores & activity
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DashCard(icon: "gauge.with.dots.needle.33percent", label: "准备度", value: fmt(data.readinessScore, decimals: 0), unit: "", dateLabel: dateLabel(data.readinessScore), color: Color(hex: 0x34D399))
                    DashCard(icon: "flame", label: "活动", value: fmt(data.activityScore, decimals: 0), unit: "", dateLabel: dateLabel(data.activityScore), color: Color(hex: 0xFB923C))
                    DashCard(icon: "moon.stars", label: "睡眠分", value: fmt(data.sleepScore, decimals: 0), unit: "", dateLabel: dateLabel(data.sleepScore), color: Color(hex: 0xC084FC))
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DashCard(icon: "bolt.heart", label: "压力", value: fmt(data.stressHigh, decimals: 0), unit: "min", dateLabel: dateLabel(data.stressHigh), color: Color(hex: 0xF87171))
                    DashCard(icon: "leaf", label: "恢复", value: fmt(data.recoveryHigh, decimals: 0), unit: "min", dateLabel: dateLabel(data.recoveryHigh), color: Color(hex: 0x6EE7B7))
                    DashCard(icon: "figure.run", label: "活动", value: fmt(data.activeMinutes, decimals: 0), unit: "min", dateLabel: dateLabel(data.activeMinutes), color: Color(hex: 0xFBBF24))
                }
            }
        }
    }
}

struct DashCard: View {
    let icon: String
    let label: String
    let value: String?
    let unit: String
    var dateLabel: String? = nil
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(waTextSec)
            }
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(waTextPri)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(waTextSec)
                }
                if let dateLabel {
                    Text(dateLabel)
                        .font(.caption2)
                        .foregroundStyle(waTextSec.opacity(0.7))
                }
            } else {
                Text("--")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(waTextSec.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Health Alert Banner

struct HealthAlertBanner: View {
    @Environment(ItemStore.self) private var store

    private var alerts: [MiraItem] {
        store.items.filter {
            $0.tags.contains("health") && $0.tags.contains("alert") && $0.status != .archived
        }
        .sorted { $0.date > $1.date }
    }

    @State private var selectedAlertId: String?

    var body: some View {
        if let alert = alerts.first {
            NavigationLink(value: alert.id) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("健康提醒")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(relativeDate(alert.date))
                            .font(.caption2)
                            .foregroundStyle(waTextSec)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(waTextSec)
                    }

                    Text(alert.lastMessagePreview)
                        .font(.caption)
                        .foregroundStyle(waTextPri)
                        .lineLimit(6)
                }
                .padding(12)
                .background(Color(hex: 0x7C2D12).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(Color(hex: 0x00A884))
                        Text("今日健康洞察")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(waTextSec)
                    }

                    Text(item.lastMessagePreview)
                        .font(.caption)
                        .foregroundStyle(waTextPri)
                        .lineLimit(8)
                }
                .padding(12)
                .background(waCardBg, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Trend Charts (from health_summary.json trends)

struct HealthTrendCharts: View {
    let data: HealthDataProvider

    var body: some View {
        VStack(spacing: 12) {
            if data.weightTrend.count >= 2 {
                MiniTrendChart(title: "体重趋势", unit: "kg", data: data.weightTrend, color: Color(hex: 0x4A9EFF))
            }
            if data.sleepTrend.count >= 2 {
                MiniTrendChart(title: "睡眠趋势", unit: "h", data: data.sleepTrend, color: Color(hex: 0xA78BFA))
            }
            if data.hrvTrend.count >= 2 {
                MiniTrendChart(title: "HRV 趋势", unit: "ms", data: data.hrvTrend, color: Color(hex: 0x818CF8))
            }
            if data.bodyFatTrend.count >= 2 {
                MiniTrendChart(title: "体脂趋势", unit: "%", data: data.bodyFatTrend, color: Color(hex: 0xE8A838))
            }
            if data.bloodOxygenTrend.count >= 2 {
                MiniTrendChart(title: "血氧趋势", unit: "%", data: data.bloodOxygenTrend, color: Color(hex: 0x38BDF8))
            }
            if data.heartRateTrend.count >= 2 {
                MiniTrendChart(title: "心率趋势", unit: "bpm", data: data.heartRateTrend, color: Color(hex: 0xEF4444))
            }
        }
    }
}

struct MiniTrendChart: View {
    let title: String
    let unit: String
    let data: [(date: Date, value: Double)]
    let color: Color

    private var avg: Double {
        guard !data.isEmpty else { return 0 }
        return data.map(\.value).reduce(0, +) / Double(data.count)
    }

    private var yRange: ClosedRange<Double> {
        let values = data.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let span = hi - lo
        let padding = max(span * 0.15, 0.5) // at least 0.5 padding
        return (lo - padding)...(hi + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(waTextSec)
                Spacer()
                Text("均值 \(avg, specifier: "%.1f")\(unit)")
                    .font(.caption2)
                    .foregroundStyle(waTextSec)
            }
            Chart(data, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("Date", point.date), yStart: .value("Min", yRange.lowerBound), yEnd: .value("Value", point.value))
                    .foregroundStyle(color.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(color)
                    .symbolSize(20)
            }
            .chartYScale(domain: yRange)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(waTextSec)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(waTextSec.opacity(0.3))
                    AxisValueLabel().foregroundStyle(waTextSec)
                }
            }
            .frame(height: 100)
        }
        .padding(12)
        .background(waCardBg, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Health Notes Section

struct HealthNotesSection: View {
    let notes: [HealthNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近记录")
                .font(.caption.weight(.semibold))
                .foregroundStyle(waTextSec)

            VStack(spacing: 1) {
                ForEach(notes.prefix(5)) { note in
                    HStack(spacing: 10) {
                        Image(systemName: noteIcon(note.category))
                            .foregroundStyle(noteColor(note.category))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(note.content)
                                .font(.subheadline)
                                .foregroundStyle(waTextPri)
                                .lineLimit(2)
                            Text("\(note.date) · \(note.category)")
                                .font(.caption2)
                                .foregroundStyle(waTextSec)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
            }
            .background(waCardBg, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func noteIcon(_ category: String) -> String {
        switch category {
        case "symptom": return "stethoscope"
        case "medication": return "pills"
        case "exercise": return "figure.run"
        case "diet": return "fork.knife"
        default: return "note.text"
        }
    }

    private func noteColor(_ category: String) -> Color {
        switch category {
        case "symptom": return Color(hex: 0xD97706)
        case "medication": return Color(hex: 0x818CF8)
        case "exercise": return Color(hex: 0x22C55E)
        default: return waTextSec
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
            VStack(alignment: .leading, spacing: 8) {
                Text("活动")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(waTextSec)
                    .padding(.horizontal, 16)

                VStack(spacing: 1) {
                    ForEach(healthItems.prefix(10)) { item in
                        NavigationLink(value: item.id) {
                            HealthItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(waCardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: - Health Item Row

struct HealthItemRow: View {
    let item: MiraItem

    private var icon: String {
        if item.title.contains("体重") || item.title.contains("weight") { return "scalemass" }
        if item.title.contains("睡眠") || item.title.contains("sleep") { return "moon.zzz" }
        if item.title.contains("步") || item.title.contains("step") { return "figure.walk" }
        if item.title.contains("心率") || item.title.contains("heart") { return "heart" }
        if item.title.contains("周报") || item.title.contains("report") { return "chart.bar.doc.horizontal" }
        if item.title.contains("提醒") || item.tags.contains("alert") { return "exclamationmark.triangle" }
        if item.tags.contains("symptom") { return "stethoscope" }
        return "heart.text.clipboard"
    }

    private var iconColor: Color {
        if item.title.contains("周报") { return Color(hex: 0x22C55E) }
        if item.title.contains("提醒") || item.tags.contains("alert") { return Color(hex: 0xD97706) }
        if item.tags.contains("symptom") { return Color(hex: 0xD97706) }
        return Color(hex: 0x4A9EFF)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(iconColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline).foregroundStyle(waTextPri).lineLimit(1)
                Text(item.lastMessagePreview).font(.caption).foregroundStyle(waTextSec).lineLimit(1)
            }
            Spacer()
            Text(formatTime(item.date)).font(.caption2).foregroundStyle(waTextSec)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
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
                        .foregroundStyle(Color(hex: 0x00A884))

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
