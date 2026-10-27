import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct DataHealthPhotoTests {

    // 待办整改照片缺失检测
    @Test func missingRectificationPhotosAreDetected() throws {
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: true)

        let pid = UUID()
        let project = Project(id: pid, name: "test project", location: "", status: .active, startDate: BusinessDateValue(legacyText: "2025-01-01"), expectedEndDate: BusinessDateValue(legacyText: "2025-06-01"))
        store.appendProject(project)

        // 创建一个有待办但没有实际照片文件的待办
        var todo = SiteTodo(title: "整改检查", priority: .high, issueType: .safety, projectId: pid)
        todo.rectificationBeforePhotoFileName = "nonexistent_before.jpg"
        todo.rectificationAfterPhotoFileName = "nonexistent_after.jpg"
        store.appendSiteTodo(todo)

        // 验证缺失检测逻辑
        let logPhotoNames = store.dailyLogs.flatMap(\.allPhotoFileNames)
        let todoPhotoNames = store.siteTodos.flatMap { [$0.rectificationBeforePhotoFileName, $0.rectificationAfterPhotoFileName] }.compactMap { $0 }
        let allNames = logPhotoNames + todoPhotoNames

        let missing = allNames.filter { !PhotoStorage.exists(fileName: $0) }
        #expect(missing.contains("nonexistent_before.jpg"))
        #expect(missing.contains("nonexistent_after.jpg"))
    }

    // 修复后照片引用被清空
    @Test func repairClearsMissingRectificationPhotoReferences() throws {
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: true)

        let pid = UUID()
        let project = Project(id: pid, name: "repair test", location: "", status: .active, startDate: BusinessDateValue(legacyText: "2025-01-01"), expectedEndDate: BusinessDateValue(legacyText: "2025-06-01"))
        store.appendProject(project)

        var todo = SiteTodo(title: "安全整改", priority: .high, issueType: .safety, projectId: pid)
        todo.rectificationBeforePhotoFileName = "ghost_photo.jpg"
        store.appendSiteTodo(todo)

        // 模拟修复：清除缺失的照片引用
        var repairedTodos = store.siteTodos
        for index in repairedTodos.indices {
            if let fileName = repairedTodos[index].rectificationBeforePhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                repairedTodos[index].rectificationBeforePhotoFileName = nil
            }
            if let fileName = repairedTodos[index].rectificationAfterPhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                repairedTodos[index].rectificationAfterPhotoFileName = nil
            }
        }
        store.replaceSiteTodos(repairedTodos)

        #expect(store.siteTodos[0].rectificationBeforePhotoFileName == nil)
    }

    // 日志 + 待办照片统一收集
    @Test func combinedPhotoNamesIncludesRectificationPhotos() throws {
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: true)

        let pid = UUID()
        let project = Project(id: pid, name: "combined test", location: "", status: .active, startDate: BusinessDateValue(legacyText: "2025-01-01"), expectedEndDate: BusinessDateValue(legacyText: "2025-06-01"))
        store.appendProject(project)

        var todo = SiteTodo(title: "整改项", priority: .medium, issueType: .quality, projectId: pid)
        todo.rectificationBeforePhotoFileName = "rect_before_combined.jpg"
        store.appendSiteTodo(todo)

        let logPhotos = store.dailyLogs.flatMap(\.allPhotoFileNames)
        let todoPhotos = store.siteTodos.compactMap(\.rectificationBeforePhotoFileName) + store.siteTodos.compactMap(\.rectificationAfterPhotoFileName)
        let combined = Set(logPhotos + todoPhotos)

        #expect(combined.contains("rect_before_combined.jpg"))
        #expect(!combined.contains("rect_after_combined.jpg")) // 没有设置 after
    }

    @Test func scannerSummarizesTriggeredHealthIssues() {
        let validProjectId = UUID()
        let invalidProjectId = UUID()
        let missingDocumentId = UUID()
        let missingFinancialRecordId = UUID()
        let document = ProjectDocument(
            projectId: validProjectId,
            title: "Receipt",
            fileName: "missing-receipt.pdf",
            linkedFinancialRecordId: missingFinancialRecordId
        )
        let financialRecord = ProjectFinancialRecord(
            projectId: validProjectId,
            linkedDocumentIds: [missingDocumentId]
        )
        let log = DailyLog(
            date: BusinessDateValue(legacyText: "2026-05-21"),
            weather: "",
            content: "",
            workers: NumericInputSupport.quantity(""),
            photoFileName: "missing-log.jpg",
            projectId: invalidProjectId
        )
        let todo = SiteTodo(
            title: "Fix",
            rectificationBeforePhotoFileName: "missing-before.jpg",
            projectId: invalidProjectId
        )
        let material = MaterialItem(
            name: "Cement",
            quantity: NumericInputSupport.quantity("1"),
            unit: "bag",
            projectId: invalidProjectId
        )
        let warehouseMovement = ProjectWarehouseMovement(
            projectId: invalidProjectId,
            linkedDocumentIds: [missingDocumentId]
        )
        let input = DataHealthScanInput(
            projects: [Project(id: validProjectId, name: "Project", location: "")],
            dailyLogs: [log],
            siteTodos: [todo],
            projectDocuments: [document],
            projectFinancialRecords: [financialRecord],
            projectWarehouseMovements: [warehouseMovement],
            materialItems: [material],
            storageIssues: ["photo.save_failed"]
        )
        var storage = DataHealthScanStorage()
        storage.photoExists = { _ in false }
        storage.projectDocumentExists = { _ in false }
        storage.quickNoteAttachmentExists = { _ in true }
        storage.orphanPhotoFileNames = { _, _ in ["orphan-photo.jpg"] }
        storage.orphanDrawingFileNames = { _ in [] }
        storage.orphanProjectDocumentFileNames = { _ in [] }
        storage.orphanQuickNoteAttachmentFileNames = { _, _ in [] }

        let summary = DataHealthScanner.scan(
            input: input,
            reason: .dataChanged,
            scannedAt: Date(timeIntervalSince1970: 1_800_000_000),
            storage: storage
        )

        #expect(summary.reason == .dataChanged)
        #expect(summary.missingPhotoFiles == 2)
        #expect(summary.missingDocumentFiles == 1)
        #expect(summary.orphanPhotoFiles == 1)
        #expect(summary.orphanAttachmentMappings == 1)
        #expect(summary.orphanWarehouseAttachmentMappings == 1)
        #expect(summary.danglingDocumentLinks == 1)
        #expect(summary.invalidProjectRefs == 4)
        #expect(summary.storageIssues == 1)
        #expect(summary.totalIssues == 12)
        #expect(summary.hasIssues)
    }
}

@MainActor
struct BackgroundDataHealthTests {
    nonisolated private static func summary(
        _ input: DataHealthScanInput, _ reason: DataHealthScanReason, _ includeMetrics: Bool
    ) -> DataHealthScanSummary {
        DataHealthScanSummary(
            scannedAt: Date(), reason: reason,
            missingPhotoFiles: input.siteTodos.count, missingDocumentFiles: 0,
            missingQuickNoteAttachmentFiles: 0, orphanPhotoFiles: 0, orphanDrawingFiles: 0,
            orphanDocumentFiles: 0, orphanQuickNoteAttachmentFiles: 0,
            orphanAttachmentMappings: 0, orphanWarehouseAttachmentMappings: 0,
            danglingDocumentLinks: 0, invalidProjectRefs: 0, storageIssues: 0,
            fileSnapshot: DataHealthScanFileSnapshot(
                missingPhotoFileNames: [], missingDocumentFileNames: [],
                missingQuickNoteAttachmentFileNames: [], orphanPhotoFileNames: [],
                orphanDrawingFileNames: [], orphanDocumentFileNames: [], orphanQuickNoteAttachmentFileNames: []
            ), storageIssueEntries: [], widgetHealth: nil,
            storageUsage: includeMetrics ? .zero : nil
        )
    }

    private func makeStore(worker: DataHealthScanWorker) async throws -> (DataStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("background-health-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory, dataHealthWorker: worker)
        await store.awaitInitialLoad()
        store.invalidateDataHealthScan()
        return (store, directory)
    }

    @Test func workerScansOffTheMainThread() async throws {
        let worker = DataHealthScanWorker { input, reason, includeMetrics in
            #expect(!Thread.isMainThread)
            return Self.summary(input, reason, includeMetrics)
        }
        let (store, directory) = try await makeStore(worker: worker)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scanned = await store.scanDataHealthNow()
        #expect(scanned != nil)
        #expect(store.latestDataHealthScan == scanned)
        #expect(store.latestDataHealthSnapshot != nil)
    }

    @Test func mutationDuringScanRejectsOldResultAndPreservesMetricsRequest() async throws {
        let started = AsyncStream<Void>.makeStream()
        let gate = DispatchSemaphore(value: 0)
        let worker = DataHealthScanWorker { input, reason, includeMetrics in
            started.continuation.yield(())
            #expect(gate.wait(timeout: .now() + 5) == .success)
            return Self.summary(input, reason, includeMetrics)
        }
        let (store, directory) = try await makeStore(worker: worker)
        defer {
            gate.signal()
            started.continuation.finish()
            store.cancelScheduledSave()
            store.invalidateDataHealthScan()
            try? FileManager.default.removeItem(at: directory)
        }
        let first = Task { await store.scanDataHealthNow() }
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()
        // This MainActor mutation executes while the worker is blocked on its own executor.
        store.projectStore.setSiteTodos([SiteTodo(title: "new revision")])
        gate.signal()
        #expect(await first.value == nil)
        #expect(store.latestDataHealthScan == nil)
        gate.signal()
        let fresh = await store.scanDataHealthNow(reason: .dataChanged, includeSupplementalMetrics: false)
        #expect(fresh?.missingPhotoFiles == 1)
        #expect(fresh?.storageUsage != nil)
    }

    @Test func explicitSaveSchedulingReplacesAnInFlightScan() async throws {
        let started = AsyncStream<Void>.makeStream()
        let gate = DispatchSemaphore(value: 0)
        let worker = DataHealthScanWorker { input, reason, includeMetrics in
            if reason == .manual {
                started.continuation.yield(())
                #expect(gate.wait(timeout: .now() + 5) == .success)
            }
            return Self.summary(input, reason, includeMetrics)
        }
        let (store, directory) = try await makeStore(worker: worker)
        defer {
            gate.signal()
            started.continuation.finish()
            store.cancelScheduledSave()
            store.invalidateDataHealthScan()
            try? FileManager.default.removeItem(at: directory)
        }
        let first = Task { await store.scanDataHealthNow() }
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()
        store.scheduleSave()
        store.cancelScheduledSave()
        let replacement = store.dataHealthScanTask
        gate.signal()
        #expect(await first.value == nil)
        #expect(await replacement?.value != nil)
        #expect(store.latestDataHealthScan?.reason == .dataChanged)
    }

    @Test func newerRequestWinsWithoutDataMutation() async throws {
        let started = AsyncStream<Void>.makeStream()
        let gate = DispatchSemaphore(value: 0)
        let worker = DataHealthScanWorker { input, reason, includeMetrics in
            if reason == .scheduled {
                started.continuation.yield(())
                #expect(gate.wait(timeout: .now() + 5) == .success)
            }
            return Self.summary(input, reason, includeMetrics)
        }
        let (store, directory) = try await makeStore(worker: worker)
        defer {
            gate.signal()
            started.continuation.finish()
            store.invalidateDataHealthScan()
            try? FileManager.default.removeItem(at: directory)
        }
        let first = Task { await store.scanDataHealthNow(reason: .scheduled) }
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()
        store.runDataHealthScanNow(reason: .manual)
        let newest = store.dataHealthScanTask
        gate.signal()
        #expect(await first.value == nil)
        #expect(await newest?.value != nil)
        #expect(store.latestDataHealthScan?.reason == .manual)
    }

    @Test func cancelledCallerDoesNotPublishScan() async throws {
        let started = AsyncStream<Void>.makeStream()
        let gate = DispatchSemaphore(value: 0)
        let worker = DataHealthScanWorker { input, reason, includeMetrics in
            started.continuation.yield(())
            #expect(gate.wait(timeout: .now() + 5) == .success)
            return Self.summary(input, reason, includeMetrics)
        }
        let (store, directory) = try await makeStore(worker: worker)
        defer {
            gate.signal()
            started.continuation.finish()
            store.invalidateDataHealthScan()
            try? FileManager.default.removeItem(at: directory)
        }
        let scan = Task { await store.scanDataHealthNow() }
        var events = started.stream.makeAsyncIterator()
        _ = await events.next()
        scan.cancel()
        gate.signal()
        #expect(await scan.value == nil)
        #expect(store.latestDataHealthScan == nil)
    }

    @Test func unchangedAutomaticScanKeepsPublishedSnapshotAndUpdatesFreshness() async throws {
        let worker = DataHealthScanWorker { input, reason, includeMetrics in
            Self.summary(input, reason, includeMetrics)
        }
        let (store, directory) = try await makeStore(worker: worker)
        defer {
            store.invalidateDataHealthScan()
            try? FileManager.default.removeItem(at: directory)
        }
        _ = await store.scanDataHealthNow()
        let published = store.latestDataHealthScan
        let snapshot = store.latestDataHealthSnapshot
        let automatic = await store.scanDataHealthNow(reason: .dataChanged, includeSupplementalMetrics: false)
        #expect(automatic != nil)
        #expect(store.latestDataHealthScan == published)
        #expect(store.latestDataHealthSnapshot == snapshot)
        #expect(store.dataHealthLastCompletedAt == automatic?.scannedAt)
        store.scheduleDataHealthScanIfStale(maxAge: 60)
        #expect(store.dataHealthScanTask == nil)
    }

    @Test func restoreAndFailedLoadDoNotStartScans() async throws {
        let worker = DataHealthScanWorker { input, reason, includeMetrics in
            Issue.record("Scan must not start while persistence is unavailable")
            return Self.summary(input, reason, includeMetrics)
        }
        let (store, directory) = try await makeStore(worker: worker)
        defer {
            store.invalidateDataHealthScan()
            try? FileManager.default.removeItem(at: directory)
        }
        store.isApplyingBackup = true
        #expect(await store.scanDataHealthNow() == nil)
        #expect(store.dataHealthScanTask == nil)
        store.isApplyingBackup = false
        store.setLoadState(.failed)
        #expect(await store.scanDataHealthNow() == nil)
        #expect(store.dataHealthScanTask == nil)
    }
}
