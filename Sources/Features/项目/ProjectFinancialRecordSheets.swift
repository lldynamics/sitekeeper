import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import PDFKit

struct ProjectFinancialRecordAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let onSave: (ProjectFinancialRecord, Bool) -> Void

    @State private var date = Date()
    @State private var direction: ProjectFinancialDirection = .expense
    @State private var category: ProjectFinancialCategory = ProjectFinancialDirection.expense.defaultCategory
    @State private var amount = ""
    @State private var counterparty = ""
    @State private var invoiceNumber = ""
    @State private var note = ""
    @State private var scanAfterSave = false

    private var availableCategories: [ProjectFinancialCategory] {
        ProjectFinancialCategory.allowed(for: direction)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账目") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("类型", selection: $direction) {
                        ForEach(ProjectFinancialDirection.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("分类", selection: $category) {
                        ForEach(availableCategories, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("金额", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("对方单位/个人", text: $counterparty)
                    TextField("发票号/收据号", text: $invoiceNumber)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("附件") {
                    Toggle("保存后立即扫描票据（可选）", isOn: $scanAfterSave)
                }
            }
            .navigationTitle("项目记账")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: direction) { _, newDirection in
                category = ProjectFinancialCategory.normalized(category, for: newDirection)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let record = ProjectFinancialRecord(
                            projectId: projectId,
                            date: Formatters.date.string(from: date),
                            direction: direction.rawValue,
                            category: category.rawValue,
                            amount: amount,
                            counterparty: counterparty,
                            invoiceNumber: invoiceNumber,
                            note: note
                        )
                        onSave(record, scanAfterSave)
                        dismiss()
                    }
                    .disabled(!InputValidator.nonNegativeNumber(amount) || ReportBuilder.number(amount) <= 0)
                }
            }
        }
    }
}

struct ProjectFinancialRecordEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: ProjectFinancialRecord
    let linkedAttachmentCount: Int
    let onSave: (ProjectFinancialRecord) -> Void
    let onDelete: (ProjectFinancialRecord) -> Void
    let onScan: (ProjectFinancialRecord) -> Void
    let onManageAttachments: (ProjectFinancialRecord) -> Void

    @State private var date: Date
    @State private var direction: ProjectFinancialDirection
    @State private var category: ProjectFinancialCategory
    @State private var amount: String
    @State private var counterparty: String
    @State private var invoiceNumber: String
    @State private var note: String
    @State private var showDeleteConfirm = false

    private var availableCategories: [ProjectFinancialCategory] {
        ProjectFinancialCategory.allowed(for: direction)
    }

    init(
        record: ProjectFinancialRecord,
        linkedAttachmentCount: Int,
        onSave: @escaping (ProjectFinancialRecord) -> Void,
        onDelete: @escaping (ProjectFinancialRecord) -> Void,
        onScan: @escaping (ProjectFinancialRecord) -> Void,
        onManageAttachments: @escaping (ProjectFinancialRecord) -> Void
    ) {
        self.record = record
        self.linkedAttachmentCount = linkedAttachmentCount
        self.onSave = onSave
        self.onDelete = onDelete
        self.onScan = onScan
        self.onManageAttachments = onManageAttachments
        let initialDirection = ProjectFinancialDirection(rawValue: record.direction) ?? .expense
        _date = State(initialValue: Formatters.date.date(from: record.date) ?? Date())
        _direction = State(initialValue: initialDirection)
        _category = State(initialValue: ProjectFinancialCategory.normalized(rawValue: record.category, for: initialDirection))
        _amount = State(initialValue: record.amount)
        _counterparty = State(initialValue: record.counterparty)
        _invoiceNumber = State(initialValue: record.invoiceNumber)
        _note = State(initialValue: record.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账目") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("类型", selection: $direction) {
                        ForEach(ProjectFinancialDirection.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("分类", selection: $category) {
                        ForEach(availableCategories, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("金额", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("对方单位/个人", text: $counterparty)
                    TextField("发票号/收据号", text: $invoiceNumber)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("票据") {
                    Button("补扫/追加票据") {
                        onScan(updatedRecord)
                    }
                    Button("管理票据附件（\(linkedAttachmentCount)）") {
                        onManageAttachments(updatedRecord)
                    }
                }
                Section {
                    Button("删除账目", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("编辑账目")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: direction) { _, newDirection in
                category = ProjectFinancialCategory.normalized(category, for: newDirection)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedRecord)
                        dismiss()
                    }
                    .disabled(!InputValidator.nonNegativeNumber(amount) || ReportBuilder.number(amount) <= 0)
                }
            }
            .alert("删除这条账目？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    onDelete(record)
                    dismiss()
                }
            }
        }
    }

    private var updatedRecord: ProjectFinancialRecord {
        var value = record
        value.date = Formatters.date.string(from: date)
        value.direction = direction.rawValue
        value.category = ProjectFinancialCategory.normalized(category, for: direction).rawValue
        value.amount = amount
        value.counterparty = counterparty
        value.invoiceNumber = invoiceNumber
        value.note = note
        return value
    }
}

struct ProjectFinancialAttachmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: ProjectFinancialRecord
    let documents: [ProjectDocument]
    let onDetach: (ProjectDocument) -> Void
    let onAttach: (ProjectDocument) -> Void
    let onBulkSetCategory: ([ProjectDocument], ProjectDocumentCategory) -> Void
    let onScan: () -> Void
    let onImportFiles: ([URL]) -> Void
    let onImportImage: (UIImage, String) -> Void

    @State private var showFileImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedLinkedDocumentIds: Set<UUID> = []
    @State private var selectedUnlinkedDocumentIds: Set<UUID> = []
    @State private var bulkCategory: ProjectDocumentCategory = .receipt
    @State private var previewURL: URL?

    private static let allowedImportTypes: [UTType] = [.item]

    private var linkedDocuments: [ProjectDocument] {
        let idSet = Set(record.linkedDocumentIds)
        return documents.filter { $0.linkedFinancialRecordId == record.id || idSet.contains($0.id) }
    }

    private var unlinkedDocuments: [ProjectDocument] {
        let linkedSet = Set(linkedDocuments.map(\.id))
        return documents.filter { !linkedSet.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedDocuments: [ProjectDocument] {
        let ids = selectedLinkedDocumentIds.union(selectedUnlinkedDocumentIds)
        return documents.filter { ids.contains($0.id) }
    }

    private var selectedDocumentURLs: [URL] {
        selectedDocuments.map { ProjectDocumentStorage.fileURL(for: $0.fileName) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selectedDocuments.isEmpty {
                    Section("选中操作") {
                        LabeledContent("已选附件", value: "\(selectedDocuments.count) 份")
                        Button {
                            previewURL = ProjectDocumentStorage.fileURL(for: selectedDocuments[0].fileName)
                        } label: {
                            Label("预览第一份", systemImage: "eye")
                        }
                        ShareLink(items: selectedDocumentURLs) {
                            Label("导出/分享选中附件", systemImage: "square.and.arrow.up")
                        }
                        Picker("批量分类", selection: $bulkCategory) {
                            ForEach(ProjectDocumentCategory.allCases, id: \.self) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        Button {
                            onBulkSetCategory(selectedDocuments, bulkCategory)
                            selectedLinkedDocumentIds.removeAll()
                            selectedUnlinkedDocumentIds.removeAll()
                        } label: {
                            Label("应用分类到选中附件", systemImage: "tag.fill")
                        }
                    }
                }

                Section("已关联附件 (\(linkedDocuments.count))") {
                    if linkedDocuments.isEmpty {
                        Text("暂无附件")
                            .foregroundStyle(.secondary)
                    } else {
                        if !selectedLinkedDocumentIds.isEmpty {
                            Button("移除选中 \(selectedLinkedDocumentIds.count) 项") {
                                for document in linkedDocuments where selectedLinkedDocumentIds.contains(document.id) {
                                    onDetach(document)
                                }
                                selectedLinkedDocumentIds.removeAll()
                            }
                            .font(.caption.weight(.semibold))
                        }
                        ForEach(linkedDocuments) { document in
                            ProjectFinancialAttachmentRow(
                                document: document,
                                isSelected: selectedLinkedDocumentIds.contains(document.id),
                                trailingTitle: "移除",
                                onToggleSelection: { toggleLinked(document.id) },
                                onAction: { onDetach(document) }
                            )
                        }
                    }
                }

                Section("新增附件") {
                    Button("扫描添加") {
                        onScan()
                    }
                    Button("从文件导入附件") {
                        showFileImporter = true
                    }
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("从相册选择照片", systemImage: "photo.on.rectangle")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("拍照保存") {
                            imagePickerSource = .camera
                            showImagePicker = true
                        }
                    }
                }

                Section("关联已有资料") {
                    if unlinkedDocuments.isEmpty {
                        Text("暂无可关联资料")
                            .foregroundStyle(.secondary)
                    } else {
                        if !selectedUnlinkedDocumentIds.isEmpty {
                            Button("关联选中 \(selectedUnlinkedDocumentIds.count) 项") {
                                for document in unlinkedDocuments where selectedUnlinkedDocumentIds.contains(document.id) {
                                    onAttach(document)
                                }
                                selectedUnlinkedDocumentIds.removeAll()
                            }
                            .font(.caption.weight(.semibold))
                        }
                        ForEach(unlinkedDocuments) { document in
                            ProjectFinancialAttachmentRow(
                                document: document,
                                isSelected: selectedUnlinkedDocumentIds.contains(document.id),
                                trailingTitle: "关联",
                                warning: document.linkedFinancialRecordId != nil && document.linkedFinancialRecordId != record.id ? "已关联其他账目，点击后将重新关联" : nil,
                                onToggleSelection: { toggleUnlinked(document.id) },
                                onAction: { onAttach(document) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("票据附件管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.allowedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                onImportFiles(urls)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: imagePickerSource) { image in
                onImportImage(image, "来源: 拍照")
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await importPhotoLibraryItem(item)
            }
        }
    }

    private func importPhotoLibraryItem(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            await MainActor.run {
                selectedPhotoItem = nil
            }
            return
        }
        await MainActor.run {
            if let image = UIImage(data: data) {
                onImportImage(image, "来源: 相册")
            }
            selectedPhotoItem = nil
        }
    }

    private func toggleLinked(_ id: UUID) {
        if selectedLinkedDocumentIds.contains(id) {
            selectedLinkedDocumentIds.remove(id)
        } else {
            selectedLinkedDocumentIds.insert(id)
        }
    }

    private func toggleUnlinked(_ id: UUID) {
        if selectedUnlinkedDocumentIds.contains(id) {
            selectedUnlinkedDocumentIds.remove(id)
        } else {
            selectedUnlinkedDocumentIds.insert(id)
        }
    }
}

private struct ProjectFinancialAttachmentRow: View {
    let document: ProjectDocument
    let isSelected: Bool
    let trailingTitle: String
    var warning: String?
    let onToggleSelection: () -> Void
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            ProjectDocumentPDFThumbnail(document: document)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(.callout.weight(.medium))
                Text(metaText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let warning {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(trailingTitle, action: onAction)
                .font(.caption.weight(.semibold))
        }
    }

    private var metaText: String {
        let fileType = document.fileType.isEmpty ? "附件" : document.fileType.uppercased()
        let pageText = document.fileType.lowercased() == "pdf" ? " · \(document.pageCount) 页" : ""
        return "\(document.category) · \(fileType)\(pageText) · \(document.createdAt)"
    }
}

private struct ProjectDocumentPDFThumbnail: View {
    let document: ProjectDocument

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackIcon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.blue.opacity(0.1))
            }
        }
        .frame(width: 44, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separator).opacity(0.35), lineWidth: 0.5))
    }

    private var thumbnail: UIImage? {
        guard let data = ProjectDocumentStorage.data(for: document.fileName) else { return nil }
        if document.fileType.lowercased() != "pdf", let image = UIImage(data: data) {
            return image
        }
        guard let pdf = PDFDocument(data: data),
              let page = pdf.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: 88, height: 108), for: .cropBox)
    }

    private var fallbackIcon: String {
        switch document.fileType.lowercased() {
        case "jpg", "jpeg", "png", "heic", "webp":
            return "photo"
        case "mov", "mp4", "m4v":
            return "video.fill"
        case "dwg", "dxf":
            return "ruler"
        case "xls", "xlsx", "csv", "numbers":
            return "tablecells"
        case "doc", "docx", "pages":
            return "doc.text"
        default:
            return ProjectDetailFinanceDocumentHelper.documentIcon(document.category)
        }
    }
}
