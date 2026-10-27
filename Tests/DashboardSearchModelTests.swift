import Foundation
import Testing
@testable import sitekeeper

struct DashboardSearchModelTests {
    @Test func boundedRankingMatchesFullSortForEveryTieBreakAndLimit() {
        let categories = RealtimeSearchSuggestion.Category.allCases
        let titles = ["工地2", "工地10", "alpha", "Alpha", "éclair", "同名"]
        let input = (0..<600).reversed().map { index in
            RealtimeSearchSuggestion(id: String(format: "%04d", index), category: categories[index % categories.count],
                                     entityId: UUID(), title: titles[index % titles.count], subtitle: "", score: index % 4)
        }
        // This is the pre-optimization ordering contract, independent of top K.
        let fullySorted = input.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
            let order = lhs.title.localizedStandardCompare(rhs.title)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
        for limit in [-1, 0, 1, 5, 10, 64, 1000] {
            #expect(RealtimeSearchSuggestionBuilder.topSuggestions(input, limit: limit) == Array(fullySorted.prefix(max(0, limit))))
        }
    }

    @Test @MainActor func slowerEarlierQueryCannotOverwriteNewQueryOrFilter() async {
        let gate = DashboardSearchGate()
        let older = suggestion("old"), newer = suggestion("new")
        let model = DashboardSearchModel { _, request in
            if request.keyword == "old" { await gate.suspend() }
            return request.keyword == "old" ? [older] : [newer]
        }
        let oldRequest = DashboardSearchRequest(keyword: "old")
        let newRequest = DashboardSearchRequest(keyword: "new", category: .note)
        let oldTask = Task { await model.refresh(snapshot: .init(), request: oldRequest, debounce: .zero) }
        await gate.waitUntilStarted()
        await model.refresh(snapshot: .init(), request: newRequest, debounce: .zero)
        #expect(model.suggestions(for: oldRequest).isEmpty)
        await gate.release()
        await oldTask.value
        #expect(model.suggestions(for: newRequest) == [newer])
    }

    @Test @MainActor func cancelledWorkerCannotPublishAndReceivesCancellation() async {
        let gate = DashboardSearchGate()
        let record = suggestion("record")
        let model = DashboardSearchModel { _, _ in
            await gate.suspend()
            await gate.recordCancellation(Task.isCancelled)
            return [record]
        }
        let request = DashboardSearchRequest(keyword: "record")
        let task = Task { await model.refresh(snapshot: .init(), request: request, debounce: .zero) }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.release()
        await task.value
        #expect(model.suggestions(for: request).isEmpty)
        #expect(await gate.wasCancelled)
    }

    @Test @MainActor func cancelledDebounceNeverStartsSearch() async {
        let calls = DashboardSearchCalls()
        let model = DashboardSearchModel { _, _ in
            await calls.record()
            return []
        }
        let task = Task { await model.refresh(snapshot: .init(), request: .init(keyword: "record"), debounce: .seconds(60)) }
        task.cancel()
        await task.value
        #expect(await calls.count == 0)
    }

    @Test @MainActor func emptyQueryClearsRowsAndInvalidatesOlderWork() async {
        let gate = DashboardSearchGate()
        let record = suggestion("record")
        let model = DashboardSearchModel { _, _ in
            await gate.suspend()
            return [record]
        }
        let request = DashboardSearchRequest(keyword: "record")
        let task = Task { await model.refresh(snapshot: .init(), request: request, debounce: .zero) }
        await gate.waitUntilStarted()
        let empty = DashboardSearchRequest(keyword: " \n ")
        await model.refresh(snapshot: .init(), request: empty, debounce: .zero)
        await gate.release()
        await task.value
        #expect(model.suggestions(for: empty).isEmpty)
        #expect(model.suggestions(for: request).isEmpty)
    }

    @Test @MainActor func requestChangesImmediatelyHidePreviousRowsBeforeRefreshStarts() async {
        let record = suggestion("record")
        let model = DashboardSearchModel { _, _ in [record] }
        let request = DashboardSearchRequest(keyword: "record", collectionVersions: [1])
        await model.refresh(snapshot: .init(), request: request, debounce: .zero)
        #expect(model.suggestions(for: request) == [record])
        var project = request; project.projectID = UUID()
        var category = request; category.category = .financial
        var data = request; data.collectionVersions = [2]
        var language = request; language.language = "en"
        var keyword = request; keyword.keyword = "other"
        for changed in [project, category, data, language, keyword] {
            #expect(model.suggestions(for: changed).isEmpty)
        }
    }

    @Test @MainActor func sameCountEditAndDeletionRefreshFromNewSnapshot() async {
        let model = DashboardSearchModel()
        var project = Project(name: "旧项目", location: "")
        let note = QuickNote(title: "现场记录", content: "", projectId: project.id)
        let request = DashboardSearchRequest(keyword: "新项目", category: .note, collectionVersions: [1])
        await model.refresh(snapshot: .init(projects: [project], notes: [note]), request: request, debounce: .zero)
        #expect(model.suggestions(for: request).isEmpty)
        project.name = "新项目"
        var edited = request; edited.collectionVersions = [2]
        await model.refresh(snapshot: .init(projects: [project], notes: [note]), request: edited, debounce: .zero)
        #expect(model.suggestions(for: edited).map(\.entityId) == [note.id])
        var deleted = edited; deleted.collectionVersions = [3]
        await model.refresh(snapshot: .init(projects: [project]), request: deleted, debounce: .zero)
        #expect(model.suggestions(for: deleted).isEmpty)
    }

    @Test @MainActor func independentSearchOwnersDoNotInvalidateEachOther() async {
        let gate = DashboardSearchGate()
        let firstRecord = suggestion("first"), secondRecord = suggestion("second")
        let first = DashboardSearchModel { _, _ in await gate.suspend(); return [firstRecord] }
        let second = DashboardSearchModel { _, _ in [secondRecord] }
        let one = DashboardSearchRequest(keyword: "first"), two = DashboardSearchRequest(keyword: "second")
        let task = Task { await first.refresh(snapshot: .init(), request: one, debounce: .zero) }
        await gate.waitUntilStarted()
        await second.refresh(snapshot: .init(), request: two, debounce: .zero)
        await gate.release()
        await task.value
        #expect(first.suggestions(for: one) == [firstRecord])
        #expect(second.suggestions(for: two) == [secondRecord])
    }

    private func suggestion(_ title: String) -> RealtimeSearchSuggestion {
        .init(id: title, category: .note, entityId: UUID(), title: title, subtitle: "", score: 300)
    }
}

private actor DashboardSearchCalls {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor DashboardSearchGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var wasCancelled = false

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func recordCancellation(_ value: Bool) { wasCancelled = value }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
