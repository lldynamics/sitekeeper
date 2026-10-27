import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct DashboardBusinessSearchTests {
    private func quote(projectID: UUID?, id: UUID = UUID(), name: String = "Search copper quote") -> QuoteItem {
        QuoteItem(id: id, name: name, unitPrice: NumericInputSupport.money("12"), quantity: NumericInputSupport.quantity("2"), unit: "m", notes: "Search notes", taxRate: .zero, discountRate: .zero, versionName: "V3", projectId: projectID)
    }

    @Test func findsQuoteNameInvoiceNumberDrawingNumberAndDocumentArchiveNumber() {
        let project = Project(name: "Project", location: "")
        let quote = quote(projectID: project.id)
        let finance = ProjectFinancialRecord(projectId: project.id, amount: NumericInputSupport.money("123.45"), invoiceNumber: "INV-unique-708")
        let drawing = ProjectDrawing(projectId: project.id, name: "Electrical", drawingNumber: "DWG-unique-709", fileName: "missing.dwg", fileType: "dwg")
        let document = ProjectDocument(projectId: project.id, title: "Acceptance", fileName: "missing.pdf", archiveNumber: "DOC-unique-710")
        for (keyword, category, id) in [("copper", RealtimeSearchSuggestion.Category.quote, quote.id), ("INV-unique-708", .financial, finance.id), ("DWG-unique-709", .drawing, drawing.id), ("DOC-unique-710", .file, document.id)] {
            let result = RealtimeSearchSuggestionBuilder.suggestions(keyword: keyword, projects: [project], quotes: [quote], financialRecords: [finance], drawings: [drawing], documents: [document])
            #expect(result.map(\.entityId) == [id])
            #expect(result.first?.category == category)
            #expect(result.first?.subtitle.contains(project.name) == true)
        }
    }

    @Test func projectAndCategoryFiltersExcludeOtherProjectsAndGlobalCatalogs() {
        let first = Project(name: "Search first", location: ""), second = Project(name: "Search second", location: "")
        let one = quote(projectID: first.id), two = quote(projectID: second.id), unassigned = quote(projectID: nil)
        let finance = ProjectFinancialRecord(projectId: first.id, amount: NumericInputSupport.money("1"), counterparty: "Search vendor")
        let result = RealtimeSearchSuggestionBuilder.suggestions(keyword: "Search", categories: [.quote], projects: [first, second], quotes: [one, two, unassigned], financialRecords: [finance], projectID: first.id)
        #expect(result.map(\.entityId) == [one.id])
        let all = RealtimeSearchSuggestionBuilder.suggestions(keyword: "Search", categories: [.quote], quotes: [one, two, unassigned])
        #expect(Set(all.map(\.entityId)) == [one.id, two.id, unassigned.id])
    }

    @Test func projectScopeAlsoAppliesToExistingRecordsAndRelatedContacts() {
        let first = UUID(), second = UUID()
        let contact = ProjectContact(projectId: second, relatedProjectIds: [first], name: "Search related")
        let one = SiteTodo(title: "Search one", projectId: first), two = SiteTodo(title: "Search two", projectId: second)
        let note = QuickNote(title: "Search note", content: "", projectId: second)
        let result = RealtimeSearchSuggestionBuilder.suggestions(keyword: "Search", categories: [.contact, .todo, .note], contacts: [contact], todos: [one, two], notes: [note], projectID: first)
        #expect(Set(result.map(\.entityId)) == [contact.id, one.id])
    }

    @Test func equalTitlesHaveStableIdentityOrderAndSearchRespectsLimits() {
        let first = quote(projectID: nil, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = quote(projectID: nil, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        #expect(RealtimeSearchSuggestionBuilder.suggestions(keyword: "Search", quotes: [second, first], limit: 1).map(\.entityId) == [first.id])
        #expect(RealtimeSearchSuggestionBuilder.suggestions(keyword: "  ", quotes: [first]).isEmpty)
        #expect(RealtimeSearchSuggestionBuilder.suggestions(keyword: "Search", quotes: [first], limit: 0).isEmpty)
    }

    @Test func financialSearchPreservesStatusesAndMatchesLongNotesAndCounterparty() {
        let projectID = UUID()
        let record = ProjectFinancialRecord(projectId: projectID, amount: NumericInputSupport.money("1"), counterparty: "Unique supplier", status: .archived, note: String(repeating: "x", count: 2000) + " tail-token")
        for keyword in ["supplier", "tail-token"] {
            let result = RealtimeSearchSuggestionBuilder.suggestions(keyword: keyword, financialRecords: [record])
            #expect(result.map(\.entityId) == [record.id])
            #expect(result.first?.subtitle.contains(record.status.displayName) == true)
        }
    }

    @Test func drawingFocusResolvesExactHistoricalRecordAndRoutesToItsEditorOnce() {
        let drawing = ProjectDrawing(projectId: UUID(), name: "Historical", fileName: "missing.pdf", fileType: "pdf", isCurrentVersion: false)
        let routing = ProjectDetailOnAppearRouter.resolve(autoOpenFinancialAdd: false, didAutoOpenFinancialAdd: false, autoOpenDocumentScanSetup: false, didAutoOpenDocumentScanSetup: false, autoOpenDeliveryGuide: false, didAutoOpenDeliveryGuide: false, focus: .drawing(drawing.id), didOpenFocusedItem: false, financialRecords: [], documents: [], contacts: [], drawings: [drawing])
        guard let item = routing.focusedItem else { Issue.record("Missing drawing focus")
        return }
        #expect(item.mode == .assets)
        var selected: UUID?
        ProjectDetailFocusedItemApplier.apply(item, setFinancialRecord: { _ in Issue.record("Wrong editor") }, setDocument: { _ in Issue.record("Wrong editor") }, setContact: { _ in Issue.record("Wrong editor") }, setDrawing: { selected = $0.id })
        #expect(selected == drawing.id)
        #expect(ProjectDetailFocusRouter.resolve(focus: .drawing(UUID()), financialRecords: [], documents: [], contacts: [], drawings: [drawing]) == nil)
    }
}
