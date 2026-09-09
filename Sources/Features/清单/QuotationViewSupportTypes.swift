import Foundation

enum QuoteStatusChip: CaseIterable, Hashable {
    case all
    case draft
    case sent
    case confirmed

    init(status: QuoteStatus?) {
        switch status {
        case .draft: self = .draft
        case .sent: self = .sent
        case .confirmed: self = .confirmed
        case nil: self = .all
        }
    }

    var status: QuoteStatus? {
        switch self {
        case .all: return nil
        case .draft: return .draft
        case .sent: return .sent
        case .confirmed: return .confirmed
        }
    }

    var title: String {
        switch self {
        case .all: return String(localized: "全部")
        case .draft: return String(localized: "草稿")
        case .sent: return String(localized: "已发送")
        case .confirmed: return String(localized: "已确认")
        }
    }
}

enum QuotationSheetRoute: String, Identifiable {
    case edit
    case generate
    case export
    case contractWrite

    var id: String { rawValue }
}

enum MaterialQuotePriceMode: String, CaseIterable, Identifiable {
    case useMaterialPrice
    case overrideAll
    case leaveUnpriced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .useMaterialPrice:
            String(localized: "沿用材料单价（成本参考）")
        case .overrideAll:
            String(localized: "统一设置对外报价")
        case .leaveUnpriced:
            String(localized: "留空待补")
        }
    }
}

enum MaterialQuoteGenerator {
    static func resolvedUnitPrice(
        for material: MaterialItem,
        mode: MaterialQuotePriceMode,
        overridePrice: String
    ) -> String {
        switch mode {
        case .useMaterialPrice:
            return material.unitPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        case .overrideAll:
            return NumericInputSupport.normalizedStorageText(overridePrice, kind: .amount)
        case .leaveUnpriced:
            return ""
        }
    }

    static func makeQuoteItem(
        from material: MaterialItem,
        mode: MaterialQuotePriceMode,
        overridePrice: String = "",
        taxRate: String = "0",
        discountRate: String = "0"
    ) -> QuoteItem {
        QuoteItem(
            name: material.name,
            unitPrice: resolvedUnitPrice(for: material, mode: mode, overridePrice: overridePrice),
            quantity: material.quantity,
            unit: material.unit,
            notes: String(localized: "材料清单导入"),
            taxRate: NumericInputSupport.normalizedStorageText(taxRate, kind: .taxRate),
            discountRate: NumericInputSupport.normalizedStorageText(discountRate, kind: .discountRate),
            versionName: "V1",
            status: .draft,
            projectId: material.projectId
        )
    }
}

struct QuotationContractWritePlan: Equatable {
    let projectId: UUID
    let projectName: String
    let versionName: String
    let status: QuoteStatus
    let itemCount: Int
    let itemNames: [String]
    let incompleteItemCount: Int
    let oldAmount: MoneyValue
    let newAmount: MoneyValue
    let selectionSignature: String

    var canApply: Bool { itemCount > 0 && incompleteItemCount == 0 }
}

enum QuotationContractWritePlanner {
    static func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "V1" : trimmed
    }

    static func confirmedVersions(projectId: UUID, quotes: [QuoteItem]) -> [String] {
        Array(Set(quotes.compactMap { item in
            guard item.projectId == projectId, item.status == .confirmed else { return nil }
            return normalizedVersion(item.versionName)
        }))
        .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
    }

    static func makePlan(project: Project, versionName: String, quotes: [QuoteItem]) -> QuotationContractWritePlan? {
        let normalizedVersionName = normalizedVersion(versionName)
        let items = quotes.filter {
            $0.projectId == project.id &&
                $0.status == .confirmed &&
                normalizedVersion($0.versionName) == normalizedVersionName
        }
        guard !items.isEmpty else { return nil }

        let itemAmounts = items.map(contractAmount(for:))
        let incompleteItemCount = itemAmounts.filter { $0 == nil }.count
        let newAmount = itemAmounts.compactMap { $0 }.reduce(MoneyValue.zero) { $0 + $1 }
        let selectionSignature = items
            .map { item in
                [
                    item.id.uuidString,
                    item.status.rawValue,
                    normalizedVersion(item.versionName),
                    item.unitPrice,
                    item.quantity,
                    item.taxRate,
                    item.discountRate,
                    item.contractAmount
                ].joined(separator: "\u{1f}")
            }
            .sorted()
            .joined(separator: "\u{1e}")
        return QuotationContractWritePlan(
            projectId: project.id,
            projectName: project.name,
            versionName: normalizedVersionName,
            status: .confirmed,
            itemCount: items.count,
            itemNames: items.map { item in
                let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? String(localized: "未命名报价") : name
            },
            incompleteItemCount: incompleteItemCount,
            oldAmount: project.contractAmountValue,
            newAmount: newAmount,
            selectionSignature: selectionSignature
        )
    }

    private static func contractAmount(for item: QuoteItem) -> MoneyValue? {
        let explicitContract = item.contractAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitContract.isEmpty {
            guard InputValidator.validate(
                explicitContract,
                kind: .amount,
                requirement: .requiredNonNegative
            ).isValid else { return nil }
            return MoneyValue(text: explicitContract)
        }

        guard InputValidator.validate(
            item.unitPrice,
            kind: .amount,
            requirement: .requiredNonNegative
        ).isValid,
            InputValidator.validate(
                item.quantity,
                kind: .quantity,
                requirement: .requiredNonNegative
            ).isValid,
            InputValidator.validate(
                item.taxRate,
                kind: .taxRate,
                requirement: .requiredNonNegative
            ).isValid,
            InputValidator.validate(
                item.discountRate,
                kind: .discountRate,
                requirement: .requiredNonNegative
            ).isValid,
            let discount = DataValueParser.decimalValueIfPresent(
                from: item.discountRate,
                requiresEntireString: true
            ),
            discount <= 100 else { return nil }
        return ReportBuilder.quoteGrandTotalValue(item)
    }
}
