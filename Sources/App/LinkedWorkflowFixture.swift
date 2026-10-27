#if DEBUG
import Foundation

@MainActor
enum LinkedWorkflowFixture {
    static func prepareIfRequested(store: DataStore) async {
        guard ProcessInfo.processInfo.environment["UITEST_LINKED_WORKFLOW_FIXTURE"] == "1" else { return }
        await store.awaitInitialLoad()
        let projectID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
        guard store.loadState == .ready, !store.projects.contains(where: { $0.id == projectID }) else { return }
        let plan = ProjectPaymentPlan(id: UUID(uuidString: "70000000-0000-0000-0000-000000000010")!, title: "Linked Contract", direction: .income,
            counterparty: "Linked Customer", installments: [
                ProjectPaymentInstallment(id: UUID(uuidString: "70000000-0000-0000-0000-000000000011")!, title: "Linked Deposit", dueDate: BusinessDateValue(legacyText: "2099-01-01"), amount: 100),
                ProjectPaymentInstallment(id: UUID(uuidString: "70000000-0000-0000-0000-000000000012")!, title: "Linked Retention", dueDate: BusinessDateValue(legacyText: "2099-06-01"), amount: 20, isRetention: true)
            ])
        store.appendProject(Project(id: projectID, name: "Linked Site", location: "Test", paymentPlans: [plan]))
        store.replaceMaterialItems((0 ..< 60).map { index in
            MaterialItem(id: index == 0 ? UUID(uuidString: "70000000-0000-0000-0000-000000000003")! : UUID(), name: index == 0 ? "Linked Cable" : "Paged Material \(index)", quantity: 10, unit: "m", unitPrice: NumericInputSupport.money("1.25"),
                supplier: "Linked Supplier", projectId: projectID)
        })
        do { try await store.flushSaveOrThrow() } catch { assertionFailure("Linked workflow fixture: \(error)") }
    }
}
#endif
