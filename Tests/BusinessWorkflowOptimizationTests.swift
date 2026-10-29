import Foundation
import Testing
@testable import sitekeeper

@Suite(.serialized)
struct BusinessWorkflowOptimizationTests {
    enum Failure: Error { case injected }

    @MainActor private func temporaryStore() async throws -> DataStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("linked-workflows-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        return store
    }

    private func plan(direction: ProjectFinancialDirection = .income) -> ProjectPaymentPlan {
        ProjectPaymentPlan(title: "Contract", direction: direction, counterparty: "Customer", installments: [
            ProjectPaymentInstallment(title: "Deposit", dueDate: BusinessDateValue(legacyText: "2099-01-01"), amount: NumericInputSupport.money("100.10")),
            ProjectPaymentInstallment(title: "Retention", dueDate: BusinessDateValue(legacyText: "2099-06-01"), amount: NumericInputSupport.money("20.20"), isRetention: true)
        ])
    }

    private func payment(_ plan: ProjectPaymentPlan, project: UUID, amount: String, status: ProjectFinancialStatus = .active) -> ProjectFinancialRecord {
        ProjectFinancialRecord(projectId: project, direction: plan.direction, category: plan.direction == .income ? .collection : .receipt,
            amount: NumericInputSupport.money(amount), status: status,
            paymentAllocation: ProjectPaymentAllocation(planID: plan.id, installmentID: plan.installments[0].id))
    }

    private func receivableSchedule(_ project: Project, records: [ProjectFinancialRecord] = [],
                                    timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> ProjectReceivableScheduleSummary {
        ProjectReceivableScheduleSummary(project: project, records: records,
            today: CalendarDay(year: 2099, month: 1, day: 1)!, timeZone: timeZone)
    }

    @Test func receivableScheduleSeparatesTodayOverdueFutureAndRetentionWithoutChangingContract() throws {
        var plan = plan()
        plan.installments.insert(ProjectPaymentInstallment(title: "Overdue", dueDate: BusinessDateValue(legacyText: "2098-12-30"), amount: 30), at: 1)
        let project = Project(name: "A", location: "", contractAmount: 500, paymentPlans: [plan])
        let paid = payment(plan, project: project.id, amount: "0.10")
        let result = receivableSchedule(project, records: [paid])
        #expect(result.state == .ready)
        #expect(result.reviewReasons.isEmpty)
        #expect(result.planID == plan.id)
        #expect(result.dueUnpaidAmount == 130)
        #expect(result.dueTodayUnpaidAmount == 100)
        #expect(result.overdueUnpaidAmount == 30)
        #expect(result.futureUnpaidAmount == NumericInputSupport.money("20.20"))
        #expect(result.retentionUnpaidAmount == result.futureUnpaidAmount)
        #expect(result.oldestOverdueDays == 2)
        #expect(ProjectFinancialMetrics.unpaidAmount(project: project, records: [paid]) == NumericInputSupport.money("499.90"))
    }

    @Test func receivableScheduleUsesInjectedCivilDayForLegacyInstantDates() {
        var plan = plan()
        plan.installments = [ProjectPaymentInstallment(title: "Instant", dueDate: BusinessDateValue(legacyText: "2099-01-02T00:30:00.000Z"), amount: 10)]
        let project = Project(name: "A", location: "", paymentPlans: [plan])
        let utc = receivableSchedule(project)
        let west = receivableSchedule(project, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(utc.futureUnpaidAmount == 10)
        #expect(utc.dueTodayUnpaidAmount == 0)
        #expect(west.futureUnpaidAmount == 0)
        #expect(west.dueTodayUnpaidAmount == 10)
    }

    @Test func receivableScheduleLeavesManualAndUnallocatedCollectionsForReview() {
        var project = Project(name: "A", location: "", paidAmount: 20, paymentPlans: [plan()])
        let manual = receivableSchedule(project)
        #expect(manual.state == .needsReview)
        #expect(manual.reviewReasons.contains(.historicalManualPaid))
        #expect(manual.dueUnpaidAmount == nil)
        let unallocated = ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: 5)
        let actual = receivableSchedule(project, records: [unallocated])
        #expect(actual.reviewReasons.contains(.unallocatedCollections))
        #expect(!actual.reviewReasons.contains(.historicalManualPaid))
        #expect(actual.futureUnpaidAmount == nil)
        // Positive formal receipts retain the established precedence over manual history.
        let allocated = payment(project.paymentPlans[0], project: project.id, amount: "5")
        #expect(receivableSchedule(project, records: [allocated]).state == .ready)
        project.paidAmount = NumericInputSupport.money("unknown")
        #expect(receivableSchedule(project).state == .needsReview)
    }

    @Test func receivableScheduleRejectsOverlappingAndRestoredDuplicateIdentities() {
        let first = plan()
        var second = plan()
        var project = Project(name: "A", location: "", paymentPlans: [first, second])
        let overlapping = receivableSchedule(project)
        #expect(overlapping.reviewReasons.contains(.multipleActiveIncomePlans))
        #expect(overlapping.dueUnpaidAmount == nil)
        second.isArchived = true
        second.installments[0].id = first.installments[0].id
        project.paymentPlans = [first, second]
        #expect(receivableSchedule(project).reviewReasons.contains(.duplicateIdentity))
        second = plan()
        second.id = first.id
        second.isArchived = true
        project.paymentPlans = [first, second]
        #expect(receivableSchedule(project).reviewReasons.contains(.duplicateIdentity))
        project.paymentPlans = [first]
        project.paymentPlans[0].installments.append(first.installments[0])
        #expect(receivableSchedule(project).reviewReasons.contains(.duplicateIdentity))
    }

    @Test func receivableScheduleRejectsOverpaymentAndInvalidAllocationProvenance() {
        let plan = plan()
        let project = Project(name: "A", location: "", paymentPlans: [plan])
        let overpaid = payment(plan, project: project.id, amount: "101")
        let result = receivableSchedule(project, records: [overpaid])
        #expect(result.reviewReasons.contains(.overpaidPlan))
        #expect(result.retentionUnpaidAmount == nil)
        var invalid = payment(plan, project: project.id, amount: "10")
        invalid.category = .other
        #expect(receivableSchedule(project, records: [invalid]).reviewReasons.contains(.invalidAllocation))
        invalid.category = .collection
        invalid.paymentAllocation?.installmentID = UUID()
        #expect(receivableSchedule(project, records: [invalid]).reviewReasons.contains(.invalidAllocation))
        invalid.paymentAllocation?.planID = UUID()
        #expect(receivableSchedule(project, records: [invalid]).reviewReasons.contains(.invalidAllocation))
        let paid = payment(plan, project: project.id, amount: "10")
        #expect(receivableSchedule(project, records: [paid, paid]).reviewReasons.contains(.duplicateIdentity))
    }

    @Test func receivableScheduleExcludesOtherProjectsPayablesArchivesAndInactivePayments() {
        let income = plan()
        let expense = plan(direction: .expense)
        var archived = plan()
        archived.isArchived = true
        let project = Project(name: "A", location: "", paymentPlans: [income, expense, archived])
        let records = [payment(income, project: UUID(), amount: "999"),
                       payment(income, project: project.id, amount: "999", status: .draft),
                       payment(income, project: project.id, amount: "999", status: .archived),
                       payment(expense, project: project.id, amount: "10")]
        let result = receivableSchedule(project, records: records)
        #expect(result.state == .ready)
        #expect(result.dueUnpaidAmount == NumericInputSupport.money("100.10"))
        #expect(result.futureUnpaidAmount == NumericInputSupport.money("20.20"))
        let historicalCollection = payment(archived, project: project.id, amount: "10")
        let historical = receivableSchedule(project, records: records + [historicalCollection])
        #expect(historical.state == .needsReview)
        #expect(historical.reviewReasons.contains(.unallocatedCollections))
        #expect(historical.dueUnpaidAmount == nil)
        let noPlan = Project(name: "B", location: "", paidAmount: 10, paymentPlans: [expense, archived])
        let missing = receivableSchedule(noPlan)
        #expect(missing.state == .noActiveIncomePlan)
        #expect(missing.dueUnpaidAmount == nil)
        #expect(missing.futureUnpaidAmount == nil)
    }

    @Test func receivableScheduleRejectsInvalidPlanInputs() {
        for kind in ["amount", "date", "title", "planTitle", "overflow"] {
            var plan = plan()
            switch kind {
            case "amount": plan.installments[0].amount = NumericInputSupport.money("unresolved")
            case "date": plan.installments[0].dueDate = .unresolved("unknown")
            case "title": plan.installments[0].title = " "
            case "planTitle": plan.title = " "
            default:
                plan.installments[0].amount = NumericInputSupport.money("99999999999999999999999999999999999999")
                plan.installments[1].amount = NumericInputSupport.money("0.1")
            }
            let result = receivableSchedule(Project(name: "A", location: "", paymentPlans: [plan]))
            #expect(result.state == .needsReview)
            #expect(result.reviewReasons.contains(.invalidPlan))
            #expect(result.dueUnpaidAmount == nil)
        }
    }

    @Test func receivableScheduleKeepsInvalidCollectionsUnknownAndSettledTodayDistinctFromOverdue() {
        let plan = plan()
        let project = Project(name: "A", location: "", paymentPlans: [plan])
        let invalid = ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection,
            amount: NumericInputSupport.money("unknown"))
        #expect(receivableSchedule(project, records: [invalid]).reviewReasons.contains(.invalidCollectionAmount))
        let paid = payment(plan, project: project.id, amount: "100.10")
        let settled = receivableSchedule(project, records: [paid])
        #expect(settled.state == .ready)
        #expect(settled.dueUnpaidAmount == 0)
        #expect(settled.overdueUnpaidAmount == 0)
        #expect(settled.oldestOverdueDays == nil)
        #expect(settled.futureUnpaidAmount == settled.retentionUnpaidAmount)
    }

    @Test func plansDoNotCountAsCashAndPartialPaymentsUseExactDecimal() throws {
        let plan = plan()
        let project = Project(name: "A", location: "", paymentPlans: [plan])
        let paid = payment(plan, project: project.id, amount: "0.10")
        let draft = payment(plan, project: project.id, amount: "90", status: .draft)
        let archived = payment(plan, project: project.id, amount: "80", status: .archived)
        let summary = try #require(ProjectPaymentMetrics.summaries(project: project, records: [paid, draft, archived]).first)
        #expect(summary.total == NumericInputSupport.money("120.30"))
        #expect(summary.paid == NumericInputSupport.money("0.10"))
        #expect(summary.remaining == NumericInputSupport.money("120.20"))
        #expect(summary.nextDue?.id == plan.installments[0].id)
        #expect(ProjectFinancialMetrics.businessRecords([paid, draft, archived]).count == 1)
        #expect(ProjectPaymentMetrics.summaries(project: project, records: []).first?.paid.isZero == true)
    }

    @Test func rejectsOverpayWrongDirectionRefundAndMissingPlan() throws {
        let plan = plan()
        let project = Project(name: "A", location: "", paymentPlans: [plan])
        var record = payment(plan, project: project.id, amount: "100.11")
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validateAllocation(record, projects: [project], records: []) }
        record.amount = NumericInputSupport.money("100.10")
        try ProjectPaymentMetrics.validateAllocation(record, projects: [project], records: [])
        let paid = record
        record.id = UUID()
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validateAllocation(record, projects: [project], records: [paid]) }
        record.direction = .expense
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validateAllocation(record, projects: [project], records: []) }
        record.direction = .income
        record.category = .refund
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validateAllocation(record, projects: [project], records: []) }
        record.category = .collection
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validateAllocation(record, projects: [], records: []) }
    }

    @Test func activeEditsExcludeSelfAndArchivedPlansCannotReceiveNewCash() throws {
        var plan = plan()
        var project = Project(name: "A", location: "", paymentPlans: [plan])
        var record = payment(plan, project: project.id, amount: "60")
        try ProjectPaymentMetrics.validateAllocation(record, projects: [project], records: [record])
        plan.isArchived = true
        project.paymentPlans = [plan]
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validateAllocation(record, projects: [project], records: []) }
        record.status = .archived
        try ProjectPaymentMetrics.validateAllocation(record, projects: [project], records: [])
    }

    @Test func allocatedInstallmentsCannotDisappearOrShrinkBelowPaid() throws {
        let original = plan()
        let project = Project(name: "A", location: "", paymentPlans: [original])
        let paid = payment(original, project: project.id, amount: "50")
        var edited = original
        edited.installments.removeFirst()
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validate(edited, in: project, records: [paid]) }
        edited = original
        edited.installments[0].amount = 49
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validate(edited, in: project, records: [paid]) }
        edited = original
        edited.title = "Renamed"
        try ProjectPaymentMetrics.validate(edited, in: project, records: [paid])
    }

    @Test func invalidAndOverflowedPlansStayVisibleAsInvalid() {
        var plan = plan()
        plan.installments[0].amount = MoneyValue(storage: .unresolved("broken"))
        let project = Project(name: "A", location: "", paymentPlans: [plan])
        #expect(ProjectPaymentMetrics.summaries(project: project, records: []).first?.isValid == false)
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validate(plan, in: project, records: []) }
        plan.installments[0].amount = NumericInputSupport.money("99999999999999999999999999999999999999")
        plan.installments[1].amount = NumericInputSupport.money("0.1")
        #expect(throws: (any Error).self) { try ProjectPaymentMetrics.validate(plan, in: project, records: []) }
    }

    @Test func restoredOverpaymentIsReportedInsteadOfClampedAway() throws {
        let plan = plan()
        let project = Project(name: "A", location: "", paymentPlans: [plan])
        let first = payment(plan, project: project.id, amount: "80")
        let second = payment(plan, project: project.id, amount: "30.10")
        let summary = try #require(ProjectPaymentMetrics.summaries(project: project, records: [first, second]).first)
        #expect(summary.overpaid == 10)
        #expect(summary.paid == NumericInputSupport.money("110.10"))
        #expect(summary.installments[0].remaining.isZero)
    }

    @Test func settledInstallmentRemindersMoveToRetentionAndStopOnArchive() throws {
        var plan = plan()
        plan.remindersEnabled = true
        var project = Project(name: "A", location: "", paymentPlans: [plan])
        let paid = payment(plan, project: project.id, amount: "100.10")
        let plans = DueReminderPlanBuilder.makePlans(snapshot: DueReminderSnapshot(projects: [project], todos: [], financialRecords: [paid]))
        #expect(plans.filter { $0.identifier.contains("installment") }.map(\.identifier) == ["sitekeeper.due.installment.\(project.id.uuidString).\(plan.installments[1].id.uuidString)"])
        #expect(ProjectPaymentMetrics.summaries(project: project, records: [paid]).first?.nextDue?.installment.isRetention == true)
        project.paymentPlans[0].isArchived = true
        #expect(DueReminderPlanBuilder.makePlans(snapshot: DueReminderSnapshot(projects: [project], todos: [], financialRecords: [paid])).isEmpty)
    }

    @Test func copiedPlansInDifferentProjectsHaveIndependentReminderIdentities() {
        var plan = plan()
        plan.remindersEnabled = true
        let first = Project(name: "A", location: "", paymentPlans: [plan])
        let second = Project(name: "B", location: "", paymentPlans: [plan])
        let reminders = DueReminderPlanBuilder.makePlans(snapshot: DueReminderSnapshot(projects: [first, second], todos: [], financialRecords: []))
        #expect(reminders.count == 4)
        #expect(Set(reminders.map(\.identifier)).count == 4)
    }

    @MainActor @Test func failedPlanSavePreservesConcurrentProjectChangesAndRetry() async throws {
        let store = try await temporaryStore()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: store.storeURL.deletingLastPathComponent()) }
        let project = Project(name: "Original", location: "")
        store.appendProject(project)
        let plan = plan()
        do {
            try await ProjectPaymentService.savePlan(plan, projectID: project.id, expected: nil, store: store, persist: {
                var edited = try #require(store.projects.first)
                edited.name = "Concurrent"
                store.updateProject(edited)
                throw Failure.injected
            })
            Issue.record("Expected failure")
        } catch Failure.injected {}
        #expect(store.projects.first?.name == "Concurrent")
        #expect(store.projects.first?.paymentPlans.isEmpty == true)
        try await ProjectPaymentService.savePlan(plan, projectID: project.id, expected: nil, store: store)
        await #expect(throws: (any Error).self) { try await ProjectPaymentService.savePlan(plan, projectID: project.id, expected: nil, store: store) }
        #expect(store.projects.first?.paymentPlans.count == 1)
    }

    @MainActor @Test func failedPartialPaymentRollsBackOwnRecordThenPersistsAcrossRestart() async throws {
        let store = try await temporaryStore()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: store.storeURL.deletingLastPathComponent()) }
        let plan = plan()
        let project = Project(name: "A", location: "", paymentPlans: [plan])
        store.appendProject(project)
        let paid = payment(plan, project: project.id, amount: "30.10")
        let other = ProjectFinancialRecord(projectId: project.id, amount: 9, note: "Another edit")
        do {
            try await ProjectPaymentService.recordPayment(paid, store: store, persist: {
                store.appendProjectFinancialRecord(other)
                throw Failure.injected
            })
            Issue.record("Expected failure")
        } catch Failure.injected {}
        #expect(store.projectFinancialRecords.map(\.id) == [other.id])
        try await ProjectPaymentService.recordPayment(paid, store: store)
        await #expect(throws: (any Error).self) { try await ProjectPaymentService.recordPayment(paid, store: store) }
        let restarted = DataStore(storageDirectory: store.storeURL.deletingLastPathComponent())
        await restarted.awaitInitialLoad()
        #expect(restarted.projects.first?.paymentPlans == [plan])
        #expect(ProjectPaymentMetrics.summaries(project: project, records: restarted.projectFinancialRecords).first?.remaining == NumericInputSupport.money("90.20"))
        restarted.cancelScheduledSave()
    }

    @MainActor @Test func receiptDraftLedgerIsIdempotentAndKeepsPlanAndProvenanceAcrossRestart() async throws {
        let store = try await temporaryStore()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: store.storeURL.deletingLastPathComponent()) }
        let project = Project(name: "A", location: "")
        store.appendProject(project)
        let material = MaterialItem(name: "Cable", quantity: 10, unit: "m", unitPrice: NumericInputSupport.money("1.25"), supplier: "Supplier", projectId: project.id)
        store.appendMaterialItem(material)
        let request = MaterialReceiptRequest(materialID: material.id, expectedMaterial: BusinessDraftStore.fingerprint(material), quantity: 4,
            unitPrice: NumericInputSupport.money("1.25"), date: .today(), handler: "Worker", note: "Delivery")
        let movement = try await MaterialWarehouseWorkflow.receive(request, store: store)
        await #expect(throws: (any Error).self) { _ = try await MaterialWarehouseWorkflow.receive(request, store: store) }
        let progress = MaterialWarehouseWorkflow.progress(material: material, movements: store.projectWarehouseMovements)
        #expect(progress.received == 4 && progress.remaining == 6 && progress.stock == 4)
        #expect(store.materialItems.first?.quantity == 10)
        let draft = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: BusinessDraftStore.fingerprint(movement), unitPrice: NumericInputSupport.money("1.25"), store: store)
        let repeated = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: nil, unitPrice: 99, store: store)
        #expect(draft.id == repeated.id)
        #expect(draft.amount == 5 && draft.status == .draft)
        #expect(draft.origin?.materialItemID == material.id && draft.origin?.warehouseMovementID == movement.id)
        #expect(ProjectFinancialMetrics.businessRecords(store.projectFinancialRecords).isEmpty)
        let restarted = DataStore(storageDirectory: store.storeURL.deletingLastPathComponent())
        await restarted.awaitInitialLoad()
        #expect(restarted.projectFinancialRecords.count == 1)
        #expect(restarted.projectFinancialRecords.first?.origin == draft.origin)
        #expect(restarted.projectWarehouseMovements.first?.origin == movement.origin)
        restarted.cancelScheduledSave()
    }

    @MainActor @Test func staleAndFailedReceiptsCannotOverwriteSourceOrOtherMovements() async throws {
        let store = try await temporaryStore()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: store.storeURL.deletingLastPathComponent()) }
        let project = Project(name: "A", location: "")
        store.appendProject(project)
        var material = MaterialItem(name: "Cable", quantity: 10, unit: "m", projectId: project.id)
        store.appendMaterialItem(material)
        var request = MaterialReceiptRequest(materialID: material.id, expectedMaterial: nil, quantity: 4, unitPrice: .empty, date: .today(), handler: "", note: "")
        await #expect(throws: (any Error).self) { _ = try await MaterialWarehouseWorkflow.receive(request, store: store) }
        request.expectedMaterial = BusinessDraftStore.fingerprint(material)
        let other = ProjectWarehouseMovement(projectId: project.id, materialName: "Other", quantity: 3)
        do {
            _ = try await MaterialWarehouseWorkflow.receive(request, store: store, persist: {
                store.insertProjectWarehouseMovementAtTop(other)
                material.quantity = 20
                store.updateMaterialItem(material)
                throw Failure.injected
            })
            Issue.record("Expected failure")
        } catch Failure.injected {}
        #expect(store.projectWarehouseMovements.map(\.id) == [other.id])
        #expect(store.materialItems.first?.quantity == 20)
        await #expect(throws: (any Error).self) { _ = try await MaterialWarehouseWorkflow.receive(request, store: store) }
    }

    @MainActor @Test func invalidPriceAndFailedLedgerSaveLeaveNoPhantomCash() async throws {
        let store = try await temporaryStore()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: store.storeURL.deletingLastPathComponent()) }
        let project = Project(name: "A", location: "")
        store.appendProject(project)
        let movement = ProjectWarehouseMovement(projectId: project.id, materialName: "Cable", quantity: NumericInputSupport.quantity("0.1"))
        store.appendProjectWarehouseMovement(movement)
        await #expect(throws: (any Error).self) { _ = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: BusinessDraftStore.fingerprint(movement), unitPrice: 0, store: store) }
        do {
            _ = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: BusinessDraftStore.fingerprint(movement), unitPrice: 2, store: store, persist: { throw Failure.injected })
            Issue.record("Expected failure")
        } catch Failure.injected {}
        #expect(store.projectFinancialRecords.isEmpty)
        let draft = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: BusinessDraftStore.fingerprint(movement), unitPrice: NumericInputSupport.money("0.2"), store: store)
        #expect(draft.amount == NumericInputSupport.money("0.02"))
    }

    @Test func legacyRecordsDecodeWithoutNewFieldsAndNestedFieldsRoundTrip() throws {
        let projectID = UUID()
        let decoder = JSONDecoder()
        let project = try decoder.decode(Project.self, from: Data("{\"id\":\"\(projectID)\",\"name\":\"Old\"}".utf8))
        #expect(project.paymentPlans.isEmpty)
        let financial = try decoder.decode(ProjectFinancialRecord.self, from: Data("{\"projectId\":\"\(projectID)\",\"amount\":\"1.25\"}".utf8))
        #expect(financial.origin == nil && financial.paymentAllocation == nil)
        let movement = try decoder.decode(ProjectWarehouseMovement.self, from: Data("{\"projectId\":\"\(projectID)\",\"materialName\":\"Old\"}".utf8))
        #expect(movement.origin == nil)
        let plan = plan()
        let current = Project(id: projectID, name: "New", location: "", paymentPlans: [plan])
        let roundTrip = try decoder.decode(Project.self, from: JSONEncoder().encode(current))
        #expect(roundTrip.paymentPlans == [plan])
        let paid = payment(plan, project: projectID, amount: "0.10")
        #expect(try decoder.decode(ProjectFinancialRecord.self, from: JSONEncoder().encode(paid)).paymentAllocation == paid.paymentAllocation)
    }
}
