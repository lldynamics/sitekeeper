import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct ProjectFileBrowserModelTests {
    @Test func filenameSearchKeepsItsProjectWhenChangingCategory() {
        let project = UUID()
        let unrelated = UUID()
        #expect(ProjectFileBrowserSelection.projectID(current: project, projectMatches: [], fileMatches: [project]) == project)
        #expect(ProjectFileBrowserSelection.projectID(current: project, projectMatches: [unrelated], fileMatches: [project]) == project)
        #expect(ProjectFileBrowserSelection.projectID(current: project, projectMatches: [unrelated], fileMatches: []) == unrelated)
        #expect(ProjectFileBrowserSelection.projectID(current: project, projectMatches: [], fileMatches: []) == nil)
    }

    @Test func realFilePreparationRunsOffMainAndMatchesSynchronousCollection() async throws {
        let files = try ProjectFileBrowserTestFiles()
        defer { files.remove() }
        let model = ProjectFileBrowserModel { snapshot in
            #expect(!Thread.isMainThread)
            return try ProjectFilePreparedData.build(snapshot)
        }
        await model.refresh(snapshot: files.snapshot, signature: 1, keyword: "Acceptance", debounce: .zero)
        let data = try #require(model.data(for: 1))
        let records = try #require(files.snapshot.filesByProject[files.project.id])
        for category in ProjectFileCategory.allCases {
            let expected = ProjectFileCollector.items(in: records, category: category)
            let actual = data.items(for: files.project.id, category: category)
            #expect(Set(actual.map(\.id)) == Set(expected.map(\.id)))
            for item in actual {
                let original = try #require(expected.first { $0.id == item.id })
                #expect(item.title == original.title && item.url == original.url)
                #expect(item.exists == original.exists && item.size == original.size)
                #expect(item.sortDate == original.sortDate && item.documentStatus == original.documentStatus)
                #expect(item.documentLedgerIssueCount == original.documentLedgerIssueCount)
            }
        }
        #expect(model.resultIDs.count == files.documents.count)
        #expect(data.items(for: files.project.id, health: .missing).count == 1)
        #expect(data.items(for: files.project.id, health: .returnedDocuments).count == 1)
        #expect(data.inspections.first?.missingFiles.count == 1)
        #expect(data.items(for: files.project.id, category: .drawings).first?.size == 7)
    }

    @Test func cacheReusesPreparedFilesUntilVersionChangesIncludingEmptyResults() async throws {
        let files = try ProjectFileBrowserTestFiles()
        defer { files.remove() }
        let count = FilePreparationProbe()
        let model = ProjectFileBrowserModel { snapshot in
            count.markStarted()
            return try ProjectFilePreparedData.build(snapshot)
        }
        await model.refresh(snapshot: files.snapshot, signature: 1, keyword: "Acceptance", debounce: .zero)
        let first = try #require(model.data(for: 1))
        let removed = try #require(first.items(for: files.project.id, category: .drawings).first)
        try FileManager.default.removeItem(at: removed.url)
        await model.refresh(snapshot: files.snapshot, signature: 1, keyword: "不存在", debounce: .zero)
        #expect(count.starts == 1)
        #expect(model.resultIDs.isEmpty)
        #expect(model.data(for: 1)?.items(for: files.project.id, category: .drawings).first?.exists == true)
        await model.refresh(snapshot: files.snapshot, signature: 2, keyword: "", debounce: .zero)
        #expect(count.starts == 2)
        #expect(model.data(for: 1) == nil)
        #expect(model.data(for: 2)?.items(for: files.project.id, category: .drawings).first?.exists == false)

        let empty = ProjectFileBrowserSnapshot(projects: [], filesByProject: [:])
        await model.refresh(snapshot: empty, signature: 3, keyword: "", debounce: .zero)
        await model.refresh(snapshot: empty, signature: 3, keyword: "again", debounce: .zero)
        #expect(count.starts == 3)
        #expect(model.data(for: 3)?.resultsByID.isEmpty == true)
    }

    @Test func modelSnapshotDoesNotReadLaterStoreMutations() async throws {
        let store = ProjectStore()
        let project = Project(name: "Original", location: "")
        store.setProjects([project])
        store.setProjectDocuments([ProjectDocument(projectId: project.id, title: "Acceptance", fileName: "missing.pdf")])
        let snapshot = ProjectFileBrowserSnapshot(projectStore: store)
        let signature = store.fileSearchVersion
        store.setProjects([])
        store.setProjectDocuments([])
        let model = ProjectFileBrowserModel()
        await model.refresh(snapshot: snapshot, signature: signature, keyword: "Acceptance", debounce: .zero)
        #expect(model.resultIDs.count == 1)
        #expect(model.prepared?.resultsByID.values.first?.project.name == "Original")
        await model.refresh(snapshot: ProjectFileBrowserSnapshot(projectStore: store),
                            signature: store.fileSearchVersion, keyword: "Acceptance", debounce: .zero)
        #expect(model.resultIDs.isEmpty)
    }

    @Test func cancelledPreparationNeverPublishesPartialFiles() async throws {
        let gate = FilePreparationProbe()
        let snapshot = ProjectFileBrowserSnapshot(projects: [], filesByProject: [:])
        let model = ProjectFileBrowserModel { snapshot in
            gate.markStarted()
            try gate.waitForRelease()
            return try ProjectFilePreparedData.build(snapshot)
        }
        let request = Task { await model.refresh(snapshot: snapshot, signature: 1, keyword: "", debounce: .zero) }
        defer { gate.release()
        request.cancel() }
        try await waitForStart(gate)
        request.cancel()
        gate.release()
        await request.value
        #expect(model.prepared == nil && model.loadedSignature == nil)
        #expect(!model.isPreparing && !model.isSearching)
    }

    @Test func slowerOldVersionCannotOverwriteNewerFiles() async throws {
        let gate = FilePreparationProbe()
        let old = Project(name: "Old", location: "")
        let new = Project(name: "New", location: "")
        let model = ProjectFileBrowserModel { snapshot in
            if snapshot.projects.first?.id == old.id {
                gate.markStarted()
                try gate.waitForRelease()
            }
            return try ProjectFilePreparedData.build(snapshot)
        }
        let earlier = Task {
            await model.refresh(snapshot: .init(projects: [old], filesByProject: [:]),
                                signature: 1, keyword: "Old", debounce: .zero)
        }
        defer { gate.release()
        earlier.cancel() }
        try await waitForStart(gate)
        await model.refresh(snapshot: .init(projects: [new], filesByProject: [:]),
                            signature: 2, keyword: "New", debounce: .zero)
        gate.release()
        await earlier.value
        #expect(model.loadedSignature == 2 && model.keyword == "New")
        #expect(model.prepared?.inspections.map(\.project.id) == [new.id])
    }

    private func waitForStart(_ gate: FilePreparationProbe) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while gate.starts == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(gate.starts > 0)
    }
}

private final class FilePreparationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var count = 0

    var starts: Int { lock.withLock { count } }
    func markStarted() { lock.withLock { count += 1 } }
    func release() { semaphore.signal() }
    func waitForRelease() throws {
        guard semaphore.wait(timeout: .now() + 3) == .success else { throw CancellationError() }
    }
}

final class ProjectFileBrowserTestFiles {
    let project = Project(name: "File Test Site", location: "")
    private(set) var documents: [ProjectDocument] = []
    private var fileURLs: [URL] = []
    private var records = ProjectFileCollectionSnapshot()

    var snapshot: ProjectFileBrowserSnapshot {
        .init(projects: [project], filesByProject: [project.id: records])
    }

    init(documentCount: Int = 3) throws {
        let prefix = UUID().uuidString
        do {
            for index in 0..<documentCount {
                let name = "\(prefix)-\(index).pdf"
                if index != documentCount - 1 {
                    try write(ProjectDocumentStorage.fileURL(for: name), size: 64)
                }
                documents.append(ProjectDocument(
                    projectId: project.id, title: "Acceptance \(index)", fileName: name,
                    submissionStatus: index == documentCount - 1 ? .returned : .archived,
                    createdAt: "2026-10-15 10:00"
                ))
            }
            records.documents = documents
            try addOtherCategories(prefix: prefix)
        } catch {
            remove()
            throw error
        }
    }

    func remove() {
        for url in fileURLs { try? FileManager.default.removeItem(at: url) }
    }

    private func write(_ url: URL, size: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: size).write(to: url)
        fileURLs.append(url)
    }

    private func addOtherCategories(prefix: String) throws {
        let drawing = "\(prefix)-drawing.pdf"
        let photo = "\(prefix)-photo.jpg"
        let attachment = "\(prefix)-attachment.bin"
        try write(DrawingStorage.fileURL(for: drawing), size: 7)
        try write(PhotoStorage.fileURL(for: photo), size: 5)
        try write(QuickNoteAttachmentStorage.fileURL(for: attachment), size: 9)
        records.drawings = [ProjectDrawing(projectId: project.id, name: "Drawing", fileName: drawing, fileType: "pdf")]
        records.logs = [DailyLog(date: "2026-10-15", weather: "", content: "", workers: "1", photoFileName: photo, projectId: project.id)]
        records.todos = [SiteTodo(title: "Rectification", rectificationBeforePhotoFileName: photo, projectId: project.id)]
        records.quickNotes = [QuickNote(projectId: project.id, attachments: [.init(kind: .file, fileName: attachment)])]
    }
}
