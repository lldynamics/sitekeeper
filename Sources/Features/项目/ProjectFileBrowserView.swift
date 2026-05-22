import SwiftUI
import QuickLook

struct ProjectFileBrowserView: View {
    @Environment(ProjectStore.self) var projectStore
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State var searchText = ""
    @State var debouncedSearchText = ""
    @State var searchResultIDs: [String] = []
    @State var searchResultByID: [String: ProjectFileSearchResult] = [:]
    @State var indexedDataSignature = 0
    @State var fileSearchService = ProjectFileSearchIndexService()
    @State var isBuildingFileIndex = false
    @State var isSearchingFiles = false
    @State var previewURL: URL?
    @State var selectedProjectId: UUID?
    @State var selectedCategory: ProjectFileCategory = .images
    @State var healthFilter: ProjectFileHealthFilter = .all
    @State var selectedSplitItemId: String?
    @State var deliveryInspectionExportPayload: ExportPayload?
    @State var showDeliveryInspectionExporter = false
    @State var operationNotice: OperationToastNotice?

    var body: some View {
        Group {
            if usesThreeColumnLayout {
                splitBrowserLayout
            } else {
                compactBrowserLayout
            }
        }
        .quickLookPreview($previewURL)
        .fileExporter(
            isPresented: $showDeliveryInspectionExporter,
            document: ExportDocument(data: deliveryInspectionExportPayload?.data ?? Data()),
            contentType: deliveryInspectionExportPayload?.contentType ?? .pdf,
            defaultFilename: deliveryInspectionExportPayload?.defaultFilename ?? String(localized: "交付体检清单.pdf")
        ) { result in
            switch result {
            case .success:
                AppHaptics.success()
                operationNotice = .info(String(localized: "已导出体检清单"))
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    AppHaptics.error()
                    operationNotice = .info(String(format: String(localized: "导出失败：%@"), error.localizedDescription))
                }
            }
            deliveryInspectionExportPayload = nil
        }
        .operationToast(notice: $operationNotice)
        .onAppear {
            syncSplitSelectionIfNeeded()
        }
        .task(id: fileSearchExecutionKey) {
            await runFileSearchTask(for: fileSearchExecutionKey.keyword)
        }
        .onChange(of: fileSearchDataSignature) { _, _ in
            syncSplitSelectionIfNeeded()
        }
        .onChange(of: filteredProjects.map(\.id)) { _, _ in
            syncSplitSelectionIfNeeded()
        }
        .onChange(of: selectedCategory) { _, _ in
            syncSplitSelectionIfNeeded()
        }
        .onChange(of: healthFilter) { _, _ in
            syncSplitSelectionIfNeeded()
        }
        .onDisappear {
            isSearchingFiles = false
        }
    }
}
