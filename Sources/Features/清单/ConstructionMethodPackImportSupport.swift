import Foundation

struct RemoteConstructionMethodPackPayload: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let count: Int
    let packs: [RemoteConstructionMethodPack]
}

struct RemoteConstructionMethodPackLink: Codable, Hashable {
    let title: String
    let href: String
}

struct RemoteConstructionMethodPack: Identifiable, Codable {
    let id: String
    let sourceSlug: String
    let sourceURL: String
    let sourceVersion: String
    let title: String
    let trade: String
    let versionName: String
    let publishStatus: String
    let tutorialBody: String
    let procedureSteps: [String]
    let qualityChecklist: [String]
    let safetyChecklist: [String]
    let relatedStandards: [String]
    let relatedTemplates: [RemoteConstructionMethodPackLink]
    let relatedArticles: [RemoteConstructionMethodPackLink]
    let tags: [String]
    let updatedAt: String

    func constructionMethod(existing: ConstructionMethod?) -> ConstructionMethod {
        var method = existing ?? ConstructionMethod()
        method.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        method.trade = trade.trimmingCharacters(in: .whitespacesAndNewlines)
        method.versionName = versionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "知识网站 V1" : versionName
        method.publishStatus = ConstructionMethod.PublishStatus(rawValue: publishStatus) ?? .published
        method.tutorialBody = absolutizedMarkdownLinks(tutorialBody).trimmingCharacters(in: .whitespacesAndNewlines)
        method.tutorialTextSize = .normal
        method.procedureSteps = normalized(procedureSteps)
        method.qualityChecklist = normalized(qualityChecklist)
        method.safetyChecklist = normalized(safetyChecklist)
        method.sourceID = id
        method.sourceURL = absoluteURLString(sourceURL)
        method.sourceVersion = sourceVersion
        method.sourceUpdatedAt = updatedAt
        method.relatedStandards = normalized(relatedStandards)
        method.relatedTemplates = normalizedLinks(relatedTemplates)
        method.relatedArticles = normalizedLinks(relatedArticles)
        method.updatedAt = Formatters.now()
        return method
    }

    private func normalized(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func absoluteURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return trimmed }
        return "https://gongchengzhishi.chengjinfang.com\(trimmed)"
    }

    private func absolutizedMarkdownLinks(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\]\((/[^)]+)\)"#,
            with: "](https://gongchengzhishi.chengjinfang.com$1)",
            options: .regularExpression
        )
    }

    private func normalizedLinks(_ links: [RemoteConstructionMethodPackLink]) -> [ConstructionMethodKnowledgeLink] {
        var seen = Set<String>()
        var result: [ConstructionMethodKnowledgeLink] = []
        for link in links {
            let title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let href = absoluteURLString(link.href)
            guard !href.isEmpty else { continue }
            let displayTitle = title.isEmpty ? href : title
            let dedupeKey = "\(displayTitle)|\(href)"
            guard seen.insert(dedupeKey).inserted else { continue }
            result.append(ConstructionMethodKnowledgeLink(title: displayTitle, href: href))
        }
        return result
    }
}

struct ConstructionMethodPackImportStatus: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case success
        case failed
    }

    let outcome: Outcome
    let endpoint: String
    let generatedAt: String?
    let message: String
    let importedCount: Int
    let newCount: Int
    let updateCount: Int
    let timestamp: TimeInterval

    var happenedAt: Date? {
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }
}

enum ConstructionMethodPackImportStatusStore {
    private static let key = UserPreferenceKeys.constructionMethodPackImportLastStatus

    static func load() -> ConstructionMethodPackImportStatus? {
        guard let data = UserPreferencesStore.shared.data(key) else { return nil }
        return try? JSONDecoder().decode(ConstructionMethodPackImportStatus.self, from: data)
    }

    static func save(_ status: ConstructionMethodPackImportStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        UserPreferencesStore.shared.set(data, for: key)
    }
}

struct ConstructionMethodPackOfflineCacheSnapshot: Codable {
    let endpoint: String
    let payload: RemoteConstructionMethodPackPayload
    let cachedAt: TimeInterval
    let rawBytes: Int

    var cachedDate: Date? {
        guard cachedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: cachedAt)
    }
}

enum ConstructionMethodPackOfflineCacheStore {
    private static let key = UserPreferenceKeys.constructionMethodPackOfflineCache

    static func load() -> ConstructionMethodPackOfflineCacheSnapshot? {
        guard let data = UserPreferencesStore.shared.data(key) else { return nil }
        return try? JSONDecoder().decode(ConstructionMethodPackOfflineCacheSnapshot.self, from: data)
    }

    @discardableResult
    static func save(
        endpoint: URL,
        payload: RemoteConstructionMethodPackPayload
    ) -> ConstructionMethodPackOfflineCacheSnapshot? {
        let rawBytes = (try? JSONEncoder().encode(payload).count) ?? 0
        let snapshot = ConstructionMethodPackOfflineCacheSnapshot(
            endpoint: endpoint.absoluteString,
            payload: payload,
            cachedAt: Date().timeIntervalSince1970,
            rawBytes: rawBytes
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        UserPreferencesStore.shared.set(data, for: key)
        return snapshot
    }

    static func clear() {
        UserPreferencesStore.shared.removeObject(for: key)
    }
}

struct ConstructionMethodPackFetchResult: Sendable {
    let endpoint: URL
    let payload: RemoteConstructionMethodPackPayload
}

enum ConstructionMethodPackImportConfiguration {
    private static let productionEndpointRaw = "https://gongchengzhishi.chengjinfang.com/sitekeeper/method-packs.json"
    private static let localDebugEndpointRaw = "http://127.0.0.1:4321/sitekeeper/method-packs.json"

    static var productionEndpoint: URL {
        requiredURL(productionEndpointRaw)
    }

    static var localDebugEndpoint: URL {
        requiredURL(localDebugEndpointRaw)
    }

    static var configuredPrimaryEndpoint: URL {
        guard AppFeatureFlags.allowsConstructionMethodPackEndpointOverride else {
            return productionEndpoint
        }
        guard let override = validUserEndpoint(
            UserPreferences.string(UserPreferenceKeys.constructionMethodPackImportEndpoint, default: "")
        ) else {
            return productionEndpoint
        }
        return override
    }

    static var configuredEndpointSource: String {
        let configured = configuredPrimaryEndpoint.absoluteString
        if configuredPrimaryEndpoint == productionEndpoint {
            return String(localized: "默认端点")
        }
        return String(format: String(localized: "自定义端点：%@"), configured)
    }

    private static func validUserEndpoint(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func requiredURL(_ raw: String) -> URL {
        guard let url = URL(string: raw) else {
            preconditionFailure("Invalid URL configuration: \(raw)")
        }
        return url
    }
}

enum ConstructionMethodPackImportService {
    static var configuredPrimaryEndpoint: URL {
        ConstructionMethodPackImportConfiguration.configuredPrimaryEndpoint
    }

    static func fetch() async throws -> ConstructionMethodPackFetchResult {
        var lastError: Error?
        for endpoint in candidateEndpoints {
            do {
                let payload = try await fetch(from: endpoint)
                return ConstructionMethodPackFetchResult(endpoint: endpoint, payload: payload)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }

    private static var candidateEndpoints: [URL] {
        var endpoints: [URL] = [configuredPrimaryEndpoint]
#if DEBUG
        if !endpoints.contains(ConstructionMethodPackImportConfiguration.localDebugEndpoint) {
            endpoints.append(ConstructionMethodPackImportConfiguration.localDebugEndpoint)
        }
#endif
        return endpoints
    }

    static func fetch(from endpoint: URL) async throws -> RemoteConstructionMethodPackPayload {
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(RemoteConstructionMethodPackPayload.self, from: data)
    }
}
