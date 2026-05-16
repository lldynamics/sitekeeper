import SwiftUI

struct TrayFillView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.trayWidth) private var trayW = "200"
    @AppStorage(UserPreferenceKeys.Calculator.trayHeight) private var trayH = "100"
    @AppStorage(UserPreferenceKeys.Calculator.trayCables) private var cablesDraft = ""
    @State private var cables: [CableEntry] = [CableEntry(odia: 12, count: 5), CableEntry(odia: 18, count: 3)]
    @State private var showAdd = false; @State private var newDia = ""; @State private var newCount = ""
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("桥架尺寸 (mm)") {
                LabeledContent("宽 (mm)") { TextField("200", text: $trayW.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(trayW, min: 50, max: 10_000, hint: "请输入 50–10000"))
                CalculatorPresetChips(title: "常用宽度", options: ["100", "150", "200", "300", "400", "600"], selection: $trayW)
                LabeledContent("高 (mm)") { TextField("100", text: $trayH.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(trayH, min: 30, max: 2000, hint: "请输入 30–2000"))
                CalculatorPresetChips(title: "常用高度", options: ["50", "75", "100", "150", "200"], selection: $trayH)
            }
            Section("电缆列表") {
                ForEach(cables.indices, id: \.self) { i in
                    HStack {
                        Text("Φ\(cables[i].odia, specifier: "%.0f")mm × \(cables[i].count) 根")
                        Spacer()
                        Button {
                            cables.remove(at: i)
                            persistCableDraft()
                        } label: { Image(systemName: "trash").foregroundStyle(.appRisk) }
                        .accessibilityLabel("删除此电缆")
                    }
                }
                Button { showAdd = true } label: { Label("添加电缆", systemImage: "plus") }
            }
            Section {
                Button("计算") {
                    isInputFocused = false
                    calc()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            if let resultModel {
                Section("结果") {
                    CalculatorResultCard(
                        title: "桥架填充率",
                        result: resultModel
                    )
                }
            }
        }
        .alert("添加电缆", isPresented: $showAdd) {
            TextField("外径 (mm)", text: $newDia.numericInput(.quantity)).keyboardType(.decimalPad).focused($isInputFocused)
            TextField("根数 (根)", text: $newCount.numericInput(.quantity)).keyboardType(.numberPad).focused($isInputFocused)
            Button("取消", role: .cancel) { newDia = ""; newCount = "" }
            Button("添加") {
                if let d = CalculatorInputParser.double(newDia),
                   let c = CalculatorInputParser.int(newCount),
                   d > 0, c > 0 {
                    cables.append(CableEntry(odia: d, count: c))
                    persistCableDraft()
                }
                newDia = ""; newCount = ""
            }
        }
        .navigationTitle("桥架填充率").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
        .onAppear(perform: restoreCableDraftIfNeeded)
    }

    private func calc() {
        guard let w = CalculatorInputParser.double(trayW),
              let h = CalculatorInputParser.double(trayH) else {
            presentError("请输入有效桥架尺寸")
            return
        }
        let trayArea = w * h
        var cableArea = 0.0
        for (index, cable) in cables.enumerated() {
            switch EngineeringCalculations.cableAreaValidated(diameter: cable.odia, count: cable.count) {
            case .success(let area):
                cableArea += area
            case .failure(let error):
                presentError("第\(index + 1)项电缆：\(error.userMessage)")
                return
            }
        }
        let fillRate: Double
        switch EngineeringCalculations.trayFillRateValidated(width: w, height: h, cableArea: cableArea) {
        case .success(let rate):
            fillRate = rate
        case .failure(let error):
            presentError(error.userMessage)
            return
        }
        let rate = fillRate * 100
        let recommended = EngineeringCalculations.recommendedTraySize(cableArea: cableArea)
        let pass = rate <= 40
        resultModel = .singleSection(
            headline: "填充率 \(fmt(rate))%",
            formula: "填充率 = (电缆总截面积 ÷ 桥架截面积)×100%",
            items: [
                CalculationResult.item("桥架截面积", "\(fmt(trayArea)) mm²"),
                CalculationResult.item("电缆总截面积", "\(fmt(cableArea)) mm²"),
                CalculationResult.item("规范校核", pass ? "符合规范（≤40%）" : "超出规范（>40%）", status: pass ? .pass : .warning),
                CalculationResult.item("推荐桥架", recommended.map { "\(fmt($0.width))×\(fmt($0.height)) mm" } ?? "超出常用规格", status: pass ? .normal : .warning),
            ]
        )
        result = """
        桥架截面积: \(fmt(trayArea)) mm²
        电缆总截面积: \(fmt(cableArea)) mm²
        填充率: \(fmt(rate)) %
        \(rate <= 40 ? "符合规范" : "超过 40%，请增大桥架")
        推荐桥架: \(recommended.map { "\(fmt($0.width))×\(fmt($0.height)) mm" } ?? "超出常用规格")
        """
        store.appendCalculationHistory(
            tool: "桥架填充率",
            input: "\(trayW)×\(trayH)mm, \(cables.count)种电缆",
            result: "\(fmt(rate))%"
        )
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 1; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func rangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.double(trimmed) else { return "请输入数值" }
        return (value >= min && value <= max) ? nil : hint
    }

    private func presentError(_ message: String) {
        result = message
        resultModel = .error(message)
    }

    private func restoreCableDraftIfNeeded() {
        guard !cablesDraft.isEmpty,
              let data = cablesDraft.data(using: .utf8) else {
            return
        }
        do {
            let decoded = try JSONDecoder().decode([CableEntry].self, from: data)
            guard !decoded.isEmpty else { return }
            cables = decoded
        } catch {
            StorageIssueLog.record("桥架填充草稿解析失败：\(error.localizedDescription)")
        }
    }

    private func persistCableDraft() {
        do {
            let data = try JSONEncoder().encode(cables)
            guard let encoded = String(data: data, encoding: .utf8) else {
                StorageIssueLog.record("桥架填充草稿编码后 UTF8 转换失败")
                return
            }
            cablesDraft = encoded
        } catch {
            StorageIssueLog.record("桥架填充草稿编码失败：\(error.localizedDescription)")
        }
    }
}

struct CableEntry: Codable { var odia: Double; var count: Int }
