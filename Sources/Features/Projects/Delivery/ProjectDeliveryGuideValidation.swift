import Foundation

struct ProjectDeliveryRepairWizardStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: ProjectDeliveryRepairAction
    let isResolved: Bool
}

enum ProjectDeliveryGuideStatus {
    case ok
    case warning
    case error
}

enum ProjectDeliveryGuideValidation {
    static func repairWizardSteps(for data: ProjectDeliveryGuideData) -> [ProjectDeliveryRepairWizardStep] {
        [
            ProjectDeliveryRepairWizardStep(
                id: "receipts",
                title: AppLocalization.string("补齐票据"),
                detail: data.deliveryHealth.detail(for: .missingReceipts),
                actionTitle: AppLocalization.string("补票据"),
                action: .attachReceipts,
                isResolved: data.missingReceiptCount == 0
            ),
            drawingRepairWizardStep(for: data),
            ProjectDeliveryRepairWizardStep(
                id: "originals",
                title: AppLocalization.string("补齐原件"),
                detail: data.hasBlockingMissingOriginals
                    ? String(format: AppLocalization.string("检测到 %lld 个缺失原件"), Int64(data.missingOriginalEntries.count))
                    : AppLocalization.string("缺失原件已补齐。"),
                actionTitle: AppLocalization.string("重新导入"),
                action: .restoreMissingOriginals,
                isResolved: !data.hasBlockingMissingOriginals
            ),
            ProjectDeliveryRepairWizardStep(
                id: "drawingIssues",
                title: AppLocalization.string("关闭图纸问题"),
                detail: data.openDrawingIssueCount == 0
                    ? AppLocalization.string("没有未关闭图纸问题。")
                    : String(format: AppLocalization.string("还有 %lld 项未关闭"), Int64(data.openDrawingIssueCount)),
                actionTitle: AppLocalization.string("处理问题"),
                action: .resolveDrawingIssues,
                isResolved: data.openDrawingIssueCount == 0
            )
        ]
    }

    static func firstPendingRepairStepID(in steps: [ProjectDeliveryRepairWizardStep]) -> String? {
        steps.first { !$0.isResolved }?.id
    }

    static func repairWizardStatusText(step: ProjectDeliveryRepairWizardStep, isCurrent: Bool) -> String {
        if step.isResolved {
            return AppLocalization.string("已完成")
        }
        return isCurrent ? AppLocalization.string("当前步骤") : AppLocalization.string("等待前序")
    }

    static func readinessDetail(for data: ProjectDeliveryGuideData) -> String {
        if data.deliveryHealth.isDeliverable {
            if data.isReadyForDelivery {
                return AppLocalization.string("票据、图纸、待办、备份、当前版和原件检查均已通过，可执行最终交付。")
            }
            return String(
                format: AppLocalization.string("核心交付项已通过，另有 %lld 项建议检查。"),
                Int64(data.deliveryWarningCount)
            )
        }
        return data.deliveryHealth.summary
    }

    static func logCoverageDetail(for data: ProjectDeliveryGuideData) -> String {
        if data.missingLogDateCount == 0 {
            if data.expectedLogDateCount > 0 {
                return String(
                    format: AppLocalization.string("已覆盖 %lld 个施工日，共 %lld 条日志"),
                    Int64(data.expectedLogDateCount),
                    Int64(data.logCount)
                )
            }
            return data.logCount > 0
                ? String(format: AppLocalization.string("已记录 %lld 条"), Int64(data.logCount))
                : AppLocalization.string("未设置工期，暂无缺日志日期")
        }
        if data.expectedLogDateCount == 0 {
            return AppLocalization.string("未记录施工日志")
        }
        let sample = data.missingLogDateSamples.joined(separator: "、")
        if sample.isEmpty {
            return String(format: AppLocalization.string("缺 %lld 个施工日"), Int64(data.missingLogDateCount))
        }
        return String(
            format: AppLocalization.string("缺 %lld 个施工日：%@"),
            Int64(data.missingLogDateCount),
            sample
        )
    }

    static func unsettledFinancialDetail(for data: ProjectDeliveryGuideData) -> String {
        guard data.unsettledFinancialCount > 0 else {
            return AppLocalization.string("没有未结清账目")
        }
        if data.unsettledFinancialAmount > 0 {
            return String(
                format: AppLocalization.string("还有 %lld 笔，合计 %@"),
                Int64(data.unsettledFinancialCount),
                ReportBuilder.money(data.unsettledFinancialAmount)
            )
        }
        return String(
            format: AppLocalization.string("还有 %lld 笔未结清"),
            Int64(data.unsettledFinancialCount)
        )
    }

    static func drawingCurrentVersionDetail(for data: ProjectDeliveryGuideData) -> String {
        if data.drawingCount == 0 {
            return AppLocalization.string("还没有图纸")
        }
        if data.drawingWithoutCurrentCount > 0 {
            let sample = data.drawingGroupsWithoutCurrent.prefix(3).joined(separator: "、")
            if sample.isEmpty {
                return String(
                    format: AppLocalization.string("%lld 组图纸未标记当前版"),
                    Int64(data.drawingWithoutCurrentCount)
                )
            }
            return String(
                format: AppLocalization.string("%lld 组图纸未标记当前版：%@"),
                Int64(data.drawingWithoutCurrentCount),
                sample
            )
        }
        return String(format: AppLocalization.string("已上传 %lld 份，均有当前版"), Int64(data.drawingCount))
    }

    static func drawingCurrentVersionStatus(for data: ProjectDeliveryGuideData) -> ProjectDeliveryGuideStatus {
        if data.drawingCount == 0 {
            return .warning
        }
        return data.drawingWithoutCurrentCount > 0 ? .warning : .ok
    }

    static func exportButtonTitle(for data: ProjectDeliveryGuideData) -> String {
        data.hasDeliveryChecklistWarning || !data.deliveryHealth.isDeliverable
            ? AppLocalization.string("检查后导出交付包 ZIP")
            : AppLocalization.string("一键导出交付包 ZIP")
    }

    private static func drawingRepairWizardStep(for data: ProjectDeliveryGuideData) -> ProjectDeliveryRepairWizardStep {
        if data.drawingCount == 0 {
            return ProjectDeliveryRepairWizardStep(
                id: "drawings",
                title: AppLocalization.string("补齐图纸"),
                detail: AppLocalization.string("项目还没有图纸文件。"),
                actionTitle: AppLocalization.string("导入图纸"),
                action: .importDrawings,
                isResolved: false
            )
        }
        if data.drawingWithoutCurrentCount > 0 {
            return ProjectDeliveryRepairWizardStep(
                id: "drawings",
                title: AppLocalization.string("确认当前版"),
                detail: drawingCurrentVersionDetail(for: data),
                actionTitle: AppLocalization.string("标当前版"),
                action: .markCurrentDrawingVersion,
                isResolved: false
            )
        }
        return ProjectDeliveryRepairWizardStep(
            id: "drawings",
            title: AppLocalization.string("补齐图纸"),
            detail: AppLocalization.string("图纸已上传并确认当前版。"),
            actionTitle: AppLocalization.string("导入图纸"),
            action: .importDrawings,
            isResolved: true
        )
    }
}
