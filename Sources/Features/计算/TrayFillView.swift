import SwiftUI

struct TrayFillView: View {
    @Environment(DataStore.self) private var store
    @State private var trayW = "200"; @State private var trayH = "100"
    @State private var cables: [CableEntry] = [CableEntry(odia: 12, count: 5), CableEntry(odia: 18, count: 3)]
    @State private var showAdd = false; @State private var newDia = ""; @State private var newCount = ""
    @State private var result = ""

    var body: some View {
        Form {
            Section("桥架尺寸 (mm)") {
                LabeledContent("宽") { TextField("200", text: $trayW).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("高") { TextField("100", text: $trayH).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section("电缆列表") {
                ForEach(cables.indices, id: \.self) { i in
                    HStack {
                        Text("Φ\(cables[i].odia, specifier: "%.0f")mm × \(cables[i].count) 根")
                        Spacer()
                        Button { cables.remove(at: i) } label: { Image(systemName: "trash").foregroundStyle(.red) }
                        .accessibilityLabel("删除此电缆")
                    }
                }
                Button { showAdd = true } label: { Label("添加电缆", systemImage: "plus") }
            }
            Section { Button("计算") { calc() }.frame(maxWidth: .infinity).fontWeight(.semibold) }
            if !result.isEmpty {
                Section("结果") { Text(result).font(.system(.body, design: .monospaced)) }
            }
        }
        .alert("添加电缆", isPresented: $showAdd) {
            TextField("外径 (mm)", text: $newDia)
            TextField("根数", text: $newCount)
            Button("取消", role: .cancel) { newDia = ""; newCount = "" }
            Button("添加") {
                if let d = Double(newDia), let c = Int(newCount), d > 0, c > 0 {
                    cables.append(CableEntry(odia: d, count: c))
                }
                newDia = ""; newCount = ""
            }
        }
        .navigationTitle("桥架填充率").navigationBarTitleDisplayMode(.inline)
    }

    private func calc() {
        guard let w = Double(trayW), w > 0, let h = Double(trayH), h > 0 else { result = "请输入有效桥架尺寸"; return }
        let trayArea = w * h
        let cableArea = cables.reduce(0.0) { $0 + EngineeringCalculations.cableArea(diameter: $1.odia, count: $1.count) }
        let rate = EngineeringCalculations.trayFillRate(width: w, height: h, cableArea: cableArea) * 100
        let recommended = EngineeringCalculations.recommendedTraySize(cableArea: cableArea)
        result = """
        桥架截面积: \(fmt(trayArea)) mm²
        电缆总截面积: \(fmt(cableArea)) mm²
        填充率: \(fmt(rate)) %
        \(rate <= 40 ? "符合规范" : "超过 40%，请增大桥架")
        推荐桥架: \(recommended.map { "\(fmt($0.width))×\(fmt($0.height)) mm" } ?? "超出常用规格")
        """
        store.historyRecords.insert(HistoryRecord(tool: "桥架填充率", input: "\(trayW)×\(trayH)mm, \(cables.count)种电缆", result: "\(fmt(rate))%", date: now()), at: 0)
        store.scheduleSave()
    }

    private func now() -> String { let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df.string(from: Date()) }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 1; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
}

struct CableEntry { var odia: Double; var count: Int }
