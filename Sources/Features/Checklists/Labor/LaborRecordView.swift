import SwiftUI

struct LaborRecordView: View {
    enum LaborFormField: Hashable {
        case workers
        case hours
        case unitRate
    }

    @Environment(DataStore.self) var store
    @AppStorage(UserPreferenceKeys.laborSavedTeams) var savedTeamsRaw = ""
    @AppStorage(UserPreferenceKeys.laborSavedWorkTypes) var savedWorkTypesRaw = ""
    let focusedLaborId: UUID?
    @State var searchText = ""
    @State var showAdd = false
    @State var editingRecord: LaborRecord?
    @State var didOpenFocusedLabor = false
    @State var newDate = Date()
    @State var newWorkers = ""
    @State var newDays = ""
    @State var newUnitRate = ""
    @State var newWorkType = ""
    @State var newTeamName = ""
    @State var newIsSettled = false
    @State var newNote = ""
    @State var newProjectId: UUID?
    @State var projectFilter: UUID?
    @State var settlementFilter: Bool? = nil
    @State var unitFilter: LaborUnitFilterChip = .all
    @State var pendingBulkUnit: LaborWorkloadUnit?
    @State var pendingBulkRecordIDs = Set<UUID>()
    @State var showBulkUnitConfirmation = false
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()
    @State var exportPayload: ExportPayload?
    @State var showExporter = false
    @State var exportProjectFilter: UUID?
    @State var exportTeamFilter = ""
    @State var exportWorkTypeFilter = ""
    @State var exportStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State var exportEndDate = Date()
    @State var showExportConfig = false
    @State var exportFormat: LaborExportFormat = .html

    init(focusedLaborId: UUID? = nil) {
        self.focusedLaborId = focusedLaborId
    }
}
