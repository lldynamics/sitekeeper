import SwiftUI

struct DataManagementShortcutCardModel: Identifiable {
    let id: String
    let target: DataManagementView.DataSafetySecondaryTarget
    let title: String
    let subtitle: String
    let icon: String
    let tone: StatusChipTone
    let isSelected: Bool
}

struct DataManagementSecondaryFlowShortcutGrid: View {
    let usesWideLayout: Bool
    let usesCompactRow: Bool
    let cards: [DataManagementShortcutCardModel]
    let onSelect: (DataManagementView.DataSafetySecondaryTarget) -> Void

    init(
        usesWideLayout: Bool,
        cards: [DataManagementShortcutCardModel],
        onSelect: @escaping (DataManagementView.DataSafetySecondaryTarget) -> Void,
        usesCompactRow: Bool? = nil
    ) {
        self.usesWideLayout = usesWideLayout
        self.usesCompactRow = usesCompactRow ?? !usesWideLayout
        self.cards = cards
        self.onSelect = onSelect
    }

    var body: some View {
        if usesCompactRow {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ForEach(cards) { card in
                        compactShortcutButton(card)
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: usesWideLayout ? 154 : 134), spacing: AppSpacing.tight)],
                alignment: .leading,
                spacing: AppSpacing.tight
            ) {
                ForEach(cards) { card in
                    shortcutCardButton(card)
                }
            }
            .padding(.horizontal)
        }
    }

    private func shortcutCardButton(_ card: DataManagementShortcutCardModel) -> some View {
        Button {
            onSelect(card.target)
        } label: {
            AppPanel(
                tone: card.isSelected ? selectedCardTone(for: card.tone) : .grouped,
                cornerRadius: 10,
                padding: 10,
                stroke: card.isSelected ? card.tone.tint.opacity(0.3) : Color.appStrokeSecondary.opacity(0.35)
            ) {
                HStack(alignment: .top, spacing: AppSpacing.tight) {
                    Image(systemName: card.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(card.tone.tint)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(card.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("data-management-shortcut-\(card.id)")
    }

    private func compactShortcutButton(_ card: DataManagementShortcutCardModel) -> some View {
        Button {
            onSelect(card.target)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: card.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(card.tone.tint)
                    .frame(width: 16, height: 16)
                Text(card.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background {
                Capsule()
                    .fill(card.isSelected ? card.tone.tint.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
            }
            .overlay {
                Capsule()
                    .stroke(card.isSelected ? card.tone.tint.opacity(0.35) : Color.appStrokeSecondary.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("data-management-shortcut-\(card.id)")
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
                    Label(String(localized: "数据安全状态"), systemImage: "externaldrive.badge.shield.half.filled")
                        .font(.headline)

                    Text(String(localized: "先看当前风险，再选择备份、修复、清理或导出；普通入口按处理顺序排列。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: AppSpacing.tight) {
                        statusChip(title: String(localized: "备份"), value: backupStatusValue, tone: backupStatusTone)
                        statusChip(title: String(localized: "健康"), value: healthStatusValue, tone: healthStatusTone)
                        statusChip(title: String(localized: "清理"), value: cleanupStatusValue, tone: cleanupStatusTone)
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
                                        Label(String(localized: "导入恢复"), systemImage: "square.and.arrow.down")
                                    }

                                    Button {
                                        onOpenExport()
                                    } label: {
                                        Label(String(localized: "导出交付"), systemImage: "square.and.arrow.up")
                                    }

                                    Button {
                                        onOpenStorageCleanup()
                                    } label: {
                                        Label(String(localized: "存储清理"), systemImage: "internaldrive")
                                    }

                                    Button {
                                        onOpenAudit()
                                    } label: {
                                        Label(String(localized: "审计"), systemImage: "checklist.checked")
                                    }
                                } label: {
                                    Label(String(localized: "更多操作"), systemImage: "ellipsis.circle")
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
            return String(localized: "正常")
        case .warning:
            return String(localized: "注意")
        case .risk:
            return String(localized: "风险")
        case .primary:
            return String(localized: "已启用")
        default:
            return String(localized: "待处理")
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
            Label(String(localized: "测试数据导入"), systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))

            Text(String(localized: "可一键恢复一套更完整的测试环境。当前样例包含多个项目、材料、报价、进度、图纸、票据、照片与附件。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(String(localized: "当前环境允许导入测试数据。"), systemImage: "checkmark.shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.appSuccess)

            if hasAnyBusinessData {
                Label(String(localized: "会覆盖当前本机数据，建议先导出备份 ZIP。"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appRisk)
            }

            Button {
                onImport()
            } label: {
                Label(String(localized: "清空并导入测试数据"), systemImage: "square.and.arrow.down")
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
                Label(String(localized: "去备份"), systemImage: "externaldrive.badge.plus")
            }

            Button {
                selectedTab = .backupAndRestore
                shouldAutoOpenBackupImporter = true
            } label: {
                Label(String(localized: "导入恢复"), systemImage: "square.and.arrow.down")
            }

            Button {
                selectedTab = .export
            } label: {
                Label(String(localized: "导出交付"), systemImage: "square.and.arrow.up")
            }

            Divider()

            Button {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .health
            } label: {
                Label(String(localized: "健康检查"), systemImage: "stethoscope")
            }

            Button {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .storage
            } label: {
                Label(String(localized: "存储清理"), systemImage: "internaldrive")
            }

            Button {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .audit
            } label: {
                Label(String(localized: "审计"), systemImage: "checklist.checked")
            }

            if sampleDataImportEnabled || hasHistoryRecords {
                Divider()
            }

            if showsUITestBackupPreviewShortcut {
                Button {
                    selectedTab = .backupAndRestore
                } label: {
                    Label(String(localized: "UI测试：模拟覆盖导入预览"), systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("ui-test-backup-preview")

                Button {
                    showUITestOverwriteImportConfirm = true
                } label: {
                    Label(String(localized: "UI测试：触发覆盖二次确认"), systemImage: "exclamationmark.triangle")
                }
                .accessibilityIdentifier("ui-test-overwrite-confirm")
            }

            if sampleDataImportEnabled {
                Button(role: hasAnyBusinessData ? .destructive : nil) {
                    showSampleDataImportConfirm = true
                } label: {
                    Label(String(localized: "导入测试数据"), systemImage: "testtube.2")
                }
            }

            if hasHistoryRecords {
                if historyTrimCount > 0 {
                    Button {
                        onTrimHistory()
                    } label: {
                        Label(String(format: String(localized: "按策略清理 %lld 条"), Int64(historyTrimCount)), systemImage: "clock.arrow.circlepath")
                    }
                }

                Button(role: .destructive) {
                    showClearHistoryConfirm = true
                } label: {
                    Label(String(localized: "清空计算历史"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .visibleIconStyle()
        }
        .accessibilityLabel(String(localized: "数据安全中心操作"))
        .accessibilityIdentifier("data-management-actions-menu")
    }
}
