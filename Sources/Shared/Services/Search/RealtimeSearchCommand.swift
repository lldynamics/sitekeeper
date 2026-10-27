import Foundation

enum RealtimeSearchCommand: String, CaseIterable, Hashable {
    case newDailyLog = "new-daily-log"
    case newTodo = "new-todo"
    case newQuickNote = "new-quick-note"
    case newBookkeeping = "new-bookkeeping"
    case attachReceipt = "attach-receipt"
    case exportDeliveryPackage = "export-delivery-package"
    case backupNow = "backup-now"
    case dataHealthCheck = "data-health-check"

    var suggestionId: String {
        "command-\(rawValue)"
    }

    var entityId: UUID {
        switch self {
        case .newDailyLog:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        case .newTodo:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000006")!
        case .newQuickNote:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000007")!
        case .newBookkeeping:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000008")!
        case .attachReceipt:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        case .exportDeliveryPackage:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        case .backupNow:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
        case .dataHealthCheck:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
        }
    }

    var title: String {
        switch self {
        case .newDailyLog:
            return AppLocalization.string("新建日志")
        case .newTodo:
            return AppLocalization.string("新建待办")
        case .newQuickNote:
            return AppLocalization.string("新建随手记")
        case .newBookkeeping:
            return AppLocalization.string("快速记账")
        case .attachReceipt:
            return AppLocalization.string("补票据")
        case .exportDeliveryPackage:
            return AppLocalization.string("导出交付包")
        case .backupNow:
            return AppLocalization.string("立即备份")
        case .dataHealthCheck:
            return AppLocalization.string("打开数据健康检查")
        }
    }

    var subtitle: String {
        switch self {
        case .newDailyLog:
            return AppLocalization.string("打开施工日志并直接新建一条")
        case .newTodo:
            return AppLocalization.string("打开现场待办并直接新建一条")
        case .newQuickNote:
            return AppLocalization.string("进入随手记快速记录现场信息")
        case .newBookkeeping:
            return AppLocalization.string("为当前工程录入收支流水")
        case .attachReceipt:
            return AppLocalization.string("进入缺票工程或当前工程补扫票据")
        case .exportDeliveryPackage:
            return AppLocalization.string("打开交付向导或导出交付中心")
        case .backupNow:
            return AppLocalization.string("进入数据安全中心生成本地或 iCloud 备份")
        case .dataHealthCheck:
            return AppLocalization.string("扫描缺失文件、无效关联和孤立文件")
        }
    }

    var aliases: [String] {
        switch self {
        case .newDailyLog:
            return ["新建日志", "写日志", "施工日志", "日志", "daily log", "log"]
        case .newTodo:
            return ["新建待办", "加待办", "待办", "任务", "todo", "task"]
        case .newQuickNote:
            return ["新建随手记", "随手记", "记一下", "备忘", "note", "memo"]
        case .newBookkeeping:
            return ["快速记账", "记账", "收入", "支出", "流水", "bookkeeping", "expense"]
        case .attachReceipt:
            return ["补票据", "补票", "缺票", "票据", "发票", "收据", "receipt", "invoice"]
        case .exportDeliveryPackage:
            return ["导出交付包", "交付包", "导出交付", "项目交付", "交付", "delivery", "package", "export"]
        case .backupNow:
            return ["立即备份", "备份", "本地备份", "iCloud备份", "iCloud backup", "backup"]
        case .dataHealthCheck:
            return ["数据健康检查", "数据健康", "健康检查", "数据体检", "修复数据", "health", "check"]
        }
    }

    init?(suggestionId: String) {
        guard suggestionId.hasPrefix("command-") else { return nil }
        self.init(rawValue: String(suggestionId.dropFirst("command-".count)))
    }
}
