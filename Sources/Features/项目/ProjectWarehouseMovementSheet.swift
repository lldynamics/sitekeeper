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
    @State private var date = Date()
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
        NavigationStack {
            Form {
                Section(String(localized: "出入库")) {
                    if fixedProjectId == nil {
                        Picker(String(localized: "项目"), selection: $projectId) {
                            ForEach(projects) { project in
                                Text(project.name).tag(project.id as UUID?)
                            }
                        }
                    }
                    DatePicker(String(localized: "日期"), selection: $date, displayedComponents: .date)
                    Picker(String(localized: "类型"), selection: $movementType) {
                        ForEach(WarehouseMovementType.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(String(localized: "材料")) {
                    TextField(String(localized: "材料名称"), text: $materialName)
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
                    TextField(String(localized: "规格/型号"), text: $specification)
                    TextField(String(localized: "单位"), text: $unit)
                    TextField(String(localized: "数量"), text: $quantity)
                        .keyboardType(.decimalPad)
                        .focused($movementFocusedField, equals: .quantity)
                }

                Section(String(localized: "备注")) {
                    TextField(movementType == .inbound ? String(localized: "供应商/来源") : String(localized: "领用班组/去向"), text: $counterparty)
                    TextField(String(localized: "经手人"), text: $handler)
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section(String(localized: "附件")) {
                    if attachments.isEmpty {
                        Text(String(localized: "可上传现场照片、签收视频、送货单 PDF、CAD 或其他文件。"))
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
                        Label(String(localized: "从相册选择照片/视频"), systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label(String(localized: "从文件导入附件"), systemImage: "paperclip")
                    }
                    Text(String(localized: "选择文件时会预先检查单文件大小，超限文件会立即提示并跳过。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            mediaImport.showImagePicker = true
                        } label: {
                            Label(String(localized: "拍照添加"), systemImage: "camera.fill")
                        }
                    }
                    if mediaImport.isImporting {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mediaImport.status.isEmpty ? String(localized: "正在导入媒体...") : mediaImport.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: mediaImport.progressValue)
                            HStack {
                                Text("\(mediaImport.completedCount)/\(max(mediaImport.totalCount, 1))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(String(localized: "取消导入"), role: .destructive) {
                                    mediaImport.cancelImport()
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(movementType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        guard let projectId else { return }
                        onSave(ProjectWarehouseMovement(
                            projectId: projectId,
                            date: Formatters.date.string(from: date),
                            movementType: movementType,
                            materialName: materialName.trimmingCharacters(in: .whitespacesAndNewlines),
                            specification: specification.trimmingCharacters(in: .whitespacesAndNewlines),
                            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
                            quantity: quantity.trimmingCharacters(in: .whitespacesAndNewlines),
                            counterparty: counterparty.trimmingCharacters(in: .whitespacesAndNewlines),
                            handler: handler.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        ), attachments)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
                KeyboardNavigationToolbar(
                    focusedField: $movementFocusedField,
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
                attachments.append(ProjectWarehouseAttachmentDraft(image: image, title: String(localized: "拍照附件")))
            }
        }
        .onChange(of: mediaImport.selectedItems) { _, items in
            guard !items.isEmpty else { return }
            mediaImport.startImport(items) { imported in
                attachments.append(contentsOf: imported)
            }
        }
        .alert(String(localized: "媒体导入失败"), isPresented: $mediaImport.showError) {
            Button(String(localized: "知道了"), role: .cancel) {}
        } message: {
            Text(mediaImport.errorMessage)
        }
        .alert(String(localized: "部分附件未添加"), isPresented: $showFileImportWarning) {
            Button(String(localized: "知道了"), role: .cancel) {}
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
            && QuantityValue(text: quantity).isPositive
    }

    private var materialSuggestionTitle: String {
        materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "常用材料") : String(localized: "匹配材料")
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
                let reason = (error as? LocalizedError)?.errorDescription ?? String(localized: "无法读取或文件过大")
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
            return String(format: String(localized: "以下文件未添加：\n%@\n等共 %lld 个。"), lines, Int64(rejected.count))
        }
        return String(format: String(localized: "以下文件未添加：\n%@"), lines)
    }

}

private struct ProjectWarehouseMaterialSuggestion: Identifiable {
    let name: String
    let specification: String
    let unit: String
    let source: String
    let usageCount: Int
    let projectMatched: Bool

    var id: String {
        [name, specification, unit].joined(separator: "|").lowercased()
    }

    var detailText: String {
        [specification, unit].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func suggestions(
        input: String,
        projectId: UUID?,
        warehouseMovements: [ProjectWarehouseMovement],
        materialItems: [MaterialItem],
        priceEntries: [MaterialPriceEntry]
    ) -> [ProjectWarehouseMaterialSuggestion] {
        var buckets: [String: ProjectWarehouseMaterialSuggestionBucket] = [:]
        func add(name: String, specification: String, unit: String, source: String, sourceRank: Int, count: Int, projectMatched: Bool) {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let specification = specification.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = [name.lowercased(), specification.lowercased(), unit.lowercased()].joined(separator: "|")
            var bucket = buckets[key] ?? ProjectWarehouseMaterialSuggestionBucket(
                name: name,
                specification: specification,
                unit: unit,
                source: source,
                sourceRank: sourceRank,
                usageCount: 0,
                projectMatched: false
            )
            bucket.usageCount += count
            bucket.projectMatched = bucket.projectMatched || projectMatched
            if sourceRank < bucket.sourceRank {
                bucket.source = source
                bucket.sourceRank = sourceRank
            }
            buckets[key] = bucket
        }

        for movement in warehouseMovements {
            add(
                name: movement.materialName,
                specification: movement.specification,
                unit: movement.unit,
                source: String(localized: "仓库"),
                sourceRank: 0,
                count: 1,
                projectMatched: movement.projectId == projectId
            )
        }

        for item in materialItems {
            add(
                name: item.name,
                specification: item.specification,
                unit: item.unit,
                source: String(localized: "材料"),
                sourceRank: 1,
                count: 1,
                projectMatched: item.projectId == projectId
            )
        }

        for entry in priceEntries {
            add(
                name: entry.name,
                specification: entry.specification,
                unit: entry.unit,
                source: String(localized: "材料库"),
                sourceRank: 2,
                count: 0,
                projectMatched: false
            )
        }

        for material in MaterialLibrary.all {
            add(
                name: material.name,
                specification: material.specification,
                unit: material.unit,
                source: String(localized: "预置材料"),
                sourceRank: 3,
                count: 0,
                projectMatched: false
            )
        }

        let keyword = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return buckets.values
            .filter { keyword.isEmpty || $0.matches(keyword) }
            .sorted { lhs, rhs in
                if !keyword.isEmpty {
                    let lhsPrefix = lhs.hasNamePrefix(keyword)
                    let rhsPrefix = rhs.hasNamePrefix(keyword)
                    if lhsPrefix != rhsPrefix { return lhsPrefix }
                }
                if lhs.projectMatched != rhs.projectMatched { return lhs.projectMatched }
                if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
                if lhs.sourceRank != rhs.sourceRank { return lhs.sourceRank < rhs.sourceRank }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(8)
            .map { bucket in
                ProjectWarehouseMaterialSuggestion(
                    name: bucket.name,
                    specification: bucket.specification,
                    unit: bucket.unit,
                    source: bucket.source,
                    usageCount: bucket.usageCount,
                    projectMatched: bucket.projectMatched
                )
            }
    }
}

private struct ProjectWarehouseMaterialSuggestionBucket {
    var name: String
    var specification: String
    var unit: String
    var source: String
    var sourceRank: Int
    var usageCount: Int
    var projectMatched: Bool

    func matches(_ keyword: String) -> Bool {
        name.localizedStandardContains(keyword)
            || specification.localizedStandardContains(keyword)
            || unit.localizedStandardContains(keyword)
    }

    func hasNamePrefix(_ keyword: String) -> Bool {
        name.lowercased().hasPrefix(keyword.lowercased())
    }
}

private struct ProjectWarehouseMaterialSuggestionRow: View {
    let suggestion: ProjectWarehouseMaterialSuggestion
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(Color.appPrimaryAction)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !suggestion.detailText.isEmpty {
                        Text(suggestion.detailText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(sourceText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: String(localized: "%@，%@"), suggestion.name, suggestion.detailText.isEmpty ? sourceText : suggestion.detailText))
        .accessibilityHint(String(localized: "双击填充材料信息"))
    }

    private var sourceText: String {
        if suggestion.projectMatched {
            return suggestion.source == String(localized: "仓库") ? String(localized: "本项目常用") : String(localized: "本项目")
        }
        if suggestion.usageCount > 1 {
            return String(format: String(localized: "%@ %lld"), suggestion.source, Int64(suggestion.usageCount))
        }
        return suggestion.source
    }
}
