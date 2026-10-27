import Foundation
import Observation

/// Holds one page, never accumulated bodies or the complete project/log collection.
@MainActor @Observable
final class RepositoryPageModel {
    private(set) var laborSummary: RepositoryLaborSummary?
    private(set) var quoteSummary: RepositoryQuoteSummary?
    private(set) var materialSummary: RepositoryMaterialSummary?
    private(set) var financialSummary: RepositoryFinancialSummary?
    private(set) var items: [RepositoryListItem] = []
    private(set) var query: RepositoryQuery
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var pageNumber = 1
    private(set) var nextCursor: RepositoryCursor?
    @ObservationIgnored private let repository: any BusinessRepository
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var starts: [RepositoryCursor?] = [nil]
    @ObservationIgnored private var generation = UUID()

    init(repository: any BusinessRepository, query: RepositoryQuery, pageSize: Int = 50) {
        self.repository = repository
        self.query = query
        self.pageSize = pageSize
    }

    func reset(to query: RepositoryQuery? = nil) async {
        if let query { self.query = query }
        generation = UUID()
        starts = [nil]
        pageNumber = 1
        items = []
        financialSummary = nil
        materialSummary = nil
        quoteSummary = nil
        laborSummary = nil
        nextCursor = nil
        await load(start: nil, targetPage: 1)
    }

    func next() async {
        guard !isLoading, let nextCursor else { return }
        await load(start: nextCursor, targetPage: pageNumber + 1)
    }

    func previous() async {
        guard !isLoading, pageNumber > 1 else { return }
        await load(start: starts[pageNumber - 2], targetPage: pageNumber - 1)
    }

    func retry() async {
        guard !isLoading else { return }
        await load(start: starts[pageNumber - 1], targetPage: pageNumber)
    }

    func cancel() {
        generation = UUID()
        isLoading = false
    }

    private func load(start: RepositoryCursor?, targetPage: Int) async {
        let token = generation
        isLoading = true
        errorMessage = nil
        defer { if token == generation { isLoading = false } }
        do {
            let result = try await readPage(start: start)
            let page = result.page
            guard token == generation, !Task.isCancelled else { return }
            items = page.items
            financialSummary = result.financial
            materialSummary = result.material
            quoteSummary = result.quote
            laborSummary = result.labor
            nextCursor = page.next
            if targetPage > starts.count { starts.append(start) }
            pageNumber = targetPage
        } catch RepositoryError.staleRevision {
            guard token == generation, !Task.isCancelled else { return }
            await reset()
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            errorMessage = RepositoryUserMessage.describe(error)
        }
    }

    private struct LoadedPage {
        let page: RepositoryPage
        var financial: RepositoryFinancialSummary?
        var material: RepositoryMaterialSummary?
        var quote: RepositoryQuoteSummary?
        var labor: RepositoryLaborSummary?
    }

    private func readPage(start: RepositoryCursor?) async throws -> LoadedPage {
        switch query.collection {
        case .projectFinancialRecords:
            let result = try await FinanceRepository(repository: repository).page(query, after: start, limit: pageSize)
            return LoadedPage(page: result.page, financial: result.summary)
        case .materialItems:
            let result = try await repository.materialPage(query, after: start, limit: pageSize)
            return LoadedPage(page: result.page, material: result.summary)
        case .laborRecords:
            let result = try await repository.laborPage(query, after: start, limit: pageSize)
            return LoadedPage(page: result.page, labor: result.summary)
        case .quoteItems:
            let result = try await repository.quotePage(query, after: start, limit: pageSize)
            return LoadedPage(page: result.page, quote: result.summary)
        default:
            return try await LoadedPage(page: repository.page(query, after: start, limit: pageSize))
        }
    }
}

@MainActor @Observable
final class RepositoryWorkspaceSession {
    let repository: any BusinessRepository
    private(set) var changeID = UUID()

    init(repository: any BusinessRepository) { self.repository = repository }
    func didCommit() { changeID = UUID() }
}

enum RepositoryUserMessage {
    static func describe(_ error: Error) -> String {
        if let error = error as? RepositoryError, let message = repositoryMessage(error) { return message }
        return String(format: AppLocalization.string("操作失败：%@"), error.localizedDescription)
    }

    private static func repositoryMessage(_ error: RepositoryError) -> String? {
        switch error {
        case .staleRevision:
            return AppLocalization.string("记录已变化，编辑内容已保留。请重新载入原记录并核对后再保存。")
        case .invalidContactName: return AppLocalization.string("请填写往来单位联系人姓名。")
        case .invalidLaborValues: return AppLocalization.string("请确认计量单位并填写有效的非负人数与工作量，单价可留空；金额须能精确计算。")
        case .invalidQuoteValues: return AppLocalization.string("请填写报价名称、单位及非负的单价、数量和税率；折扣率须在 0–100 之间，合同金额可留空，金额须能精确计算。")
        case .invalidMaterialValues: return AppLocalization.string("请填写材料名称、单位和非负数量。单价可留空或填写非负数，金额须能精确计算。")
        case .invalidQuantity: return AppLocalization.string("请输入大于零的有效数量，使用小数点且最多保留 38 位有效数字。")
        case .invalidAmount: return AppLocalization.string("请输入大于零的有效金额，使用小数点且最多保留 38 位有效数字。")
        case .missingRecord: return AppLocalization.string("记录已不存在，请返回列表刷新。")
        case .invalidCandidate: return AppLocalization.string("此副本不可用，原件与现有文件已保留。")
        default: return nil
        }
    }
}
