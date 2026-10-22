import Foundation
import XCTest
@testable import sitekeeper

final class ProjectFilePreparationPerformanceTests: XCTestCase {
    func testPrepareOneThousandRealFilesIncludingMetadataAndHealthInspection() throws {
        let files = try ProjectFileBrowserTestFiles(documentCount: 1_000)
        defer { files.remove() }
        let snapshot = files.snapshot
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            // Exercise the production preparation function and real filesystem, not just index rows.
            let result = DispatchQueue.global(qos: .userInitiated).sync {
                Result { try ProjectFilePreparedData.build(snapshot) }
            }
            switch result {
            case .success(let data):
                XCTAssertEqual(data.items(for: files.project.id, category: .documents).count, 1_000)
                XCTAssertEqual(data.items(for: files.project.id, health: .missing).count, 1)
                XCTAssertEqual(data.items(for: files.project.id, category: .documents).filter(\.exists).count, 999)
                XCTAssertEqual(data.inspections.first?.missingFiles.count, 1)
            case .failure(let error):
                XCTFail("Real file preparation failed: \(error)")
            }
        }
    }
}
