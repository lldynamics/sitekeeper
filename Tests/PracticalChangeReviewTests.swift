import Foundation
import Testing
@testable import sitekeeper

@Suite(.serialized)
struct PracticalChangeReviewTests {
    private let firstDate = BusinessDateValue(legacyText: "2026-10-28T10:00:00Z")
    private let secondDate = BusinessDateValue(legacyText: "2026-10-29T10:00:00Z")

    @Test func oldJSONKeepsOrdinaryTodoBehaviorAndNoChangeOrders() throws {
        let project = try JSONDecoder().decode(Project.self, from: Data(#"{"name":"Legacy","location":"Site"}"#.utf8))
        #expect(project.changeOrders.isEmpty)
        var todo = try JSONDecoder().decode(SiteTodo.self, from: Data(#"{"title":"Legacy","isDone":false}"#.utf8))
        #expect(todo.review == nil)
        todo.toggleCompletionForWorkflow(at: firstDate)
        #expect(todo.isDone && todo.completedAt == firstDate)
        todo.toggleCompletionForWorkflow(at: secondDate)
        #expect(!todo.isDone && todo.completedAt == nil && todo.review == nil)
    }

    @Test func submissionReturnPassAndReopenPreserveHistoryAndDates() throws {
        var todo = SiteTodo(title: "Wall repair")
        todo.enableReview()
        todo.requestCompletion(at: firstDate)
        #expect(todo.review?.status == .awaitingReview && !todo.isDone && todo.completedAt == nil)
        let rejectedEmptyReviewer = todo.recordReview(outcome: .passed, reviewer: "  ", note: "", at: firstDate)
        #expect(!rejectedEmptyReviewer)
        #expect(todo.review?.history.isEmpty == true)
        let returned = todo.recordReview(outcome: .returned, reviewer: "Inspector A", note: "Repair again", at: firstDate)
        #expect(returned)
        #expect(todo.review?.status == .rectifying && !todo.isDone && todo.completedAt == nil)
        let disabledAfterReturn = todo.disableReviewIfUnused()
        #expect(!disabledAfterReturn)
        todo.toggleCompletionForWorkflow(at: secondDate)
        #expect(todo.review?.status == .awaitingReview && !todo.isDone)
        let passed = todo.recordReview(outcome: .passed, reviewer: "Inspector B", note: "Accepted", at: secondDate)
        #expect(passed)
        #expect(todo.isDone && todo.completedAt == secondDate)
        #expect(todo.review?.history.map(\.outcome) == [.returned, .passed])
        let restored = try JSONDecoder().decode(SiteTodo.self, from: JSONEncoder().encode(todo))
        #expect(restored.review == todo.review && restored.completedAt == secondDate)
        todo.reopenForWork()
        #expect(todo.review?.status == .rectifying && !todo.isDone && todo.completedAt == nil)
        #expect(todo.review?.history.count == 2 && todo.review?.history.last?.reviewer == "Inspector B")
        let disabledAfterReopen = todo.disableReviewIfUnused()
        #expect(!disabledAfterReopen)
    }

    @Test func completionCannotBypassReviewAndOnlyUnusedWorkflowCanBeDisabled() throws {
        var todo = SiteTodo(title: "Repair", isDone: true, completedAt: firstDate)
        todo.enableReview()
        #expect(!todo.isDone && todo.completedAt == nil)
        todo.isDone = true
        todo.completedAt = firstDate
        todo.normalizeReviewCompletion()
        #expect(!todo.isDone && todo.completedAt == nil)
        todo.review?.status = .closed
        todo.normalizeReviewCompletion()
        #expect(todo.review?.status == .rectifying && !todo.isDone)
        let disabledUnusedReview = todo.disableReviewIfUnused()
        #expect(disabledUnusedReview && todo.review == nil)

        var encoded = SiteTodo(title: "Attempted bypass")
        encoded.enableReview()
        encoded.isDone = true
        encoded.completedAt = firstDate
        let decoded = try JSONDecoder().decode(SiteTodo.self, from: JSONEncoder().encode(encoded))
        #expect(!decoded.isDone && decoded.completedAt == nil)
    }

    @Test func unfinishedReviewNoteSurvivesRecordAndDraftJSONUntilSuccessfulDecision() throws {
        let legacyReview = try JSONDecoder().decode(SiteTodoReview.self, from: Data(
            #"{"status":"awaitingReview","reviewer":"Inspector","history":[]}"#.utf8
        ))
        #expect(legacyReview.pendingNote == nil)

        var todo = SiteTodo(title: "Wall repair")
        todo.enableReview()
        todo.requestCompletion(at: firstDate)
        todo.review?.reviewer = "Inspector"
        todo.review?.pendingNote = "  Unfinished review\nkeep the next step  "
        let savedJSON = try JSONEncoder().encode(todo)
        var restarted = try JSONDecoder().decode(SiteTodo.self, from: savedJSON)
        #expect(restarted.review?.pendingNote == todo.review?.pendingNote)
        #expect(restarted.review?.status == .awaitingReview && !restarted.isDone)
        let draft = SiteTodoFormDraft(record: restarted)
        let restoredDraft = try JSONDecoder().decode(SiteTodoFormDraft.self, from: JSONEncoder().encode(draft))
        #expect(restoredDraft.record.review?.pendingNote == todo.review?.pendingNote)

        let rejectedEmptyReviewer = restarted.recordReview(outcome: .passed, reviewer: " ", note: "", at: secondDate)
        #expect(!rejectedEmptyReviewer)
        #expect(restarted.review?.pendingNote == todo.review?.pendingNote)
        let pending = restarted.review?.pendingNote ?? ""
        let returned = restarted.recordReview(outcome: .returned, reviewer: "Inspector", note: pending, at: secondDate)
        #expect(returned)
        #expect(restarted.review?.pendingNote == nil)
        #expect(restarted.review?.history.last?.note == pending)
        restarted.reopenForWork()
        let final = try JSONDecoder().decode(SiteTodo.self, from: JSONEncoder().encode(restarted))
        #expect(final.review?.pendingNote == nil && final.review?.history.last?.note == pending)
    }

    @Test func changeOrderValidationRejectsInvalidConfirmationAndForeignOrMissingDocuments() throws {
        let project = Project(name: "A", location: "")
        let own = ProjectDocument(projectId: project.id, title: "Own", fileName: "own.pdf")
        let foreign = ProjectDocument(projectId: UUID(), title: "Foreign", fileName: "foreign.pdf")
        var order = ProjectChangeOrder(title: "Extra", proposedAmount: NumericInputSupport.money("0.10"), documentIDs: [own.id])
        try order.validate(projectID: project.id, documents: [own, foreign])
        order.documentIDs = [foreign.id]
        #expect(throws: (any Error).self) { try order.validate(projectID: project.id, documents: [own, foreign]) }
        order.documentIDs = [UUID()]
        #expect(throws: (any Error).self) { try order.validate(projectID: project.id, documents: [own]) }
        order.documentIDs = [own.id, own.id]
        #expect(throws: (any Error).self) { try order.validate(projectID: project.id, documents: [own]) }
        order.documentIDs = []
        order.proposedAmount = NumericInputSupport.money("-1")
        #expect(throws: (any Error).self) { try order.validate(projectID: project.id, documents: []) }
        order.proposedAmount = NumericInputSupport.money("0.10")
        order.confirmationState = .confirmed
        #expect(throws: (any Error).self) { try order.validate(projectID: project.id, documents: []) }
        order.confirmedAmount = NumericInputSupport.money("0.20")
        order.confirmedBy = "Recorder"
        order.confirmedAt = firstDate
        try order.validate(projectID: project.id, documents: [])
        #expect(try JSONDecoder().decode(ProjectChangeOrder.self, from: JSONEncoder().encode(order)) == order)
    }

    @Test func confirmationPreviewMarksPendingAndNeverRevealsForeignDocumentTitle() {
        let project = Project(name: "A", location: "")
        let foreign = ProjectDocument(projectId: UUID(), title: "Private foreign title", fileName: "secret.pdf")
        var order = ProjectChangeOrder(title: "Extra", proposedAmount: 10,
                                       confirmedAmount: NumericInputSupport.money("738204.918273"),
                                       confirmationState: .pendingConfirmation, documentIDs: [foreign.id])
        let pending = ReportBuilder.changeOrderConfirmationText(project: project, order: order, documents: [foreign])
        #expect(pending.contains(AppLocalization.string("未确认，不可作为已确认金额依据")))
        #expect(pending.contains(AppLocalization.string("关联资料已失效，请核对原项目资料。")))
        #expect(!pending.contains(foreign.title) && !pending.contains(foreign.fileName))
        let confirmedAmountField = "\(AppLocalization.string("确认金额")): \(ReportBuilder.money(order.confirmedAmount))"
        let hasConfirmedAmountField = pending.components(separatedBy: "\n").contains(confirmedAmountField)
        #expect(!hasConfirmedAmountField)
        order.confirmationState = .confirmed
        order.confirmedBy = "Recorder"
        order.confirmedAt = firstDate
        let confirmed = ReportBuilder.changeOrderConfirmationText(project: project, order: order, documents: [])
        #expect(confirmed.contains(AppLocalization.string("已确认（本机记录）")))
        let confirmedHasAmountField = confirmed.components(separatedBy: "\n").contains(confirmedAmountField)
        #expect(confirmedHasAmountField)
        #expect(confirmed.contains(AppLocalization.string("本单仅为本机记录，不代表甲方签章；增项金额独立记录，不计入合同金额、经营汇总或结算。")))
    }

    @MainActor @Test func failedChangeOrderSaveRollsBackOnlyItsRecordAndRetryDoesNotPostMoney() async throws {
        enum Failure: Error { case injected }
        let store = ChangeReviewTestStore()
        let project = Project(name: "A", location: "Site", contractAmount: 100, paidAmount: 20, materialCost: 5, laborCost: 6)
        store.projects = [project]
        let order = ProjectChangeOrder(title: "Extra", proposedAmount: 30)
        let unrelated = ProjectChangeOrder(title: "Another record", proposedAmount: 9)
        do {
            try await ProjectChangeOrderService.save(order, projectID: project.id, expected: nil, store: store, persist: {
                store.projects[0].name = "Concurrent edit"
                store.projects[0].changeOrders.append(unrelated)
                throw Failure.injected
            })
            Issue.record("Expected persistence failure")
        } catch Failure.injected {}
        #expect(store.projects[0].name == "Concurrent edit")
        #expect(store.projects[0].changeOrders == [unrelated])
        #expect(store.savingPaymentProjects.isEmpty)
        try await ProjectChangeOrderService.save(order, projectID: project.id, expected: nil, store: store)
        await #expect(throws: (any Error).self) {
            try await ProjectChangeOrderService.save(order, projectID: project.id, expected: nil, store: store)
        }
        #expect(store.projects[0].changeOrders.count == 2)
        #expect(store.projects[0].contractAmount == 100 && store.projects[0].paidAmount == 20)
        #expect(store.projects[0].materialCost == 5 && store.projects[0].laborCost == 6)
        #expect(store.projectFinancialRecords.isEmpty)
        let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(store.projects[0]))
        #expect(restored.changeOrders == store.projects[0].changeOrders)
    }

    @MainActor @Test func staleEditCannotOverwriteOtherChangeOrderVersion() async throws {
        let store = ChangeReviewTestStore()
        let original = ProjectChangeOrder(title: "Original", proposedAmount: 10)
        var concurrent = original
        concurrent.detail = "Saved elsewhere"
        let project = Project(name: "A", location: "", changeOrders: [concurrent])
        store.projects = [project]
        var edit = original
        edit.detail = "Stale form"
        await #expect(throws: (any Error).self) {
            try await ProjectChangeOrderService.save(edit, projectID: project.id, expected: original, store: store)
        }
        #expect(store.projects[0].changeOrders == [concurrent])
    }
}

@MainActor
private final class ChangeReviewTestStore: BusinessWorkflowStore {
    var projects: [Project] = []
    var materialItems: [MaterialItem] = []
    var projectWarehouseMovements: [ProjectWarehouseMovement] = []
    var projectFinancialRecords: [ProjectFinancialRecord] = []
    var projectDocuments: [ProjectDocument] = []
    var savingPaymentProjects: Set<UUID> = []
    func awaitInitialLoad() async {}
    func requireBusinessWritesAllowed() throws {}
    func flushSaveOrThrow() async throws {}
    @discardableResult func updateProject(_ value: Project) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == value.id }) else { return false }
        projects[index] = value
        return true
    }
    func appendProjectFinancialRecord(_ value: ProjectFinancialRecord) { projectFinancialRecords.append(value) }
    func insertProjectWarehouseMovementAtTop(_ value: ProjectWarehouseMovement) { projectWarehouseMovements.insert(value, at: 0) }
    func rollbackLinkedFinancialRecord(id: UUID) { projectFinancialRecords.removeAll { $0.id == id } }
    func rollbackLinkedWarehouseMovement(id: UUID) { projectWarehouseMovements.removeAll { $0.id == id } }
}
