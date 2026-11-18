import Foundation
import UIKit
@testable import sitekeeper

@MainActor
enum TestFixtures {
    static func makeJPEGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw FileStorageError.imageEncodingFailed
        }
        return data
    }

    static func projectSnapshot(projectName: String) -> BackupSnapshot {
        BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: projectName, location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
    }
}
