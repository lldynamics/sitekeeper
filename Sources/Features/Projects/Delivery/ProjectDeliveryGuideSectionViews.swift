import SwiftUI

struct ProjectDeliveryGuideRepairWizardSectionView: View {
    let steps: [ProjectDeliveryRepairWizardStep]
    let firstPendingRepairStepID: String?
    let onRepair: (ProjectDeliveryRepairAction) -> Void
    let onReturnToExport: () -> Void

    var body: some View {
        Section(AppLocalization.string("交付修复向导")) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { offset, step in
                ProjectDeliveryGuideRepairWizardRow(
                    step: step,
                    number: offset + 1,
                    isCurrent: firstPendingRepairStepID == step.id,
                    onRepair: onRepair
                )
            }
            if steps.allSatisfy(\.isResolved) {
                Button {
                    onReturnToExport()
                } label: {
                    Label(AppLocalization.string("回到交付包导出页"), systemImage: "archivebox.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appProminent())
            } else if let firstPendingRepairStepID, let currentStep = steps.first(where: { $0.id == firstPendingRepairStepID }) {
                Text(String(format: AppLocalization.string("当前步骤：%@"), currentStep.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProjectDeliveryGuideRepairWizardRow: View {
    let step: ProjectDeliveryRepairWizardStep
    let number: Int
    let isCurrent: Bool
    let onRepair: (ProjectDeliveryRepairAction) -> Void

    var body: some View {
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
                Text(ProjectDeliveryGuideValidation.repairWizardStatusText(step: step, isCurrent: isCurrent))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(step.isResolved ? Color.appSuccess : (isCurrent ? Color.appRisk : .secondary))
            }
            Spacer()
            if step.isResolved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
            } else if isWaiting {
                Text(AppLocalization.string("等待前序"))
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
}

struct ProjectDeliveryGuideCheckRowView: View {
    let title: String
    let detail: String
    let status: ProjectDeliveryGuideStatus
    let fixActionTitle: String
    let fixAction: (() -> Void)?

    var body: some View {
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
}

struct ProjectDeliveryGuideHealthRowView: View {
    let issue: ProjectDeliveryHealth.Issue
    let deliveryHealth: ProjectDeliveryHealth
    let onRepair: (ProjectDeliveryRepairAction) -> Void

    var body: some View {
        let isPassed = deliveryHealth.isPassed(issue)
        return HStack(spacing: AppSpacing.tight) {
            Image(systemName: issue.icon)
                .foregroundStyle(isPassed ? Color.appSuccess : Color.appRisk)
                .font(.caption.weight(.semibold))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(isPassed ? issue.passedTitle : issue.title)
                    .font(.callout.weight(.semibold))
                Text(deliveryHealth.detail(for: issue))
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
                Button(issue.repairButtonTitle) {
                    onRepair(issue.repairAction)
                }
                .font(.caption.weight(.semibold))
            }
        }
    }
}

struct ProjectDeliveryGuideBackupRowView: View {
    let backupState: ProjectDeliveryBackupState
    let onRepair: (ProjectDeliveryRepairAction) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.tight) {
            let status: ProjectDeliveryGuideStatus = backupState.isFresh ? .ok : .warning
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.string("最近备份"))
                    .font(.callout.weight(.semibold))
                Text(backupState.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !backupState.isFresh {
                Button {
                    onRepair(.createBackup)
                } label: {
                    Text(AppLocalization.string("去备份"))
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }
}

private extension ProjectDeliveryGuideStatus {
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
