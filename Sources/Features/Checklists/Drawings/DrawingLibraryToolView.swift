import SwiftUI
import UniformTypeIdentifiers

struct DrawingLibraryToolView: View {
    @Environment(DataStore.self) var store
    @State var selectedProjectID: UUID?
    @State var quickLookURL: URL?
    @State var shareURL: URL?
    @State var shareDrawingID: UUID?
    @State var operationMessage: String?
    @State var showDrawingImporter = false
    @State var pendingImportURLs: [URL] = []
    @State var showImportProjectPicker = false
    @State var pendingImportProjectID: UUID?
    @State var pendingImportConflictNames: [String] = []
    @State var showImportStrategyDialog = false
    @State var searchText = ""
    @State var availabilityFilter: DrawingAvailabilityFilter = .all
    @State private var showHistoricalDrawings = false
    @AppStorage(UserPreferenceKeys.drawingLibraryRecentDrawingIDs) var recentDrawingIDsRaw = ""

    private static let drawingImportTypes: [UTType] = {
        var types: [UTType] = [.pdf, .zip]
        if let dwg = UTType(filenameExtension: "dwg") {
            types.append(dwg)
        }
        if let dxf = UTType(filenameExtension: "dxf") {
            types.append(dxf)
        }
        if !types.contains(.item) {
            types.append(.item)
        }
        return types
    }()

    var listModel: DrawingListViewModel {
        DrawingListViewModel(
            projects: store.projects,
            drawings: store.projectDrawings,
            selectedProjectID: selectedProjectID,
            searchText: searchText,
            recentDrawingIDs: DrawingListViewModel.recentDrawingIDs(from: recentDrawingIDsRaw),
            availabilityFilter: availabilityFilter
        )
    }

    private var importStrategyMessage: String {
        DrawingImportCoordinator.importStrategyMessage(for: pendingImportConflictNames)
    }

    private var drawingSearchSuggestions: [RealtimeSearchSuggestion] {
        listModel.filteredDrawings.prefix(8).map { drawing in
            RealtimeSearchSuggestion(
                id: "drawing-\(drawing.id.uuidString)",
                category: .drawing,
                entityId: drawing.id,
                title: drawing.name.isEmpty ? drawing.fileName : drawing.name,
                subtitleParts: [
                    listModel.projectName(for: drawing.projectId),
                    drawing.drawingNumber,
                    drawing.discipline,
                    drawing.floorArea
                ],
                score: drawing.isCurrentVersion ? 120 : 100
            )
        }
    }

    var body: some View {
        List {
            DrawingLibrarySearchSections(
                projects: store.projects,
                listModel: listModel,
                selectedProjectID: $selectedProjectID,
                searchText: $searchText,
                availabilityFilter: $availabilityFilter,
                suggestions: drawingSearchSuggestions,
                onSelectSuggestion: { suggestion in
                    guard let drawing = listModel.filteredDrawings.first(where: { $0.id == suggestion.entityId }) else { return }
                    openDrawing(drawing)
                },
                onScan: scanDrawingFileAvailability
            )

            if !listModel.recentDrawings.isEmpty {
                Section(AppLocalization.string("最近打开")) {
                    ForEach(listModel.recentDrawings.prefix(3)) { drawing in
                        drawingRow(drawing, showsProject: selectedProjectID == nil)
                    }
                }
            }

            Section(selectedProjectID == nil ? AppLocalization.string("图纸台账") : AppLocalization.string("项目图纸")) {
                if listModel.filteredDrawings.isEmpty {
                    DrawingLibraryEmptyState(
                        isFiltered: hasActiveListFilter,
                        onClearFilters: clearDrawingFilters,
                        onImport: beginImportDrawings
                    )
                } else {
                    ForEach(listModel.currentFilteredDrawings) { drawing in
                        drawingRow(drawing, showsProject: selectedProjectID == nil)
                    }
                    if !listModel.historicalFilteredDrawings.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHistoricalDrawings.toggle()
                            }
                        } label: {
                            HStack {
                                Label(
                                    String(
                                        format: AppLocalization.string("历史版本 (%lld)"),
                                        Int64(listModel.historicalFilteredDrawings.count)
                                    ),
                                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                                )
                                Spacer()
                                Image(systemName: showHistoricalDrawings ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if showHistoricalDrawings {
                            ForEach(listModel.historicalFilteredDrawings) { drawing in
                                drawingRow(drawing, showsProject: selectedProjectID == nil)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(AppLocalization.string("图纸台账"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            DrawingLibraryToolbar(onImport: beginImportDrawings)
        }
        .fileImporter(
            isPresented: $showDrawingImporter,
            allowedContentTypes: Self.drawingImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                handleImportedDrawings(urls)
            case .failure(let error):
                StorageIssueLog.recordEvent(
                    "drawing_library.import_picker_failed",
                    category: .fileStorage,
                    details: [
                        "source": "DrawingLibraryToolView.fileImporter"
                    ],
                    error: error
                )
                operationMessage = String(format: AppLocalization.string("图纸导入失败：%@"), error.localizedDescription)
            }
        }
        .confirmationDialog(AppLocalization.string("选择导入项目"), isPresented: $showImportProjectPicker, titleVisibility: .visible) {
            ForEach(store.projects) { project in
                Button(project.name) {
                    prepareImportDrawings(pendingImportURLs, projectId: project.id)
                }
            }
            Button(AppLocalization.string("取消"), role: .cancel) {
                pendingImportURLs.removeAll()
            }
        } message: {
            Text(AppLocalization.string("请选择图纸归属的项目。"))
        }
        .confirmationDialog(AppLocalization.string("同名图纸导入策略"), isPresented: $showImportStrategyDialog, titleVisibility: .visible) {
            ForEach(ProjectDrawingImportStrategy.allCases) { strategy in
                Button(strategy.displayName) {
                    applyImportStrategy(strategy)
                }
            }
            Button(AppLocalization.string("取消"), role: .cancel) {
                clearImportStrategyState()
            }
        } message: {
            Text(importStrategyMessage)
        }
        .appFilePreview($quickLookURL)
        .drawingLibrarySharePresenter(shareURL: $shareURL, shareDrawingID: $shareDrawingID, store: store)
        .operationToast(message: $operationMessage)
    }

    private var hasActiveListFilter: Bool {
        !listModel.normalizedSearchText.isEmpty || availabilityFilter != .all
    }

    private func drawingRow(_ drawing: ProjectDrawing, showsProject: Bool) -> some View {
        DrawingRow(
            drawing: drawing,
            projectName: showsProject ? listModel.projectName(for: drawing.projectId) : nil
        ) {
            openDrawing(drawing)
        }
    }
}
