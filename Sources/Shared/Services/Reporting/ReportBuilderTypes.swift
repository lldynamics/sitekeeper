import Foundation
import UniformTypeIdentifiers

struct ExportContentOptions {
    var includeMaterials = true
    var includeQuotes = true
    var includeLabor = true
    var includeDailyLogs = true
    var includeProgress = true
    var includeTodos = true
    var includeProjectFinance = true
    var includeProjectDocuments = true
    var includeProjectContacts = true
    var includeProjectDrawings = true
    var includeWarehouseMovements = true
    var includeQuickNotes = true
    var includeOperationAuditLogs = false
    var operationAuditEntries: [OperationAuditEntry] = []
    var currencyDisplayMode = ExportCurrencyDisplayMode.defaultMode
}

enum ExportCurrencyDisplayMode: String, CaseIterable, Identifiable, Codable {
    case cny
    case usd
    case eur
    case system
    case numberOnly = "number_only"

    static let defaultMode: ExportCurrencyDisplayMode = .cny

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cny:
            return AppLocalization.string("人民币（¥）")
        case .usd:
            return AppLocalization.string("美元（$）")
        case .eur:
            return AppLocalization.string("欧元（€）")
        case .system:
            return AppLocalization.string("跟随系统地区")
        case .numberOnly:
            return AppLocalization.string("仅数字")
        }
    }

    func format(decimal value: Decimal) -> String {
        let raw = Formatters.money(decimal: value)
        let symbol: String
        switch self {
        case .cny: symbol = "¥"
        case .usd: symbol = "$"
        case .eur: symbol = "€"
        case .numberOnly: return raw
        case .system:
            return value.formatted(.currency(code: Locale.autoupdatingCurrent.currency?.identifier ?? "CNY")
                .precision(.fractionLength(2)).locale(.autoupdatingCurrent))
        }
        return raw.hasPrefix("-") ? "-\(symbol)\(raw.dropFirst())" : symbol + raw
    }
}

struct ExportPayload: Sendable {
    var data: Data
    var sourceFileURL: URL?
    var contentType: UTType
    var defaultFilename: String

    init(data: Data, contentType: UTType, defaultFilename: String) {
        self.data = data
        self.sourceFileURL = nil
        self.contentType = contentType
        self.defaultFilename = defaultFilename
    }

    init(fileURL: URL, contentType: UTType, defaultFilename: String) {
        self.data = Data()
        self.sourceFileURL = fileURL
        self.contentType = contentType
        self.defaultFilename = defaultFilename
    }
}

extension UTType {
    static var zipArchive: UTType {
        UTType.zip
    }

    static var tabSeparatedText: UTType {
        UTType(filenameExtension: "tsv", conformingTo: .text) ?? .plainText
    }

    static var vCard: UTType {
        UTType(filenameExtension: "vcf", conformingTo: .data) ?? .data
    }
}

struct QuotationDocumentMeta {
    var companyName: String
    var companyPhone: String
    var companyAddress: String
    var customerName: String
    var projectAddress: String
    var validUntil: String
    var signerName: String
}

struct ReportPhotoItem {
    var date: BusinessDateValue
    var projectName: String
    var tag: String
    var note: String
    var fileName: String
}

enum ProjectPackageArchiveError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消交付包导出。"
        }
    }
}

struct ProjectPackageExportProgress {
    let completedSteps: Int
    let totalSteps: Int
    let currentItem: String

    var fractionCompleted: Double {
        guard totalSteps > 0 else { return 0 }
        return min(max(Double(completedSteps) / Double(totalSteps), 0), 1)
    }
}
