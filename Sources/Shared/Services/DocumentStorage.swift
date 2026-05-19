import Foundation

enum DocumentStorageIssueLogger {
    static func record(
        _ event: String,
        fileName: String? = nil,
        error: Error? = nil,
        details: [String: String] = [:]
    ) {
        var payload = details
        if let fileName, !fileName.isEmpty {
            payload["file"] = fileName
        }
        StorageIssueLog.recordEvent(
            event,
            category: .fileStorage,
            details: payload,
            error: error
        )
    }
}
