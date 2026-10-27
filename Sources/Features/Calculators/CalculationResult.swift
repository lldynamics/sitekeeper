import SwiftUI

struct CalculationResult {
    let headline: String
    let formula: String?
    let sections: [ResultSection]
    // A snapshot of the inputs used for this result; persisted only by an explicit save.
    var historyDraft: HistoryDraft?

    struct HistoryDraft: Equatable {
        let tool: String
        let input: String
        let result: String
    }

    struct ResultSection {
        let id = UUID()
        let title: String
        let items: [ResultItem]
    }

    struct ResultItem {
        let id = UUID()
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
        title: String = calculatorLoc("明细"),
        formula: String? = nil,
        items: [ResultItem]
    ) -> CalculationResult {
        CalculationResult(
            headline: headline,
            formula: formula,
            sections: [ResultSection(title: title, items: items)]
        )
    }

    static func error(_ message: String) -> CalculationResult {
        singleSection(
            headline: message,
            title: calculatorLoc("错误"),
            items: [item(calculatorLoc("提示"), message, status: .fail)]
        )
    }

    func plainText(title: String) -> String {
        var lines: [String] = []
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            lines.append("【\(cleanTitle)】")
        }
        if !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(headline)
        }
        if let formula, !formula.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(calculatorLocFormat("公式: %@", formula))
        }

        for section in sections {
            if !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("")
                lines.append(section.title)
            }
            for item in section.items {
                lines.append("\(item.label): \(item.value)")
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
