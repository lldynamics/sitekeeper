#if DEBUG
import UIKit

@MainActor
enum WorkflowOptimizationFixture {
    static func prepareIfRequested(store: DataStore) async {
        guard ProcessInfo.processInfo.environment["UITEST_WORKFLOW_OPTIMIZATION_FIXTURE"] == "1" else { return }
        await store.awaitInitialLoad()
        guard store.loadState == .ready, !store.projects.contains(where: { $0.name == "Workflow Alpha" }) else { return }
        let first = Project(id: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!, name: "Workflow Alpha", location: "North")
        let second = Project(id: UUID(uuidString: "60000000-0000-0000-0000-000000000002")!, name: "Workflow Beta", location: "South")
        store.appendProject(first)
        store.appendProject(second)
        for (index, project) in [first, second].enumerated() {
            store.appendQuoteItem(QuoteItem(id: UUID(uuidString: "60000000-0000-0000-0000-00000000001\(index)")!, name: "SharedSearch", unitPrice: NumericInputSupport.money("10"), quantity: NumericInputSupport.quantity("2"), unit: "m", notes: "Quote Needle", taxRate: .zero, discountRate: .zero, projectId: project.id))
        }
        store.appendProjectFinancialRecord(ProjectFinancialRecord(id: UUID(uuidString: "60000000-0000-0000-0000-000000000020")!, projectId: first.id, amount: NumericInputSupport.money("123.45"), counterparty: "Workflow Supplier", invoiceNumber: "INV-WORKFLOW-001"))
        let document = ProjectDocument(id: UUID(uuidString: "60000000-0000-0000-0000-000000000030")!, projectId: first.id, title: "Workflow Document", fileName: "workflow-missing.pdf", archiveNumber: "DOC-WORKFLOW-001")
        store.appendProjectDocument(document)
        store.appendProjectDrawing(ProjectDrawing(id: UUID(uuidString: "60000000-0000-0000-0000-000000000040")!, projectId: first.id, name: "Workflow Drawing", drawingNumber: "DWG-WORKFLOW-001", fileName: "workflow-missing.dwg", fileType: "dwg", isCurrentVersion: false))
        let context = store.projectStore.dayContext
        let week = context.calendar.dateInterval(of: .weekOfYear, for: context.dayStart)!
        func day(_ offset: Int) -> BusinessDateValue {
            .day(CalendarDay(date: context.calendar.date(byAdding: .day, value: offset, to: week.start)!, timeZone: context.calendar.timeZone))
        }
        for (name, start, end) in [("Spanning Week Work", -7, 14), ("Inside Week Work", 1, 4), ("Past Week Work", -14, -8), ("Next Week Work", 8, 10)] {
            store.appendProgressTask(ProgressTask(projectId: first.id, title: name, startDate: day(start), dueDate: day(end), completion: 0.2, note: "Weekly filter fixture"))
        }
        do {
            let drafts = BusinessDraftStore.scoped(to: store.storeURL)
            let key = BusinessDraftStore.Key.todo(projectID: nil)
            let before = UUID(), after = UUID()
            let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).jpegData(withCompressionQuality: 0.8) { context in
                UIColor.orange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
            }
            try drafts.savePhoto(image, id: before, key: key)
            try drafts.savePhoto(image, id: after, key: key)
            try drafts.save(SiteTodoFormDraft(record: SiteTodo(id: UUID(uuidString: "60000000-0000-0000-0000-000000000050")!, title: ""), beforePhotoID: before, afterPhotoID: after), key: key)
            try await store.flushSaveOrThrow()
        } catch { assertionFailure("Workflow fixture failed: \(error)") }
    }
}
#endif
