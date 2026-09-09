import SwiftUI
import UniformTypeIdentifiers

struct DataHealthView: View {
    @Environment(DataStore.self) var store
    @State private var showReferenceFixConfirm = false
    @State private var showOrphanFileCleanupConfirm = false
    @State private var showRepairGuidanceDialog = false
    @State var exportPayload: ExportPayload?
    @State var showExporter = false
    @State var operationNotice: OperationToastNotice?
    @State var selectedIssueProjectFilter = DataHealthIssueProjectFilter.all
    @State var showsOnlyAutoFixableIssues = false
    @State var issueSearchText = ""
    @State var selectedIssueSort: DataHealthIssueSortOption = .severityDescending
    @State var expandedIssueSectionIDs: Set<String> = []
    @State private var handledRepairRequestID: UUID?
    private let showsNavigationTitle: Bool
    private let bottomContentInset: CGFloat
    private let repairRequestID: UUID?
    private let onRepairRequestConsumed: (() -> Void)?
    let issuePreviewLimit = 50
    let impactRecordPreviewLimit = 8

    init(
        showsNavigationTitle: Bool = true,
        bottomContentInset: CGFloat = 0,
        repairRequestID: UUID? = nil,
        onRepairRequestConsumed: (() -> Void)? = nil
    ) {
        self.showsNavigationTitle = showsNavigationTitle
        self.bottomContentInset = bottomContentInset
        self.repairRequestID = repairRequestID
        self.onRepairRequestConsumed = onRepairRequestConsumed
    }

    func handleRepairRequestIfNeeded(_ requestID: UUID?) {
        guard let requestID, handledRepairRequestID != requestID else { return }
        handledRepairRequestID = requestID
        onRepairRequestConsumed?()

        if referenceIssueCount > 0 {
            showReferenceFixConfirm = true
            return
        }

        if orphanFileIssueCount > 0 {
            showOrphanFileCleanupConfirm = true
            return
        }

        AppHaptics.warning()
        if totalIssues > 0 {
            showRepairGuidanceDialog = true
            return
        }

        operationNotice = .info(l("当前没有待修复的数据健康异常。"))
    }

    func l(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }

    func lf(_ key: String, _ args: CVarArg...) -> String {
        String(format: l(key), arguments: args)
    }

    var body: some View {
        List {
            Section(l("健康概览")) {
                LabeledContent(l("问题总数"), value: "\(totalIssues)")
                LabeledContent(l("缺失照片"), value: "\(missingPhotoFiles.count)")
                LabeledContent(l("缺失票据文件"), value: "\(missingDocumentFiles.count)")
                LabeledContent(l("缺失随手记附件"), value: "\(missingQuickNoteAttachmentFiles.count)")
                LabeledContent(l("孤立照片文件"), value: "\(orphanPhotoFiles.count)")
                LabeledContent(l("孤立图纸文件"), value: "\(orphanDrawingFiles.count)")
                LabeledContent(l("孤立票据文件"), value: "\(orphanDocumentFiles.count)")
                LabeledContent(l("孤立随手记附件"), value: "\(orphanQuickNoteAttachmentFiles.count)")
                LabeledContent(l("孤立附件映射"), value: "\(orphanAttachmentMappings.count)")
                LabeledContent(l("仓库悬空附件映射"), value: "\(orphanWarehouseAttachmentMappings.count)")
                LabeledContent(l("资料悬空关联"), value: "\(danglingDocumentLinks.count)")
                LabeledContent(l("无效项目关联"), value: "\(invalidProjectRefs.count)")
                LabeledContent(l("可自动修复项目关联"), value: "\(autoFixableInvalidProjectRefs.count)")
                LabeledContent(l("需手动处理项目关联"), value: "\(manualInvalidProjectRefs.count)")
                LabeledContent(l("存储错误记录"), value: "\(storageIssues.count)")
            }

            Section(l("存储空间")) {
                LabeledContent(l("照片"), value: QuickNoteAttachmentStorage.formattedFileSize(photoStorageBytes))
                LabeledContent(l("资料（票据/图纸/附件）"), value: QuickNoteAttachmentStorage.formattedFileSize(projectAssetBytes))
                LabeledContent(l("备份（iCloud）"), value: QuickNoteAttachmentStorage.formattedFileSize(cloudBackupBytes))
                LabeledContent(l("历史计算"), value: "\(store.historyRecords.count) 条 · \(QuickNoteAttachmentStorage.formattedFileSize(historyRecordBytes))")
                LabeledContent(l("缩略图缓存"), value: QuickNoteAttachmentStorage.formattedFileSize(mediaThumbnailCacheBytes))
                LabeledContent(l("合计"), value: QuickNoteAttachmentStorage.formattedFileSize(totalStorageBytes))
            }

            Section(l("Widget 与缓存")) {
                LabeledContent(l("App Group 可读"), value: widgetHealth.appGroupReadable ? l("是") : l("否"))
                LabeledContent(l("Widget 项目数"), value: "\(widgetHealth.projectCount)")
                LabeledContent(l("Widget 待办数"), value: "\(widgetHealth.pendingTodos)")
                LabeledContent(
                    l("Widget 最近同步"),
                    value: widgetHealth.lastUpdatedAt.map { Formatters.dateTime.string(from: $0) } ?? l("暂无")
                )
                LabeledContent(l("照片缩略图缓存"), value: QuickNoteAttachmentStorage.formattedFileSize(photoThumbnailCacheBytes))
                LabeledContent(l("附件缩略图缓存"), value: QuickNoteAttachmentStorage.formattedFileSize(quickNoteThumbnailCacheBytes))
                LabeledContent(l("缩略图缓存合计"), value: QuickNoteAttachmentStorage.formattedFileSize(mediaThumbnailCacheBytes))
                Button(role: .destructive) {
                    clearMediaThumbnailCaches()
                } label: {
                    Label(l("清理缩略图缓存"), systemImage: "trash")
                }
                .disabled(mediaThumbnailCacheBytes == 0)
            }

            Section(l("处理")) {
                Button {
                    showReferenceFixConfirm = true
                } label: {
                    Label(l("修复引用与关联（不删原件）"), systemImage: "wrench.and.screwdriver")
                }
                .disabled(referenceIssueCount == 0)
                Button(role: .destructive) {
                    showOrphanFileCleanupConfirm = true
                } label: {
                    Label(l("清理孤立原文件"), systemImage: "trash")
                }
                .disabled(orphanFileIssueCount == 0)
                Button {
                    createDataHealthRepairTodo()
                } label: {
                    Label(l("生成健康整改待办"), systemImage: "checklist.checked")
                }
                .disabled(totalIssues == 0)
                Button {
                    exportHealthReport()
                } label: {
                    Label(l("导出健康报告"), systemImage: "square.and.arrow.up")
                }
                if !storageIssues.isEmpty {
                    Button(role: .destructive) {
                        StorageIssueLog.clear()
                        _ = store.scanDataHealthNow(reason: .manual)
                    } label: {
                        Label(l("清空存储错误记录"), systemImage: "trash")
                    }
                }
            }

            issueRepairImpactPreviewSection

            issueRepairRecordPreviewSection

            issueFilterSection

            ForEach(displayedIssueSections) { section in
                issueSection(section)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomContentInset)
        }
        .modifier(OptionalInlineTitleModifier(
            isEnabled: showsNavigationTitle,
            title: l("数据健康检查")
        ))
        .searchable(text: $issueSearchText, prompt: Text(l("搜索问题标题、详情、项目")))
        .task {
            if store.latestDataHealthSnapshot == nil {
                store.runDataHealthScanNow(reason: .manual)
            } else {
                store.scheduleDataHealthScanIfStale(reason: .scheduled, maxAge: 15 * 60)
            }
        }
        .onAppear {
            handleRepairRequestIfNeeded(repairRequestID)
        }
        .onChange(of: repairRequestID) { _, newValue in
            handleRepairRequestIfNeeded(newValue)
        }
        .alert(l("修复引用与关联？"), isPresented: $showReferenceFixConfirm) {
            Button(l("取消"), role: .cancel) {}
            Button(l("修复"), role: .destructive) {
                repairReferenceIssues()
            }
        } message: {
            Text(referenceRepairConfirmMessage)
        }
        .alert(l("清理孤立原文件？"), isPresented: $showOrphanFileCleanupConfirm) {
            Button(l("取消"), role: .cancel) {}
            Button(l("清理"), role: .destructive) {
                cleanupOrphanFiles()
            }
        } message: {
            Text(orphanCleanupConfirmMessage)
        }
        .confirmationDialog(l("当前异常需要逐项处理"), isPresented: $showRepairGuidanceDialog) {
            Button(l("生成健康整改待办")) {
                createDataHealthRepairTodo()
            }
            Button(l("展开异常列表")) {
                expandedIssueSectionIDs = Set(issueSections.map(\.id))
                operationNotice = .info(l("已展开异常列表，请按分组逐项处理。"))
            }
            Button(l("取消"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: l("检测到 %lld 项异常，但当前没有可一键执行的引用修复。可先生成整改待办，或直接展开异常列表处理。"),
                    Int64(totalIssues)
                )
            )
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .plainText,
            defaultFilename: exportPayload?.defaultFilename ?? l("数据健康报告.txt")
        ) { result in
            handleHealthReportExportCompletion(result)
        }
        .operationToast(notice: $operationNotice)
    }
}
