import SwiftUI

struct CurrentCalcView: View {
    @Environment(DataStore.self) private var store
    @State private var power: String = ""
    @State private var voltage: String = "220"
    @State private var powerFactor: String = "0.85"
    @State private var isThreePhase: Bool = false {
        didSet { voltage = isThreePhase ? "380" : "220" }
    }

    @State private var resultText: String = ""

    var body: some View {
        Form {
            Section("输入参数") {
                LabeledContent("功率 (kW)") {
                    TextField("例如 10", text: $power)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("电压 (V)") {
                    TextField("220", text: $voltage)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("功率因数") {
                    TextField("0.85", text: $powerFactor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("三相电", isOn: $isThreePhase)

                HStack(spacing: 8) {
                    Text("电压预设:").font(.caption).foregroundStyle(.secondary)
                    ForEach(["220", "380"], id: \.self) { v in
                        Button(v + "V") { voltage = v }
                            .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(voltage == v ? Color.orange : Color.gray.opacity(0.15))
                            .foregroundStyle(voltage == v ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text("功率因数:").font(.caption).foregroundStyle(.secondary)
                    ForEach(["0.80", "0.85", "0.90", "0.95"], id: \.self) { pf in
                        Button(pf) { powerFactor = pf }
                            .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(powerFactor == pf ? Color.orange : Color.gray.opacity(0.15))
                            .foregroundStyle(powerFactor == pf ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }

            Section("公式") {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if isThreePhase {
                            Text("I = P / (√3 × U × cosφ)").font(.system(.caption, design: .monospaced))
                            Text("P → W (kW × 1000)").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("I = P / (U × cosφ)").font(.system(.caption, design: .monospaced))
                            Text("P → W (kW × 1000)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("计算") { calc() }
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
        .navigationTitle("电流计算")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func calc() {
        guard let p = Double(power), p > 0,
              let v = Double(voltage), v > 0,
              let pf = Double(powerFactor), pf > 0, pf <= 1 else {
            resultText = "请输入有效数值"
            return
        }
        let pWatts = p * 1000
        let divisor = isThreePhase ? (sqrt(3) * v * pf) : (v * pf)
        let current = pWatts / divisor
        resultText = """
        功率: \(String(format: "%.2f", p)) kW
        电压: \(String(format: "%.0f", v)) V (\(isThreePhase ? "三相" : "单相"))
        电流: \(String(format: "%.2f", current)) A
        """
        saveHistory("\(String(format: "%.2f", current)) A")
    }

    private func saveHistory(_ r: String) {
        store.historyRecords.insert(HistoryRecord(tool: "电流计算", input: "\(power)kW / \(voltage)V", result: r, date: Formatters.now()), at: 0)
        store.scheduleSave()
    }
}
