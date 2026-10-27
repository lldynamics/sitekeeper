import SwiftUI
import Foundation

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
                        StatusChip(text: AppLocalization.string("最近"), tone: .warning, compact: true)
                    }
                }
                Text(file.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(file.uploadState.statusMessage)
                    .font(.caption)
                    .foregroundStyle(file.uploadState == .uploaded ? Color.appSuccess : Color.appWarning)
                Text(file.fileName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(AppLocalization.string("恢复")) {
                onRestore()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }
}

struct BackupQuickStartCard: View {
    let onExport: () -> Void
    let onShowImporter: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(AppLocalization.string("先完成首份备份"), systemImage: "shield.lefthalf.filled.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appWarning)
                Spacer()
                Button(AppLocalization.string("不再提示"), action: onDismiss)
                    .font(.caption.weight(.semibold))
            }

            Text(AppLocalization.string("建议先导出一份完整 ZIP。后续误删、覆盖导入或换机时都能快速恢复。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onExport) {
                Label(AppLocalization.string("导出完整备份 ZIP"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.appProminent(tint: .appWarning))

            Button(action: onShowImporter) {
                Label(AppLocalization.string("导入备份 ZIP"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
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
        AppPanel(
            tone: .materialThick,
            cornerRadius: 14,
            padding: 16,
            shadow: .overlay
        ) {
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
        }
        .frame(maxWidth: 320)
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
        AppBusinessFormSheet(
            title: AppLocalization.string("确认导入"),
            primaryActionTitle: nil,
            onCancel: onCancel
        ) {
                Section(AppLocalization.string("导入预览")) {
                    LabeledContent(AppLocalization.string("材料"), value: "\(snapshot.materialItems.count) 条")
                    LabeledContent(AppLocalization.string("报价"), value: "\(snapshot.quoteItems.count) 条")
                    LabeledContent(AppLocalization.string("人工记录"), value: "\(snapshot.laborRecords.count) 条")
                    LabeledContent(AppLocalization.string("项目"), value: "\(snapshot.projects.count) 个")
                    LabeledContent(AppLocalization.string("现场待办"), value: "\(snapshot.siteTodos.count) 条")
                    LabeledContent(AppLocalization.string("项目图纸"), value: "\(snapshot.projectDrawings.count) 份")
                    LabeledContent(AppLocalization.string("项目联系人"), value: "\(snapshot.projectContacts.count) 位")
                    LabeledContent(AppLocalization.string("零星收支"), value: "\(snapshot.projectFinancialRecords.count) 条")
                    LabeledContent(AppLocalization.string("项目资料"), value: "\(snapshot.projectDocuments.count) 份")
                    LabeledContent(AppLocalization.string("随手记"), value: "\(snapshot.quickNotes.count) 条")
                    LabeledContent(AppLocalization.string("施工日志"), value: "\(snapshot.dailyLogs.count) 条")
                    LabeledContent(AppLocalization.string("材料价格库"), value: "\(snapshot.materialPriceEntries.count) 条")
                    LabeledContent(AppLocalization.string("供应商库"), value: "\(snapshot.supplierProfiles.count) 条")
                    LabeledContent(AppLocalization.string("施工工艺库"), value: "\(snapshot.constructionMethods.count) 条")
                    LabeledContent(AppLocalization.string("进度任务"), value: "\(snapshot.progressTasks.count) 条")
                    LabeledContent(AppLocalization.string("历史计算"), value: "\(snapshot.historyRecords.count) 条")
                }
                BackupFileImpactSectionView(
                    title: AppLocalization.string("将恢复到本机的原文件"),
                    summary: preview.incomingFiles,
                    emptyMessage: AppLocalization.string("该备份不包含独立原文件，导入时只会恢复数据索引。"),
                    footer: AppLocalization.string("这些原文件会随导入一起恢复到本机。")
                )
                BackupFileImpactSectionView(
                    title: AppLocalization.string("若选择覆盖，将移除的本机原文件"),
                    summary: preview.overwrittenLocalFiles,
                    emptyMessage: AppLocalization.string("当前本机没有会被这份备份移除的原文件。"),
                    footer: AppLocalization.string("仅覆盖导入会执行这一步；合并导入不会删除现有原文件。")
                )
                Section(AppLocalization.string("导入方式")) {
                    Picker(AppLocalization.string("方式"), selection: $importMode) {
                        Text(AppLocalization.string("合并（保留现有数据）")).tag(ImportMode.merge)
                        Text(AppLocalization.string("覆盖（替换全部数据）")).tag(ImportMode.overwrite)
                    }
                    .pickerStyle(.segmented)
                    if importMode == .overwrite {
                        Text(AppLocalization.string("覆盖会替换当前本机数据，并移除上方列出的本机原文件。请先导出备份。"))
                            .font(.caption)
                            .foregroundStyle(.appWarning)
                    }
                }
                Section {
                    if importMode == .merge {
                        Button(AppLocalization.string("确认导入"), action: onApplyImport)
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                            .tint(.appWarning)
                            .accessibilityIdentifier("backup-import-confirm")
                    } else if isOverwriteImportArmed {
                        Button(AppLocalization.string("确认覆盖导入"), role: .destructive, action: onApplyImport)
                            .accessibilityIdentifier("backup-import-overwrite-confirm")
                        Button(AppLocalization.string("返回合并导入"), role: .cancel) {
                            importMode = .merge
                            isOverwriteImportArmed = false
                        }
                    } else {
                        Button(AppLocalization.string("继续（下一步确认覆盖）"), role: .destructive) {
                            isOverwriteImportArmed = true
                            AppHaptics.warning()
                        }
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                    }
                }
        }
        .onChange(of: importMode) { _, mode in
            if mode != .overwrite {
                isOverwriteImportArmed = false
            }
        }
    }
}

private struct BackupFileImpactSectionView: View {
    let title: String
    let summary: BackupFileImpactSummary
    let emptyMessage: String
    let footer: String?

    var body: some View {
        Section {
            if summary.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent(AppLocalization.string("合计"), value: "\(summary.totalCount) 项")
                categoryDisclosure(
                    title: AppLocalization.string("现场照片"),
                    value: "\(summary.photoFileCount) 张",
                    fileNames: summary.photoFileNames
                )
                categoryDisclosure(
                    title: AppLocalization.string("图纸文件"),
                    value: "\(summary.drawingFileCount) 份",
                    fileNames: summary.drawingFileNames
                )
                categoryDisclosure(
                    title: AppLocalization.string("扫描资料"),
                    value: "\(summary.documentFileCount) 份",
                    fileNames: summary.documentFileNames
                )
                categoryDisclosure(
                    title: AppLocalization.string("随手记/工艺附件"),
                    value: "\(summary.quickNoteAttachmentFileCount) 份",
                    fileNames: summary.quickNoteAttachmentFileNames
                )
            }
        } header: {
            Text(title)
        } footer: {
            if let footer {
                Text(footer)
            }
        }
    }

    @ViewBuilder
    private func categoryDisclosure(title: String, value: String, fileNames: [String]) -> some View {
        if !fileNames.isEmpty {
            DisclosureGroup {
                ForEach(fileNames, id: \.self) { fileName in
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Text(value)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
