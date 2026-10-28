import Foundation

extension ReportBuilder {
    /// A previewable, manually shared record, with no original files or financial posting.
    static func changeOrderConfirmationText(project: Project, order: ProjectChangeOrder,
                                            documents: [ProjectDocument]) -> String {
        let validConfirmation = order.confirmationState == .confirmed
            && order.confirmedAmount.isValid && !order.confirmedAmount.isNegative
            && !order.confirmedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && order.confirmedAt?.isResolved == true
        let marker = validConfirmation ? loc("已确认（本机记录）") : loc("未确认，不可作为已确认金额依据")
        func field(_ key: String, _ value: String) -> String {
            "\(loc(key)): \(value.isEmpty ? locNotFilled : value)"
        }
        func amount(_ value: MoneyValue) -> String {
            if value.isEmpty { return locNotFilled }
            guard value.isValid, !value.isNegative else { return loc("金额异常，请核对") }
            return money(value)
        }
        var lines = [
            loc("增项确认单"),
            "【\(marker)】",
            loc("本单仅为本机记录，不代表甲方签章；增项金额独立记录，不计入合同金额、经营汇总或结算。"),
            "",
            field("项目", project.name),
            field("增项编号", order.id.uuidString),
            field("增项标题", order.title),
            field("增项说明", order.detail),
            field("提出人", order.requester),
            field("记录日期", Formatters.displayDateText(order.createdAt)),
            field("确认状态", order.confirmationState.displayName),
            field("申报金额", amount(order.proposedAmount))
        ]
        if validConfirmation {
            lines += [
                field("确认金额", amount(order.confirmedAmount)),
                field("确认记录人", order.confirmedBy),
                field("确认记录日期", order.confirmedAt.map { Formatters.displayDateText($0) } ?? locNotFilled)
            ]
        } else {
            lines.append(field("确认金额", loc("未确认，不可作为已确认金额依据")))
        }
        lines += [field("确认备注", order.confirmationNote), "", loc("关联项目资料")]
        let projectDocuments = documents.filter { $0.projectId == project.id }
        if order.documentIDs.isEmpty { lines.append(loc("未关联资料")) }
        for id in order.documentIDs {
            if let document = projectDocuments.first(where: { $0.id == id }) {
                lines.append("- \(document.title) [\(id.uuidString)]")
            } else {
                lines.append("- \(loc("关联资料已失效，请核对原项目资料。")) [\(id.uuidString)]")
            }
        }
        return lines.joined(separator: "\n")
    }
}
