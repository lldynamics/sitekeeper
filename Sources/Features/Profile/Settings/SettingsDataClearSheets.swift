import SwiftUI

struct ClearLocalDataImpactPreview {
    struct Item: Identifiable {
        let title: String
        let count: Int

        var id: String { title }
    }

    let projectCount: Int
    let photoCount: Int
    let ticketCount: Int
    let documentCount: Int
    let historyCount: Int
    let photoFileCount: Int
    let drawingFileCount: Int
    let documentFileCount: Int
    let attachmentFileCount: Int
    var repositoryCopyCount = 0
    var repositoryCopyBytes: Int64 = 0

    static let empty = ClearLocalDataImpactPreview(
        projectCount: 0,
        photoCount: 0,
        ticketCount: 0,
        documentCount: 0,
        historyCount: 0,
        photoFileCount: 0,
        drawingFileCount: 0,
        documentFileCount: 0,
        attachmentFileCount: 0
    )

    var recordItems: [Item] {
        [
            Item(title: AppLocalization.string("项目"), count: projectCount),
            Item(title: AppLocalization.string("照片记录"), count: photoCount),
            Item(title: AppLocalization.string("票据记录"), count: ticketCount),
            Item(title: AppLocalization.string("资料记录"), count: documentCount),
            Item(title: AppLocalization.string("历史记录"), count: historyCount),
            Item(title: AppLocalization.string("试用副本"), count: repositoryCopyCount)
        ]
    }

    var fileItems: [Item] {
        [
            Item(title: AppLocalization.string("照片文件（含缩略图）"), count: photoFileCount),
            Item(title: AppLocalization.string("图纸文件"), count: drawingFileCount),
            Item(title: AppLocalization.string("资料文件"), count: documentFileCount),
            Item(title: AppLocalization.string("附件文件"), count: attachmentFileCount)
        ]
    }

    var totalFileCount: Int {
        fileItems.reduce(0) { partial, item in
            partial + item.count
        }
    }

    var auditSnapshot: String {
        [
            "projects=\(projectCount)",
            "photoRecords=\(photoCount)",
            "ticketRecords=\(ticketCount)",
            "documentRecords=\(documentCount)",
            "historyRecords=\(historyCount)",
            "photoFiles=\(photoFileCount)",
            "drawingFiles=\(drawingFileCount)",
            "documentFiles=\(documentFileCount)",
            "attachmentFiles=\(attachmentFileCount)",
            "repositoryCopies=\(repositoryCopyCount)",
            "repositoryCopyBytes=\(repositoryCopyBytes)"
        ].joined(separator: ", ")
    }
}

struct ClearLocalDataBackupGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) private var localBackupLastSuccessAt = 0.0

    let flowStartedAt: Double
    let onContinue: () -> Void

    private var hasBackupCreatedInThisFlow: Bool {
        localBackupLastSuccessAt > flowStartedAt
    }

    private var canContinueClearing: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["UITEST_ALLOW_CLEAR_WITHOUT_BACKUP"] == "1" || hasBackupCreatedInThisFlow
#else
        hasBackupCreatedInThisFlow
#endif
    }

    private var backupStatusText: String {
        guard localBackupLastSuccessAt > 0 else {
            return AppLocalization.string("尚未生成本机备份")
        }
        let date = Date(timeIntervalSince1970: localBackupLastSuccessAt)
        return String(format: AppLocalization.string("最近本机备份：%@"), Formatters.dateTime.string(from: date))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label(AppLocalization.string("先备份再清空"), systemImage: "externaldrive.badge.checkmark")
                    .font(.title3.weight(.semibold))

                Text(AppLocalization.string("清空本机数据前，必须先生成一份新的本机备份 ZIP。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    DataManagementView(initialRoute: .backup)
                } label: {
                    Label(AppLocalization.string("去备份并导出 ZIP"), systemImage: "externaldrive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text(AppLocalization.string("导出完成后回到这里继续。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(backupStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hasBackupCreatedInThisFlow {
                    Label(AppLocalization.string("已检测到本次流程内的新备份"), systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appSuccess)
                } else {
                    Label(AppLocalization.string("请先完成本机备份后再继续清空。"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appRisk)
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button(AppLocalization.string("取消"), role: .cancel) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button(AppLocalization.string("继续清空"), role: .destructive) {
                        onContinue()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!canContinueClearing)
                }
            }
            .padding(20)
            .navigationTitle(AppLocalization.string("清空本机数据"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ClearLocalDataConfirmationSheet: View {
    let preview: ClearLocalDataImpactPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var requiredPhrase: String {
        AppLocalization.string("确认删除数据")
    }

    private var isInputValid: Bool {
        input == requiredPhrase
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.appRisk)
                        .padding(.top, 24)

                    Text(AppLocalization.string("即将清空本机全部数据"))
                        .font(.title2.weight(.semibold))

                    Text(AppLocalization.string("此操作不可恢复。以下内容将被删除："))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppLocalization.string("预计影响记录："))
                            .font(.callout.weight(.semibold))
                        ForEach(preview.recordItems) { item in
                            Text(
                                String(
                                    format: AppLocalization.string("- %@ %lld 条"),
                                    item.title,
                                    Int64(item.count)
                                )
                            )
                            .font(.callout)
                        }

                        Text(AppLocalization.string("预计删除文件："))
                            .font(.callout.weight(.semibold))
                            .padding(.top, 4)
                        ForEach(preview.fileItems) { item in
                            Text(
                                String(
                                    format: AppLocalization.string("- %@ %lld 个"),
                                    item.title,
                                    Int64(item.count)
                                )
                            )
                            .font(.callout)
                        }
                        Text(
                            String(
                                format: AppLocalization.string("合计 %lld 个文件。"),
                                Int64(preview.totalFileCount)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    if preview.repositoryCopyCount > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: AppLocalization.string("试用副本占用：%@"), ByteCountFormatter.string(fromByteCount: preview.repositoryCopyBytes, countStyle: .file)))
                            Text(AppLocalization.string("试用副本及其中的独立修改也将删除。常规备份不包含这些修改，请先在试用副本管理中分别导出。"))
                        }
                        .font(.callout)
                        .foregroundStyle(.appRisk)
                        .padding(.horizontal)
                        .accessibilityIdentifier("clear-repository-copies-warning")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: AppLocalization.string("请输入「%@」以确认："), requiredPhrase))
                            .font(.callout.weight(.medium))
                        TextField(requiredPhrase, text: $input)
                            .textFieldStyle(.roundedBorder)
                            .focused($isFocused)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        Button(AppLocalization.string("取消"), role: .cancel) {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(AppLocalization.string("确认清空"), role: .destructive) {
                            onConfirm()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!isInputValid)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 0)
                }
            }
            .interactiveDismissDisabled()
            .onAppear { isFocused = true }
        }
    }
}
