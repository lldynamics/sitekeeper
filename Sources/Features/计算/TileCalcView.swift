import SwiftUI

struct TileCalcView: View {
    @Environment(DataStore.self) private var store
    @State private var rl = "6"; @State private var rw = "4"
    @State private var tl = "600"; @State private var tw = "600"
    @State private var waste = "8"; @State private var box = "4"
    @State private var result = ""

    var body: some View {
        Form {
            Section("房间") {
                LabeledContent("长度 (m)") { TextField("6", text: $rl).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("宽度 (m)") { TextField("4", text: $rw).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section("瓷砖") {
                LabeledContent("长度 (mm)") { TextField("600", text: $tl).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("宽度 (mm)") { TextField("600", text: $tw).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("损耗 (%)") { TextField("8", text: $waste).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("每箱片数") { TextField("4", text: $box).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section { Button("估算") { calc() }.frame(maxWidth: .infinity).fontWeight(.semibold) }
            if !result.isEmpty {
                Section("结果") { Text(result).font(.system(.body, design: .monospaced)) }
            }
        }
        .navigationTitle("地砖排料").navigationBarTitleDisplayMode(.inline)
    }

    private func calc() {
        guard let rl = Double(rl), rl > 0, let rw = Double(rw), rw > 0,
              let tl = Double(tl), tl > 0, let tw = Double(tw), tw > 0,
              let ws = Double(waste), ws >= 0, let bp = Double(box), bp > 0 else { result = "请输入有效数值"; return }
        let area = rl * rw
        let ra = area * (1 + ws / 100)
        let ta = (tl / 1000) * (tw / 1000)
        let count = Int(ceil(ra / ta))
        let boxes = Int(ceil(Double(count) / bp))
        result = """
        地面面积: \(fmt(area)) m²
        含损耗: \(fmt(ra)) m²
        需瓷砖: \(count) 片
        需箱数: \(boxes) 箱
        胶粘剂: \(fmt(ra * 5)) kg
        """
        saveHistory("\(count) 片 / \(boxes) 箱")
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 3
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func saveHistory(_ r: String) {
        store.historyRecords.insert(HistoryRecord(tool: "地砖排料", input: "\(rl)×\(rw)m, \(tl)×\(tw)mm", result: r, date: now()), at: 0)
        store.scheduleSave()
    }
    private func now() -> String { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df.string(from: Date()) }
}
