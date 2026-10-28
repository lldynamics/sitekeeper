import Foundation

/// Resource changes restart only the corresponding visible thumbnail requests.
enum ThumbnailCacheInvalidation: Sendable {
    case resource(URL)
    case directory(URL)
    case all

    static let notificationName = Notification.Name("sitekeeper.thumbnailCacheInvalidated")

    func affects(_ resourceURL: URL) -> Bool {
        let path = resourceURL.standardizedFileURL.path
        switch self {
        case let .resource(url):
            return path == url.standardizedFileURL.path
        case let .directory(url):
            let directory = url.standardizedFileURL.path
            return path.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/")
        case .all:
            return true
        }
    }
}
