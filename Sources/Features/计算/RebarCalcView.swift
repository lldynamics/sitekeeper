import SwiftUI

struct RebarCalcView: View {
    @Environment(DataStore.self) private var store
    @State private var dia = "12"; @State private var len = "9"; @State private var qty = "30"
    @State private var price = ""; @State private var result = ""

    var body: some View {
        Form {
            Section("钢筋规格") {
                LabeledContent("直径 (mm)") { TextField("12", text: $dia).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("每根长 (m)") { TextField("9", text: $len).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("根数") { TextField("30", text: $qty).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("单价 (元/kg)") { TextField("选填", text: $price).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section { Button("估算") { calc() }.frame(maxWidth: .infinity).fontWeight(.semibold) }
            if !result.isEmpty {
                Section("结果") { Text(result).font(.system(.body, design: .monospaced)) }
            }
        }
        .navigationTitle("钢筋重量").navigationBarTitleDisplayMode(.inline)
    }

    private func calc() {
        guard let d = Double(dia), d > 0, let l = Double(len), l > 0, let q = Double(qty), q > 0 else { result = "请输入有效数值"; return }
        let uw = d * d / 162
        let tw = uw * l * q
        var lines = ["单位重: \(fmt(uw)) kg/m", "总重: \(fmt(tw)) kg", "吨位: \(fmt(tw/1000)) t"]
        if let p = Double(price), p > 0 { lines.append("造价: \(fmt(tw * p)) 元") }
        result = lines.joined(separator: "\n")
        saveHistory("总重 \(fmt(tw)) kg")
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 3
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func saveHistory(_ r: String) {
        store.historyRecords.insert(HistoryRecord(tool: "钢筋重量", input: "Φ\(dia)mm, \(len)m × \(qty)根", result: r, date: now()), at: 0)
        store.scheduleSave()
    }
    private func now() -> String { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df.string(from: Date()) }
}
