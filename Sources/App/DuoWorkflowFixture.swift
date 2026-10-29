#if DEBUG
import UIKit

@MainActor
enum DuoWorkflowFixture {
    static func prepareIfRequested(store: DataStore) async {
        await prepareScrollFixtureIfRequested(store: store)
        guard ProcessInfo.processInfo.environment["UITEST_DUO_WORKFLOW_FIXTURE"] == "1" else { return }
        await store.awaitInitialLoad()
        guard store.loadState == .ready, !store.projects.contains(where: { $0.name == "Duo Workflow Site" }) else { return }
        do {
            let project = Project(name: "Duo Workflow Site", location: "Duo test", status: .active)
            store.appendProject(project)
            let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { context in
                for page in 1...3 {
                    context.beginPage()
                    ("Duo Drawing Page \(page)" as NSString).draw(at: CGPoint(x: 30, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
                    for index in 0..<12 {
                        ("Grid \(index) — Inspection zone" as NSString).draw(at: CGPoint(x: 30, y: 110 + index * 48), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
                    }
                }
            }
            var drawing = try DrawingStorage.saveImportedDataOrThrow(data: pdf, sourceFileName: "Duo Drawing.pdf", projectId: project.id)
            drawing.id = UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
            drawing.drawingNumber = "DUO-PDF-001"
            store.appendProjectDrawing(drawing)
            store.replaceMaterialSheetDrafts([MaterialSheetDraft(title: "Duo Materials", projectId: project.id, items: [
                MaterialSheetDraftItem(id: UUID(uuidString: "71000000-0000-0000-0000-000000000002")!, name: "Duo Copper", specification: "BV 4 mm²", unit: "m", quantity: NumericInputSupport.quantity("2"), unitPrice: NumericInputSupport.money("12.50"), laborCost: NumericInputSupport.money("5"))
            ])])
            try await store.flushSaveOrThrow()
        } catch {
            assertionFailure("Duo workflow fixture failed: \(error)")
        }
    }

    private static func prepareScrollFixtureIfRequested(store: DataStore) async {
        guard ProcessInfo.processInfo.environment["UITEST_DUO_SCROLL_FIXTURE"] == "1" else { return }
        await store.awaitInitialLoad()
        guard store.loadState == .ready,
              !store.projects.contains(where: { $0.name == "Duo Scroll Site" }) else { return }
        let project = Project(name: "Duo Scroll Site", location: "UI test")
        store.appendProject(project)
        let context = store.projectStore.dayContext
        for index in 1...24 {
            let date = context.calendar.date(byAdding: .day, value: index, to: context.dayStart)!
            let day = BusinessDateValue.day(CalendarDay(date: date, timeZone: context.calendar.timeZone))
            store.appendSiteTodo(SiteTodo(title: String(format: "Duo Todo %02d", index), dueDate: day, projectId: project.id))
            let pastDate = context.calendar.date(byAdding: .day, value: -index, to: context.dayStart)!
            let pastDay = BusinessDateValue.day(CalendarDay(date: pastDate, timeZone: context.calendar.timeZone))
            store.appendProgressTask(ProgressTask(projectId: project.id, title: String(format: "Duo Progress %02d", index), startDate: pastDay, dueDate: pastDay, completion: 0.2, note: ""))
        }
        let completedDate = context.calendar.date(byAdding: .day, value: -13, to: context.dayStart)!
        let completedDay = BusinessDateValue.day(CalendarDay(date: completedDate, timeZone: context.calendar.timeZone))
        store.appendProgressTask(ProgressTask(projectId: project.id, title: "Duo Progress Completed", startDate: completedDay, dueDate: completedDay, completion: 1, note: ""))
        do { try await store.flushSaveOrThrow() }
        catch { assertionFailure("Duo scroll fixture failed: \(error)") }
    }
}
#endif
