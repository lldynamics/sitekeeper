import SwiftUI
import PhotosUI
import UIKit

struct DrawingLinkedTodoLabel: View {
    let todo: SiteTodo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(todo.title.isEmpty ? String(localized: "未命名待办") : todo.title)
            Text(todoSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var todoSummary: String {
        [
            todo.isDone ? String(localized: "已完成") : String(localized: "未完成"),
            todo.priority.displayName,
            todo.issueType.displayName,
            todo.dueDate
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: " · ")
    }
}

struct DrawingLinkedLogLabel: View {
    let log: DailyLog

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(log.date)
            Text(log.content.isEmpty ? String(localized: "未填写日志内容") : log.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

struct DrawingLinkedDocumentLabel: View {
    let document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(document.title.isEmpty ? document.fileName : document.title)
            Text(documentSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var documentSummary: String {
        [
            document.category.displayName,
            document.versionLabel,
            document.submissionStatus.displayName,
            document.formedAt
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: " · ")
    }
}

struct DrawingIssueTodoLabel: View {
    let todo: SiteTodo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : todo.isOverdue ? "exclamationmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? Color.appSuccess : todo.isOverdue ? Color.appRisk : Color.appWarning)
                Text(todo.title.isEmpty ? String(localized: "未命名待办") : todo.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                Spacer()
                Text(todo.priority.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appWarning)
            }
            FlowTagLine(tags: issueTags)
            if !todo.drawingIssueCloseEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(String(format: String(localized: "关闭证据: %@"), todo.drawingIssueCloseEvidence))
                    .font(.caption2)
                    .foregroundStyle(Color.appSuccess)
                    .lineLimit(2)
            }
            if !todo.note.isEmpty {
                Text(todo.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if todo.rectificationBeforePhotoFileName != nil || todo.rectificationAfterPhotoFileName != nil {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text(String(localized: "已附照片/截图"))
                }
                .font(.caption2)
                .foregroundStyle(Color.appDoc)
            }
        }
        .padding(.vertical, 2)
    }

    private var issueTags: [String] {
        [
            todo.isDone ? String(localized: "已完成") : String(localized: "未完成"),
            todo.owner.isEmpty ? "" : String(format: String(localized: "责任人 %@"), todo.owner),
            todo.dueDate.isEmpty ? "" : String(format: String(localized: "截止 %@"), todo.dueDate),
            todo.drawingIssueLocation.isEmpty ? "" : String(format: String(localized: "位置: %@"), todo.drawingIssueLocation),
            todo.drawingIssueLayerOrPage.isEmpty ? "" : String(format: String(localized: "图层/页码: %@"), todo.drawingIssueLayerOrPage),
            todo.drawingIssueMeasurement.isEmpty ? "" : String(format: String(localized: "测量: %@"), todo.drawingIssueMeasurement),
            todo.issueType.displayName
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct ProjectDrawingIssueSheet: View {
    @Environment(\.dismiss) private var dismiss
    let drawing: ProjectDrawing
    let onCreate: (SiteTodo) -> Void

    @State private var descriptionText = ""
    @State private var issueLocation = ""
    @State private var layerOrPage = ""
    @State private var measurementResult = ""
    @State private var closeEvidence = ""
    @State private var owner = ""
    @State private var dueDate = Date()
    @State private var priority: TodoPriority = .high
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoFileName: String?
    @State private var showImagePicker = false
    @State private var didCommit = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var photoImportTask: Task<Void, Never>?
    @State private var createdDraftPhotoFileNames: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "图纸问题单")) {
                    LabeledContent(String(localized: "图纸"), value: drawingTitle)
                    TextField(String(localized: "问题说明"), text: $descriptionText, axis: .vertical)
                        .lineLimit(3...8)
                    TextField(String(localized: "责任人"), text: $owner)
                    DatePicker(String(localized: "截止日期"), selection: $dueDate, displayedComponents: .date)
                    Picker(String(localized: "优先级"), selection: $priority) {
                        ForEach(TodoPriority.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }
                Section(String(localized: "定位与测量")) {
                    TextField(String(localized: "问题位置"), text: $issueLocation, axis: .vertical)
                        .lineLimit(1...3)
                    TextField(String(localized: "图层/页码"), text: $layerOrPage)
                    TextField(String(localized: "测量结果"), text: $measurementResult, axis: .vertical)
                        .lineLimit(1...4)
                    Text(String(localized: "drawing_issue_location_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section(String(localized: "照片/截图")) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(
                            photoFileName == nil ? String(localized: "添加照片/截图") : String(localized: "替换照片/截图"),
                            systemImage: "photo.on.rectangle"
                        )
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showImagePicker = true
                        } label: {
                            Label(String(localized: "拍照"), systemImage: "camera.fill")
                        }
                    }
                    if let photoFileName {
                        VStack(alignment: .leading, spacing: 8) {
                            AsyncPhotoThumbnailImageView(fileName: photoFileName) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(uiColor: .secondarySystemFill))
                                    .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 180)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            Button(String(localized: "移除"), role: .destructive) {
                                clearPhoto()
                            }
                            .font(.caption)
                        }
                    }
                }
                Section(String(localized: "关闭证据")) {
                    TextField(String(localized: "关闭证据（验收人/复测/照片说明）"), text: $closeEvidence, axis: .vertical)
                        .lineLimit(1...4)
                    Text(String(localized: "后续可在现场待办里补整改后照片，并用完成状态关闭问题。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text(String(localized: "问题单会进入现场待办，可用完成状态做闭环，不写入 DWG 红线。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "新建问题"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        didCommit = true
                        onCreate(makeTodo())
                        createdDraftPhotoFileNames.removeAll()
                        dismiss()
                    }
                    .disabled(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(sourceType: .camera) { image in
                    saveCameraImage(image)
                }
            }
            .alert(String(localized: "图纸问题单"), isPresented: $showAlert) {
                Button(String(localized: "知道了"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onChange(of: selectedPhotoItem) { _, item in
                photoImportTask?.cancel()
                photoImportTask = Task { await importSelectedPhoto(item) }
            }
            .onDisappear {
                photoImportTask?.cancel()
                photoImportTask = nil
                if !didCommit {
                    cleanupCreatedDraftPhotoFiles()
                }
            }
        }
    }

    private var drawingTitle: String {
        let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? drawing.fileName : name
    }

    private func makeTodo() -> SiteTodo {
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return SiteTodo(
            title: String(format: String(localized: "图纸问题: %@"), drawingTitle),
            owner: owner.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: Formatters.date.string(from: dueDate),
            priority: priority,
            issueType: .quality,
            drawingIssueLocation: issueLocation.trimmingCharacters(in: .whitespacesAndNewlines),
            drawingIssueLayerOrPage: layerOrPage.trimmingCharacters(in: .whitespacesAndNewlines),
            drawingIssueMeasurement: measurementResult.trimmingCharacters(in: .whitespacesAndNewlines),
            drawingIssueCloseEvidence: closeEvidence.trimmingCharacters(in: .whitespacesAndNewlines),
            rectificationBeforePhotoFileName: photoFileName,
            note: issueNoteText(description: text),
            projectId: drawing.projectId
        )
    }

    private func issueNoteText(description: String) -> String {
        [
            String(localized: "来源: 图纸问题单"),
            String(format: String(localized: "图纸: %@"), drawingTitle),
            String(format: String(localized: "版本: %@"), drawing.version),
            drawing.drawingNumber.isEmpty ? "" : String(format: String(localized: "图号: %@"), drawing.drawingNumber),
            drawing.floorArea.isEmpty ? "" : String(format: String(localized: "楼层/区域: %@"), drawing.floorArea),
            issueLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : String(format: String(localized: "位置: %@"), issueLocation.trimmingCharacters(in: .whitespacesAndNewlines)),
            layerOrPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : String(format: String(localized: "图层/页码: %@"), layerOrPage.trimmingCharacters(in: .whitespacesAndNewlines)),
            measurementResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : String(format: String(localized: "测量: %@"), measurementResult.trimmingCharacters(in: .whitespacesAndNewlines)),
            closeEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : String(format: String(localized: "关闭证据: %@"), closeEvidence.trimmingCharacters(in: .whitespacesAndNewlines)),
            description
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }

    private func saveCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.82) ?? image.pngData() else {
            alertMessage = String(localized: "图纸问题照片保存失败：图片数据不可用")
            showAlert = true
            return
        }
        Task { await savePhotoData(data) }
    }

    private func importSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let data: Data
        do {
            guard let loaded = try await item.loadTransferable(type: Data.self) else { return }
            data = loaded
        } catch {
            await MainActor.run {
                alertMessage = String(format: String(localized: "图纸问题照片导入失败：%@"), error.localizedDescription)
                showAlert = true
            }
            return
        }
        guard !Task.isCancelled else { return }
        await savePhotoData(data)
    }

    @MainActor
    private func savePhotoData(_ data: Data) async {
        let normalizedData = ImageDownsampleService.downsampledJPEGData(
            data,
            maxPixelSize: 1600,
            compressionQuality: 0.82
        ) ?? data
        let fileName = "drawing-issue-\(drawing.id.uuidString)-\(UUID().uuidString).jpg"
        let saved: String
        do {
            saved = try PhotoStorage.saveOrThrow(original: normalizedData, fileName: fileName)
        } catch {
            alertMessage = String(format: String(localized: "图纸问题照片保存失败：%@"), error.localizedDescription)
            showAlert = true
            return
        }
        deleteDraftPhotoIfNeeded(photoFileName)
        createdDraftPhotoFileNames.insert(saved)
        photoFileName = saved
        selectedPhotoItem = nil
    }

    private func clearPhoto() {
        deleteDraftPhotoIfNeeded(photoFileName)
        photoFileName = nil
    }

    private func deleteDraftPhotoIfNeeded(_ fileName: String?) {
        guard let fileName, createdDraftPhotoFileNames.remove(fileName) != nil else { return }
        DataStoreDeferredFileCleanup.photoFiles(
            [fileName],
            summary: "drawingIssue.draftPhoto"
        )?.perform()
    }

    private func cleanupCreatedDraftPhotoFiles() {
        let fileNames = createdDraftPhotoFileNames
        createdDraftPhotoFileNames.removeAll()
        DataStoreDeferredFileCleanup.photoFiles(
            Array(fileNames),
            summary: "drawingIssue.createdDraftPhotos"
        )?.perform()
    }
}
