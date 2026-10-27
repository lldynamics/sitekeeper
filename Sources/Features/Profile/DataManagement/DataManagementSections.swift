import SwiftUI

struct DataManagementSafetyHeaderSection: View {
    let backupStatusValue: String
    let backupStatusTone: StatusChipTone
    let healthStatusValue: String
    let healthStatusTone: StatusChipTone
    let cleanupStatusValue: String
    let cleanupStatusTone: StatusChipTone
    let action: DataManagementView.DataSafetyPrimaryAction
    let onPrimaryAction: () -> Void
    let onOpenBackupImport: () -> Void
    let onOpenExport: () -> Void
    let onOpenStorageCleanup: () -> Void
    let onOpenAudit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            AppPanel(
                tone: .grouped,
                cornerRadius: 12,
                padding: AppSpacing.normal,
                stroke: Color.appStrokeSecondary.opacity(0.45)
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    Label(AppLocalization.string("数据安全状态"), systemImage: "externaldrive.badge.shield.half.filled")
                        .font(.headline)

                    Text(AppLocalization.string("先看当前风险，再选择备份、修复、清理或导出；普通入口按处理顺序排列。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: AppSpacing.tight) {
                        statusChip(title: AppLocalization.string("备份"), value: backupStatusValue, tone: backupStatusTone)
                        statusChip(title: AppLocalization.string("健康"), value: healthStatusValue, tone: healthStatusTone)
                        statusChip(title: AppLocalization.string("清理"), value: cleanupStatusValue, tone: cleanupStatusTone)
                    }

                    AppPanel(
                        tone: selectedCardTone(for: action.tone),
                        cornerRadius: 10,
                        padding: 12,
                        stroke: action.tone.tint.opacity(0.2)
                    ) {
                        VStack(alignment: .leading, spacing: AppSpacing.tight) {
                            HStack(alignment: .top, spacing: AppSpacing.tight) {
                                Image(systemName: action.systemImage)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(action.tone.tint)
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(action.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 4)
                            }

                            HStack(spacing: AppSpacing.tight) {
                                Button {
                                    onPrimaryAction()
                                } label: {
                                    Label(action.buttonTitle, systemImage: "arrow.right.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.appProminent(tint: action.tone.tint))

                                Menu {
                                    Button {
                                        onOpenBackupImport()
                                    } label: {
                                        Label(AppLocalization.string("导入恢复"), systemImage: "square.and.arrow.down")
                                    }

                                    Button {
                                        onOpenExport()
                                    } label: {
                                        Label(AppLocalization.string("导出交付"), systemImage: "square.and.arrow.up")
                                    }

                                    Button {
                                        onOpenStorageCleanup()
                                    } label: {
                                        Label(AppLocalization.string("存储清理"), systemImage: "internaldrive")
                                    }

                                    Button {
                                        onOpenAudit()
                                    } label: {
                                        Label(AppLocalization.string("审计"), systemImage: "checklist.checked")
                                    }
                                } label: {
                                    Label(AppLocalization.string("更多操作"), systemImage: "ellipsis.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func statusChip(title: String, value: String, tone: StatusChipTone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            StatusChip(text: chipLabel(for: tone), tone: tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipLabel(for tone: StatusChipTone) -> String {
        switch tone {
        case .success:
            return AppLocalization.string("正常")
        case .warning:
            return AppLocalization.string("注意")
        case .risk:
            return AppLocalization.string("风险")
        case .primary:
            return AppLocalization.string("已启用")
        default:
            return AppLocalization.string("待处理")
        }
    }

    private func selectedCardTone(for tone: StatusChipTone) -> AppSurfaceTone {
        switch tone {
        case .success:
            return .tinted(Color.appSuccessSurfaceSubtle)
        case .warning:
            return .tinted(Color.appWarning.opacity(0.12))
        case .risk:
            return .tinted(Color.appRiskSurface)
        case .doc:
            return .tinted(Color.appDocSurfaceSubtle)
        case .primary:
            return .tinted(Color.appPrimarySurfaceSubtle)
        default:
            return .grouped
        }
    }
}

struct DataManagementSampleDataImportCard: View {
    let hasAnyBusinessData: Bool
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Label(AppLocalization.string("测试数据导入"), systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))

            Text(AppLocalization.string("可一键恢复一套更完整的测试环境。当前样例包含多个项目、材料、报价、进度、图纸、票据、照片与附件。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(AppLocalization.string("当前环境允许导入测试数据。"), systemImage: "checkmark.shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.appSuccess)

            if hasAnyBusinessData {
                Label(AppLocalization.string("会覆盖当前本机数据，建议先导出备份 ZIP。"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appRisk)
            }

            Button {
                onImport()
            } label: {
                Label(AppLocalization.string("清空并导入测试数据"), systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.appWarning)
            .accessibilityIdentifier("data-management-import-sample-data")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal)
    }
}

struct DataManagementCompactActionMenu: View {
    @Binding var selectedTab: DataManagementView.DataManagementTab
    @Binding var healthCleanupSection: DataManagementView.HealthCleanupSection
    @Binding var shouldAutoOpenBackupImporter: Bool
    @Binding var showClearHistoryConfirm: Bool
    @Binding var showSampleDataImportConfirm: Bool
    @Binding var showUITestOverwriteImportConfirm: Bool
    let sampleDataImportEnabled: Bool
    let showsUITestBackupPreviewShortcut: Bool
    let hasHistoryRecords: Bool
    let hasAnyBusinessData: Bool
    let historyTrimCount: Int
    let onTrimHistory: () -> Void

    var body: some View {
        Menu {
            Button {
                selectedTab = .backupAndRestore
            } label: {
                Label(AppLocalization.string("去备份"), systemImage: "externaldrive.badge.plus")
            }

            Button {
                selectedTab = .backupAndRestore
                shouldAutoOpenBackupImporter = true
            } label: {
                Label(AppLocalization.string("导入恢复"), systemImage: "square.and.arrow.down")
            }

            Button {
                selectedTab = .export
            } label: {
                Label(AppLocalization.string("导出交付"), systemImage: "square.and.arrow.up")
            }

            Divider()

            Button {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .health
            } label: {
                Label(AppLocalization.string("健康检查"), systemImage: "stethoscope")
            }

            Button {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .storage
            } label: {
                Label(AppLocalization.string("存储清理"), systemImage: "internaldrive")
            }

            Button {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .audit
            } label: {
                Label(AppLocalization.string("审计"), systemImage: "checklist.checked")
            }

            if sampleDataImportEnabled || hasHistoryRecords {
                Divider()
            }

            if showsUITestBackupPreviewShortcut {
                Button {
                    selectedTab = .backupAndRestore
                } label: {
                    Label(AppLocalization.string("UI测试：模拟覆盖导入预览"), systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("ui-test-backup-preview")

                Button {
                    showUITestOverwriteImportConfirm = true
                } label: {
                    Label(AppLocalization.string("UI测试：触发覆盖二次确认"), systemImage: "exclamationmark.triangle")
                }
                .accessibilityIdentifier("ui-test-overwrite-confirm")
            }

            if sampleDataImportEnabled {
                Button(role: hasAnyBusinessData ? .destructive : nil) {
                    showSampleDataImportConfirm = true
                } label: {
                    Label(AppLocalization.string("导入测试数据"), systemImage: "testtube.2")
                }
            }

            if hasHistoryRecords {
                if historyTrimCount > 0 {
                    Button {
                        onTrimHistory()
                    } label: {
                        Label(String(format: AppLocalization.string("按策略清理 %lld 条"), Int64(historyTrimCount)), systemImage: "clock.arrow.circlepath")
                    }
                }

                Button(role: .destructive) {
                    showClearHistoryConfirm = true
                } label: {
                    Label(AppLocalization.string("清空计算历史"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .visibleIconStyle()
        }
        .accessibilityLabel(AppLocalization.string("数据安全中心操作"))
        .accessibilityIdentifier("data-management-actions-menu")
    }
}
