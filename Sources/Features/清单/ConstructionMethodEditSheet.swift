import SwiftUI
import PhotosUI
import UIKit

private let constructionMethodEditorDeleteUndoHint = String(localized: "删除后可在提示中撤销，附件会延迟清理。")

struct ConstructionMethodEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let method: ConstructionMethod?
    let draftScopeID: UUID
    let onSave: (ConstructionMethod) -> Void
    var onDelete: ((ConstructionMethod) -> Void)?

    @State var title: String
    @State var trade: String
    @State var versionName: String
    @State var publishStatus: ConstructionMethod.PublishStatus
    @State var tutorialBody: String
    @State var tutorialAttachments: [QuickNoteAttachment]
    @State var procedureSteps: [String]
    @State var qualityChecklist: [String]
    @State var safetyChecklist: [String]
    @State private var newProcedureStep = ""
    @State private var newQualityItem = ""
    @State private var newSafetyItem = ""
    @State var selectedTutorialMediaItems: [PhotosPickerItem] = []
    @State var showTutorialCamera = false
    @State var previewAttachment: QuickNoteAttachment?
    @State var isImportingTutorialMedia = false
    @State var tutorialMediaImportMessage = ""
    @State var alertMessage = ""
    @State var showAlert = false
    @State var showDeleteConfirm = false
    @State var sessionAddedFileNames: Set<String> = []
    @State var didSave = false
    @State var didRestoreDraft = false
    @State var draftSaveTask: Task<Void, Never>?

    init(method: ConstructionMethod?, onSave: @escaping (ConstructionMethod) -> Void, onDelete: ((ConstructionMethod) -> Void)? = nil) {
        self.method = method
        self.draftScopeID = method?.id ?? UUID()
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: method?.title ?? "")
        _trade = State(initialValue: method?.trade ?? "")
        _versionName = State(initialValue: method?.versionName ?? "V1")
        _publishStatus = State(initialValue: method?.publishStatus ?? .draft)
        _tutorialBody = State(initialValue: method?.tutorialBody ?? "")
        _tutorialAttachments = State(initialValue: method?.tutorialAttachments ?? [])
        _procedureSteps = State(initialValue: method?.procedureSteps ?? [])
        _qualityChecklist = State(initialValue: method?.qualityChecklist ?? [])
        _safetyChecklist = State(initialValue: method?.safetyChecklist ?? [])
    }

    var body: some View {
        AppBusinessEditForm(
            title: method == nil ? String(localized: "新增施工工艺") : String(localized: "编辑施工工艺"),
            isPrimaryActionDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onCancel: { cancelEditingAndDismiss() },
            onPrimaryAction: { saveAndDismiss() }
        ) {
            Form {
                basicInfoSection
                ConstructionMethodProcessEditorSections(
                    procedureSteps: $procedureSteps,
                    newProcedureStep: $newProcedureStep
                )
                tutorialSections
                ConstructionMethodQualityChecklistEditorSections(
                    qualityChecklist: $qualityChecklist,
                    safetyChecklist: $safetyChecklist,
                    newQualityItem: $newQualityItem,
                    newSafetyItem: $newSafetyItem
                )
            }
        }
        .onAppear {
            restoreDraftIfNeeded()
        }
        .onDisappear {
            draftSaveTask?.cancel()
            if didSave {
                ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                return
            }
            if hasDraftContent {
                persistDraftImmediately()
            } else {
                ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                    Array(sessionAddedFileNames),
                    summary: "constructionMethodEditor.sessionAddedFiles"
                )?.perform()
            }
        }
        .onChange(of: draftAutosaveFingerprint) { _, _ in
            scheduleDraftSave()
        }
        .onChange(of: scenePhase) { _, phase in
            guard !didSave else { return }
            if phase == .inactive || phase == .background {
                draftSaveTask?.cancel()
                persistDraftImmediately()
            }
        }
        .onChange(of: selectedTutorialMediaItems) { _, newItems in
            Task { await importTutorialMediaItems(newItems) }
        }
        .sheet(isPresented: $showTutorialCamera) {
            ImagePickerView(sourceType: .camera) { image in
                appendTutorialCameraImageAttachment(image)
            }
        }
        .sheet(item: $previewAttachment) { attachment in
            QuickNoteAttachmentPreview(attachment: attachment)
        }
        .toolbar {
            if method != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .alert(String(localized: "删除这条施工工艺？"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "删除"), role: .destructive) {
                deleteAndDismiss()
            }
        } message: {
            Text(constructionMethodEditorDeleteUndoHint)
        }
        .alert(String(localized: "无法添加媒体"), isPresented: $showAlert) {
            Button(String(localized: "知道了"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
}
