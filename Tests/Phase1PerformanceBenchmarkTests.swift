import Foundation
import XCTest
@testable import sitekeeper

/// Opt-in workload baseline. Run serially with the same optimized configuration,
/// simulator, fixture sizes and this exact file on both frozen source versions.
@MainActor
final class Phase1PerformanceBenchmarkTests: XCTestCase {
    func testDashboardAndSingleRecordWorkloads() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_RUN_PERFORMANCE_BASELINE"] == "1")
        for count in [1_000, 10_000, 100_000] {
            try autoreleasepool { try runWorkloads(count: count) }
        }
    }

    private func runWorkloads(count: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fixedCalendar = calendar
        let now = Date(timeIntervalSince1970: 1_793_145_600)
        let store = ProjectStore(now: { now }, calendar: { fixedCalendar })
        let finance = FinanceStore()
        let projects = (0..<100).map { index in
            Project(id: identity(index + 1), name: "Project \(index)", location: "Site", status: .active,
                    contractAmount: 100_000, paidAmount: 0)
        }
        let logs = (0..<count).map { index in
            DailyLog(id: identity(index + 1_000), date: BusinessDateValue(legacyText: "2026-10-28"),
                     weather: "", content: index == count / 2 ? "施工 rare-token" : "施工记录 \(index)",
                     workers: 1, projectId: projects[index % projects.count].id)
        }
        let records = (0..<(count / 4)).map { index in
            ProjectFinancialRecord(id: identity(index + 200_000), projectId: projects[index % projects.count].id,
                                   date: BusinessDateValue(legacyText: "2026-10-28"), direction: .income,
                                   category: .collection, amount: NumericInputSupport.money("1.25"), counterparty: "施工供应商 \(index)")
        }
        store.withBatchUpdates {
            store.setProjects(projects)
            store.setDailyLogs(logs)
            store.setProjectFinancialRecords(records)
        }

        for keyword in ["施工", "rare-token"] {
            let operation = {
                RealtimeSearchSuggestionBuilder.suggestions(keyword: keyword, projects: projects,
                    logs: store.dailyLogs, financialRecords: records, limit: 10)
            }
            let expected = keyword == "rare-token" ? 1 : 10
            XCTAssertEqual(operation().count, expected)
            try sample(name: keyword == "施工" ? "search_broad" : "search_rare", count: count) {
                XCTAssertEqual(operation().count, expected)
            }
        }

        // The frozen runner injects the original provider expressions into a test-only
        // adapter. Ordinary regression builds do not need that historical source.
#if SITEKEEPER_PHASE1_REFERENCE
        let legacy = Phase1LegacyDashboard(projectStore: store, financeStore: finance)
        let expectedSummary = legacy.read()
#if SITEKEEPER_PHASE1_BASELINE
        try sample(name: "summary_cold", count: count) { XCTAssertEqual(legacy.read(), expectedSummary) }
        try sample(name: "summary_warm", count: count) { XCTAssertEqual(legacy.read(), expectedSummary) }
#else
        let cache = DashboardSummaryCache()
        func read(_ target: DashboardSummaryCache) -> Phase1SummaryDigest {
            let value = target.value(revision: DashboardSummaryRevision(projectStore: store, financeStore: finance)) {
                DashboardSummaryInput(projectStore: store, financeStore: finance)
            }
            return Phase1SummaryDigest(summary: value)
        }
        XCTAssertEqual(read(cache), expectedSummary)
        try sample(name: "summary_cold", count: count) { XCTAssertEqual(read(DashboardSummaryCache()), expectedSummary) }
        try sample(name: "summary_warm", count: count) { XCTAssertEqual(read(cache), expectedSummary) }
        XCTAssertEqual(cache.buildCount, 1)
#endif
#endif

        var revision = 0
        try sample(name: "single_log_date_edit", count: count) {
            var changed = store.dailyLogs
            revision += 1
            changed[count / 2].date = BusinessDateValue(legacyText: revision.isMultiple(of: 2) ? "2026-10-28" : "2026-10-27")
            store.setDailyLogs(changed)
            XCTAssertEqual(store.dailyLogs.count, count)
        }
#if !SITEKEEPER_PHASE1_BASELINE
        XCTAssertLessThanOrEqual(store.lastActivityIndexProcessedRecordCount, count / 100 + count / 400 + 2)
        print("PHASE1_WORK records=\(count) processed=\(store.lastActivityIndexProcessedRecordCount) projects=\(store.lastActivityIndexRebuiltProjectCount)")
#endif
    }

    private func sample(name: String, count: Int, operation: () -> Void) throws {
        operation()
        var values: [Double] = []
        for _ in 0..<7 {
            let start = DispatchTime.now().uptimeNanoseconds
            autoreleasepool(invoking: operation)
            values.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        let sorted = values.sorted()
#if SITEKEEPER_PHASE1_BASELINE
        let phase = "before"
#else
        let phase = "after"
#endif
        let result: [String: Any] = ["phase": phase, "name": name, "logs": count, "financialRecords": count / 4,
                                    "projects": 100, "samples_ms": values, "median_ms": sorted[3], "max_ms": sorted[6]]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("PHASE1_BENCH " + String(decoding: data, as: UTF8.self))
    }

    private func identity(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
