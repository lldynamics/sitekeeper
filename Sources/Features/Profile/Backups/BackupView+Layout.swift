import SwiftUI
import UniformTypeIdentifiers

extension BackupView {
    var usesWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if showsNavigationTitle {
                backupSurface
                    .navigationTitle(AppLocalization.string("数据安全中心"))
            } else {
                backupSurface
            }
        }
    }

    var backupSurface: some View {
        ZStack {
            if usesWideLayout {
                HStack(alignment: .top, spacing: 14) {
                    backupSidebar
                        .frame(minWidth: 260, maxWidth: 320)
                    backupDetailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Form {
                    DataManagementMobileScrollProbeRow(onOffsetChange: onMobileScrollOffsetChange)
                    backupQuickStartSection
                    backupLocalSection
                    cloudBackupSection
                    backupMicroGuideSection
                    backupEstimateSection
                    backupStatusSection
                }
                .accessibilityIdentifier("backup-local-form")
                .contentMargins(.bottom, bottomContentInset, for: .scrollContent)
            }
            if isExportingArchive || cloudState.isUploadingCloudBackup {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    exportProgressCard
                }
            }
            if isImportingBackup {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    importProgressCard
                }
            }
        }
        .sheet(isPresented: $showExporter) {
            AppPreparedFileExporterSheet(fileURL: exportFileURL) { result in
                if case .success = result {
                    setStatus(exportSummary.isEmpty ? AppLocalization.string("导出成功") : exportSummary)
                    localBackupLastSuccessAt = Date().timeIntervalSince1970
                    hasCompletedBackupExportTask = true
                    lastExportSucceeded = true
                    lastImportSucceeded = false
                }
                showExporter = false
                cleanupExportArchiveIfNeeded()
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zipArchive]) { result in
            switch result {
            case .success(let url):
                startPreviewImport(from: url)
            case .failure(let error):
                setStatus(String(format: AppLocalization.string("未能读取所选文件：%@"), error.localizedDescription))
                OperationAuditLog.record(
                    action: .import,
                    outcome: .failed,
                    summary: String(format: AppLocalization.string("未能读取所选文件：%@"), error.localizedDescription),
                    source: "BackupView"
                )
            }
        }
        .sheet(isPresented: $showPreview) {
            if let preview = pendingImportPreview {
                importPreview(preview: preview)
            } else {
                AppBusinessFormSheet(
                    title: AppLocalization.string("导入预览"),
                    cancelTitle: nil,
                    primaryActionTitle: nil
                ) {
                    ProgressView(AppLocalization.string("正在加载预览..."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
        }
        .alert(AppLocalization.string("确认覆盖导入？"), isPresented: $showUITestOverwriteImportConfirm) {
            Button(AppLocalization.string("取消"), role: .cancel) {}
            Button(AppLocalization.string("覆盖导入"), role: .destructive) {}
        } message: {
            Text(AppLocalization.string("覆盖会删除当前本机数据，请先导出备份。"))
        }
        .alert(AppLocalization.string("从 iCloud 恢复备份？"), isPresented: $cloudState.showCloudRestoreConfirm) {
            Button(AppLocalization.string("取消"), role: .cancel) {}
            Button(AppLocalization.string("读取备份")) {
                restorePendingCloudBackup()
            }
        } message: {
            Text(AppLocalization.string("将先读取云端备份预览，确认后可选择合并或覆盖当前本机数据。"))
        }
        .onAppear {
            normalizeCloudBackupSettings()
            refreshBackupEstimateIfNeeded(force: true)
            refreshCloudBackups()
            guard autoOpenImporter, !didAutoOpenImporter else { return }
            didAutoOpenImporter = true
            onAutoOpenImporterConsumed?()
            showImporter = true
        }
        .onChange(of: backupEstimateSignature) { _, _ in
            refreshBackupEstimateIfNeeded()
        }
        .onDisappear {
            // 展示预览/导入导出弹层时，父视图可能暂时 disappear，避免误清空待导入预览状态。
            guard !showPreview, !showImporter, !showExporter else { return }
            resetBackupRuntimeStateOnDisappear()
        }
    }

    var backupSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(AppLocalization.string("备份恢复"), systemImage: "arrow.triangle.2.circlepath.icloud")
                        .font(.headline)

                    Text(AppLocalization.string("先做本地或 iCloud 备份，再执行恢复预览和正式导入。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(DataSafetySidebarPanelModifier())

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.string("安全链路"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(BackupSection.allCases, id: \.self) { section in
                        Button {
                            selectedBackupSection = section
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: section.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 16)
                                Text(section.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if selectedBackupSection == section {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.appWarning)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background {
                                AppSurface(
                                    tone: selectedBackupSection == section ? .tinted(Color.appPrimarySurface) : .grouped,
                                    cornerRadius: 10
                                ) {
                                    Color.clear
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.string("立即执行"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button {
                        exportBackupZIP()
                    } label: {
                        Label(AppLocalization.string("生成本地备份 ZIP"), systemImage: "archivebox")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.appSuccess)
                    .disabled(isBusy)

                    Button {
                        showImporter = true
                    } label: {
                        Label(AppLocalization.string("读取恢复备份 ZIP"), systemImage: "square.and.arrow.down")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)

                    Button {
                        uploadBackupToICloud()
                    } label: {
                        Label(AppLocalization.string("同步备份到 iCloud"), systemImage: "icloud.and.arrow.up")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.appPrimaryAction)
                    .disabled(isBusy)
                }

                if !statusMessage.isEmpty {
                    InlineNotice(
                        title: AppLocalization.string("当前状态"),
                        message: statusMessage,
                        tone: .info
                    )
                }

                Spacer()
            }
            .padding(.vertical, 2)
            .background(alignment: .top) {
                if onMobileScrollOffsetChange != nil {
                    DataManagementMobileScrollProbeRow(onOffsetChange: onMobileScrollOffsetChange)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomContentInset)
        }
    }

    var backupDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DataSafetyStatusStrip(items: backupStatusItems)
                switch selectedBackupSection {
                case .local:
                    backupQuickStartSection
                    backupLocalSection
                    backupMicroGuideSection
                case .cloud:
                    cloudBackupSection
                case .overview:
                    backupEstimateSection
                    backupMicroGuideSection
                }
                backupStatusSection
            }
            .padding(4)
            .background(alignment: .top) {
                if onMobileScrollOffsetChange != nil {
                    DataManagementMobileScrollProbeRow(onOffsetChange: onMobileScrollOffsetChange)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomContentInset)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

struct DataSafetySidebarPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        AppPanel(
            tone: .grouped,
            cornerRadius: 12,
            padding: 12,
            stroke: Color.appStrokeSecondary.opacity(0.45)
        ) {
            content
        }
    }
}
