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
    var includeLightingCircuits = true
    var includePaymentRecords = true
}

struct ExportPayload {
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
    static var excelHTML: UTType {
        UTType(filenameExtension: "xls", conformingTo: .data) ?? .data
    }

    static var zipArchive: UTType {
        UTType.zip
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
    var date: String
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
