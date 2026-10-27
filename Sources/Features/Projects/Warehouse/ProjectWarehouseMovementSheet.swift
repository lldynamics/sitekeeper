import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ProjectWarehouseMovementSheet: View {
    private enum MovementField: Hashable {
        case quantity
    }

    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projects: [Project]
    var fixedProjectId: UUID?
    let onSave: (ProjectWarehouseMovement, [ProjectWarehouseAttachmentDraft]) -> Void

    @State private var projectId: UUID?
    @State private var date = BusinessDateValue.today()
    @State private var movementType: WarehouseMovementType = .inbound
    @State private var materialName = ""
    @State private var specification = ""
    @State private var unit = ""
    @State private var quantity = ""
    @State private var counterparty = ""
    @State private var handler = ""
    @State private var note = ""
    @State private var attachments: [ProjectWarehouseAttachmentDraft] = []
    @State private var showFileImporter = false
    @State private var fileImportWarningMessage = ""
    @State private var showFileImportWarning = false
    @State private var mediaImport = ProjectWarehouseMovementMediaImportHelper()
    @FocusState private var movementFocusedField: MovementField?

    init(
        projects: [Project],
        fixedProjectId: UUID? = nil,
        onSave: @escaping (ProjectWarehouseMovement, [ProjectWarehouseAttachmentDraft]) -> Void
    ) {
        self.projects = projects
        self.fixedProjectId = fixedProjectId
        self.onSave = onSave
        _projectId = State(initialValue: fixedProjectId ?? projects.first?.id)
    }

    var body: some View {
        AppBusinessEditForm(
            title: movementType.displayName,
            isPrimaryActionDisabled: !canSave,
            onCancel: {
                dismiss()
            },
            onPrimaryAction: {
                guard let projectId else { return }
                onSave(ProjectWarehouseMovement(
                    projectId: projectId,
                    date: date,
                    movementType: movementType,
                    materialName: materialName.trimmingCharacters(in: .whitespacesAndNewlines),
                    specification: specification.trimmingCharacters(in: .whitespacesAndNewlines),
                    unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantity: NumericInputSupport.quantity(quantity.trimmingCharacters(in: .whitespacesAndNewlines)),
                    counterparty: counterparty.trimmingCharacters(in: .whitespacesAndNewlines),
                    handler: handler.trimmingCharacters(in: .whitespacesAndNewlines),
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                ), attachments)
                dismiss()
            }
        ) {
            Form {
                Section(AppLocalization.string("出入库")) {
                    if fixedProjectId == nil {
                        Picker(AppLocalization.string("项目"), selection: $projectId) {
                            ForEach(projects) { project in
                                Text(project.name).tag(project.id as UUID?)
                            }
                        }
                    }
                    DatePicker(AppLocalization.string("日期"), selection: $date.daySelection, displayedComponents: .date)
                    Picker(AppLocalization.string("类型"), selection: $movementType) {
                        ForEach(WarehouseMovementType.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(AppLocalization.string("材料")) {
                    TextField(AppLocalization.string("材料名称"), text: $materialName)
                    if !materialSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(materialSuggestionTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(materialSuggestions) { suggestion in
                                ProjectWarehouseMaterialSuggestionRow(suggestion: suggestion) {
                                    applyMaterialSuggestion(suggestion)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    TextField(AppLocalization.string("规格/型号"), text: $specification)
                    TextField(AppLocalization.string("单位"), text: $unit)
                    TextField(AppLocalization.string("数量"), text: $quantity)
                        .keyboardType(.decimalPad)
                        .focused($movementFocusedField, equals: .quantity)
                }

                Section(AppLocalization.string("备注")) {
                    TextField(movementType == .inbound ? AppLocalization.string("供应商/来源") : AppLocalization.string("领用班组/去向"), text: $counterparty)
                    TextField(AppLocalization.string("经手人"), text: $handler)
                    TextField(AppLocalization.string("备注"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section(AppLocalization.string("附件")) {
                    if attachments.isEmpty {
                        Text(AppLocalization.string("可上传现场照片、签收视频、送货单 PDF、DWG/DXF 图纸或其他文件。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(attachments) { attachment in
                            ProjectWarehouseAttachmentDraftRow(attachment: attachment) {
                                attachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    PhotosPicker(selection: $mediaImport.selectedItems, maxSelectionCount: 6, matching: .any(of: [.images, .videos])) {
                        Label(AppLocalization.string("从相册选择照片/视频"), systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label(AppLocalization.string("从文件导入附件"), systemImage: "paperclip")
                    }
                    Text(AppLocalization.string("选择文件时会预先检查单文件大小，超限文件会立即提示并跳过。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            mediaImport.showImagePicker = true
                        } label: {
                            Label(AppLocalization.string("拍照添加"), systemImage: "camera.fill")
                        }
                    }
                    if mediaImport.isImporting {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mediaImport.status.isEmpty ? AppLocalization.string("正在导入媒体...") : mediaImport.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: mediaImport.progressValue)
                            HStack {
                                Text("\(mediaImport.completedCount)/\(max(mediaImport.totalCount, 1))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(AppLocalization.string("取消导入"), role: .destructive) {
                                    mediaImport.cancelImport()
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .appKeyboardToolbar {
                KeyboardNavigationToolbar(
                    focusedField: $movementFocusedField,
                    currentField: movementFocusedField,
                    fields: [.quantity]
                )
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                handleImportedFileURLs(urls)
            }
        }
        .sheet(isPresented: $mediaImport.showImagePicker) {
            ImagePickerView(sourceType: .camera) { image in
                attachments.append(ProjectWarehouseAttachmentDraft(image: image, title: AppLocalization.string("拍照附件")))
            }
        }
        .onChange(of: mediaImport.selectedItems) { _, items in
            guard !items.isEmpty else { return }
            mediaImport.startImport(items) { imported in
                attachments.append(contentsOf: imported)
            }
        }
        .alert(AppLocalization.string("媒体导入失败"), isPresented: $mediaImport.showError) {
            Button(AppLocalization.string("知道了"), role: .cancel) {}
        } message: {
            Text(mediaImport.errorMessage)
        }
        .alert(AppLocalization.string("部分附件未添加"), isPresented: $showFileImportWarning) {
            Button(AppLocalization.string("知道了"), role: .cancel) {}
        } message: {
            Text(fileImportWarningMessage)
        }
        .onDisappear {
            mediaImport.handleDisappear()
        }
    }

    private var canSave: Bool {
        projectId != nil
            && !materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && InputValidator.nonNegativeNumber(quantity)
            && NumericInputSupport.quantity(quantity).isPositive
    }

    private var materialSuggestionTitle: String {
        materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppLocalization.string("常用材料") : AppLocalization.string("匹配材料")
    }

    private var materialSuggestions: [ProjectWarehouseMaterialSuggestion] {
        ProjectWarehouseMaterialSuggestion.suggestions(
            input: materialName,
            projectId: projectId,
            warehouseMovements: store.projectWarehouseMovements,
            materialItems: store.materialItems,
            priceEntries: store.materialPriceEntries
        )
    }

    private func applyMaterialSuggestion(_ suggestion: ProjectWarehouseMaterialSuggestion) {
        materialName = suggestion.name
        specification = suggestion.specification
        unit = suggestion.unit
    }

    private func handleImportedFileURLs(_ urls: [URL]) {
        var accepted: [ProjectWarehouseAttachmentDraft] = []
        var rejected: [String] = []

        for url in urls {
            do {
                try ProjectWarehouseAttachmentImporter.validateFileURLForImport(url)
                accepted.append(ProjectWarehouseAttachmentDraft(fileURL: url))
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? AppLocalization.string("无法读取或文件过大")
                rejected.append("\(url.lastPathComponent)（\(reason)）")
            }
        }

        if !accepted.isEmpty {
            attachments.append(contentsOf: accepted)
        }

        guard !rejected.isEmpty else { return }
        fileImportWarningMessage = makeFileImportWarningMessage(from: rejected)
        showFileImportWarning = true
    }

    private func makeFileImportWarningMessage(from rejected: [String]) -> String {
        let preview = rejected.prefix(3)
        let lines = preview.joined(separator: "\n")
        if rejected.count > preview.count {
            return String(format: AppLocalization.string("以下文件未添加：\n%@\n等共 %lld 个。"), lines, Int64(rejected.count))
        }
        return String(format: AppLocalization.string("以下文件未添加：\n%@"), lines)
    }
}
