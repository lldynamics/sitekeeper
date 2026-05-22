import SwiftUI
import UniformTypeIdentifiers

struct ProjectDetailDataManagementDestination: Identifiable, Hashable {
    let route: DataManagementRoute

    var id: DataManagementRoute { route }
}

struct ProjectDetailContainer: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    @Environment(FinanceStore.self) var financeStore
    @AppStorage(UserPreferenceKeys.useMetric) var useMetric = true
    let projectId: UUID
    let focus: ProjectDetailFocus?
    let autoOpenFinancialAdd: Bool
    let autoOpenDocumentScanSetup: Bool
    let autoOpenDeliveryGuide: Bool

    @State var exportState = ProjectDetailExportStateModel()
    @State var routeState: ProjectDetailRouteState
    @State var financeState = ProjectDetailFinanceState()
    @State var assetState = ProjectDetailAssetState()
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()

    @State var didAutoOpenFinancialAdd = false
    @State var didAutoOpenDocumentScanSetup = false
    @State var didAutoOpenDeliveryGuide = false
    @State var didOpenFocusedItem = false
    @State var showTodoFilterView = false
    @State var dataManagementDestination: ProjectDetailDataManagementDestination?

    init(
        projectId: UUID,
        initialMode: ProjectDetailMode? = nil,
        focus: ProjectDetailFocus? = nil,
        autoOpenFinancialAdd: Bool = false,
        autoOpenDocumentScanSetup: Bool = false,
        autoOpenDeliveryGuide: Bool = false
    ) {
        self.projectId = projectId
        self.focus = focus
        self.autoOpenFinancialAdd = autoOpenFinancialAdd
        self.autoOpenDocumentScanSetup = autoOpenDocumentScanSetup
        self.autoOpenDeliveryGuide = autoOpenDeliveryGuide
        _routeState = State(initialValue: ProjectDetailRouteState(mode: initialMode ?? .overview))
    }

    static let drawingImportTypes: [UTType] = {
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

    static let documentImportTypes: [UTType] = [.item]

    var drawingShareSheetPresented: Binding<Bool> {
        Binding(
            get: { assetState.drawingShareURL != nil },
            set: { isPresented in
                if !isPresented {
                    assetState.drawingShareURL = nil
                    assetState.drawingShareDrawingID = nil
                }
            }
        )
    }

    var project: Project? { projectStore.projects.first { $0.id == projectId } }

    var projectSnapshot: ProjectDetailSnapshot? {
        guard let project else { return nil }
        return ProjectDetailSnapshot(
            project: project,
            projectId: projectId,
            projectStore: projectStore,
            financeStore: financeStore
        )
    }

    var usesSingleCanvasLayoutOnPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var drawingImportConflictDialogMessage: String {
        let names = assetState.drawingImportConflictNames
        guard !names.isEmpty else {
            return String(localized: "检测到同名图纸，请选择导入策略。")
        }
        let preview = names.prefix(3).joined(separator: "、")
        if names.count > 3 {
            return String(
                format: String(localized: "检测到同名图纸：%@ 等 %lld 项，请选择导入策略。"),
                preview,
                Int64(names.count)
            )
        }
        return String(
            format: String(localized: "检测到同名图纸：%@，请选择导入策略。"),
            preview
        )
    }

    var body: some View {
        Group {
            if let snapshot = projectSnapshot {
                self.content(snapshot: snapshot)
            } else {
                ContentUnavailableView(String(localized: "项目不存在"), systemImage: "questionmark.folder")
            }
        }
    }
}

enum DetailSheet: String, Identifiable {
    case material, quote, log, labor
    var id: String { rawValue }
}
