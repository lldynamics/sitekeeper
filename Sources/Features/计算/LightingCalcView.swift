import SwiftUI

struct LightingCalcView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.lightingRoomLength) private var roomLength: String = "6"
    @AppStorage(UserPreferenceKeys.Calculator.lightingRoomWidth) private var roomWidth: String = "4"
    @AppStorage(UserPreferenceKeys.Calculator.lightingTargetLux) private var targetLux: String = "300"
    @AppStorage(UserPreferenceKeys.Calculator.lightingLumensPerFixture) private var lumensPerFixture: String = "2400"
    @AppStorage(UserPreferenceKeys.Calculator.lightingUtilizationFactor) private var utilizationFactor: String = "0.6"
    @AppStorage(UserPreferenceKeys.Calculator.lightingMaintenanceFactor) private var maintenanceFactor: String = "0.8"

    @State private var resultText: String = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("房间参数") {
                LabeledContent("长度 (m)") {
                    TextField("6", text: $roomLength)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(roomLength, min: 0.5, max: 10_000, hint: "请输入 0.5–10000"))
                CalculatorPresetChips(title: "长度预设", options: ["4", "6", "8", "10", "12"], selection: $roomLength)
                LabeledContent("宽度 (m)") {
                    TextField("4", text: $roomWidth)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(roomWidth, min: 0.5, max: 10_000, hint: "请输入 0.5–10000"))
                CalculatorPresetChips(title: "宽度预设", options: ["3", "4", "5", "6", "8"], selection: $roomWidth)
            }
            Section("照明要求") {
                LabeledContent("目标照度 (lux)") {
                    TextField("300", text: $targetLux)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(targetLux, min: 50, max: 2000, hint: "请输入 50–2000"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(RoomType.presets) { preset in
                            Button(preset.name) {
                                targetLux = String(preset.lux)
                            }
                            .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(targetLux == String(preset.lux) ? Color.appPrimaryAction : Color(uiColor: .tertiarySystemGroupedBackground))
                            .foregroundStyle(targetLux == String(preset.lux) ? .white : .primary)
                            .clipShape(Capsule())
                        }
                    }
                }
                LabeledContent("单灯光通量 (lm)") {
                    TextField("2400", text: $lumensPerFixture)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(lumensPerFixture, min: 100, max: 200_000, hint: "请输入 100–200000"))
                CalculatorPresetChips(title: "常用光通量", options: ["1200", "1800", "2400", "3200", "4000"], selection: $lumensPerFixture)
                LabeledContent("利用系数 (0-1)") {
                    TextField("0.6", text: $utilizationFactor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(utilizationFactor, min: 0.1, max: 1, hint: "请输入 0.1–1"))
                CalculatorPresetChips(title: "利用系数", options: ["0.50", "0.60", "0.70", "0.80"], selection: $utilizationFactor)
                LabeledContent("维护系数 (0-1)") {
                    TextField("0.8", text: $maintenanceFactor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(maintenanceFactor, min: 0.1, max: 1, hint: "请输入 0.1–1"))
                CalculatorPresetChips(title: "维护系数", options: ["0.70", "0.80", "0.90"], selection: $maintenanceFactor)
            }

            Section {
                Button("估算") {
                    isInputFocused = false
                    calc()
                }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }

            if let resultModel {
                Section("估算结果") {
                    CalculatorResultCard(
                        title: "照明估算结果",
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle("照明估算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
    }

    private func calc() {
        guard let l = CalculatorInputParser.double(roomLength), l > 0,
              let w = CalculatorInputParser.double(roomWidth), w > 0,
              let lux = CalculatorInputParser.double(targetLux), lux > 0,
              let lumen = CalculatorInputParser.double(lumensPerFixture), lumen > 0,
              let uf = CalculatorInputParser.double(utilizationFactor), uf > 0, uf <= 1,
              let mf = CalculatorInputParser.double(maintenanceFactor), mf > 0, mf <= 1 else {
            presentError("请输入有效数值")
            return
        }
        let area = l * w
        let totalLumens = area * lux / (uf * mf)
        let count = Int(ceil(totalLumens / lumen))
        let perArea = Double(count) / area
        resultModel = .singleSection(
            headline: "建议 \(count) 盏",
            formula: "需总光通量 = 面积×照度 ÷ (利用系数×维护系数)",
            items: [
                CalculationResult.item("房间面积", "\(String(format: "%.2f", area)) m²"),
                CalculationResult.item("总光通量需求", "\(String(format: "%.0f", totalLumens)) lm"),
                CalculationResult.item("每平米灯具数量", "\(String(format: "%.1f", perArea)) 盏", status: .pass),
            ]
        )

        resultText = """
        房间面积: \(String(format: "%.2f", area)) m²
        总光通量需求: \(String(format: "%.0f", totalLumens)) lm
        需要灯具: \(count) 盏
        每平米: \(String(format: "%.1f", perArea)) 盏
        """
        saveHistory("\(count) 盏")
    }

    private func saveHistory(_ r: String) {
        store.appendCalculationHistory(
            tool: "照明估算",
            input: "\(roomLength)×\(roomWidth)m, \(targetLux)lux",
            result: r
        )
    }

    private func rangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.double(trimmed) else { return "请输入数值" }
        return (value >= min && value <= max) ? nil : hint
    }

    private func presentError(_ message: String) {
        resultText = message
        resultModel = .error(message)
    }
}

struct RoomType: Identifiable {
    let id = UUID()
    let name: String
    let lux: Int

    static let presets: [RoomType] = [
        RoomType(name: "办公室", lux: 300),
        RoomType(name: "教室", lux: 300),
        RoomType(name: "车间", lux: 200),
        RoomType(name: "仓库", lux: 150),
        RoomType(name: "走廊", lux: 100),
        RoomType(name: "商场", lux: 500),
    ]
}
