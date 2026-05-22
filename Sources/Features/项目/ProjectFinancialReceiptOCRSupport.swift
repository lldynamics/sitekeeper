import SwiftUI
import UniformTypeIdentifiers

struct ReceiptOCRAmountCandidatesView: View {
    let candidates: [ReceiptOCRAmountCandidate]
    let onApply: (ReceiptOCRAmountCandidate) -> Void

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: String(localized: "识别到 %lld 个金额候选，请点选确认："), Int64(candidates.count)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(candidates) { candidate in
                    HStack(alignment: .top, spacing: 6) {
                        Button {
                            onApply(candidate)
                        } label: {
                            Text(String(format: String(localized: "回填金额：%@"), candidate.amount))
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        Text(
                            String(
                                format: String(localized: "置信度：%lld%%"),
                                Int64(candidate.confidencePercent)
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Text(candidate.sourceLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

struct ProjectFinancialDuplicateWarningsSection: View {
    let warnings: [ProjectFinancialDuplicateWarning]

    var body: some View {
        Section(String(localized: "重复票据风险")) {
            Text(String(localized: "检测到当前票据可能已经入账，请确认后再保存。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(warnings.prefix(3)) { warning in
                VStack(alignment: .leading, spacing: 4) {
                    Label(warning.reasonText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appWarning)
                    Text(
                        String(
                            format: String(localized: "已有账目：%@"),
                            ProjectFinancialReceiptOCRSupport.duplicateRecordSummary(warning.record)
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if !warning.record.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(String(format: String(localized: "票号 %@"), warning.record.invoiceNumber))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

enum ProjectFinancialReceiptOCRSupport {
    static let allowedImportTypes: [UTType] = [.image, .pdf]

    static func ocrCandidates(from documents: [ProjectDocument]) -> [ProjectDocument] {
        documents
            .filter { isRecognizableDocument($0) }
            .sorted { lhs, rhs in
                let left = Formatters.parseDateOrDateTime(lhs.createdAt) ?? .distantPast
                let right = Formatters.parseDateOrDateTime(rhs.createdAt) ?? .distantPast
                return left > right
            }
    }

    static func summaryLines(from result: ReceiptOCRResult) -> [String] {
        var lines: [String] = []
        if let amount = result.amount, !amount.isEmpty {
            lines.append(String(format: String(localized: "金额：%@"), amount))
        }
        if let date = result.date, !date.isEmpty {
            lines.append(String(format: String(localized: "日期：%@"), date))
        }
        if let counterparty = result.counterparty, !counterparty.isEmpty {
            lines.append(String(format: String(localized: "单位：%@"), counterparty))
        }
        if let invoice = result.invoiceNumber, !invoice.isEmpty {
            lines.append(String(format: String(localized: "票号：%@"), invoice))
        }
        if lines.isEmpty {
            lines.append(String(localized: "未提取到结构化字段，可手动补录。"))
        }
        return lines
    }

    static func duplicateRecordSummary(_ record: ProjectFinancialRecord) -> String {
        let dateText = ProjectFinancialDuplicateDetector.normalizedDay(from: record.date) ?? record.date
        var parts = [
            dateText,
            record.normalizedDirection.displayName,
            ReportBuilder.money(record.amountValue.doubleValue)
        ]
        let party = record.counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        if !party.isEmpty {
            parts.append(party)
        }
        return parts.joined(separator: " · ")
    }

    static func duplicateConfirmationMessage(from warnings: [ProjectFinancialDuplicateWarning]) -> String {
        guard let first = warnings.first else { return "" }
        return String(
            format: String(localized: "%lld 条现有账目可能重复：%@"),
            Int64(warnings.count),
            duplicateRecordSummary(first.record)
        )
    }

    static func mergeDate(_ recognizedDay: Date, keepingTimeOf reference: Date) -> Date {
        let calendar = Calendar.current
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: recognizedDay)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: reference)
        dayComponents.hour = timeComponents.hour
        dayComponents.minute = timeComponents.minute
        return calendar.date(from: dayComponents) ?? recognizedDay
    }

    private static func isRecognizableDocument(_ document: ProjectDocument) -> Bool {
        let ext = normalizedExtension(for: document)
        if ext == "pdf" { return true }
        guard !ext.isEmpty,
              let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }

    private static func normalizedExtension(for document: ProjectDocument) -> String {
        let fileType = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !fileType.isEmpty { return fileType }
        return URL(fileURLWithPath: document.fileName).pathExtension.lowercased()
    }
}
