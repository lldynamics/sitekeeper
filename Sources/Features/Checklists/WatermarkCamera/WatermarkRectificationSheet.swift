import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WatermarkRectificationSheet: View {
    let photo: WatermarkCapturedPhoto
    let onSaved: (UUID) -> Void

    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var editorTarget: SiteTodo?
    @State private var afterPhotoData: Data?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var comparisonDocument: WatermarkComparisonDocument?
    @State private var showExporter = false

    init(photo: WatermarkCapturedPhoto, initialTodoId: UUID? = nil, onSaved: @escaping (UUID) -> Void) {
        self.photo = photo
        self.onSaved = onSaved
        _selectedID = State(initialValue: initialTodoId)
    }

    private var matchingTodos: [SiteTodo] {
        store.siteTodos.filter { $0.projectId == photo.projectId }
    }

    private var selectedTodo: SiteTodo? {
        matchingTodos.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(AppLocalization.string("选择同一项目的已有问题，将本次照片作为整改后证据。进入编辑页面核对并保存后才会关联。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(String(format: AppLocalization.string("拍摄归属：%@"), (photo.context.projectName ?? "").isEmpty ? AppLocalization.string("未关联项目") : (photo.context.projectName ?? "")))
                        .font(.caption)
                }
                if let selectedTodo {
                    Section(AppLocalization.string("整改前后对照")) {
                        comparisonPreview(for: selectedTodo)
                        Button(AppLocalization.string("导出对照图"), systemImage: "square.and.arrow.up") { exportComparison(for: selectedTodo) }
                            .disabled(selectedTodo.rectificationBeforePhotoFileName == nil || isPreparing)
                    }
                }
                Section(AppLocalization.string("已有问题")) {
                    if matchingTodos.isEmpty {
                        ContentUnavailableView(AppLocalization.string("暂无同项目问题"), systemImage: "checklist", description: Text(AppLocalization.string("请先在项目中建立整改事项。")))
                    }
                    ForEach(matchingTodos) { todo in
                        Button { selectedID = todo.id } label: {
                            HStack(spacing: 12) {
                                if let before = todo.rectificationBeforePhotoFileName {
                                    AsyncPhotoThumbnailImageView(fileName: before) { image in
                                        image.resizable().scaledToFill().frame(width: 48, height: 48).clipped()
                                    } placeholder: { Image(systemName: "photo").frame(width: 48, height: 48) }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(todo.title).foregroundStyle(.primary)
                                    if todo.rectificationAfterPhotoFileName != nil {
                                        Text(AppLocalization.string("已有整改后证据，请到原事项中核对")).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text(todo.owner.isEmpty ? (todo.isDone ? AppLocalization.string("已完成") : AppLocalization.string("待整改")) : todo.owner)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedID == todo.id { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                        .disabled(todo.rectificationAfterPhotoFileName != nil)
                        .accessibilityValue(todo.rectificationAfterPhotoFileName != nil ? AppLocalization.string("已有整改后证据，无法覆盖") : (selectedID == todo.id ? AppLocalization.string("已选择") : AppLocalization.string("未选择")))
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                if isPreparing { ProgressView(AppLocalization.string("正在准备照片…")) }
            }
            .navigationTitle(AppLocalization.string("关联已有整改"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string("关闭")) { dismiss() }.disabled(isPreparing) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("核对并保存")) { prepareEditor() }
                        .disabled(selectedTodo == nil || isPreparing || selectedTodo?.rectificationAfterPhotoFileName != nil)
                }
            }
            .sheet(item: $editorTarget) { todo in
                SiteTodoEditSheet(
                    todo: todo,
                    projects: store.projects.filter { $0.id == photo.projectId },
                    constructionMethods: store.constructionMethods,
                    initialProjectId: photo.projectId,
                    initialAfterPhotoData: afterPhotoData
                ) { saved in
                    // The editor calls this only after its draft transaction commits successfully.
                    guard saved.rectificationAfterPhotoFileName != nil else {
                        errorMessage = AppLocalization.string("事项已保存，但未保留整改后照片，本次照片仍在水印相机草稿中。")
                        return
                    }
                    onSaved(saved.id)
                    dismiss()
                }
            }
            .fileExporter(isPresented: $showExporter, document: comparisonDocument, contentType: .jpeg, defaultFilename: AppLocalization.string("整改前后对照")) { result in
                if case .failure(let error) = result { errorMessage = String(format: AppLocalization.string("导出失败：%@"), error.localizedDescription) }
            }
        }
        .interactiveDismissDisabled(isPreparing)
    }

    private func comparisonPreview(for todo: SiteTodo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                Text(AppLocalization.string("整改前")).font(.caption.weight(.semibold))
                if let name = todo.rectificationBeforePhotoFileName {
                    AsyncPhotoThumbnailImageView(fileName: name) { image in
                        image.resizable().scaledToFit().frame(maxHeight: 180)
                    } placeholder: { Image(systemName: "photo").frame(height: 100) }
                } else { Text(AppLocalization.string("未留存整改前照片")).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                Text(AppLocalization.string("本次整改后")).font(.caption.weight(.semibold))
                Image(uiImage: photo.thumbnail).resizable().scaledToFit().frame(maxHeight: 180)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private func prepareEditor() {
        guard let selectedTodo, selectedTodo.rectificationAfterPhotoFileName == nil else { return }
        isPreparing = true
        errorMessage = nil
        let capture = photo
        let todoID = selectedTodo.id
        Task { @MainActor in
            defer { isPreparing = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try capture.jpegDataForDelivery(compression: 0.9)
                }.value
                guard let current = store.siteTodos.first(where: { $0.id == todoID }),
                      WatermarkRectificationEligibility.accepts(current, projectID: capture.projectId) else {
                    errorMessage = AppLocalization.string("事项归属或整改证据已变化，请重新选择。")
                    return
                }
                afterPhotoData = data
                editorTarget = current
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func exportComparison(for todo: SiteTodo) {
        guard let beforeName = todo.rectificationBeforePhotoFileName else { return }
        let beforeURL = PhotoStorage.fileURL(for: beforeName)
        let capture = photo
        isPreparing = true
        errorMessage = nil
        Task { @MainActor in
            defer { isPreparing = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try WatermarkRectificationComparison.jpegData(beforeURL: beforeURL, after: capture, title: todo.title)
                }.value
                comparisonDocument = WatermarkComparisonDocument(data: data)
                showExporter = true
            } catch { errorMessage = String(format: AppLocalization.string("对照图准备失败：%@"), error.localizedDescription) }
        }
    }
}

struct WatermarkRectificationEligibility {
    static func accepts(_ todo: SiteTodo, projectID: UUID?) -> Bool {
        todo.projectId == projectID && todo.rectificationAfterPhotoFileName == nil
    }
}

private struct WatermarkComparisonDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.jpeg] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private enum WatermarkRectificationComparison {
    static func jpegData(beforeURL: URL, after: WatermarkCapturedPhoto, title: String) throws -> Data {
        guard let before = UIImage(contentsOfFile: beforeURL.path) else { throw WatermarkDraftImageError.missingImage }
        let afterImage = try after.imageForDelivery()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2200, height: 1800), format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 2200, height: 1800))
            (title as NSString).draw(in: CGRect(x: 60, y: 32, width: 2080, height: 100), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 44), .foregroundColor: UIColor.black
            ])
            for (label, source, x) in [(AppLocalization.string("整改前"), before, CGFloat(60)), (AppLocalization.string("整改后"), afterImage, CGFloat(1130))] {
                (label as NSString).draw(at: CGPoint(x: x, y: 145), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 36), .foregroundColor: UIColor.black
                ])
                let box = CGRect(x: x, y: 210, width: 1010, height: 1490)
                let scale = min(box.width / max(1, source.size.width), box.height / max(1, source.size.height))
                let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
                source.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
            }
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else { throw WatermarkDraftImageError.encodingFailed }
        return data
    }
}
