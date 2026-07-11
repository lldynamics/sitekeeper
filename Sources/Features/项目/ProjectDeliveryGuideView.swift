import SwiftUI

private enum ProjectDeliveryGuideAnchor: Hashable {
    case packageExport
}

struct ProjectDeliveryGuideView: View {
    let data: ProjectDeliveryGuideData
    let onStartExport: () -> Void
    let onExportInspection: () -> Void
    let onOpenMode: (ProjectDetailMode) -> Void
    let onRepair: (ProjectDeliveryRepairAction) -> Void

    private var repairWizardSteps: [ProjectDeliveryRepairWizardStep] {
        ProjectDeliveryGuideValidation.repairWizardSteps(for: data)
    }

    private var firstPendingRepairStepID: String? {
        ProjectDeliveryGuideValidation.firstPendingRepairStepID(in: repairWizardSteps)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        readinessCard
                    }

                    ProjectDeliveryGuideRepairWizardSectionView(
                        steps: repairWizardSteps,
                        firstPendingRepairStepID: firstPendingRepairStepID,
                        onRepair: onRepair
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(ProjectDeliveryGuideAnchor.packageExport, anchor: .center)
                        }
                    }

                    Section(String(localized: "交付健康分")) {
                        ForEach(ProjectDeliveryHealth.Issue.allCases) { issue in
                            ProjectDeliveryGuideHealthRowView(
                                issue: issue,
                                deliveryHealth: data.deliveryHealth,
                                onRepair: onRepair
                            )
                        }
                    }

                    Section(String(localized: "交付检查")) {
                        ProjectDeliveryGuideCheckRowView(
                            title: String(localized: "缺日志检查"),
                            detail: ProjectDeliveryGuideValidation.logCoverageDetail(for: data),
                            status: data.missingLogDateCount == 0 ? .ok : .warning,
                            fixActionTitle: String(localized: "去处理"),
                            fixAction: { onOpenMode(.records) }
                        )
                        ProjectDeliveryGuideCheckRowView(
                            title: String(localized: "缺票检查"),
                            detail: data.missingReceiptCount == 0
                                ? String(localized: "全部已关联")
                                : String(format: String(localized: "还有 %lld 条待关联"), Int64(data.missingReceiptCount)),
                            status: data.missingReceiptCount == 0 ? .ok : .warning,
                            fixActionTitle: String(localized: "补票据"),
                            fixAction: { onRepair(.attachReceipts) }
                        )
                        ProjectDeliveryGuideCheckRowView(
                            title: String(localized: "未完成待办"),
                            detail: data.openTodoCount == 0
                                ? String(localized: "没有未完成待办")
                                : String(format: String(localized: "还有 %lld 条待办未完成"), Int64(data.openTodoCount)),
                            status: data.openTodoCount == 0 ? .ok : .warning,
                            fixActionTitle: String(localized: "处理待办"),
                            fixAction: { onRepair(.resolveTodos) }
                        )
                        ProjectDeliveryGuideCheckRowView(
                            title: String(localized: "图纸当前版检查"),
                            detail: ProjectDeliveryGuideValidation.drawingCurrentVersionDetail(for: data),
                            status: ProjectDeliveryGuideValidation.drawingCurrentVersionStatus(for: data),
                            fixActionTitle: data.drawingCount == 0
                                ? String(localized: "导入图纸")
                                : String(localized: "标当前版"),
                            fixAction: {
                                onRepair(data.drawingCount == 0 ? .importDrawings : .markCurrentDrawingVersion)
                            }
                        )
                        ProjectDeliveryGuideCheckRowView(
                            title: String(localized: "未关闭图纸问题"),
                            detail: data.openDrawingIssueCount == 0
                                ? String(localized: "没有未关闭图纸问题")
                                : String(format: String(localized: "还有 %lld 项未关闭"), Int64(data.openDrawingIssueCount)),
                            status: data.openDrawingIssueCount == 0 ? .ok : .warning,
                            fixActionTitle: String(localized: "处理问题"),
                            fixAction: { onRepair(.resolveDrawingIssues) }
                        )
                        ProjectDeliveryGuideCheckRowView(
                            title: String(localized: "联系人缺失检查"),
                            detail: data.contactCount > 0
                                ? String(format: String(localized: "已维护 %lld 位"), Int64(data.contactCount))
                                : String(localized: "还没有联系人"),
                            status: data.contactCount > 0 ? .ok : .warning,
                            fixActionTitle: String(localized: "去处理"),
                            fixAction: { onOpenMode(.assets) }
                        )
                        ProjectDeliveryGuideCheckRowView(
                            title: String(localized: "未结清检查"),
                            detail: ProjectDeliveryGuideValidation.unsettledFinancialDetail(for: data),
                            status: data.unsettledFinancialCount == 0 ? .ok : .warning,
                            fixActionTitle: String(localized: "去处理"),
                            fixAction: { onOpenMode(.finance) }
                        )
                        ProjectDeliveryGuideCheckRowView(
                            title: String(localized: "原件完整性"),
                            detail: data.hasBlockingMissingOriginals
                                ? String(format: String(localized: "检测到 %lld 个缺失原件"), Int64(data.missingOriginalEntries.count))
                                : String(localized: "未发现缺失原件"),
                            status: data.hasBlockingMissingOriginals ? .error : .ok,
                            fixActionTitle: String(localized: "重新导入"),
                            fixAction: { onRepair(.restoreMissingOriginals) }
                        )
                        ProjectDeliveryGuideBackupRowView(
                            backupState: data.backupState,
                            onRepair: onRepair
                        )
                    }

                    if data.hasDeliveryChecklistWarning {
                        Section {
                            Text(String(localized: "仍可先预览交付包，但建议先补齐日志、票据、图纸当前版、联系人和未结清账目，再执行最终交付。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if data.hasBlockingMissingOriginals {
                        Section(String(localized: "缺失原件（导出前需处理）")) {
                            ForEach(Array(data.missingOriginalEntries.prefix(20)), id: \.self) { item in
                                HStack(alignment: .top, spacing: AppSpacing.tight) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color.appRisk)
                                        .font(.caption)
                                    Text(item)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if data.missingOriginalEntries.count > 20 {
                                Text(
                                    String(
                                        format: String(localized: "还有 %lld 项未显示"),
                                        Int64(data.missingOriginalEntries.count - 20)
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section(String(localized: "交付包预估")) {
                        LabeledContent(String(localized: "工程名称")) {
                            Text(data.projectName)
                                .lineLimit(1)
                        }
                        LabeledContent(String(localized: "预计原始附件体积")) {
                            Text(ProjectDetailImportExportActions.formattedBytes(data.estimatedPackageBytes))
                                .foregroundStyle(.secondary)
                        }
                        Text(String(localized: "将导出包含日志、图纸、票据、联系人、财务摘要与原件的 ZIP 交付包。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .id(ProjectDeliveryGuideAnchor.packageExport)

                    Section(String(localized: "project.preDeliveryInspection.export.section")) {
                        Button {
                            onExportInspection()
                        } label: {
                            Label(String(localized: "project.preDeliveryInspection.export.button"), systemImage: "checklist")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Text(String(localized: "project.preDeliveryInspection.export.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button {
                            onStartExport()
                        } label: {
                            Label(ProjectDeliveryGuideValidation.exportButtonTitle(for: data), systemImage: "archivebox.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appProminent())
                        .disabled(data.hasBlockingMissingOriginals)
                        .accessibilityIdentifier("project-delivery-export-package")
                    } footer: {
                        if data.hasBlockingMissingOriginals {
                            Text(String(localized: "检测到缺失原件，需先补齐后才能导出。"))
                        }
                    }
                }
                .navigationTitle(String(localized: "完工交付向导"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var readinessCard: some View {
        HStack(alignment: .top, spacing: AppSpacing.normal) {
            Image(systemName: data.isReadyForDelivery ? "checkmark.seal.fill" : "checklist.unchecked")
                .font(.title2.weight(.semibold))
                .foregroundStyle(data.deliveryHealth.isDeliverable ? Color.appSuccess : Color.appRisk)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    String(
                        format: String(localized: "交付健康分 %lld · %@"),
                        Int64(data.deliveryHealth.score),
                        data.deliveryHealth.verdictTitle
                    )
                )
                .font(.headline)
                ProgressView(value: Double(data.deliveryHealth.score), total: 100)
                    .tint(data.deliveryHealth.isDeliverable ? Color.appSuccess : Color.appRisk)
                Text(ProjectDeliveryGuideValidation.readinessDetail(for: data))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
