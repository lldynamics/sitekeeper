import SwiftUI

struct ConcreteCalcView: View {
    @Environment(DataStore.self) private var store
    @State private var length = "10"; @State private var width = "8"; @State private var thickness = "12"
    @State private var waste = "5"; @State private var grade: ConcreteGrade = .c25
    @State private var result = ""

    var body: some View {
        Form {
            Section("板面尺寸") {
                LabeledContent("长度 (m)") { TextField("10", text: $length).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("宽度 (m)") { TextField("8", text: $width).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("厚度 (cm)") { TextField("12", text: $thickness).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("损耗 (%)") { TextField("5", text: $waste).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Picker("标号", selection: $grade) {
                    ForEach(ConcreteGrade.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section { Button("估算") { calc() }.frame(maxWidth: .infinity).fontWeight(.semibold) }
            if !result.isEmpty {
                Section("结果") { Text(result).font(.system(.body, design: .monospaced)) }
            }
        }
        .navigationTitle("混凝土算量").navigationBarTitleDisplayMode(.inline)
    }

    private func calc() {
        guard let l = Double(length), l > 0, let w = Double(width), w > 0,
              let t = Double(thickness), t > 0, let ws = Double(waste), ws >= 0 else { result = "请输入有效数值"; return }
        let net = l * w * t / 100
        let total = net * (1 + ws / 100)
        let cement = total * grade.cementKgPerM3
        let sand = total * grade.sandM3PerM3
        let gravel = total * grade.gravelM3PerM3
        result = """
        净方量: \(fmt(net)) m³
        含损耗: \(fmt(total)) m³
        水泥: \(fmt(cement)) kg (\(Int(ceil(cement/50))) 袋)
        砂: \(fmt(sand)) m³
        碎石: \(fmt(gravel)) m³
        """
        saveHistory("净方量 \(fmt(net)) m³")
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 3
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func saveHistory(_ r: String) {
        store.historyRecords.insert(HistoryRecord(tool: "混凝土算量", input: "\(length)×\(width)m, \(thickness)cm, \(grade.displayName)", result: r, date: now()), at: 0)
        store.scheduleSave()
    }

    private func now() -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df.string(from: Date())
    }
}

enum ConcreteGrade: String, CaseIterable {
    case c20 = "C20"; case c25 = "C25"; case c30 = "C30"

    var displayName: String { rawValue }

    var cementKgPerM3: Double { switch self { case .c20: 320; case .c25: 350; case .c30: 380 } }
    var sandM3PerM3: Double { switch self { case .c20: 0.53; case .c25: 0.50; case .c30: 0.47 } }
    var gravelM3PerM3: Double { switch self { case .c20: 0.84; case .c25: 0.80; case .c30: 0.77 } }
}
