import SwiftUI

enum DataManagementRoute: Hashable {
    case export
    case backup
    case restore
    case health
    case storage
    case audit
}

extension DataManagementView {
    enum HealthCleanupSection: CaseIterable {
        case health
        case storage
        case audit

        var displayName: String {
            switch self {
            case .health:
                return AppLocalization.string("健康检查")
            case .storage:
                return AppLocalization.string("存储清理")
            case .audit:
                return AppLocalization.string("审计")
            }
        }

        var icon: String {
            switch self {
            case .health:
                return "stethoscope"
            case .storage:
                return "internaldrive"
            case .audit:
                return "checklist.checked"
            }
        }

        var summary: String {
            switch self {
            case .health:
                return AppLocalization.string("扫描缺失文件、无效关联与孤立文件，并支持一键修复。")
            case .storage:
                return AppLocalization.string("查看照片/视频/图纸原件/备份/历史计算占用，支持按项目清理附件文件。")
            case .audit:
                return AppLocalization.string("查看导入、恢复、清理、修复、删除等高风险操作记录。")
            }
        }

        static func from(route: DataManagementRoute?) -> Self {
            guard let route else { return .health }
            switch route {
            case .storage:
                return .storage
            case .audit:
                return .audit
            default:
                return .health
            }
        }
    }

    enum DataManagementTab: CaseIterable {
        case backupAndRestore
        case export
        case healthAndCleanup

        var displayName: String {
            switch self {
            case .backupAndRestore:
                return AppLocalization.string("备份恢复")
            case .export:
                return AppLocalization.string("导出交付")
            case .healthAndCleanup:
                return AppLocalization.string("体检清理")
            }
        }

        var icon: String {
            switch self {
            case .export:
                return "square.and.arrow.up"
            case .backupAndRestore:
                return "arrow.triangle.2.circlepath.icloud"
            case .healthAndCleanup:
                return "cross.case.fill"
            }
        }

        var summary: String {
            switch self {
            case .backupAndRestore:
                return AppLocalization.string("统一完成本地/iCloud 备份、恢复预览与导入校验。")
            case .export:
                return AppLocalization.string("按项目或日期筛选后导出 CSV / PDF / HTML。")
            case .healthAndCleanup:
                return AppLocalization.string("统一查看健康检查、存储占用、审计记录与清理风险。")
            }
        }

        static func from(route: DataManagementRoute?) -> Self {
            guard let route else { return .backupAndRestore }
            switch route {
            case .export:
                return .export
            case .backup, .restore:
                return .backupAndRestore
            case .health, .storage, .audit:
                return .healthAndCleanup
            }
        }
    }

    enum DataSafetyPrimaryTarget {
        case backup
        case health
        case storage
    }

    enum DataSafetySecondaryTarget: Hashable {
        case backupAndRestore
        case health
        case storage
        case export
    }

    struct DataSafetyPrimaryAction {
        let title: String
        let message: String
        let buttonTitle: String
        let systemImage: String
        let tone: StatusChipTone
        let target: DataSafetyPrimaryTarget
    }
}
