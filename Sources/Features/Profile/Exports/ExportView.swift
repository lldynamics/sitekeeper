import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct ExportView: View {
    struct FilteredExportResult {
        var snapshot: BackupSnapshot
        var invalidDateCount: Int
    }

    @Environment(DataStore.self) var store
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State var exportFormat: ExportFormat = .csv
    @State var includeMaterials = true
    @State var includeQuotes = true
    @State var includeLabor = true
    @State var includeDailyLogs = true
    @State var includeProgress = true
    @State var includeTodos = true
    @State var includeProjectFinance = true
    @State var includeProjectDocuments = true
    @State var includeProjectContacts = true
    @State var includeProjectDrawings = true
    @State var includeWarehouseMovements = true
    @State var includeQuickNotes = true
    @State var includeOperationAuditLogs = false
    @State var filterProjectId: UUID?
    @State var enableDateFilter = false
    @State var filterStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State var filterEnd = Date()
    @State var payload: ExportPayload?
    @State var showExporter = false
    @State var showExportErrorAlert = false
    @State var exportErrorMessage = ""
    @AppStorage(UserPreferenceKeys.exportCurrencyDisplayMode) var currencyDisplayModeRaw = ExportCurrencyDisplayMode.defaultMode.rawValue
    let showsNavigationTitle: Bool
    let bottomContentInset: CGFloat
    let onMobileScrollOffsetChange: ((CGFloat) -> Void)?

    init(
        showsNavigationTitle: Bool = true,
        bottomContentInset: CGFloat = 0,
        onMobileScrollOffsetChange: ((CGFloat) -> Void)? = nil
    ) {
        self.showsNavigationTitle = showsNavigationTitle
        self.bottomContentInset = bottomContentInset
        self.onMobileScrollOffsetChange = onMobileScrollOffsetChange
    }
}

enum ExportFormat: String, CaseIterable {
    case csv
    case pdf
    case html

    var displayName: String {
        switch self {
        case .csv: AppLocalization.string("CSV（可用 Excel 打开）")
        case .pdf: "PDF"
        case .html: AppLocalization.string("HTML 网页")
        }
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .plainText, .commaSeparatedText, .pdf, .html, .zipArchive, .jpeg, .png] }
    var data: Data
    var sourceFileURL: URL?

    init(data: Data, sourceFileURL: URL? = nil) {
        self.data = data
        self.sourceFileURL = sourceFileURL
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        sourceFileURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let sourceFileURL,
           FileManager.default.fileExists(atPath: sourceFileURL.path) {
            return try FileWrapper(url: sourceFileURL, options: .immediate)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
