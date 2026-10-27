import Foundation

enum BusinessWorkflowError: LocalizedError {
    case invalidInput
    case staleSource
    case missingSource
    case duplicateSource
    case invalidAllocation
    case settledInstallment
    case operationInProgress

    var errorDescription: String? {
        switch self {
        case .invalidInput: AppLocalization.string("请核对名称、日期、数量与金额。")
        case .staleSource: AppLocalization.string("源记录已变化，请重新打开并核对；当前输入仍保留。")
        case .missingSource: AppLocalization.string("关联记录不存在，已保留输入，请重新选择。")
        case .duplicateSource: AppLocalization.string("这条来源记录已经生成记账，请打开原账目核对。")
        case .invalidAllocation: AppLocalization.string("收付金额、方向或关联期次不符合当前计划，请重新核对。")
        case .settledInstallment: AppLocalization.string("本期已结清，不能重复收付。")
        case .operationInProgress: AppLocalization.string("该工程的收付计划正在保存，请稍后重试。")
        }
    }
}
