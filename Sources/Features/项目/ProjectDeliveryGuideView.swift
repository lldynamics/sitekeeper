import SwiftUI

private enum ProjectDeliveryGuideAnchor: Hashable {
    case packageExport
}

private struct ProjectDeliveryRepairWizardStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: ProjectDeliveryRepairAction
    let isResolved: Bool
}

struct ProjectDeliveryGuideView: View {
    let data: ProjectDeliveryGuideData
    let onStartExport: () -> Void
    let onOpenMode: (ProjectDetailMode) -> Void
    let onRepair: (ProjectDeliveryRepairAction) -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        readinessCard
                    }

                    repairWizardSection {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(ProjectDeliveryGuideAnchor.packageExport, anchor: .center)
                        }
                    }

                    Section(String(localized: "交付健康分")) {
                        ForEach(ProjectDeliveryHealth.Issue.allCases) { issue in
                            healthRow(issue)
                        }
                    }

                    Section(String(localized: "交付检查")) {
                    guideRow(
                        title: String(localized: "缺日志检查"),
                        detail: logCoverageDetail,
                        status: data.missingLogDateCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.records)
                    }
                    guideRow(
                        title: String(localized: "缺票检查"),
                        detail: data.missingReceiptCount == 0
                            ? String(localized: "全部已关联")
                            : String(format: String(localized: "还有 %lld 条待关联"), Int64(data.missingReceiptCount)),
                        status: data.missingReceiptCount == 0 ? .ok : .warning,
                        fixActionTitle: String(localized: "补票据")
                    ) {
                        onRepair(.attachReceipts)
                    }
                    guideRow(
                        title: String(localized: "未完成待办"),
                        detail: data.openTodoCount == 0
                            ? String(localized: "没有未完成待办")
                            : String(format: String(localized: "还有 %lld 条待办未完成"), Int64(data.openTodoCount)),
                        status: data.openTodoCount == 0 ? .ok : .warning,
                        fixActionTitle: String(localized: "处理待办")
                    ) {
                        onRepair(.resolveTodos)
                    }
                    guideRow(
                        title: String(localized: "图纸当前版检查"),
                        detail: drawingCurrentVersionDetail,
                        status: drawingCurrentVersionStatus,
                        fixActionTitle: data.drawingCount == 0
                            ? String(localized: "导入图纸")
                            : String(localized: "标当前版")
                    ) {
                        onRepair(data.drawingCount == 0 ? .importDrawings : .markCurrentDrawingVersion)
                    }
                    guideRow(
                        title: String(localized: "未关闭图纸问题"),
                        detail: data.openDrawingIssueCount == 0
                            ? String(localized: "没有未关闭图纸问题")
                            : String(format: String(localized: "还有 %lld 项未关闭"), Int64(data.openDrawingIssueCount)),
                        status: data.openDrawingIssueCount == 0 ? .ok : .warning,
                        fixActionTitle: String(localized: "处理问题")
                    ) {
                        onRepair(.resolveDrawingIssues)
                    }
                    guideRow(
                        title: String(localized: "联系人缺失检查"),
                        detail: data.contactCount > 0
                            ? String(format: String(localized: "已维护 %lld 位"), Int64(data.contactCount))
                            : String(localized: "还没有联系人"),
                        status: data.contactCount > 0 ? .ok : .warning
                    ) {
                        onOpenMode(.assets)
                    }
                    guideRow(
                        title: String(localized: "未结清检查"),
                        detail: unsettledFinancialDetail,
                        status: data.unsettledFinancialCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.finance)
                    }
                    guideRow(
                        title: String(localized: "原件完整性"),
                        detail: data.hasBlockingMissingOriginals
                            ? String(format: String(localized: "检测到 %lld 个缺失原件"), Int64(data.missingOriginalEntries.count))
                            : String(localized: "未发现缺失原件"),
                        status: data.hasBlockingMissingOriginals ? .error : .ok,
                        fixActionTitle: String(localized: "重新导入")
                    ) {
                        onRepair(.restoreMissingOriginals)
                    }
                    backupGuideRow
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

                Section {
                    Button {
                        onStartExport()
                    } label: {
                        Label(exportButtonTitle, systemImage: "archivebox.fill")
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

    @ViewBuilder
    private func repairWizardSection(onReturnToExport: @escaping () -> Void) -> some View {
        Section(String(localized: "交付修复向导")) {
            ForEach(Array(repairWizardSteps.enumerated()), id: \.element.id) { offset, step in
                repairWizardRow(
                    step: step,
                    number: offset + 1,
                    isCurrent: firstPendingRepairStepID == step.id
                )
            }
            if repairWizardSteps.allSatisfy(\.isResolved) {
                Button {
                    onReturnToExport()
                } label: {
                    Label(String(localized: "回到交付包导出页"), systemImage: "archivebox.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appProminent())
            } else if let currentStep = repairWizardSteps.first(where: { $0.id == firstPendingRepairStepID }) {
                Text(String(format: String(localized: "当前步骤：%@"), currentStep.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func repairWizardRow(
        step: ProjectDeliveryRepairWizardStep,
        number: Int,
        isCurrent: Bool
    ) -> some View {
        let isWaiting = !step.isResolved && !isCurrent
        return HStack(alignment: .top, spacing: AppSpacing.tight) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(step.isResolved ? Color.appSuccess : (isCurrent ? Color.appRisk : .secondary))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(step.isResolved ? Color.appSuccessSurfaceSubtle : Color(.secondarySystemBackground))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.callout.weight(.semibold))
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(repairWizardStatusText(step: step, isCurrent: isCurrent))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(step.isResolved ? Color.appSuccess : (isCurrent ? Color.appRisk : .secondary))
            }
            Spacer()
            if step.isResolved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
            } else if isWaiting {
                Text(String(localized: "等待前序"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button(step.actionTitle) {
                    onRepair(step.action)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }

    private var repairWizardSteps: [ProjectDeliveryRepairWizardStep] {
        [
            ProjectDeliveryRepairWizardStep(
                id: "receipts",
                title: String(localized: "补齐票据"),
                detail: data.deliveryHealth.detail(for: .missingReceipts),
                actionTitle: String(localized: "补票据"),
                action: .attachReceipts,
                isResolved: data.missingReceiptCount == 0
            ),
            drawingRepairWizardStep,
            ProjectDeliveryRepairWizardStep(
                id: "originals",
                title: String(localized: "补齐原件"),
                detail: data.hasBlockingMissingOriginals
                    ? String(format: String(localized: "检测到 %lld 个缺失原件"), Int64(data.missingOriginalEntries.count))
                    : String(localized: "缺失原件已补齐。"),
                actionTitle: String(localized: "重新导入"),
                action: .restoreMissingOriginals,
                isResolved: !data.hasBlockingMissingOriginals
            ),
            ProjectDeliveryRepairWizardStep(
                id: "drawingIssues",
                title: String(localized: "关闭图纸问题"),
                detail: data.openDrawingIssueCount == 0
                    ? String(localized: "没有未关闭图纸问题。")
                    : String(format: String(localized: "还有 %lld 项未关闭"), Int64(data.openDrawingIssueCount)),
                actionTitle: String(localized: "处理问题"),
                action: .resolveDrawingIssues,
                isResolved: data.openDrawingIssueCount == 0
            )
        ]
    }

    private var drawingRepairWizardStep: ProjectDeliveryRepairWizardStep {
        if data.drawingCount == 0 {
            return ProjectDeliveryRepairWizardStep(
                id: "drawings",
                title: String(localized: "补齐图纸"),
                detail: String(localized: "项目还没有图纸文件。"),
                actionTitle: String(localized: "导入图纸"),
                action: .importDrawings,
                isResolved: false
            )
        }
        if data.drawingWithoutCurrentCount > 0 {
            return ProjectDeliveryRepairWizardStep(
                id: "drawings",
                title: String(localized: "确认当前版"),
                detail: drawingCurrentVersionDetail,
                actionTitle: String(localized: "标当前版"),
                action: .markCurrentDrawingVersion,
                isResolved: false
            )
        }
        return ProjectDeliveryRepairWizardStep(
            id: "drawings",
            title: String(localized: "补齐图纸"),
            detail: String(localized: "图纸已上传并确认当前版。"),
            actionTitle: String(localized: "导入图纸"),
            action: .importDrawings,
            isResolved: true
        )
    }

    private var firstPendingRepairStepID: String? {
        repairWizardSteps.first { !$0.isResolved }?.id
    }

    private func repairWizardStatusText(step: ProjectDeliveryRepairWizardStep, isCurrent: Bool) -> String {
        if step.isResolved {
            return String(localized: "已完成")
        }
        return isCurrent ? String(localized: "当前步骤") : String(localized: "等待前序")
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
                Text(readinessDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var readinessDetail: String {
        if data.deliveryHealth.isDeliverable {
            if data.isReadyForDelivery {
                return String(localized: "票据、图纸、待办、备份、当前版和原件检查均已通过，可执行最终交付。")
            }
            return String(
                format: String(localized: "核心交付项已通过，另有 %lld 项建议检查。"),
                Int64(data.deliveryWarningCount)
            )
        }
        return data.deliveryHealth.summary
    }

    private var logCoverageDetail: String {
        if data.missingLogDateCount == 0 {
            if data.expectedLogDateCount > 0 {
                return String(
                    format: String(localized: "已覆盖 %lld 个施工日，共 %lld 条日志"),
                    Int64(data.expectedLogDateCount),
                    Int64(data.logCount)
                )
            }
            return data.logCount > 0
                ? String(format: String(localized: "已记录 %lld 条"), Int64(data.logCount))
                : String(localized: "未设置工期，暂无缺日志日期")
        }
        if data.expectedLogDateCount == 0 {
            return String(localized: "未记录施工日志")
        }
        let sample = data.missingLogDateSamples.joined(separator: "、")
        if sample.isEmpty {
            return String(format: String(localized: "缺 %lld 个施工日"), Int64(data.missingLogDateCount))
        }
        return String(
            format: String(localized: "缺 %lld 个施工日：%@"),
            Int64(data.missingLogDateCount),
            sample
        )
    }

    private var unsettledFinancialDetail: String {
        guard data.unsettledFinancialCount > 0 else {
            return String(localized: "没有未结清账目")
        }
        if data.unsettledFinancialAmount > 0 {
            return String(
                format: String(localized: "还有 %lld 笔，合计 %@"),
                Int64(data.unsettledFinancialCount),
                ReportBuilder.money(data.unsettledFinancialAmount)
            )
        }
        return String(
            format: String(localized: "还有 %lld 笔未结清"),
            Int64(data.unsettledFinancialCount)
        )
    }

    private var exportButtonTitle: String {
        data.hasDeliveryChecklistWarning || !data.deliveryHealth.isDeliverable
            ? String(localized: "检查后导出交付包 ZIP")
            : String(localized: "一键导出交付包 ZIP")
    }

    private var backupGuideRow: some View {
        HStack(spacing: AppSpacing.tight) {
            let status: GuideStatus = data.backupState.isFresh ? .ok : .warning
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "最近备份"))
                    .font(.callout.weight(.semibold))
                Text(data.backupState.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !data.backupState.isFresh {
                Button {
                    onRepair(.createBackup)
                } label: {
                    Text(String(localized: "去备份"))
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private func guideRow(
        title: String,
        detail: String,
        status: GuideStatus,
        fixActionTitle: String = String(localized: "去处理"),
        fixAction: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status != .ok, let fixAction {
                Button(fixActionTitle) {
                    fixAction()
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func healthRow(_ issue: ProjectDeliveryHealth.Issue) -> some View {
        let isPassed = data.deliveryHealth.isPassed(issue)
        return HStack(spacing: AppSpacing.tight) {
            Image(systemName: issue.icon)
                .foregroundStyle(isPassed ? Color.appSuccess : Color.appRisk)
                .font(.caption.weight(.semibold))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(isPassed ? issue.passedTitle : issue.title)
                    .font(.callout.weight(.semibold))
                Text(data.deliveryHealth.detail(for: issue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !isPassed {
                    Text(issue.repairHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !isPassed {
                repairButton(for: issue)
            }
        }
    }

    @ViewBuilder
    private func repairButton(for issue: ProjectDeliveryHealth.Issue) -> some View {
        Button(issue.repairButtonTitle) {
            onRepair(issue.repairAction)
        }
        .font(.caption.weight(.semibold))
    }

    private var drawingCurrentVersionDetail: String {
        if data.drawingCount == 0 {
            return String(localized: "还没有图纸")
        }
        if data.drawingWithoutCurrentCount > 0 {
            let sample = data.drawingGroupsWithoutCurrent.prefix(3).joined(separator: "、")
            if sample.isEmpty {
                return String(
                    format: String(localized: "%lld 组图纸未标记当前版"),
                    Int64(data.drawingWithoutCurrentCount)
                )
            }
            return String(
                format: String(localized: "%lld 组图纸未标记当前版：%@"),
                Int64(data.drawingWithoutCurrentCount),
                sample
            )
        }
        return String(format: String(localized: "已上传 %lld 份，均有当前版"), Int64(data.drawingCount))
    }

    private var drawingCurrentVersionStatus: GuideStatus {
        if data.drawingCount == 0 {
            return .warning
        }
        return data.drawingWithoutCurrentCount > 0 ? .warning : .ok
    }

    private enum GuideStatus {
        case ok
        case warning
        case error

        var icon: String {
            switch self {
            case .ok:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.circle.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .ok:
                return .appSuccess
            case .warning:
                return .appPrimaryAction
            case .error:
                return .appRisk
            }
        }
    }
}
