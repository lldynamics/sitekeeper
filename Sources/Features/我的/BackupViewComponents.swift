import SwiftUI
import Foundation
import UniformTypeIdentifiers

enum ImportMode: String, CaseIterable { case merge, overwrite }

struct CloudBackupListRow: View {
    let file: CloudBackupFile
    let isLatest: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isLatest ? "clock.arrow.circlepath" : "icloud")
                .foregroundStyle(isLatest ? .appWarning : .appPrimaryAction)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.formattedModifiedAt)
                        .font(.subheadline.weight(.semibold))
                    if isLatest {
                        Text(String(localized: "最近"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.appWarning)
                    }
                }
                Text(file.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(file.fileName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(String(localized: "恢复")) {
                onRestore()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zipArchive] }
    var data: Data
    var sourceFileURL: URL?

    init(data: Data, sourceFileURL: URL? = nil) {
        self.data = data
        self.sourceFileURL = sourceFileURL
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        sourceFileURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let sourceFileURL,
           FileManager.default.fileExists(atPath: sourceFileURL.path) {
            return try FileWrapper(url: sourceFileURL, options: .immediate)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

struct BackupQuickStartCard: View {
    let onExport: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(String(localized: "先完成首份备份"), systemImage: "shield.lefthalf.filled.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appWarning)
                Spacer()
                Button(String(localized: "不再提示"), action: onDismiss)
                    .font(.caption.weight(.semibold))
            }

            Text(String(localized: "建议先导出一份完整 ZIP。后续误删、覆盖导入或换机时都能快速恢复。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onExport) {
                Label(String(localized: "立即导出首份备份 ZIP"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.appProminent(tint: .appWarning))

            Text(String(localized: "导入备份可在下方“本地备份”中选择 ZIP；旧版备份会自动兼容。"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct BackupMicroGuideRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }
}

struct BackupTaskProgressCard: View {
    let title: String
    let subtitle: String
    let progressValue: Double
    let detail: String
    let cancelTitle: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: progressValue)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(cancelTitle, role: .destructive, action: onCancel)
            }
        }
        .padding(16)
        .frame(maxWidth: 320)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

struct BackupImportPreviewView: View {
    let preview: BackupImportPreview
    @Binding var importMode: ImportMode
    @Binding var isOverwriteImportArmed: Bool
    let onApplyImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let snapshot = preview.snapshot
        NavigationStack {
            Form {
                Section(String(localized: "导入预览")) {
                    LabeledContent(String(localized: "材料"), value: "\(snapshot.materialItems.count) 条")
                    LabeledContent(String(localized: "报价"), value: "\(snapshot.quoteItems.count) 条")
                    LabeledContent(String(localized: "人工记录"), value: "\(snapshot.laborRecords.count) 条")
                    LabeledContent(String(localized: "项目"), value: "\(snapshot.projects.count) 个")
                    LabeledContent(String(localized: "回路方案"), value: "\(snapshot.lightingCircuitPlans.count) 条")
                    LabeledContent(String(localized: "现场待办"), value: "\(snapshot.siteTodos.count) 条")
                    LabeledContent(String(localized: "项目图纸"), value: "\(snapshot.projectDrawings.count) 份")
                    LabeledContent(String(localized: "项目联系人"), value: "\(snapshot.projectContacts.count) 位")
                    LabeledContent(String(localized: "零星收支"), value: "\(snapshot.projectFinancialRecords.count) 条")
                    LabeledContent(String(localized: "项目资料"), value: "\(snapshot.projectDocuments.count) 份")
                    LabeledContent(String(localized: "随手记"), value: "\(snapshot.quickNotes.count) 条")
                    LabeledContent(String(localized: "施工日志"), value: "\(snapshot.dailyLogs.count) 条")
                    LabeledContent(String(localized: "现场照片"), value: "\(preview.photoFileCount) 张")
                    LabeledContent(String(localized: "图纸文件"), value: "\(preview.drawingFileCount) 份")
                    LabeledContent(String(localized: "扫描资料"), value: "\(preview.documentFileCount) 份")
                    LabeledContent(String(localized: "随手记/工艺附件"), value: "\(preview.quickNoteAttachmentFileCount) 份")
                    LabeledContent(String(localized: "材料价格库"), value: "\(snapshot.materialPriceEntries.count) 条")
                    LabeledContent(String(localized: "供应商库"), value: "\(snapshot.supplierProfiles.count) 条")
                    LabeledContent(String(localized: "施工工艺库"), value: "\(snapshot.constructionMethods.count) 条")
                    LabeledContent(String(localized: "进度任务"), value: "\(snapshot.progressTasks.count) 条")
                    LabeledContent(String(localized: "历史计算"), value: "\(snapshot.historyRecords.count) 条")
                }
                Section(String(localized: "导入方式")) {
                    Picker(String(localized: "方式"), selection: $importMode) {
                        Text(String(localized: "合并（保留现有数据）")).tag(ImportMode.merge)
                        Text(String(localized: "覆盖（替换全部数据）")).tag(ImportMode.overwrite)
                    }
                    .pickerStyle(.segmented)
                    if importMode == .overwrite {
                        Text(String(localized: "覆盖会删除当前本机数据，请先导出备份。"))
                            .font(.caption)
                            .foregroundStyle(.appWarning)
                    }
                }
                Section {
                    if importMode == .merge {
                        Button(String(localized: "确认导入"), action: onApplyImport)
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                            .tint(.appWarning)
                    } else if isOverwriteImportArmed {
                        Button(String(localized: "确认覆盖导入"), role: .destructive, action: onApplyImport)
                        Button(String(localized: "返回合并导入"), role: .cancel) {
                            importMode = .merge
                            isOverwriteImportArmed = false
                        }
                    } else {
                        Button(String(localized: "继续（下一步确认覆盖）"), role: .destructive) {
                            isOverwriteImportArmed = true
                            AppHaptics.warning()
                        }
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle(String(localized: "确认导入"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消"), action: onCancel)
                }
            }
            .onChange(of: importMode) { _, mode in
                if mode != .overwrite {
                    isOverwriteImportArmed = false
                }
            }
        }
    }
}
