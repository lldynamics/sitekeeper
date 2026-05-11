import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum CalculatorInputParser {
    static func double(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    static func int(_ value: String) -> Int? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Int(normalized)
    }
}

struct CalculatorValidationHint: View {
    let message: String?

    var body: some View {
        if let message, !message.isEmpty {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(message)
                .accessibilityHint("输入校验提示")
        }
    }
}

struct CalculatorPresetChips: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button(option) {
                            selection = option
                            AppHaptics.impact(.light, intensity: 0.65)
                        }
                        .font(.caption2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selection == option ? Color.appPrimaryAction : Color(uiColor: .secondarySystemGroupedBackground))
                        .foregroundStyle(selection == option ? .white : .primary)
                        .clipShape(Capsule())
                        .accessibilityLabel("\(title) \(option)")
                        .accessibilityValue(selection == option ? "已选中" : "未选中")
                        .accessibilityHint("双击切换")
                    }
                }
            }
        }
    }
}

struct CalculationResult {
    let headline: String
    let sections: [ResultSection]

    struct ResultSection {
        let title: String
        let items: [ResultItem]
    }

    struct ResultItem {
        let label: String
        let value: String
        let status: ResultStatus
    }

    enum ResultStatus: Equatable {
        case normal
        case pass
        case warning
        case fail

        var valueColor: Color {
            switch self {
            case .normal:
                return .primary
            case .pass:
                return .appSuccess
            case .warning:
                return .appPrimaryAction
            case .fail:
                return .appRisk
            }
        }

        var rowBackgroundColor: Color {
            switch self {
            case .normal:
                return Color.clear
            case .pass:
                return .appSuccessSurfaceSubtle
            case .warning:
                return .appPrimarySurface
            case .fail:
                return .appRiskSurface
            }
        }
    }

    var primaryStatus: ResultStatus {
        if sections.contains(where: { $0.items.contains(where: { $0.status == .fail }) }) {
            return .fail
        }
        if sections.contains(where: { $0.items.contains(where: { $0.status == .warning }) }) {
            return .warning
        }
        if sections.contains(where: { $0.items.contains(where: { $0.status == .pass }) }) {
            return .pass
        }
        return .normal
    }

    static func item(
        _ label: String,
        _ value: String,
        status: ResultStatus = .normal
    ) -> ResultItem {
        ResultItem(label: label, value: value, status: status)
    }

    static func singleSection(
        headline: String,
        title: String = "明细",
        items: [ResultItem]
    ) -> CalculationResult {
        CalculationResult(
            headline: headline,
            sections: [ResultSection(title: title, items: items)]
        )
    }

    static func error(_ message: String) -> CalculationResult {
        singleSection(
            headline: message,
            title: "错误",
            items: [item("提示", message, status: .fail)]
        )
    }
}

struct CalculatorResultCard: View {
    let title: String
    let result: CalculationResult
    let copyText: String

    @State private var copied = false

    init(
        title: String,
        result: CalculationResult,
        copyText: String
    ) {
        self.title = title
        self.result = result
        self.copyText = copyText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            HStack(spacing: AppSpacing.tight) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Button {
                    copyToClipboard()
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.appSuccess : Color.secondary)
                .accessibilityLabel(copied ? "已复制结果" : "复制结果")
                .accessibilityHint("将计算结果复制到剪贴板")
            }

            if !result.headline.isEmpty {
                Text(result.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(result.primaryStatus.valueColor)
            }

            VStack(alignment: .leading, spacing: AppSpacing.normal) {
                ForEach(Array(result.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: AppSpacing.tight) {
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                                    Text(item.label)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 8)
                                    HStack(spacing: 6) {
                                        if item.status != .normal {
                                            Circle()
                                                .fill(item.status.valueColor)
                                                .frame(width: 6, height: 6)
                                        }
                                        Text(item.value)
                                            .font(.system(.footnote, design: .monospaced))
                                            .foregroundStyle(item.status.valueColor)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(item.status.rowBackgroundColor)
                                )
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(item.label)，\(item.value)")
                                .accessibilityValue(accessibilityStatus(item.status))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(result.primaryStatus.cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(result.primaryStatus.cardStrokeColor, lineWidth: 1)
        )
    }

    @MainActor
    private func copyToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = copyText
        AppHaptics.success()
        #endif
        withAnimation(.easeOut(duration: 0.18)) {
            copied = true
        }
        Task { @MainActor in
            guard await DebouncedTask.wait(for: .seconds(1.2)) else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                copied = false
            }
        }
    }

    private func accessibilityStatus(_ status: CalculationResult.ResultStatus) -> String {
        switch status {
        case .normal:
            return "普通结果"
        case .pass:
            return "通过"
        case .warning:
            return "关注"
        case .fail:
            return "不通过"
        }
    }
}

private extension CalculationResult.ResultStatus {
    var cardBackgroundColor: Color {
        switch self {
        case .normal:
            return Color(uiColor: .secondarySystemGroupedBackground)
        case .pass:
            return .appSuccessSurfaceSubtle
        case .warning:
            return .appPrimarySurface
        case .fail:
            return .appRiskSurface
        }
    }

    var cardStrokeColor: Color {
        switch self {
        case .normal:
            return .appStrokeSecondary
        case .pass:
            return .appStrokeSuccess
        case .warning:
            return .appStrokeWarning
        case .fail:
            return .appStrokeError
        }
    }
}
