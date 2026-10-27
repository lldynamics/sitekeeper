#if DEBUG
import Foundation

@MainActor
enum RepositoryWorkspaceFixture {
    static func prepareIfRequested(store: DataStore) async {
        guard ProcessInfo.processInfo.environment["UITEST_REPOSITORY_FIXTURE"] == "1" else { return }
        await store.awaitInitialLoad()
        guard store.loadState == .ready, !store.projects.contains(where: { $0.name == "分页工程 052" }) else { return }
        let projects = (0..<53).map { index in
            Project(name: String(format: "分页工程 %03d", index), location: "合成数据", startDate: BusinessDateValue(legacyText: index == 52 ? "2030-01-01" : "2026-10-24"))
        }
        for project in projects { store.appendProject(project) }
        for index in 0..<102 {
            store.appendDailyLog(DailyLog(date: BusinessDateValue(legacyText: index == 101 ? "2030-01-01" : "2026-10-24"), weather: "晴",
                content: String(format: "分页日志 %03d", index), workers: NumericInputSupport.quantity("2"), projectId: projects[52].id))
        }
        if ProcessInfo.processInfo.environment["UITEST_REPOSITORY_FINANCE_FIXTURE"] == "1" {
            for index in 0..<53 {
                store.appendProjectFinancialRecord(ProjectFinancialRecord(projectId: projects[52].id,
                    date: BusinessDateValue(legacyText: index == 52 ? "2030-01-01" : "2026-10-24"), direction: index < 50 ? .income : .expense,
                    amount: NumericInputSupport.money(index < 50 ? "0.10" : "0.20"), counterparty: String(format: "财务流水 %03d", index)))
            }
            store.appendProjectFinancialRecord(ProjectFinancialRecord(projectId: projects[52].id, amount: NumericInputSupport.money("999"), status: .draft))
            store.appendProjectFinancialRecord(ProjectFinancialRecord(projectId: projects[52].id, amount: NumericInputSupport.money("888"), status: .archived))
            store.appendProjectFinancialRecord(ProjectFinancialRecord(projectId: projects[0].id, amount: NumericInputSupport.money("777")))
        }
        if ProcessInfo.processInfo.environment["UITEST_REPOSITORY_WAREHOUSE_FIXTURE"] == "1" {
            for index in 0..<53 {
                let name = String(format: "仓储材料 %03d", index)
                store.appendProjectWarehouseMovement(ProjectWarehouseMovement(projectId: projects[52].id, date: BusinessDateValue(legacyText: index == 52 ? "2030-01-01" : "2026-10-24"), materialName: name, unit: "米", quantity: NumericInputSupport.quantity("2.5")))
                store.appendProjectWarehouseMovement(ProjectWarehouseMovement(projectId: projects[52].id, date: BusinessDateValue(legacyText: index == 52 ? "2031-01-01" : "2026-10-24"), movementType: .outbound, materialName: name, unit: "米", quantity: NumericInputSupport.quantity("0.5")))
            }
            store.appendProjectWarehouseMovement(ProjectWarehouseMovement(projectId: projects[0].id, materialName: "仓储材料 052", unit: "米", quantity: NumericInputSupport.quantity("999")))
        }
        prepareMaterials(store: store, projects: projects)
        prepareQuotes(store: store, projects: projects)
        prepareLabor(store: store, projects: projects)
        prepareContacts(store: store, projects: projects)
        do { try await store.flushSaveOrThrow() } catch { assertionFailure("Repository UI fixture: \(error)") }
    }
    private static func prepareContacts(store: DataStore, projects: [Project]) {
        guard ProcessInfo.processInfo.environment["UITEST_REPOSITORY_CONTACTS_FIXTURE"] == "1" else { return }
        for index in 0..<53 {
            store.appendProjectContact(ProjectContact(projectId: projects[52].id, relatedProjectIds: index == 0 ? [projects[0].id] : [],
                name: String(format: "候选联系人 %03d", index), role: index == 0 ? .supplier : .owner,
                company: "测试单位", phone: "00000000000", note: "原始备注"))
        }
        store.appendProjectContact(ProjectContact(projectId: projects[0].id, name: "其他项目联系人", company: "其他单位"))
    }

    private static func prepareLabor(store: DataStore, projects: [Project]) {
        guard ProcessInfo.processInfo.environment["UITEST_REPOSITORY_LABOR_FIXTURE"] == "1" else { return }
        for index in 0..<53 {
            store.appendLaborRecord(LaborRecord(date: BusinessDateValue(legacyText: index == 52 ? "2030-01-01" : "2026-10-24"),
                workers: QuantityValue(2), hours: QuantityValue(1), workloadUnit: index == 52 ? .workday : .hour,
                unitRate: MoneyValue(10), workType: "木工", teamName: String(format: "候选人工 %03d", index),
                isSettled: index == 52, note: "合成记录", projectId: projects[52].id))
        }
        store.appendLaborRecord(LaborRecord(date: BusinessDateValue(legacyText: "2026-10-24"), workers: QuantityValue(1), hours: QuantityValue(1), unitRate: MoneyValue(999), teamName: "其他项目人工", note: "", projectId: projects[0].id))
        store.appendLaborRecord(LaborRecord(date: BusinessDateValue(legacyText: "2026-10-24"), workers: QuantityValue(1), hours: QuantityValue(1), unitRate: MoneyValue(5), teamName: "未关联人工", note: ""))
    }

    private static func prepareQuotes(store: DataStore, projects: [Project]) {
        guard ProcessInfo.processInfo.environment["UITEST_REPOSITORY_QUOTE_FIXTURE"] == "1" else { return }
        for index in 0..<53 {
            store.appendQuoteItem(QuoteItem(name: String(format: "候选报价 %03d", index), unitPrice: NumericInputSupport.money("10"), quantity: NumericInputSupport.quantity("1"), unit: "项",
                notes: "合成报价", taxRate: NumericInputSupport.quantity("13"), discountRate: NumericInputSupport.quantity("5"), versionName: index == 52 ? "V2" : "V1",
                status: index == 52 ? .confirmed : .draft, customerConfirmedDate: BusinessDateValue(legacyText: index == 52 ? "2030-01-01" : "2026-10-24"), projectId: projects[52].id))
        }
        store.appendQuoteItem(QuoteItem(name: "其他项目报价", unitPrice: NumericInputSupport.money("999"), quantity: NumericInputSupport.quantity("1"), unit: "项", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("0"), projectId: projects[0].id))
        store.appendQuoteItem(QuoteItem(name: "未关联报价", unitPrice: NumericInputSupport.money("5"), quantity: NumericInputSupport.quantity("1"), unit: "项", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("0")))
    }

    private static func prepareMaterials(store: DataStore, projects: [Project]) {
        guard ProcessInfo.processInfo.environment["UITEST_REPOSITORY_MATERIAL_FIXTURE"] == "1" else { return }
        for index in 0..<53 {
            store.appendMaterialItem(MaterialItem(name: String(format: "清单材料 %03d", index), quantity: NumericInputSupport.quantity("2.5"), unit: "米", unitPrice: NumericInputSupport.money("0.2"),
                supplier: "测试供应商", purchaseStatus: index == 52 ? .arrived : .notPurchased,
                arrivalDate: BusinessDateValue(legacyText: index == 52 ? "2030-01-01" : "2026-10-24"), projectId: projects[52].id))
        }
        store.appendMaterialItem(MaterialItem(name: "其他项目材料", quantity: NumericInputSupport.quantity("1"), unit: "件", unitPrice: NumericInputSupport.money("999"), projectId: projects[0].id))
        store.appendMaterialItem(MaterialItem(name: "未关联材料", quantity: NumericInputSupport.quantity("1"), unit: "件"))
    }
}
#endif
