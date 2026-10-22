import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import PDFKit

struct ProjectFinancialAttachmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: ProjectFinancialRecord
    let documents: [ProjectDocument]
    let onDetach: (ProjectDocument) -> Void
    let onAttach: (ProjectDocument) -> Void
    let onBulkSetCategory: ([ProjectDocument], ProjectDocumentCategory) -> Void
    let onScan: () -> Void
    let onImportFiles: ([URL], ProjectDocumentImportLedgerSettings) -> Void
    let onImportImage: (UIImage, String) -> Void

    @State private var showFileImporter = false
    @State private var pendingDocumentImportRequest: ProjectDocumentImportConfirmationRequest?
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
        return documents.filter { !linkedSet.contains($0.id) }.sorted { Formatters.isLater($0.createdAt, than: $1.createdAt) }
    }

    private var selectedDocuments: [ProjectDocument] {
        let ids = selectedLinkedDocumentIds.union(selectedUnlinkedDocumentIds)
        return documents.filter { ids.contains($0.id) }
    }

    private var selectedDocumentURLs: [URL] {
        selectedDocuments.map { ProjectDocumentStorage.fileURL(for: $0.fileName) }
    }

    private var autoMatchedDocuments: [FinancialRecordDocumentSuggestion] {
        ProjectFinancialDocumentMatcher.suggestedDocuments(
            for: record,
            in: unlinkedDocuments,
            limit: 3
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if !selectedDocuments.isEmpty {
                    Section(String(localized: "选中操作")) {
                        LabeledContent(
                            String(localized: "已选附件"),
                            value: String(format: String(localized: "%lld 份"), Int64(selectedDocuments.count))
                        )
                        Button {
                            if let firstDoc = selectedDocuments.first { previewURL = ProjectDocumentStorage.fileURL(for: firstDoc.fileName) }
                        } label: {
                            Label(String(localized: "预览第一份"), systemImage: "eye")
                        }
                        ShareLink(items: selectedDocumentURLs) {
                            Label(String(localized: "导出/分享选中附件"), systemImage: "square.and.arrow.up")
                        }
                        Picker(String(localized: "批量分类"), selection: $bulkCategory) {
                            ForEach(ProjectDocumentCategory.allCases, id: \.self) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        Button {
                            onBulkSetCategory(selectedDocuments, bulkCategory)
                            selectedLinkedDocumentIds.removeAll()
                            selectedUnlinkedDocumentIds.removeAll()
                        } label: {
                            Label(String(localized: "应用分类到选中附件"), systemImage: "tag.fill")
                        }
                    }
                }

                Section(String(format: String(localized: "已关联附件 (%d)"), linkedDocuments.count)) {
                    if linkedDocuments.isEmpty {
                        ContentUnavailableView(
                            String(localized: "暂无附件"),
                            systemImage: "paperclip",
                            description: Text(String(localized: "可拍照、扫描或关联已有项目资料。"))
                        )
                    } else {
                        if !selectedLinkedDocumentIds.isEmpty {
                            Button(String(format: String(localized: "移除选中 %d 项"), selectedLinkedDocumentIds.count)) {
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
                                trailingTitle: String(localized: "移除"),
                                onToggleSelection: { toggleLinked(document.id) },
                                onAction: { onDetach(document) }
                            )
                        }
                    }
                }

                Section(String(localized: "新增附件")) {
                    Button(String(localized: "扫描添加")) {
                        onScan()
                    }
                    Button(String(localized: "从文件导入附件")) {
                        showFileImporter = true
                    }
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(String(localized: "从相册选择照片"), systemImage: "photo.on.rectangle")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(String(localized: "拍照保存")) {
                            imagePickerSource = .camera
                            showImagePicker = true
                        }
                    }
                }

                Section(String(localized: "缺票自动匹配")) {
                    if autoMatchedDocuments.isEmpty {
                        ContentUnavailableView(
                            String(localized: "暂无匹配建议"),
                            systemImage: "wand.and.stars",
                            description: Text(String(localized: "建议先在资料里补录金额、日期或单位名称，再回来一键关联。"))
                        )
                    } else {
                        ForEach(autoMatchedDocuments) { suggestion in
                            HStack(alignment: .top, spacing: AppSpacing.tight) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.document.title)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(suggestion.document.category.displayName)
                                        if suggestion.document.amountValue.isPositive {
                                            Text(ReportBuilder.money(suggestion.document.amountValue.doubleValue))
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    Text(Formatters.displayDateText(suggestion.document.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "关联")) {
                                    onAttach(suggestion.document)
                                }
                                .buttonStyle(.appProminent())
                                .font(.caption2.weight(.semibold))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section(String(localized: "关联已有资料")) {
                    if unlinkedDocuments.isEmpty {
                        ContentUnavailableView(
                            String(localized: "暂无可关联资料"),
                            systemImage: "doc.badge.plus",
                            description: Text(String(localized: "导入项目资料后可在这里关联到当前流水。"))
                        )
                    } else {
                        if !selectedUnlinkedDocumentIds.isEmpty {
                            Button(String(format: String(localized: "关联选中 %d 项"), selectedUnlinkedDocumentIds.count)) {
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
                                trailingTitle: String(localized: "关联"),
                                warning: document.linkedFinancialRecordId != nil && document.linkedFinancialRecordId != record.id ? String(localized: "已关联其他账目，点击后将重新关联") : nil,
                                onToggleSelection: { toggleUnlinked(document.id) },
                                onAction: { onAttach(document) }
                            )
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "票据附件管理"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.allowedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                pendingDocumentImportRequest = ProjectDocumentImportConfirmationRequest(
                    urls: urls,
                    defaultSettings: importLedgerDefaultSettings
                )
            }
        }
        .sheet(item: $pendingDocumentImportRequest) { request in
            ProjectDocumentImportConfirmationSheet(
                urls: request.urls,
                defaultSettings: request.defaultSettings
            ) { settings in
                onImportFiles(request.urls, settings)
                pendingDocumentImportRequest = nil
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: imagePickerSource) { image in
                onImportImage(image, String(localized: "来源: 拍照"))
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
                onImportImage(image, String(localized: "来源: 相册"))
            }
            selectedPhotoItem = nil
        }
    }

    private var importLedgerDefaultSettings: ProjectDocumentImportLedgerSettings {
        ProjectDocumentImportLedgerSettings(
            category: ProjectDetailFinanceDocumentHelper.documentCategory(for: record.category),
            formedAt: record.date
        )
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
                    .foregroundStyle(isSelected ? Color.appPrimaryAction : .secondary)
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
                        .foregroundStyle(Color.appPrimaryAction)
                }
            }
            Spacer()
            Button(trailingTitle, action: onAction)
                .font(.caption.weight(.semibold))
        }
    }

    private var metaText: String {
        let fileType = document.fileType.isEmpty ? String(localized: "附件") : document.fileType.uppercased()
        let pageText = document.fileType.lowercased() == "pdf" ? String(format: String(localized: " · %lld 页"), Int64(document.pageCount)) : ""
        return String(format: String(localized: "%@ · %@%@ · %@"), document.category.displayName, fileType, pageText, document.createdAt)
    }
}

private struct ProjectDocumentPDFThumbnail: View {
    let document: ProjectDocument
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackIcon)
                    .font(.title3)
                    .foregroundStyle(Color.appDoc)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appDocSurfaceSubtle)
            }
        }
        .frame(width: 44, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appStrokeSeparator, lineWidth: 0.5))
        .task(id: document.fileName) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        thumbnail = nil
        guard let data = await ProjectDocumentStorage.dataAsync(for: document.fileName) else { return }
        let fileType = document.fileType.lowercased()
        let loaded: UIImage?
        do {
            loaded = try await FileIOTaskRunner.run(
                priority: .utility,
                logContext: .init(
                    event: "project.document.thumbnail_decode",
                    source: "ProjectDocumentPDFThumbnail.loadThumbnail",
                    category: .fileStorage,
                    details: ["file_name": document.fileName]
                )
            ) {
                if fileType != "pdf", let image = UIImage(data: data) {
                    return image
                }
                guard let pdf = PDFDocument(data: data),
                      let page = pdf.page(at: 0) else { return nil }
                return page.thumbnail(of: CGSize(width: 88, height: 108), for: .cropBox)
            }
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        thumbnail = loaded
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
