import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

private let constructionMethodEditorDeleteUndoHint = String(localized: "删除后可在提示中撤销，附件会延迟清理。")

struct ConstructionMethodEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let method: ConstructionMethod?
    private let draftScopeID: UUID
    let onSave: (ConstructionMethod) -> Void
    var onDelete: ((ConstructionMethod) -> Void)?

    @State private var title: String
    @State private var trade: String
    @State private var versionName: String
    @State private var publishStatus: ConstructionMethod.PublishStatus
    @State private var tutorialBody: String
    @State private var tutorialAttachments: [QuickNoteAttachment]
    @State private var procedureSteps: [String]
    @State private var qualityChecklist: [String]
    @State private var safetyChecklist: [String]
    @State private var newProcedureStep = ""
    @State private var newQualityItem = ""
    @State private var newSafetyItem = ""
    @State private var attachments: [QuickNoteAttachment]
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var selectedTutorialMediaItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showTutorialCamera = false
    @State private var previewAttachment: QuickNoteAttachment?
    @State private var isImportingMedia = false
    @State private var mediaImportMessage = ""
    @State private var isImportingTutorialMedia = false
    @State private var tutorialMediaImportMessage = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showDeleteConfirm = false
    @State private var sessionAddedFileNames: Set<String> = []
    @State private var didSave = false
    @State private var didRestoreDraft = false
    @State private var draftSaveTask: Task<Void, Never>?

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
        _attachments = State(initialValue: method?.attachments ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                processSections
                tutorialSections
                qualitySections
            }
            .navigationTitle(method == nil ? String(localized: "新增施工工艺") : String(localized: "编辑施工工艺"))
            .navigationBarTitleDisplayMode(.inline)
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
            .onChange(of: selectedMediaItems) { _, newItems in
                Task { await importMediaItems(newItems, target: .general) }
            }
            .onChange(of: selectedTutorialMediaItems) { _, newItems in
                Task { await importMediaItems(newItems, target: .tutorial) }
            }
            .sheet(isPresented: $showCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    appendImageAttachment(image)
                }
            }
            .sheet(isPresented: $showTutorialCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    appendTutorialImageAttachment(image)
                }
            }
            .sheet(item: $previewAttachment) { attachment in
                QuickNoteAttachmentPreview(attachment: attachment)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        draftSaveTask?.cancel()
                        if hasDraftContent {
                            persistDraftImmediately()
                        } else {
                            ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                        }
                        dismiss()
                    }
                }
                if method != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        draftSaveTask?.cancel()
                        didSave = true
                        onSave(updatedMethod)
                        ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(String(localized: "删除这条施工工艺？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    draftSaveTask?.cancel()
                    ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
                    if let target = method { onDelete?(target) }
                    dismiss()
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

    private var stepTemplates: [String] {
        [
            String(localized: "现场交底"),
            String(localized: "材料进场验收"),
            String(localized: "放线定位"),
            String(localized: "分步施工"),
            String(localized: "隐蔽验收"),
            String(localized: "成品保护")
        ]
    }

    private var basicInfoSection: some View {
        Section(String(localized: "工艺信息")) {
            TextField(String(localized: "标题"), text: $title)
            TextField(String(localized: "专业/工种"), text: $trade)
            TextField(String(localized: "版本号"), text: $versionName)
            Picker(String(localized: "发布状态"), selection: $publishStatus) {
                ForEach(ConstructionMethod.PublishStatus.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
    }

    private var processSections: some View {
        Group {
            Section(String(localized: "施工步骤")) {
                if procedureSteps.isEmpty {
                    Text(String(localized: "暂无步骤，先新增一条。"))
                        .foregroundStyle(.secondary)
                }
                ForEach(procedureSteps.indices, id: \.self) { index in
                    procedureStepRow(index)
                }
                addItemRow(
                    placeholder: String(localized: "新增步骤"),
                    text: $newProcedureStep,
                    onAdd: appendProcedureStep
                )
            }
            Section(String(localized: "常用步骤模板")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stepTemplates, id: \.self) { template in
                            Button(template) { applyStepTemplate(template) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var tutorialSections: some View {
        ConstructionMethodTutorialEditorSections(
            didRestoreDraft: didRestoreDraft,
            tutorialBody: $tutorialBody,
            selectedTutorialMediaItems: $selectedTutorialMediaItems,
            isImportingTutorialMedia: isImportingTutorialMedia,
            tutorialMediaImportMessage: tutorialMediaImportMessage,
            tutorialAttachments: tutorialAttachments,
            onInsertBlock: appendTutorialBlock,
            onOpenCamera: openTutorialCamera,
            onPreviewAttachment: { previewAttachment = $0 },
            onRemoveAttachment: removeTutorialAttachment
        )
    }

    private var qualitySections: some View {
        Group {
            Section(String(localized: "质量检查项")) {
                if qualityChecklist.isEmpty {
                    Text(String(localized: "暂无质量检查项。"))
                        .foregroundStyle(.secondary)
                }
                ForEach(qualityChecklist.indices, id: \.self) { index in
                    qualityItemRow(index)
                }
                addItemRow(
                    placeholder: String(localized: "新增质量检查项"),
                    text: $newQualityItem,
                    onAdd: appendQualityItem
                )
            }
            Section(String(localized: "安全注意项")) {
                if safetyChecklist.isEmpty {
                    Text(String(localized: "暂无安全注意项。"))
                        .foregroundStyle(.secondary)
                }
                ForEach(safetyChecklist.indices, id: \.self) { index in
                    safetyItemRow(index)
                }
                addItemRow(
                    placeholder: String(localized: "新增安全注意项"),
                    text: $newSafetyItem,
                    onAdd: appendSafetyItem
                )
            }
        }
    }

    private var hasDraftContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !procedureSteps.isEmpty
            || !qualityChecklist.isEmpty
            || !safetyChecklist.isEmpty
            || !attachments.isEmpty
            || !tutorialAttachments.isEmpty
    }

    private var draftAutosaveFingerprint: String {
        [
            title,
            trade,
            versionName,
            publishStatus.rawValue,
            tutorialBody,
            procedureSteps.joined(separator: "\n"),
            qualityChecklist.joined(separator: "\n"),
            safetyChecklist.joined(separator: "\n"),
            attachments.map(\.fileName).joined(separator: "|"),
            tutorialAttachments.map(\.fileName).joined(separator: "|")
        ].joined(separator: "||")
    }

    private var currentDraftSnapshot: ConstructionMethodEditDraft {
        ConstructionMethodEditDraft(
            title: title,
            trade: trade,
            versionName: versionName,
            publishStatus: publishStatus,
            tutorialBody: tutorialBody,
            tutorialAttachments: tutorialAttachments,
            procedureSteps: procedureSteps,
            qualityChecklist: qualityChecklist,
            safetyChecklist: safetyChecklist,
            attachments: attachments,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    private var updatedMethod: ConstructionMethod {
        var value = method ?? ConstructionMethod()
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.trade = trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVersion = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.versionName = normalizedVersion.isEmpty ? "V1" : normalizedVersion
        value.publishStatus = publishStatus
        value.tutorialBody = tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        value.tutorialTextSize = .normal
        value.tutorialAttachments = tutorialAttachments
        value.procedureSteps = normalizeList(procedureSteps)
        value.qualityChecklist = normalizeList(qualityChecklist)
        value.safetyChecklist = normalizeList(safetyChecklist)
        value.attachments = attachments
        value.updatedAt = Formatters.now()
        return value
    }

    private func applyStepTemplate(_ template: String) {
        let normalized = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !procedureSteps.contains(normalized) else { return }
        procedureSteps.append(normalized)
    }

    private func appendTutorialBlock(_ block: String) {
        let content = tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            tutorialBody = block
        } else if tutorialBody.hasSuffix("\n") {
            tutorialBody += block
        } else {
            tutorialBody += "\n\(block)"
        }
    }

    private func binding(for items: Binding<[String]>, index: Int) -> Binding<String> {
        Binding(
            get: {
                guard items.wrappedValue.indices.contains(index) else { return "" }
                return items.wrappedValue[index]
            },
            set: { newValue in
                guard items.wrappedValue.indices.contains(index) else { return }
                items.wrappedValue[index] = newValue
            }
        )
    }

    @ViewBuilder
    private func procedureStepRow(_ index: Int) -> some View {
        let canMoveUp = index > 0
        let canMoveDown = index < procedureSteps.count - 1
        checklistRow(
            title: String(format: String(localized: "步骤 %lld"), Int64(index + 1)),
            text: binding(for: $procedureSteps, index: index),
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onMoveUp: { moveProcedureStepUp(index) },
            onMoveDown: { moveProcedureStepDown(index) },
            onDelete: { removeProcedureStep(index) }
        )
    }

    @ViewBuilder
    private func qualityItemRow(_ index: Int) -> some View {
        let canMoveUp = index > 0
        let canMoveDown = index < qualityChecklist.count - 1
        checklistRow(
            title: String(format: String(localized: "检查项 %lld"), Int64(index + 1)),
            text: binding(for: $qualityChecklist, index: index),
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onMoveUp: { moveQualityItemUp(index) },
            onMoveDown: { moveQualityItemDown(index) },
            onDelete: { removeQualityItem(index) }
        )
    }

    @ViewBuilder
    private func safetyItemRow(_ index: Int) -> some View {
        let canMoveUp = index > 0
        let canMoveDown = index < safetyChecklist.count - 1
        checklistRow(
            title: String(format: String(localized: "注意项 %lld"), Int64(index + 1)),
            text: binding(for: $safetyChecklist, index: index),
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            onMoveUp: { moveSafetyItemUp(index) },
            onMoveDown: { moveSafetyItemDown(index) },
            onDelete: { removeSafetyItem(index) }
        )
    }

    private func checklistRow(
        title: String,
        text: Binding<String>,
        canMoveUp: Bool,
        canMoveDown: Bool,
        onMoveUp: @escaping () -> Void,
        onMoveDown: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(String(localized: "输入内容"), text: text, axis: .vertical)
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func addItemRow(
        placeholder: String,
        text: Binding<String>,
        onAdd: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
            }
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func appendProcedureStep() {
        let value = newProcedureStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        procedureSteps.append(value)
        newProcedureStep = ""
    }

    private func appendQualityItem() {
        let value = newQualityItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        qualityChecklist.append(value)
        newQualityItem = ""
    }

    private func appendSafetyItem() {
        let value = newSafetyItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        safetyChecklist.append(value)
        newSafetyItem = ""
    }

    private func moveProcedureStepUp(_ index: Int) {
        guard procedureSteps.indices.contains(index), index > 0 else { return }
        procedureSteps.swapAt(index, index - 1)
    }

    private func moveProcedureStepDown(_ index: Int) {
        guard procedureSteps.indices.contains(index), index < procedureSteps.count - 1 else { return }
        procedureSteps.swapAt(index, index + 1)
    }

    private func removeProcedureStep(_ index: Int) {
        guard procedureSteps.indices.contains(index) else { return }
        procedureSteps.remove(at: index)
    }

    private func moveQualityItemUp(_ index: Int) {
        guard qualityChecklist.indices.contains(index), index > 0 else { return }
        qualityChecklist.swapAt(index, index - 1)
    }

    private func moveQualityItemDown(_ index: Int) {
        guard qualityChecklist.indices.contains(index), index < qualityChecklist.count - 1 else { return }
        qualityChecklist.swapAt(index, index + 1)
    }

    private func removeQualityItem(_ index: Int) {
        guard qualityChecklist.indices.contains(index) else { return }
        qualityChecklist.remove(at: index)
    }

    private func moveSafetyItemUp(_ index: Int) {
        guard safetyChecklist.indices.contains(index), index > 0 else { return }
        safetyChecklist.swapAt(index, index - 1)
    }

    private func moveSafetyItemDown(_ index: Int) {
        guard safetyChecklist.indices.contains(index), index < safetyChecklist.count - 1 else { return }
        safetyChecklist.swapAt(index, index + 1)
    }

    private func removeSafetyItem(_ index: Int) {
        guard safetyChecklist.indices.contains(index) else { return }
        safetyChecklist.remove(at: index)
    }

    private func normalizeList(_ items: [String]) -> [String] {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showError(String(localized: "当前设备不可用相机。"))
            return
        }
        Task { @MainActor in
            guard await requestCameraAccessIfNeeded() else {
                showError(String(localized: "未获得相机权限，无法拍摄。"))
                return
            }
            showCamera = true
        }
    }

    private func openTutorialCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showError(String(localized: "当前设备不可用相机。"))
            return
        }
        Task { @MainActor in
            guard await requestCameraAccessIfNeeded() else {
                showError(String(localized: "未获得相机权限，无法拍摄。"))
                return
            }
            showTutorialCamera = true
        }
    }

    private func requestCameraAccessIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func appendImageAttachment(_ image: UIImage) {
        do {
            let fileName = try QuickNoteAttachmentStorage.saveImageOrThrow(image)
            attachments.append(QuickNoteAttachment(kind: .photo, fileName: fileName))
            sessionAddedFileNames.insert(fileName)
        } catch {
            showError(String(format: String(localized: "图片保存失败：%@"), error.localizedDescription))
        }
    }

    private func appendTutorialImageAttachment(_ image: UIImage) {
        do {
            let fileName = try QuickNoteAttachmentStorage.saveImageOrThrow(image)
            tutorialAttachments.append(QuickNoteAttachment(kind: .photo, fileName: fileName))
            sessionAddedFileNames.insert(fileName)
        } catch {
            showError(String(format: String(localized: "教程图片保存失败：%@"), error.localizedDescription))
        }
    }

    private func removeAttachment(_ attachment: QuickNoteAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        if sessionAddedFileNames.contains(attachment.fileName) {
            DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                [attachment.fileName],
                summary: "constructionMethodEditor.removeAttachment"
            )?.perform()
            sessionAddedFileNames.remove(attachment.fileName)
        }
    }

    private func removeTutorialAttachment(_ attachment: QuickNoteAttachment) {
        tutorialAttachments.removeAll { $0.id == attachment.id }
        if sessionAddedFileNames.contains(attachment.fileName) {
            DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                [attachment.fileName],
                summary: "constructionMethodEditor.removeTutorialAttachment"
            )?.perform()
            sessionAddedFileNames.remove(attachment.fileName)
        }
    }

    private enum MediaImportTarget {
        case general
        case tutorial
    }

    private func restoreDraftIfNeeded() {
        guard let draft = ConstructionMethodEditDraftStore.load(methodID: method?.id, scopeID: draftScopeID) else { return }
        title = draft.title
        trade = draft.trade
        versionName = draft.versionName
        publishStatus = draft.publishStatus
        tutorialBody = draft.tutorialBody
        tutorialAttachments = draft.tutorialAttachments
        procedureSteps = draft.procedureSteps
        qualityChecklist = draft.qualityChecklist
        safetyChecklist = draft.safetyChecklist
        attachments = draft.attachments
        didRestoreDraft = true
    }

    private func scheduleDraftSave() {
        guard hasDraftContent else {
            ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
            return
        }
        let snapshot = currentDraftSnapshot
        let methodID = method?.id
        let scopeID = draftScopeID
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            guard await DebouncedTask.wait(for: .milliseconds(350)) else { return }
            ConstructionMethodEditDraftStore.save(snapshot, methodID: methodID, scopeID: scopeID)
        }
    }

    private func persistDraftImmediately() {
        guard hasDraftContent else {
            ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
            return
        }
        let snapshot = currentDraftSnapshot
        ConstructionMethodEditDraftStore.save(snapshot, methodID: method?.id, scopeID: draftScopeID)
    }

    private func importMediaItems(_ items: [PhotosPickerItem], target: MediaImportTarget) async {
        guard !items.isEmpty else { return }
        await MainActor.run {
            switch target {
            case .general:
                isImportingMedia = true
                mediaImportMessage = String(localized: "正在导入媒体...")
            case .tutorial:
                isImportingTutorialMedia = true
                tutorialMediaImportMessage = String(localized: "正在导入教程媒体...")
            }
        }
        defer {
            Task { @MainActor in
                switch target {
                case .general:
                    isImportingMedia = false
                    mediaImportMessage = ""
                    selectedMediaItems = []
                case .tutorial:
                    isImportingTutorialMedia = false
                    tutorialMediaImportMessage = ""
                    selectedTutorialMediaItems = []
                }
            }
        }

        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
                await MainActor.run {
                    switch target {
                    case .general:
                        mediaImportMessage = String(localized: "检查视频大小和时长...")
                    case .tutorial:
                        tutorialMediaImportMessage = String(localized: "检查视频大小和时长...")
                    }
                }
                do {
                    guard let transfer = try await item.loadTransferable(type: QuickNoteVideoTransfer.self) else {
                        await MainActor.run { showError(String(localized: "视频导入失败。")) }
                        continue
                    }
                    await MainActor.run {
                        _ = QuickNoteAttachmentStorage.videoThumbnail(for: transfer.fileName)
                        let attachment = QuickNoteAttachment(
                            kind: .video,
                            fileName: transfer.fileName,
                            originalName: transfer.originalName,
                            durationSeconds: transfer.durationSeconds
                        )
                        switch target {
                        case .general:
                            attachments.append(attachment)
                        case .tutorial:
                            tutorialAttachments.append(attachment)
                        }
                        sessionAddedFileNames.insert(transfer.fileName)
                    }
                } catch let error as QuickNoteVideoTransferError {
                    await MainActor.run { showError(error.userMessage) }
                } catch {
                    await MainActor.run { showError(String(localized: "视频导入失败。")) }
                }
                continue
            }

            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run { showError(String(localized: "有一项图片导入失败。")) }
                continue
            }
            await MainActor.run {
                switch target {
                case .general:
                    appendImageAttachment(image)
                case .tutorial:
                    appendTutorialImageAttachment(image)
                }
            }
        }
    }

    private func showError(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}
