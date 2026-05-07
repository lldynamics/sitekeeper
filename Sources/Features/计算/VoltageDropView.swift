import SwiftUI

struct VoltageDropView: View {
    @Environment(DataStore.self) private var store
    @State private var current: String = ""
    @State private var length: String = ""
    @State private var material: WireMaterial = .copper
    @State private var section: String = "2.5"
    @State private var voltage: String = "220"
    @State private var isLoopLength: Bool = false  // true = 回路长度(已含来回), false = 单程距离

    @State private var resultText: String = ""

    private let resistivityCopper: Double = 0.0175
    private let resistivityAluminum: Double = 0.0283

    let commonSections = EngineeringCalculations.standardWireSections.map { String(format: $0.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", $0) }

    var body: some View {
        Form {
            Section("线路参数") {
                LabeledContent("电流 (A)") {
                    TextField("例如 20", text: $current)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("长度 (m)") {
                    TextField("例如 100", text: $length)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("回路长度（已含来/回）", isOn: $isLoopLength)
                Picker("材质", selection: $material) {
                    Text("铜").tag(WireMaterial.copper)
                    Text("铝").tag(WireMaterial.aluminum)
                }
                LabeledContent("截面积 (mm²)") {
                    TextField("2.5", text: $section)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(commonSections, id: \.self) { s in
                            Button(s) { section = s }
                                .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(section == s ? Color.orange : Color.gray.opacity(0.15))
                                .foregroundStyle(section == s ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                LabeledContent("额定电压 (V)") {
                    TextField("220", text: $voltage)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("载流量参考") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(EngineeringCalculations.standardWireSections, id: \.self) { item in
                            VStack(spacing: 2) {
                                Text(formatSection(item)).font(.caption2)
                                Text("\(Int(EngineeringCalculations.ampacity(for: item, isCopper: material == .copper)))A")
                                    .font(.caption.weight(.medium)).foregroundStyle(.blue)
                            }
                            .padding(6)
                            .background(formatSection(item) == section ? Color.blue.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            Section {
                Button("计算") { calcAndSave() }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }

            if !resultText.isEmpty {
                Section("计算结果") {
                    Text(resultText)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .navigationTitle("电缆压降")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func calc() {
        guard let i = Double(current), i > 0,
              let l = Double(length), l > 0,
              let s = Double(section), s > 0,
              let v = Double(voltage), v > 0 else {
            resultText = "请输入有效数值"
            return
        }
        let isCopper = material == .copper
        let rho = isCopper ? resistivityCopper : resistivityAluminum
        let effectiveLength = isLoopLength ? l : l * 2
        let drop = EngineeringCalculations.voltageDrop(current: i, length: l, section: s, voltage: v, isLoopLength: isLoopLength, resistivity: rho)
        let recommended = EngineeringCalculations.recommendedWireSection(current: i, length: l, voltage: v, isLoopLength: isLoopLength, isCopper: isCopper)
        let ampacity = EngineeringCalculations.ampacity(for: s, isCopper: isCopper)
        let ampNote: String
        ampNote = i <= ampacity ? "载流量: \(Int(ampacity))A，满足" : "载流量: \(Int(ampacity))A，电流偏大"
        let recNote = recommended.map { "推荐截面: \(formatSection($0)) mm²" } ?? "推荐截面: 超出常用规格，请复核设计"

        resultText = """
        材质: \(material == .copper ? "铜" : "铝")
        有效长度: \(String(format: "%.1f", effectiveLength)) m (\(isLoopLength ? "回路" : "单程×2"))
        线路电阻: \(String(format: "%.3f", drop.resistance)) Ω
        电压降: \(String(format: "%.2f", drop.dropV)) V (\(String(format: "%.2f", drop.dropPercent))%)
        \(drop.dropPercent > 5 ? "压降 > 5%，建议增大截面" : "压降在允许范围内")
        \(ampNote)
        \(recNote)
        """
    }

    private func calcAndSave() {
        calc()
        if !resultText.isEmpty {
            saveHistory(resultText.components(separatedBy: "\n").first ?? "")
        }
    }

    private func saveHistory(_ r: String) {
        store.historyRecords.insert(HistoryRecord(tool: "电缆压降", input: "\(current)A, \(length)m, \(section)mm²", result: r, date: now()), at: 0)
        store.scheduleSave()
    }
    private func now() -> String { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df.string(from: Date()) }

    private func formatSection(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

enum WireMaterial: Hashable {
    case copper, aluminum
}
