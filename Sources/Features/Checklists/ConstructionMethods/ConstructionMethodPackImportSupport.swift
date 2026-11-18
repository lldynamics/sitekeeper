import Foundation

enum ConstructionMethodPackLimits {
    static let maximumResponseBytes = 8 * 1024 * 1024
    static let maximumCacheBytes = maximumResponseBytes + 64 * 1024
    static let maximumItems = 1_000
    static let maximumStringBytes = 256 * 1024

    static func validate(_ payload: RemoteConstructionMethodPackPayload) throws {
        func check(_ text: String) throws {
            guard text.utf8.count <= maximumStringBytes else { throw ConstructionMethodPackLimitError.exceeded }
        }
        try check(payload.generatedAt)
        guard payload.packs.count <= maximumItems else { throw ConstructionMethodPackLimitError.exceeded }
        for pack in payload.packs {
            for value in [pack.id, pack.sourceSlug, pack.sourceURL, pack.sourceVersion, pack.title,
                          pack.trade, pack.versionName, pack.publishStatus, pack.tutorialBody, pack.updatedAt] {
                try check(value)
            }
            for values in [pack.procedureSteps, pack.qualityChecklist, pack.safetyChecklist, pack.relatedStandards, pack.tags] {
                guard values.count <= maximumItems else { throw ConstructionMethodPackLimitError.exceeded }
                for value in values { try check(value) }
            }
            for links in [pack.relatedTemplates, pack.relatedArticles] {
                guard links.count <= maximumItems else { throw ConstructionMethodPackLimitError.exceeded }
                for link in links {
                    try check(link.title)
                    try check(link.href)
                }
            }
        }
    }
}

enum ConstructionMethodPackLimitError: LocalizedError {
    case exceeded

    var errorDescription: String? {
        AppLocalization.string("工艺包内容超过支持的大小或数量限制。")
    }
}

@propertyWrapper
struct ConstructionMethodPackBoundedArray<Element: Codable & Sendable>: Codable, Sendable {
    var wrappedValue: [Element]

    init(wrappedValue: [Element]) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        if let count = container.count, count > ConstructionMethodPackLimits.maximumItems {
            throw ConstructionMethodPackLimitError.exceeded
        }
        var values: [Element] = []
        while !container.isAtEnd {
            guard values.count < ConstructionMethodPackLimits.maximumItems else {
                throw ConstructionMethodPackLimitError.exceeded
            }
            values.append(try container.decode(Element.self))
        }
        wrappedValue = values
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in wrappedValue { try container.encode(value) }
    }
}

struct RemoteConstructionMethodPackPayload: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: String
    let count: Int
    @ConstructionMethodPackBoundedArray var packs: [RemoteConstructionMethodPack]
}

struct RemoteConstructionMethodPackLink: Codable, Hashable, Sendable {
    let title: String
    let href: String
}

struct RemoteConstructionMethodPack: Identifiable, Codable, Sendable {
    private static let knowledgeBaseOrigin = "https://gongdizhishi.com"

    let id: String
    let sourceSlug: String
    let sourceURL: String
    let sourceVersion: String
    let title: String
    let trade: String
    let versionName: String
    let publishStatus: String
    let tutorialBody: String
    @ConstructionMethodPackBoundedArray var procedureSteps: [String]
    @ConstructionMethodPackBoundedArray var qualityChecklist: [String]
    @ConstructionMethodPackBoundedArray var safetyChecklist: [String]
    @ConstructionMethodPackBoundedArray var relatedStandards: [String]
    @ConstructionMethodPackBoundedArray var relatedTemplates: [RemoteConstructionMethodPackLink]
    @ConstructionMethodPackBoundedArray var relatedArticles: [RemoteConstructionMethodPackLink]
    @ConstructionMethodPackBoundedArray var tags: [String]
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
        method.sourceUpdatedAt = BusinessDateValue(legacyText: updatedAt)
        method.relatedStandards = normalized(relatedStandards)
        method.relatedTemplates = normalizedLinks(relatedTemplates)
        method.relatedArticles = normalizedLinks(relatedArticles)
        method.updatedAt = .now()
        return method
    }

    private func normalized(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func absoluteURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return trimmed }
        return "\(Self.knowledgeBaseOrigin)\(trimmed)"
    }

    private func absolutizedMarkdownLinks(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\]\((/[^)]+)\)"#,
            with: "](\(Self.knowledgeBaseOrigin)$1)",
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

    static func load(store: UserPreferencesStore = .shared) -> ConstructionMethodPackOfflineCacheSnapshot? {
        guard let data = store.data(key), data.count <= ConstructionMethodPackLimits.maximumCacheBytes,
              let snapshot = try? JSONDecoder().decode(ConstructionMethodPackOfflineCacheSnapshot.self, from: data),
              (try? ConstructionMethodPackLimits.validate(snapshot.payload)) != nil else { return nil }
        return snapshot
    }

    @discardableResult
    static func save(
        endpoint: URL,
        payload: RemoteConstructionMethodPackPayload,
        rawBytes: Int,
        store: UserPreferencesStore = .shared
    ) -> ConstructionMethodPackOfflineCacheSnapshot? {
        guard rawBytes >= 0, rawBytes <= ConstructionMethodPackLimits.maximumResponseBytes,
              (try? ConstructionMethodPackLimits.validate(payload)) != nil else { return nil }
        let snapshot = ConstructionMethodPackOfflineCacheSnapshot(
            endpoint: endpoint.absoluteString,
            payload: payload,
            cachedAt: Date().timeIntervalSince1970,
            rawBytes: rawBytes
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              data.count <= ConstructionMethodPackLimits.maximumCacheBytes else { return nil }
        store.set(data, for: key)
        return snapshot
    }

    static func clear() {
        UserPreferencesStore.shared.removeObject(for: key)
    }
}

struct ConstructionMethodPackFetchResult: Sendable {
    let endpoint: URL
    let payload: RemoteConstructionMethodPackPayload
    let rawBytes: Int
}

enum ConstructionMethodPackImportConfiguration {
    private static let productionHost = "gongdizhishi.com"
    private static let productionEndpointRaw = "https://gongdizhishi.com/sitekeeper/method-packs.json"
    private static let localDebugEndpointRaw = "http://127.0.0.1:4321/sitekeeper/method-packs.json"
    private static let fallbackProductionEndpoint = makeFallbackProductionEndpoint()

    static var productionEndpoint: URL {
        staticEndpoint(
            raw: productionEndpointRaw,
            label: "production",
            fallback: fallbackProductionEndpoint
        )
    }

    static var localDebugEndpoint: URL {
        staticEndpoint(
            raw: localDebugEndpointRaw,
            label: "local-debug",
            fallback: productionEndpoint
        )
    }

    static var configuredPrimaryEndpoint: URL {
        guard AppFeatureFlags.allowsConstructionMethodPackEndpointOverride else {
            return productionEndpoint
        }
        guard let override = validUserEndpoint(
            UserPreferencesStore.shared.string(UserPreferenceKeys.constructionMethodPackImportEndpoint, default: "")
        ) else {
            return productionEndpoint
        }
        return override
    }

    static var configuredEndpointSource: String {
        let configuredEndpoint = configuredPrimaryEndpoint
        let configured = configuredEndpoint.absoluteString
        if configuredEndpoint == productionEndpoint {
            return AppLocalization.string("默认端点")
        }
        return String(format: AppLocalization.string("自定义端点：%@"), configured)
    }

    private static func validUserEndpoint(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    static func staticEndpoint(raw: String, label: String, fallback: URL) -> URL {
        guard let url = validStaticEndpoint(raw) else {
            StorageIssueLog.recordEvent(
                "construction_method_pack.invalid_static_endpoint",
                category: .dataStore,
                details: [
                    "label": label,
                    "raw": raw,
                    "fallback": fallback.absoluteString
                ]
            )
            return fallback
        }
        return url
    }

    private static func validStaticEndpoint(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard let host = url.host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return url
    }

    private static func makeFallbackProductionEndpoint() -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = productionHost
        components.path = "/sitekeeper/method-packs.json"
        if let url = components.url {
            return url
        }

        StorageIssueLog.recordEvent(
            "construction_method_pack.fallback_endpoint_unavailable",
            category: .dataStore,
            details: ["path": components.path]
        )
        return URL(fileURLWithPath: "/sitekeeper/method-packs.json")
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
                let (payload, rawBytes) = try await fetchResponse(
                    from: endpoint, session: .shared, maximumBytes: ConstructionMethodPackLimits.maximumResponseBytes
                )
                return ConstructionMethodPackFetchResult(endpoint: endpoint, payload: payload, rawBytes: rawBytes)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
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

    static func fetch(
        from endpoint: URL,
        session: URLSession = .shared,
        maximumBytes: Int = ConstructionMethodPackLimits.maximumResponseBytes
    ) async throws -> RemoteConstructionMethodPackPayload {
        try await fetchResponse(from: endpoint, session: session, maximumBytes: maximumBytes).payload
    }

    private static func fetchResponse(
        from endpoint: URL, session: URLSession, maximumBytes: Int
    ) async throws -> (payload: RemoteConstructionMethodPackPayload, rawBytes: Int) {
        let limit = min(max(0, maximumBytes), ConstructionMethodPackLimits.maximumResponseBytes)
        let (bytes, response) = try await session.bytes(from: endpoint)
        defer { bytes.task.cancel() }
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard response.expectedContentLength <= Int64(limit) else {
            throw ConstructionMethodPackLimitError.exceeded
        }
        let data = try await readBoundedBytes(bytes, maximumBytes: limit)
        let payload = try JSONDecoder().decode(RemoteConstructionMethodPackPayload.self, from: data)
        try ConstructionMethodPackLimits.validate(payload)
        return (payload, data.count)
    }

    static func readBoundedBytes<S: AsyncSequence>(_ bytes: S, maximumBytes: Int) async throws -> Data where S.Element == UInt8 {
        try Task.checkCancellation()
        var data = Data()
        for try await byte in bytes {
            if (data.count & 0xFFF) == 0 {
                try Task.checkCancellation()
            }
            guard data.count < maximumBytes else { throw ConstructionMethodPackLimitError.exceeded }
            data.append(byte)
        }
        return data
    }
}
