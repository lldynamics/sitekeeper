import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct ProjectActivityIncrementalIndexTests {
    @Test func oneProjectEditSkipsOtherProjectsAndNonActivityEditsKeepFullRecordsFresh() {
        let store = makeStore()
        let ids = (0 ..< 100).map { _ in UUID() }
        let logs = ids.flatMap { id in (0 ..< 10).map { _ in log(id) } }
        store.withBatchUpdates {
            store.setDailyLogs(logs)
            store.setProjectFinancialRecords(ids.map { ProjectFinancialRecord(projectId: $0, amount: 12) })
        }
        let count = store.activityIndexBuildCount
        var changed = logs
        changed[0].date = date("2026-10-29")
        store.setDailyLogs(changed)
        #expect(store.activityIndexBuildCount == count + 1)
        #expect(store.lastActivityIndexRebuiltProjectCount == 1)
        #expect(store.lastActivityIndexProcessedRecordCount == 11)
        assertMatchesFullBuild(store)

        let version = store.dashboardCollectionVersions["dailyLogs", default: 0]
        changed[0].content = "Content still reaches project queries and persistence"
        store.setDailyLogs(changed)
        #expect(store.dailyLogs(for: ids[0])[0].content == changed[0].content)
        #expect(store.dashboardCollectionVersions["dailyLogs"] == version + 1)
        #expect(store.activityIndexBuildCount == count + 2)
        #expect(store.lastActivityIndexProcessedRecordCount == 0)
        #expect(store.lastActivityIndexRebuiltProjectCount == 0)
        assertMatchesFullBuild(store)
    }

    @Test func batchBuildsOnceAndCountsOnlyFinalInputsForAffectedProjects() {
        let store = makeStore()
        let a = UUID(), b = UUID()
        let count = store.activityIndexBuildCount
        store.withBatchUpdates {
            store.setDailyLogs([log(a)])
            store.withBatchUpdates { store.setDailyLogs([log(a), log(a), log(b)]) }
            store.setSiteTodos([SiteTodo(title: "Open", dueDate: date("2026-10-27"), projectId: a)])
            #expect(store.activityIndexBuildCount == count)
        }
        #expect(store.activityIndexBuildCount == count + 1)
        #expect(store.lastActivityIndexProcessedRecordCount == 4)
        #expect(store.lastActivityIndexRebuiltProjectCount == 2)
        assertMatchesFullBuild(store)
        store.setDailyLogs(store.dailyLogs)
        #expect(store.activityIndexBuildCount == count + 2)
        #expect(store.lastActivityIndexProcessedRecordCount == 0)
    }

    @Test func migrationUnlinkDeletionAndLatestActivityFallbackMatchFullBuilder() {
        let store = makeStore()
        let a = UUID(), b = UUID()
        var latest = log(a, day: "2026-10-29")
        let earlier = log(a, day: "2026-10-27")
        store.setDailyLogs([earlier, latest])
        latest.projectId = b
        store.setDailyLogs([earlier, latest])
        #expect(store.lastActivityIndexRebuiltProjectCount == 2)
        #expect(store.projectActivitySummary(for: a).latestActivityDate == date("2026-10-27").date(in: store.dayContext.calendar.timeZone))
        #expect(store.projectActivitySummary(for: b).dailyLogCount == 1)
        assertMatchesFullBuild(store)
        latest.projectId = nil
        store.setDailyLogs([earlier, latest])
        #expect(store.projectActivityIndexByID[b] == nil)
        #expect(store.dailyLogs.count == 2)
        store.setDailyLogs([])
        #expect(store.projectActivityIndexByID.isEmpty)
        #expect(store.todayLogProjectIDs.isEmpty)
        assertMatchesFullBuild(store)
    }

    @Test func reverseReceiptLinkChangesReevaluateFinanceAndRespectProjectBoundary() {
        let store = makeStore()
        let a = UUID(), b = UUID()
        let record = ProjectFinancialRecord(projectId: a, direction: .expense, category: .material, amount: 10)
        var document = ProjectDocument(projectId: a, title: "Receipt", fileName: "receipt.pdf", linkedFinancialRecordId: record.id)
        store.withBatchUpdates {
            store.setProjectFinancialRecords([record])
            store.setProjectDocuments([document])
        }
        #expect(store.projectActivitySummary(for: a).unattachedReceiptCount == 0)
        document.projectId = b
        store.setProjectDocuments([document])
        #expect(store.projectActivitySummary(for: a).unattachedReceiptCount == 1)
        #expect(store.lastActivityIndexRebuiltProjectCount == 2)
        assertMatchesFullBuild(store)
        document.projectId = a
        document.linkedFinancialRecordId = nil
        store.setProjectDocuments([document])
        #expect(store.projectActivitySummary(for: a).unattachedReceiptCount == 1)
        var linked = record
        linked.linkedDocumentIds = [document.id]
        store.setProjectFinancialRecords([linked])
        #expect(store.projectActivitySummary(for: a).unattachedReceiptCount == 0)
        assertMatchesFullBuild(store)
        store.setProjectDocuments([])
        store.setProjectFinancialRecords([])
        #expect(store.projectActivityIndexByID.isEmpty)
    }

    @Test func midnightAndTimezoneChangesRefreshUntouchedProjectsEvenInBatch() {
        let clock = ActivityIndexClock()
        let store = ProjectStore(now: { clock.now }, calendar: { clock.calendar })
        let a = UUID(), b = UUID()
        store.withBatchUpdates {
            store.setDailyLogs([log(a)])
            store.setSiteTodos([SiteTodo(title: "Due", dueDate: date("2026-10-28"), projectId: b)])
        }
        clock.now = ISO8601DateFormatter().date(from: "2026-10-29T01:00:00Z")!
        let before = store.activityIndexBuildCount
        store.withBatchUpdates {
            #expect(store.refreshDateSensitiveStateIfNeeded())
            // Identical activity data must still trigger a full day-context refresh.
            store.setDailyLogs(store.dailyLogs)
        }
        #expect(store.activityIndexBuildCount == before + 1)
        #expect(store.lastActivityIndexProcessedRecordCount == 2)
        #expect(store.projectActivitySummary(for: b).overdueTodoCount == 1)
        #expect(store.todayLogProjectIDs.isEmpty)
        assertMatchesFullBuild(store)
        clock.calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(store.refreshDateSensitiveStateIfNeeded())
        #expect(store.projectActivitySummary(for: b).overdueTodoCount == 0)
        #expect(store.todayLogProjectIDs == [a])
        assertMatchesFullBuild(store)
    }

    @Test func seededMixedDomainMutationsMatchFullBuilderAfterEveryStep() {
        let store = makeStore()
        var random = ActivityIndexRandom()
        let ids = (0 ..< 7).map { _ in UUID() }
        for step in 0 ..< 192 {
            let id = ids[random.next(ids.count)]
            let text = ["2026-10-27", "2026-10-28", "2026-10-29", "", "legacy invalid"][random.next(5)]
            switch step % 8 {
            case 0:
                store.setDailyLogs(mutated(store.dailyLogs, appending: log(id, day: text), random: &random) {
                    $0.projectId = step % 3 == 0 ? nil : id; $0.date = date(text)
                })
            case 1:
                let task = ProgressTask(projectId: id, title: "Task", startDate: date(text), dueDate: date(text), completion: 0, note: "")
                store.setProgressTasks(mutated(store.progressTasks, appending: task, random: &random) {
                    $0.projectId = id; $0.dueDate = date(text); $0.completion = step % 3 == 0 ? 1 : 0.5
                })
            case 2:
                store.setSiteTodos(mutated(store.siteTodos, appending: SiteTodo(title: "Todo", dueDate: date(text), projectId: id), random: &random) {
                    $0.projectId = step % 3 == 0 ? nil : id; $0.dueDate = date(text); $0.isDone.toggle()
                })
            case 3:
                let linkedID = store.projectFinancialRecords.first?.id
                let doc = ProjectDocument(projectId: id, title: "Doc", fileName: "doc.pdf", linkedFinancialRecordId: linkedID, createdAt: date(text))
                store.setProjectDocuments(mutated(store.projectDocuments, appending: doc, random: &random) {
                    $0.projectId = id; $0.createdAt = date(text); $0.linkedFinancialRecordId = step % 3 == 0 ? nil : linkedID
                })
            case 4:
                let drawing = ProjectDrawing(projectId: id, name: "Drawing", fileName: "drawing.pdf", fileType: "pdf", importedAt: date(text))
                store.setProjectDrawings(mutated(store.projectDrawings, appending: drawing, random: &random) {
                    $0.projectId = id; $0.importedAt = date(text)
                })
            case 5:
                let record = ProjectFinancialRecord(projectId: id, date: date(text), amount: 5)
                store.setProjectFinancialRecords(mutated(store.projectFinancialRecords, appending: record, random: &random) {
                    $0.projectId = id; $0.date = date(text); $0.amount = MoneyValue(Decimal(step))
                    $0.direction = step % 3 == 0 ? .income : .expense
                    $0.category = step % 3 == 0 ? .collection : .material
                    $0.status = step % 3 == 0 ? .archived : .active
                    $0.dueDate = date(text); $0.linkedDocumentIds = step % 3 == 0 ? [UUID()] : []
                })
            case 6:
                let movement = ProjectWarehouseMovement(projectId: id, date: date(text))
                store.setProjectWarehouseMovements(mutated(store.projectWarehouseMovements, appending: movement, random: &random) {
                    $0.projectId = id; $0.date = date(text)
                })
            default:
                let note = QuickNote(projectId: id, createdAt: date(text))
                store.setQuickNotes(mutated(store.quickNotes, appending: note, random: &random) {
                    $0.projectId = step % 3 == 0 ? nil : id; $0.createdAt = date(text)
                })
            }
            assertMatchesFullBuild(store)
        }
    }

    private func mutated<Value>(_ values: [Value], appending newValue: Value, random: inout ActivityIndexRandom, edit: (inout Value) -> Void) -> [Value] {
        var result = values
        switch result.isEmpty ? 0 : random.next(4) {
        case 0: result.append(newValue)
        case 1: result.remove(at: random.next(result.count))
        case 2: edit(&result[random.next(result.count)])
        default: result.reverse()
        }
        return result
    }

    private func assertMatchesFullBuild(_ store: ProjectStore, sourceLocation: SourceLocation = #_sourceLocation) {
        var full = ProjectActivityIndexBuilder(context: store.dayContext)
        full.add(store.dailyLogs)
        full.add(store.progressTasks)
        full.add(store.siteTodos)
        full.add(store.projectDocuments)
        full.add(store.projectDrawings)
        full.add(store.projectFinancialRecords)
        full.add(store.projectWarehouseMovements)
        full.add(store.quickNotes)
        #expect(store.projectActivityIndexByID == full.summaries, sourceLocation: sourceLocation)
        #expect(store.todayLogProjectIDs == full.todayProjectIDs, sourceLocation: sourceLocation)
        #expect(store.dailyLogsByProjectID.values.flatMap { $0 }.count == store.dailyLogs.filter { $0.projectId != nil }.count, sourceLocation: sourceLocation)
    }

    private func makeStore() -> ProjectStore {
        let clock = ActivityIndexClock()
        return ProjectStore(now: { clock.now }, calendar: { clock.calendar })
    }

    private func date(_ text: String) -> BusinessDateValue { BusinessDateValue(legacyText: text) }
    private func log(_ id: UUID, day: String = "2026-10-28") -> DailyLog {
        DailyLog(date: date(day), weather: "", content: "", workers: 1, projectId: id)
    }
}

@MainActor
private final class ActivityIndexClock {
    var now = ISO8601DateFormatter().date(from: "2026-10-28T01:00:00Z")!
    var calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }()
}

private struct ActivityIndexRandom {
    private var state: UInt64 = 0x5017_2026_1028
    mutating func next(_ upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Int((state >> 32) % UInt64(upperBound))
    }
}
