import SwiftUI

struct WallAreaView: View {
    @Environment(DataStore.self) private var store
    @State private var l1 = ""; @State private var l2 = ""; @State private var l3 = ""; @State private var l4 = ""
    @State private var height = "2.8"
    @State private var doors = ""; @State private var windows = ""; @State private var result = ""

    var body: some View {
        Form {
            Section("墙面尺寸 (m)") {
                LabeledContent("墙 1 长") { TextField("0", text: $l1).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("墙 2 长") { TextField("0", text: $l2).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("墙 3 长") { TextField("0", text: $l3).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("墙 4 长") { TextField("0", text: $l4).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("层高 (m)") { TextField("2.8", text: $height).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section("扣除面积 (m²)") {
                LabeledContent("门总面积") { TextField("0", text: $doors).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("窗总面积") { TextField("0", text: $windows).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section { Button("计算") { calc() }.frame(maxWidth: .infinity).fontWeight(.semibold) }
            if !result.isEmpty {
                Section("结果") { Text(result).font(.system(.body, design: .monospaced)) }
            }
        }
        .navigationTitle("墙面面积").navigationBarTitleDisplayMode(.inline)
    }

    private func calc() {
        let walls = [l1, l2, l3, l4].compactMap { Double($0) }.filter { $0 > 0 }
        guard let h = Double(height), h > 0, !walls.isEmpty else { result = "请至少输入一面墙长度"; return }
        let perimeter = walls.reduce(0, +)
        let gross = perimeter * h
        let d = Double(doors) ?? 0
        let w = Double(windows) ?? 0
        let net = max(gross - d - w, 0)
        result = """
        周长: \(fmt(perimeter)) m
        毛面积: \(fmt(gross)) m²
        扣除门窗: \(fmt(d + w)) m²
        净面积: \(fmt(net)) m²
        """
        saveHistory("净面积 \(fmt(net)) m²")
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func saveHistory(_ r: String) {
        store.historyRecords.insert(HistoryRecord(tool: "墙面面积", input: "层高 \(height)m", result: r, date: now()), at: 0)
        store.scheduleSave()
    }
    private func now() -> String { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df.string(from: Date()) }
}
