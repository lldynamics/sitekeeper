import Foundation
import XCTest
@testable import sitekeeper

/// Run this class alone for comparable clock/peak-memory measurements on a fixed simulator.
final class WorkflowPerformanceTests: XCTestCase {
    func testSearchTenThousandNotesAcrossOneThousandProjects() {
        let projects = (0..<1_000).map { Project(name: "项目-\($0)", location: "工区", status: .active) }
        let notes = (0..<10_000).map { index in
            QuickNote(title: "现场记录-\(index)", content: index == 7_777 ? "防水验收问题" : "常规施工记录",
                      projectId: projects[index % projects.count].id, createdAt: BusinessDateValue(legacyText: "2026-09-09 12:00:00"), updatedAt: BusinessDateValue(legacyText: "2026-09-09 12:00:00"))
        }
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            XCTAssertEqual(QuickNoteSearch.filter(notes, projects: projects, keyword: " 防水验收 ").count, 1)
            XCTAssertEqual(QuickNoteSearch.filter(notes, projects: projects, keyword: "项目-999").count, 10)
            XCTAssertTrue(QuickNoteSearch.filter(notes, projects: projects, keyword: "没有此词").isEmpty)
        }
    }

    func testEncodeTenThousandBusinessRecords() throws {
        let notes = (0..<10_000).map { index in
            QuickNote(title: "记录-\(index)", content: String(repeating: "现场施工检查内容。", count: 20),
                      createdAt: BusinessDateValue(legacyText: "2026-09-09 12:00:00"), updatedAt: BusinessDateValue(legacyText: "2026-09-09 12:00:00"))
        }
        var snapshot = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [], dailyLogs: [], historyRecords: [], templates: [])
        snapshot.quickNotes = notes
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            do {
                let data = try encoder.encode(snapshot)
                XCTAssertGreaterThan(data.count, 1_000_000)
            } catch {
                XCTFail("Snapshot encoding failed: \(error)")
            }
        }
    }
}
