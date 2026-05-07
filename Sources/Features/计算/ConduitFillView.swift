import SwiftUI

struct ConduitFillView: View {
    @Environment(DataStore.self) private var store
    @State private var conduitInnerDia = "16"
    @State private var wireDia = "2.5"
    @State private var wireCount = "3"
    @State private var result = ""

    var body: some View {
        Form {
            Section("参数") {
                LabeledContent("线管内径 (mm)") { TextField("16", text: $conduitInnerDia).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("单根导线外径 (mm)") { TextField("2.5", text: $wireDia).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("导线根数") { TextField("3", text: $wireCount).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            }
            Section("参考") {
                Text("规范要求穿线率 ≤ 40%").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("计算") { calc() }.frame(maxWidth: .infinity).fontWeight(.semibold) }
            if !result.isEmpty {
                Section("结果") { Text(result).font(.system(.body, design: .monospaced)) }
            }
        }
        .navigationTitle("线管穿线率").navigationBarTitleDisplayMode(.inline)
    }

    private func calc() {
        guard let cd = Double(conduitInnerDia), cd > 0,
              let wd = Double(wireDia), wd > 0,
              let wc = Int(wireCount), wc > 0 else { result = "请输入有效数值"; return }
        let conduitArea = EngineeringCalculations.circleArea(diameter: cd)
        let wireArea = EngineeringCalculations.circleArea(diameter: wd) * Double(wc)
        let rate = EngineeringCalculations.conduitFillRate(conduitInnerDiameter: cd, wireDiameter: wd, wireCount: wc) * 100
        let recommended = EngineeringCalculations.recommendedConduitDiameter(wireDiameter: wd, wireCount: wc)
        result = """
        线管截面积: \(fmt(conduitArea)) mm²
        导线总截面积: \(fmt(wireArea)) mm²
        穿线率: \(fmt(rate)) %
        \(rate <= 40 ? "符合规范" : "超过 40%，请增大管径或减少根数")
        推荐管内径: \(recommended.map { "Φ\(fmt($0)) mm" } ?? "超出常用规格")
        """
        store.historyRecords.insert(HistoryRecord(tool: "线管穿线率", input: "Φ\(conduitInnerDia)mm, Φ\(wireDia)mm × \(wireCount)根", result: "\(fmt(rate))%", date: now()), at: 0)
        store.scheduleSave()
    }

    private func now() -> String { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df.string(from: Date()) }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 1; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
}
