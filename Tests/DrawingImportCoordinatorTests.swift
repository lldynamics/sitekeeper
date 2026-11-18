import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct DrawingImportCoordinatorTests {
    @Test func exhaustedDrawingVersionsAreRejectedWithoutOverflow() {
        let projectID = UUID()
        var drawing = ProjectDrawing(projectId: projectID, name: "平面图", fileName: "plan.pdf", fileType: "pdf", version: "V\(Int.max)")
        #expect(ProjectDetailDrawingHelper.nextDrawingVersion(name: drawing.name, drawings: [drawing]) == nil)
        drawing.version = String(Int.max)
        #expect(ProjectDetailDrawingHelper.nextDrawingVersion(name: drawing.name, drawings: [drawing]) == nil)
        drawing.version = "V9999999999999999999999999999999999999"
        #expect(ProjectDetailDrawingHelper.nextDrawingVersion(name: drawing.name, drawings: [drawing]) == nil)
        drawing.version = "V9"
        #expect(ProjectDetailDrawingHelper.nextDrawingVersion(name: drawing.name, drawings: [drawing]) == "V10")
        #expect(ProjectDetailDrawingHelper.nextDrawingVersion(name: "其他图纸", drawings: [drawing]) == "V1")
        drawing.version = "现场修订"
        #expect(ProjectDetailDrawingHelper.nextDrawingVersion(name: drawing.name, drawings: [drawing]) == "V1")
    }

    @Test func exhaustedDrawingVersionDoesNotReplaceExistingDrawing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("平面图.pdf")
        let sourceData = Data("test drawing".utf8)
        try sourceData.write(to: sourceURL)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        let projectID = UUID()
        let existing = ProjectDrawing(projectId: projectID, name: "平面图", fileName: "existing.pdf",
                                      fileType: "pdf", version: "V\(Int.max)")
        store.replaceProjects([Project(id: projectID, name: "项目", location: "")])
        store.replaceProjectDrawings([existing])

        let result = FileQuarantineStore.withRootURLForTesting(directory.appendingPathComponent("quarantine")) {
            DrawingImportCoordinator.importDrawings([sourceURL], projectId: projectID, strategy: .createNewVersion,
                                                   store: store, replacementCleanupSummary: "drawing-version-test")
        }
        #expect(result.importedCount == 0)
        #expect(result.failures.count == 1)
        #expect(store.projectDrawings.map(\.id) == [existing.id])
        #expect(store.projectDrawings.first?.isCurrentVersion == true)
        #expect(try Data(contentsOf: sourceURL) == sourceData)
    }

    @Test func unsupportedSingleFileReturnsFailureWithoutAddingDrawing() throws {
        let store = DataStore()
        let projectId = UUID()
        store.replaceProjects([Project(id: projectId, name: "测试项目", location: "")])

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-drawing-\(UUID().uuidString).txt")
        try Data("not a drawing".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = DrawingImportCoordinator.importDrawings(
            [fileURL],
            projectId: projectId,
            strategy: .createNewVersion,
            store: store,
            replacementCleanupSummary: "drawingImportCoordinatorTests.unsupported"
        )

        #expect(result.importedCount == 0)
        #expect(result.replacedCount == 0)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.fileName == fileURL.lastPathComponent)
        #expect(result.operationMessage.contains(fileURL.lastPathComponent))
        #expect(store.projectDrawings.isEmpty)
    }

    @Test func zipWithoutDrawingEntriesReturnsFailureWithoutAddingDrawing() throws {
        let store = DataStore()
        let projectId = UUID()
        store.replaceProjects([Project(id: projectId, name: "测试项目", location: "")])

        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "drawing-empty-zip")
        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        try zip.addFile(path: "notes/readme.txt", data: Data("no drawings".utf8))
        let finishedURL = try zip.finish()
        defer { try? FileManager.default.removeItem(at: finishedURL) }

        let result = DrawingImportCoordinator.importDrawings(
            [finishedURL],
            projectId: projectId,
            strategy: .createNewVersion,
            store: store,
            replacementCleanupSummary: "drawingImportCoordinatorTests.emptyZip"
        )

        #expect(result.importedCount == 0)
        #expect(result.replacedCount == 0)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.fileName == finishedURL.lastPathComponent)
        #expect(result.failures.first?.reason.contains("ZIP") == true)
        #expect(result.operationMessage.contains(finishedURL.lastPathComponent))
        #expect(store.projectDrawings.isEmpty)
    }
}

@MainActor
struct ConstructionMethodPackImportMappingTests {
    @Test func remoteFetchRejectsOversizedAdvertisedAndStreamedResponses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConstructionPackTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let validURL = try #require(URL(string: "https://example.invalid/valid"))
        let payload = try await ConstructionMethodPackImportService.fetch(from: validURL, session: session, maximumBytes: 128)
        #expect(payload.packs.isEmpty)
        for path in ["advertised", "streamed", "unknown-length"] {
            let url = try #require(URL(string: "https://example.invalid/\(path)"))
            do {
                _ = try await ConstructionMethodPackImportService.fetch(from: url, session: session, maximumBytes: 128)
                Issue.record("超限响应应被拒绝：\(path)")
            } catch is ConstructionMethodPackLimitError {
            } catch {
                Issue.record("收到意外错误：\(error)")
            }
        }
    }

    @Test func downloadedBytesAreBoundedDuringConsumption() async throws {
        func stream(_ count: Int) -> AsyncStream<UInt8> {
            AsyncStream { continuation in
                for _ in 0..<count { continuation.yield(0x41) }
                continuation.finish()
            }
        }
        let allowed = try await ConstructionMethodPackImportService.readBoundedBytes(stream(4), maximumBytes: 4)
        #expect(allowed == Data(repeating: 0x41, count: 4))
        do {
            _ = try await ConstructionMethodPackImportService.readBoundedBytes(stream(5), maximumBytes: 4)
            Issue.record("超限下载应在读取时被拒绝")
        } catch is ConstructionMethodPackLimitError {
        } catch {
            Issue.record("收到意外错误：\(error)")
        }
    }

    @Test func packLimitsProtectDecodingAndPreserveExistingCache() throws {
        let pack = RemoteConstructionMethodPack(
            id: "safe", sourceSlug: "safe", sourceURL: "/safe", sourceVersion: "1", title: "工艺",
            trade: "电气", versionName: "V1", publishStatus: "已发布", tutorialBody: "说明",
            procedureSteps: ["第一步"], qualityChecklist: [], safetyChecklist: [], relatedStandards: [],
            relatedTemplates: [], relatedArticles: [], tags: [], updatedAt: "2026-01-01"
        )
        var payload = RemoteConstructionMethodPackPayload(schemaVersion: 1, generatedAt: "2026-01-01", count: 1, packs: [pack])
        let validData = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(RemoteConstructionMethodPackPayload.self, from: validData)
        try ConstructionMethodPackLimits.validate(decoded)
        #expect(decoded.packs.first?.procedureSteps == ["第一步"])

        let domain = "sitekeeper.pack-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = UserPreferencesStore(defaults: defaults)
        let endpoint = try #require(URL(string: "https://example.invalid/packs"))
        #expect(ConstructionMethodPackOfflineCacheStore.save(endpoint: endpoint, payload: payload,
                                                            rawBytes: validData.count, store: store) != nil)
        let previous = try #require(store.data(UserPreferenceKeys.constructionMethodPackOfflineCache))

        payload.packs = Array(repeating: pack, count: ConstructionMethodPackLimits.maximumItems + 1)
        let oversized = try JSONEncoder().encode(payload)
        #expect(throws: ConstructionMethodPackLimitError.self) {
            try JSONDecoder().decode(RemoteConstructionMethodPackPayload.self, from: oversized)
        }
        #expect(ConstructionMethodPackOfflineCacheStore.save(endpoint: endpoint, payload: payload,
                                                            rawBytes: oversized.count, store: store) == nil)
        #expect(store.data(UserPreferenceKeys.constructionMethodPackOfflineCache) == previous)
        #expect(ConstructionMethodPackOfflineCacheStore.load(store: store)?.payload.packs.count == 1)

        payload.packs = [pack]
        payload.packs[0].procedureSteps = Array(repeating: "x", count: ConstructionMethodPackLimits.maximumItems + 1)
        let oversizedNested = try JSONEncoder().encode(payload)
        #expect(throws: ConstructionMethodPackLimitError.self) {
            try JSONDecoder().decode(RemoteConstructionMethodPackPayload.self, from: oversizedNested)
        }

        var object = try #require(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        var packObjects = try #require(object["packs"] as? [[String: Any]])
        packObjects[0]["tutorialBody"] = String(repeating: "x", count: ConstructionMethodPackLimits.maximumStringBytes + 1)
        object["packs"] = packObjects
        let longTextData = try JSONSerialization.data(withJSONObject: object)
        let longText = try JSONDecoder().decode(RemoteConstructionMethodPackPayload.self, from: longTextData)
        #expect(throws: ConstructionMethodPackLimitError.self) { try ConstructionMethodPackLimits.validate(longText) }
        #expect(ConstructionMethodPackOfflineCacheStore.save(endpoint: endpoint, payload: longText,
                                                            rawBytes: longTextData.count, store: store) == nil)
        #expect(store.data(UserPreferenceKeys.constructionMethodPackOfflineCache) == previous)
    }

    @Test func mappingNormalizesSourceAndKnowledgeReferences() {
        let pack = RemoteConstructionMethodPack(
            id: "method-pack-1",
            sourceSlug: "wireing",
            sourceURL: "/articles/wireing/abc",
            sourceVersion: "2026.05",
            title: "  管内穿线施工  ",
            trade: " 电气 ",
            versionName: "  ",
            publishStatus: "已发布",
            tutorialBody: """
            施工说明
            [查看原文](/articles/wireing/abc)
            """,
            procedureSteps: [" 进场交底 ", " ", "线缆检查"],
            qualityChecklist: ["端子压接", "绝缘测试"],
            safetyChecklist: ["临电断电上锁", "高处防护"],
            relatedStandards: [" GB 50303-2015 ", "", "JGJ 46-2005"],
            relatedTemplates: [
                RemoteConstructionMethodPackLink(title: "施工交底记录", href: "/templates/disclosure"),
                RemoteConstructionMethodPackLink(title: "施工交底记录", href: "/templates/disclosure"),
                RemoteConstructionMethodPackLink(title: "", href: "https://gongdizhishi.com/templates/checklist")
            ],
            relatedArticles: [
                RemoteConstructionMethodPackLink(title: "穿线质检要点", href: "/articles/wireing/quality"),
                RemoteConstructionMethodPackLink(title: " ", href: "  ")
            ],
            tags: ["电气"],
            updatedAt: "2026-05-23 10:00"
        )

        let mapped = pack.constructionMethod(existing: nil)

        #expect(mapped.title == "管内穿线施工")
        #expect(mapped.trade == "电气")
        #expect(mapped.versionName == "知识网站 V1")
        #expect(mapped.sourceID == "method-pack-1")
        #expect(mapped.sourceURL == "https://gongdizhishi.com/articles/wireing/abc")
        #expect(mapped.tutorialBody.contains("](https://gongdizhishi.com/articles/wireing/abc)"))
        #expect(mapped.relatedStandards == ["GB 50303-2015", "JGJ 46-2005"])
        #expect(mapped.relatedTemplates.count == 2)
        #expect(mapped.relatedTemplates.first?.href == "https://gongdizhishi.com/templates/disclosure")
        #expect(mapped.relatedArticles.count == 1)
        #expect(mapped.relatedArticles.first?.href == "https://gongdizhishi.com/articles/wireing/quality")
    }

    @Test func mappingUpdateKeepsExistingIdentityAndOverwritesKnowledgeFields() {
        let existingID = UUID()
        let existing = ConstructionMethod(
            id: existingID,
            title: "旧工艺",
            trade: "电气",
            versionName: "V1",
            publishStatus: .draft,
            tutorialBody: "旧正文",
            procedureSteps: ["旧步骤"],
            qualityChecklist: ["旧质检"],
            safetyChecklist: ["旧安全"],
            sourceID: "old-id",
            sourceURL: "https://example.com/old",
            sourceVersion: "old",
            sourceUpdatedAt: BusinessDateValue(legacyText: "2025-01-01 10:00"),
            relatedStandards: ["旧规范"],
            relatedTemplates: [ConstructionMethodKnowledgeLink(title: "旧模板", href: "https://example.com/template-old")],
            relatedArticles: [ConstructionMethodKnowledgeLink(title: "旧文章", href: "https://example.com/article-old")]
        )

        let pack = RemoteConstructionMethodPack(
            id: "new-id",
            sourceSlug: "wireing",
            sourceURL: "https://gongdizhishi.com/articles/new",
            sourceVersion: "2026.06",
            title: "新版工艺",
            trade: "电气",
            versionName: "V2",
            publishStatus: "无效状态",
            tutorialBody: "新正文",
            procedureSteps: ["新步骤1", "新步骤2"],
            qualityChecklist: ["新质检"],
            safetyChecklist: ["新安全"],
            relatedStandards: ["新规范"],
            relatedTemplates: [RemoteConstructionMethodPackLink(title: "新模板", href: "https://gongdizhishi.com/templates/new")],
            relatedArticles: [RemoteConstructionMethodPackLink(title: "新文章", href: "https://gongdizhishi.com/articles/new-related")],
            tags: [],
            updatedAt: "2026-05-23 11:00"
        )

        let mapped = pack.constructionMethod(existing: existing)

        #expect(mapped.id == existingID)
        #expect(mapped.publishStatus == .published)
        #expect(mapped.sourceID == "new-id")
        #expect(mapped.sourceVersion == "2026.06")
        #expect(mapped.relatedStandards == ["新规范"])
        #expect(mapped.relatedTemplates.map(\.title) == ["新模板"])
        #expect(mapped.relatedArticles.map(\.title) == ["新文章"])
    }

    @Test func staticPackEndpointFallsBackInsteadOfCrashing() throws {
        let fallback = try #require(URL(string: "https://example.com/fallback-method-packs.json"))

        let missingScheme = ConstructionMethodPackImportConfiguration.staticEndpoint(
            raw: "gongdizhishi.com/sitekeeper/method-packs.json",
            label: "test-missing-scheme",
            fallback: fallback
        )
        let unsupportedScheme = ConstructionMethodPackImportConfiguration.staticEndpoint(
            raw: "file:///tmp/method-packs.json",
            label: "test-file-url",
            fallback: fallback
        )
        let validEndpoint = ConstructionMethodPackImportConfiguration.staticEndpoint(
            raw: "https://gongdizhishi.com/sitekeeper/method-packs.json",
            label: "test-production",
            fallback: fallback
        )

        #expect(missingScheme == fallback)
        #expect(unsupportedScheme == fallback)
        #expect(validEndpoint.absoluteString == "https://gongdizhishi.com/sitekeeper/method-packs.json")
    }
}

private final class ConstructionPackTestURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.lastPathComponent
        let body = path == "valid"
            ? Data(#"{"schemaVersion":1,"generatedAt":"2026-01-01","count":0,"packs":[]}"#.utf8)
            : Data(repeating: 0x41, count: 129)
        let length = path == "advertised" ? "129" : "1"
        let headers = path == "unknown-length" ? [:] : ["Content-Length": length]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
