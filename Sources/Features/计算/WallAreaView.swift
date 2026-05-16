import SwiftUI

struct WallAreaView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.wallL1) private var l1 = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallL2) private var l2 = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallL3) private var l3 = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallL4) private var l4 = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallHeight) private var height = "2.8"
    @AppStorage(UserPreferenceKeys.Calculator.wallDoors) private var doors = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallWindows) private var windows = ""
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("墙面尺寸 (m)") {
                LabeledContent("墙 1 长 (m)") { TextField("0", text: $l1.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                LabeledContent("墙 2 长 (m)") { TextField("0", text: $l2.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                LabeledContent("墙 3 长 (m)") { TextField("0", text: $l3.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                LabeledContent("墙 4 长 (m)") { TextField("0", text: $l4.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                LabeledContent("层高 (m)") { TextField("2.8", text: $height.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(height, min: 1.8, max: 20, hint: "请输入 1.8–20"))
                CalculatorPresetChips(title: "层高预设", options: ["2.6", "2.8", "3.0", "3.2", "3.6"], selection: $height)
                CalculatorValidationHint(message: wallLengthMessage)
            }
            Section("扣除面积 (m²)") {
                LabeledContent("门总面积 (m²)") { TextField("0", text: $doors.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                LabeledContent("窗总面积 (m²)") { TextField("0", text: $windows.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: optionalRangeMessage(doors, min: 0, max: 5000, hint: "请输入 0–5000"))
                CalculatorValidationHint(message: optionalRangeMessage(windows, min: 0, max: 5000, hint: "请输入 0–5000"))
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
                        title: "墙面面积结果",
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle("墙面面积").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
    }

    private func calc() {
        let walls = [l1, l2, l3, l4].compactMap { CalculatorInputParser.double($0) }.filter { $0 > 0 }
        guard let h = CalculatorInputParser.double(height), h > 0, !walls.isEmpty else {
            presentError("请至少输入一面墙长度")
            return
        }
        let perimeter = walls.reduce(0, +)
        let gross = perimeter * h
        let d = CalculatorInputParser.double(doors) ?? 0
        let w = CalculatorInputParser.double(windows) ?? 0
        let net = max(gross - d - w, 0)
        resultModel = .singleSection(
            headline: "净面积 \(fmt(net)) m²",
            formula: "净面积 = (墙体总周长×层高) - 门窗总面积",
            items: [
                CalculationResult.item("周长", "\(fmt(perimeter)) m"),
                CalculationResult.item("毛面积", "\(fmt(gross)) m²"),
                CalculationResult.item("扣除门窗", "\(fmt(d + w)) m²"),
                CalculationResult.item("净面积", "\(fmt(net)) m²", status: .pass),
            ]
        )
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
        store.appendCalculationHistory(
            tool: "墙面面积",
            input: "层高 \(height)m",
            result: r
        )
    }

    private var wallLengthMessage: String? {
        let values = [l1, l2, l3, l4]
            .compactMap { CalculatorInputParser.double($0) }
            .filter { $0 > 0 }
        return values.isEmpty ? "请至少输入一面墙长度（>0）" : nil
    }

    private func rangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.double(trimmed) else { return "请输入数值" }
        return (value >= min && value <= max) ? nil : hint
    }

    private func optionalRangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return rangeMessage(trimmed, min: min, max: max, hint: hint)
    }

    private func presentError(_ message: String) {
        result = message
        resultModel = .error(message)
    }
}
