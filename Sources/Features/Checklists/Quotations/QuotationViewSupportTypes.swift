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
        case .all: return AppLocalization.string("全部")
        case .draft: return AppLocalization.string("草稿")
        case .sent: return AppLocalization.string("已发送")
        case .confirmed: return AppLocalization.string("已确认")
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
            AppLocalization.string("沿用材料单价（成本参考）")
        case .overrideAll:
            AppLocalization.string("统一设置对外报价")
        case .leaveUnpriced:
            AppLocalization.string("留空待补")
        }
    }
}

enum MaterialQuoteGenerator {
    static func resolvedUnitPrice(
        for material: MaterialItem,
        mode: MaterialQuotePriceMode,
        overridePrice: MoneyValue
    ) -> MoneyValue {
        switch mode {
        case .useMaterialPrice:
            return material.unitPrice
        case .overrideAll:
            return overridePrice
        case .leaveUnpriced:
            return .empty
        }
    }

    static func makeQuoteItem(
        from material: MaterialItem,
        mode: MaterialQuotePriceMode,
        overridePrice: MoneyValue = .empty,
        taxRate: QuantityValue = .zero,
        discountRate: QuantityValue = .zero
    ) -> QuoteItem {
        QuoteItem(
            name: material.name,
            unitPrice: resolvedUnitPrice(for: material, mode: mode, overridePrice: overridePrice),
            quantity: material.quantity,
            unit: material.unit,
            notes: AppLocalization.string("材料清单导入"),
            taxRate: taxRate,
            discountRate: discountRate,
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

    var canApply: Bool { itemCount > 0 && incompleteItemCount == 0 && newAmount.isValid }
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
                    item.unitPrice.wireText,
                    item.quantity.wireText,
                    item.taxRate.wireText,
                    item.discountRate.wireText,
                    item.contractAmount.wireText
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
                return name.isEmpty ? AppLocalization.string("未命名报价") : name
            },
            incompleteItemCount: incompleteItemCount,
            oldAmount: project.contractAmount,
            newAmount: newAmount,
            selectionSignature: selectionSignature
        )
    }

    private static func contractAmount(for item: QuoteItem) -> MoneyValue? {
        let explicitContract = item.contractAmount
        if !explicitContract.isEmpty {
            guard InputValidator.validate(
                explicitContract,
                kind: .amount,
                requirement: .requiredNonNegative
            ).isValid else { return nil }
            return explicitContract
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
            let discount = item.discountRate.optionalDecimal,
            discount <= 100 else { return nil }
        return ReportBuilder.quoteGrandTotal(item)
    }
}

/// Read-only business scope. Missing selection or amounts never imply zero.
struct ProjectBusinessQuoteMetrics {
    enum State: Equatable {
        case ready
        case noSelection
        case staleSelection
        case unconfirmedItems
        case incompleteAmounts
    }

    let selectedVersion: String?
    let state: State
    let amount: MoneyValue?
    let allVersionsAmount: MoneyValue?
    let confirmedVersions: [String]
    let itemCount: Int
    let incompleteItemCount: Int
    let unconfirmedItemCount: Int

    init(project: Project, quotes: [QuoteItem]) {
        let projectQuotes = quotes.filter { $0.projectId == project.id }
        confirmedVersions = QuotationContractWritePlanner.confirmedVersions(projectId: project.id, quotes: projectQuotes)
        allVersionsAmount = Self.strictTotal(projectQuotes)
        selectedVersion = project.businessQuoteVersion.map(QuotationContractWritePlanner.normalizedVersion)
        let selected = selectedVersion.map { version in
            projectQuotes.filter { QuotationContractWritePlanner.normalizedVersion($0.versionName) == version }
        } ?? []
        itemCount = selected.count
        unconfirmedItemCount = selected.filter { $0.status != .confirmed }.count
        incompleteItemCount = selected.filter { Self.strictAmount($0) == nil }.count
        let total = Self.strictTotal(selected)
        if selectedVersion == nil {
            state = .noSelection
        } else if selected.isEmpty {
            state = .staleSelection
        } else if unconfirmedItemCount > 0 {
            state = .unconfirmedItems
        } else if incompleteItemCount > 0 || total == nil {
            state = .incompleteAmounts
        } else {
            state = .ready
        }
        amount = state == .ready ? total : nil
    }

    static func strictAmount(_ item: QuoteItem) -> MoneyValue? {
        guard let price = item.unitPrice.optionalDecimal, price >= 0,
              let quantity = item.quantity.optionalDecimal, quantity >= 0,
              let tax = item.taxRate.optionalDecimal, tax >= 0,
              let discount = item.discountRate.optionalDecimal, discount >= 0, discount <= 100 else { return nil }
        let amount = ReportBuilder.quoteGrandTotal(item)
        return amount.isValid ? amount : nil
    }

    private static func strictTotal(_ items: [QuoteItem]) -> MoneyValue? {
        guard !items.isEmpty else { return nil }
        var total = MoneyValue.zero
        for item in items {
            guard let amount = strictAmount(item) else { return nil }
            total += amount
            guard total.isValid else { return nil }
        }
        return total
    }
}

@MainActor
enum ProjectBusinessQuoteSelectionService {
    static func save(
        version: String?,
        projectID: UUID,
        expectedSelection: String?,
        store: any BusinessWorkflowStore,
        quotes: () -> [QuoteItem],
        persist: (() async throws -> Void)? = nil
    ) async throws {
        await store.awaitInitialLoad()
        try store.requireBusinessWritesAllowed()
        guard store.savingPaymentProjects.insert(projectID).inserted else { throw BusinessWorkflowError.operationInProgress }
        defer { store.savingPaymentProjects.remove(projectID) }
        guard var project = store.projects.first(where: { $0.id == projectID }) else { throw BusinessWorkflowError.missingSource }
        let previous = project.businessQuoteVersion
        guard previous == expectedSelection else { throw BusinessWorkflowError.staleSource }
        let selected = version.map(QuotationContractWritePlanner.normalizedVersion)
        project.businessQuoteVersion = selected
        if selected != nil {
            guard ProjectBusinessQuoteMetrics(project: project, quotes: quotes()).state == .ready else {
                throw BusinessWorkflowError.staleSource
            }
        }
        guard store.updateProject(project) else { throw BusinessWorkflowError.missingSource }
        do {
            if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
        } catch {
            if var current = store.projects.first(where: { $0.id == projectID }), current.businessQuoteVersion == selected {
                current.businessQuoteVersion = previous
                store.updateProject(current)
            }
            throw error
        }
    }
}

/// A reference total for exactly the displayed rows, regardless of version/status.
struct QuotationReferenceSummary {
    struct Amounts {
        let subtotal: MoneyValue
        let tax: MoneyValue
        let discount: MoneyValue
        let total: MoneyValue
    }

    let itemCount: Int
    let incompleteItemCount: Int
    let amounts: Amounts?

    init(items: [QuoteItem]) {
        itemCount = items.count
        incompleteItemCount = items.filter { ProjectBusinessQuoteMetrics.strictAmount($0) == nil }.count
        var subtotal = MoneyValue.zero
        var tax = MoneyValue.zero
        var discount = MoneyValue.zero
        for item in items {
            guard ProjectBusinessQuoteMetrics.strictAmount(item) != nil else {
                amounts = nil
                return
            }
            subtotal += ReportBuilder.quoteLineTotal(item)
            tax += ReportBuilder.quoteTaxValue(item)
            discount += ReportBuilder.quoteDiscountValue(item)
        }
        let total = subtotal + tax - discount
        if !items.isEmpty, subtotal.isValid, tax.isValid, discount.isValid, total.isValid {
            amounts = Amounts(subtotal: subtotal, tax: tax, discount: discount, total: total)
        } else {
            amounts = nil
        }
    }
}

struct QuotationProjectReferenceSummary: Identifiable {
    let projectID: UUID?
    let name: String
    let summary: QuotationReferenceSummary
    var id: String { projectID?.uuidString ?? "unassigned" }
}

/// Captures the user's opt-in scope. Stale scope yields no rows until disabled or reselected.
struct QuotationBusinessVersionFilter: Equatable {
    let projectID: UUID
    let version: String

    func isValid(project: Project?, quotes: [QuoteItem]) -> Bool {
        guard let project, project.id == projectID else { return false }
        let metrics = ProjectBusinessQuoteMetrics(project: project, quotes: quotes)
        return metrics.state == .ready && metrics.selectedVersion == version
    }

    func applying(to quotes: [QuoteItem], project: Project?) -> [QuoteItem] {
        guard isValid(project: project, quotes: quotes) else { return [] }
        return quotes.filter {
            $0.projectId == projectID && $0.status == .confirmed
                && QuotationContractWritePlanner.normalizedVersion($0.versionName) == version
        }
    }
}
