import SwiftUI

enum ProjectDeliveryRepairAction: Equatable {
    case attachReceipts
    case importDrawings
    case resolveTodos
    case resolveDrawingIssues
    case createBackup
    case restoreMissingOriginals
    case markCurrentDrawingVersion

    var dismissesDeliveryGuide: Bool {
        switch self {
        case .markCurrentDrawingVersion:
            return false
        case .attachReceipts, .importDrawings, .resolveTodos, .resolveDrawingIssues, .createBackup, .restoreMissingOriginals:
            return true
        }
    }
}

struct ProjectDeliveryBackupState: Equatable {
    let latestBackupDate: Date?
    let reminderDays: Int
    let referenceDate: Date

    static func current(referenceDate: Date = Date()) -> ProjectDeliveryBackupState {
        let preferenceStore = UserPreferencesStore.shared
        let reminderDays = preferenceStore.backupReminderDays
        let latestBackupDate = preferenceStore.latestSuccessfulBackupDate
        return ProjectDeliveryBackupState(
            latestBackupDate: latestBackupDate,
            reminderDays: reminderDays,
            referenceDate: referenceDate
        )
    }

    var isFresh: Bool {
        guard latestBackupDate != nil else { return false }
        return daysSinceLatestBackup < reminderDays
    }

    var daysSinceLatestBackup: Int {
        guard let latestBackupDate else { return Int.max }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: latestBackupDate)
        let end = calendar.startOfDay(for: referenceDate)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }

    var detail: String {
        guard let latestBackupDate else {
            return AppLocalization.string("尚未记录成功备份")
        }
        if daysSinceLatestBackup == 0 {
            return String(format: AppLocalization.string("今天已备份，提醒阈值 %lld 天"), Int64(reminderDays))
        }
        return String(
            format: AppLocalization.string("最近备份 %@，已过 %lld 天"),
            Formatters.dateTime.string(from: latestBackupDate),
            Int64(daysSinceLatestBackup)
        )
    }
}

struct ProjectDeliveryHealth: Equatable {
    enum Issue: String, CaseIterable, Identifiable {
        case missingReceipts
        case missingDrawings
        case openTodos
        case backupOverdue
        case missingOriginals
        case missingCurrentDrawingVersion

        var id: String { rawValue }

        var title: String {
            switch self {
            case .missingReceipts:
                return AppLocalization.string("缺票据")
            case .missingDrawings:
                return AppLocalization.string("缺图纸")
            case .openTodos:
                return AppLocalization.string("未完成待办")
            case .backupOverdue:
                return AppLocalization.string("未备份")
            case .missingOriginals:
                return AppLocalization.string("资料缺原件")
            case .missingCurrentDrawingVersion:
                return AppLocalization.string("当前版缺失")
            }
        }

        var passedTitle: String {
            switch self {
            case .missingReceipts:
                return AppLocalization.string("票据已补齐")
            case .missingDrawings:
                return AppLocalization.string("图纸已上传")
            case .openTodos:
                return AppLocalization.string("待办已清空")
            case .backupOverdue:
                return AppLocalization.string("备份有效")
            case .missingOriginals:
                return AppLocalization.string("原件齐全")
            case .missingCurrentDrawingVersion:
                return AppLocalization.string("当前版已确认")
            }
        }

        var icon: String {
            switch self {
            case .missingReceipts:
                return "receipt.fill"
            case .missingDrawings:
                return "square.on.square.squareshape.controlhandles"
            case .openTodos:
                return "checklist"
            case .backupOverdue:
                return "externaldrive.badge.icloud"
            case .missingOriginals:
                return "doc.badge.exclamationmark"
            case .missingCurrentDrawingVersion:
                return "checkmark.rectangle.stack"
            }
        }

        var repairMode: ProjectDetailMode? {
            switch self {
            case .missingReceipts:
                return .finance
            case .missingDrawings, .missingOriginals, .missingCurrentDrawingVersion:
                return .assets
            case .openTodos:
                return .records
            case .backupOverdue:
                return nil
            }
        }

        var repairAction: ProjectDeliveryRepairAction {
            switch self {
            case .missingReceipts:
                return .attachReceipts
            case .missingDrawings:
                return .importDrawings
            case .openTodos:
                return .resolveTodos
            case .backupOverdue:
                return .createBackup
            case .missingOriginals:
                return .restoreMissingOriginals
            case .missingCurrentDrawingVersion:
                return .markCurrentDrawingVersion
            }
        }

        var repairButtonTitle: String {
            switch self {
            case .missingReceipts:
                return AppLocalization.string("补票据")
            case .missingDrawings:
                return AppLocalization.string("导入图纸")
            case .openTodos:
                return AppLocalization.string("处理待办")
            case .backupOverdue:
                return AppLocalization.string("去备份")
            case .missingOriginals:
                return AppLocalization.string("重新导入")
            case .missingCurrentDrawingVersion:
                return AppLocalization.string("标当前版")
            }
        }

        var repairHint: String {
            switch self {
            case .missingReceipts:
                return AppLocalization.string("打开第一笔缺票账目的票据附件管理。")
            case .missingDrawings:
                return AppLocalization.string("直接进入图纸导入流程。")
            case .openTodos:
                return AppLocalization.string("进入本项目待办列表，关闭或补充整改记录。")
            case .backupOverdue:
                return AppLocalization.string("进入数据安全中心完成本地或 iCloud 备份。")
            case .missingOriginals:
                return AppLocalization.string("回到资料区重新导入缺失的图纸、票据或附件原件。")
            case .missingCurrentDrawingVersion:
                return AppLocalization.string("自动把首个缺当前版图纸组的最新版本标为当前版。")
            }
        }
    }

    let missingReceiptCount: Int
    let drawingCount: Int
    let openTodoCount: Int
    let backupState: ProjectDeliveryBackupState
    let missingOriginalCount: Int
    let drawingWithoutCurrentCount: Int

    var failedIssues: [Issue] {
        Issue.allCases.filter { !isPassed($0) }
    }

    var score: Int {
        max(0, 100 - failedIssues.count * 20)
    }

    var isDeliverable: Bool {
        failedIssues.isEmpty
    }

    var verdictTitle: String {
        isDeliverable ? AppLocalization.string("可交付") : AppLocalization.string("不可交付")
    }

    var summary: String {
        if isDeliverable {
            return AppLocalization.string("票据、图纸、待办、备份、当前版和原件检查均已通过。")
        }
        let titles = failedIssues.map(\.title).joined(separator: "、")
        return String(format: AppLocalization.string("需处理：%@"), titles)
    }

    func isPassed(_ issue: Issue) -> Bool {
        switch issue {
        case .missingReceipts:
            return missingReceiptCount == 0
        case .missingDrawings:
            return drawingCount > 0
        case .openTodos:
            return openTodoCount == 0
        case .backupOverdue:
            return backupState.isFresh
        case .missingOriginals:
            return missingOriginalCount == 0
        case .missingCurrentDrawingVersion:
            return drawingWithoutCurrentCount == 0
        }
    }

    func detail(for issue: Issue) -> String {
        switch issue {
        case .missingReceipts:
            return missingReceiptCount == 0
                ? AppLocalization.string("需要留票的账目均已关联票据。")
                : String(format: AppLocalization.string("还有 %lld 笔账目缺票据。"), Int64(missingReceiptCount))
        case .missingDrawings:
            return drawingCount > 0
                ? String(format: AppLocalization.string("已上传 %lld 份图纸。"), Int64(drawingCount))
                : AppLocalization.string("项目还没有图纸文件。")
        case .openTodos:
            return openTodoCount == 0
                ? AppLocalization.string("没有未完成待办。")
                : String(format: AppLocalization.string("还有 %lld 条现场待办未完成。"), Int64(openTodoCount))
        case .backupOverdue:
            return backupState.detail
        case .missingOriginals:
            return missingOriginalCount == 0
                ? AppLocalization.string("交付包引用的本机原件均可找到。")
                : String(format: AppLocalization.string("检测到 %lld 个资料原件缺失。"), Int64(missingOriginalCount))
        case .missingCurrentDrawingVersion:
            return drawingWithoutCurrentCount == 0
                ? AppLocalization.string("所有图纸组均已确认当前版。")
                : String(format: AppLocalization.string("还有 %lld 组图纸未标记当前版。"), Int64(drawingWithoutCurrentCount))
        }
    }
}

struct ProjectDeliveryGuideData {
    let projectName: String
    let logCount: Int
    let expectedLogDateCount: Int
    let missingLogDateCount: Int
    let missingLogDateSamples: [String]
    let drawingCount: Int
    let drawingGroupsWithoutCurrent: [String]
    let documentCount: Int
    let contactCount: Int
    let missingReceiptCount: Int
    let unsettledFinancialCount: Int
    let unsettledFinancialAmount: MoneyValue
    let openTodoCount: Int
    let openDrawingIssueCount: Int
    let backupState: ProjectDeliveryBackupState
    let missingOriginalEntries: [String]
    let estimatedPackageBytes: Int

    var deliveryHealth: ProjectDeliveryHealth {
        ProjectDeliveryHealth(
            missingReceiptCount: missingReceiptCount,
            drawingCount: drawingCount,
            openTodoCount: openTodoCount,
            backupState: backupState,
            missingOriginalCount: missingOriginalEntries.count,
            drawingWithoutCurrentCount: drawingWithoutCurrentCount
        )
    }

    var drawingWithoutCurrentCount: Int {
        drawingGroupsWithoutCurrent.count
    }

    var hasBlockingMissingOriginals: Bool {
        !missingOriginalEntries.isEmpty
    }

    var hasDeliveryChecklistWarning: Bool {
        missingLogDateCount > 0
            || drawingCount == 0
            || drawingWithoutCurrentCount > 0
            || openDrawingIssueCount > 0
            || contactCount == 0
            || missingReceiptCount > 0
            || unsettledFinancialCount > 0
            || !deliveryHealth.isDeliverable
    }

    var deliveryWarningCount: Int {
        deliveryHealth.failedIssues.count + [
            missingLogDateCount > 0,
            drawingCount > 0 && drawingWithoutCurrentCount > 0,
            openDrawingIssueCount > 0,
            contactCount == 0,
            unsettledFinancialCount > 0
        ].filter { $0 }.count
    }

    var isReadyForDelivery: Bool {
        deliveryHealth.isDeliverable && !hasDeliveryChecklistWarning && !hasBlockingMissingOriginals
    }
}
