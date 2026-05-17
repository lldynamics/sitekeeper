import Testing
import Foundation
import UIKit
@testable import sitekeeper

@MainActor
struct DataStoreTests {

    let testStore: DataStore
    let storageDirectory: URL

    init() {
        TransferLimitPolicy.setRuntimeProfileOverride(.development)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageDirectory = directory
        let store = DataStore(storageDirectory: directory)
        store.clearAllBusinessData(deleteStoredFiles: false)
        self.testStore = store
    }

    // MARK: - Initial state

    @Test func emptyStoreHasNoBusinessData() {
        #expect(!testStore.hasAnyBusinessData)
    }

    @Test func emptyStoreProjectsEmpty() {
        #expect(testStore.projects.isEmpty)
    }

    // MARK: - Seed data

    @Test func importSampleDataPopulatesProjects() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.projects.isEmpty)
        #expect(testStore.projects.count >= 2)
    }

    @Test func importSampleDataPopulatesMaterials() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.materialItems.isEmpty)
    }

    @Test func importSampleDataReplacingClearsFirst() {
        testStore.importSampleData(replacingExisting: false)
        testStore.importSampleData(replacingExisting: true)
        #expect(testStore.projects.count >= 2)
    }

    @Test func importSampleDataSetsHistory() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.historyRecords.isEmpty)
    }

    @Test func calculationHistoryRemovalReturnsRestorableResult() {
        let first = HistoryRecord(tool: "墙面", input: "A", result: "1", date: "2026-05-16 10:00")
        let second = HistoryRecord(tool: "照明", input: "B", result: "2", date: "2026-05-16 10:01")
        testStore.replaceHistoryRecords([first, second])

        let deletion = testStore.removeCalculationHistory(ids: Set([first.id]))

        #expect(deletion.deletedCount == 1)
        #expect(testStore.historyRecords.map(\.id) == [second.id])
        #expect(deletion.restoredItems(current: testStore.historyRecords, id: \.id).map(\.id) == [first.id, second.id])
    }

    @Test func calculationHistoryClearReturnsRestorableResult() {
        let first = HistoryRecord(tool: "墙面", input: "A", result: "1", date: "2026-05-16 10:00")
        let second = HistoryRecord(tool: "照明", input: "B", result: "2", date: "2026-05-16 10:01")
        testStore.replaceHistoryRecords([first, second])

        let deletion = testStore.clearCalculationHistory()

        #expect(deletion.deletedCount == 2)
        #expect(testStore.historyRecords.isEmpty)
        #expect(deletion.restoredItems(current: testStore.historyRecords, id: \.id).map(\.id) == [first.id, second.id])
    }

    @Test func hasAnyBusinessDataAfterImport() {
        testStore.importSampleData(replacingExisting: false)
        #expect(testStore.hasAnyBusinessData)
    }

    // MARK: - Snapshot roundtrip

    @Test func makeSnapshotPreservesData() {
        testStore.importSampleData(replacingExisting: false)
        let snapshot = testStore.makeSnapshot(includePhotoFiles: false)
        #expect(snapshot.projects.count == testStore.projects.count)
        #expect(snapshot.materialItems.count == testStore.materialItems.count)
        #expect(snapshot.quoteItems.count == testStore.quoteItems.count)
    }

    // MARK: - Clear

    @Test func clearAllBusinessDataEmptiesStore() {
        testStore.importSampleData(replacingExisting: false)
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        #expect(!testStore.hasAnyBusinessData)
        #expect(testStore.projects.isEmpty)
    }

    // MARK: - MaterialPriceEntries

    @Test func materialPriceEntriesAfterImport() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.materialPriceEntries.isEmpty)
        #expect(testStore.materialPriceEntries.contains { $0.name.contains("BV") })
    }

    // MARK: - supplierProfiles

    @Test func supplierProfilesAfterImport() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.supplierProfiles.isEmpty)
    }

    // MARK: - templates

    @Test func templatesAfterImport() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.templates.isEmpty)
        #expect(testStore.templates.contains { $0.category == .dailyLog })
    }

    // MARK: - deleteProject full cascade

    @Test func deleteProjectRemovesProjectAndAllRelatedData() async throws {
        testStore.importSampleData(replacingExisting: true)
        let project = try #require(testStore.projects.first)
        let pid = project.id

        testStore.deleteProject(pid)

        #expect(!testStore.projects.contains { $0.id == pid })
        #expect(!testStore.materialItems.contains { $0.projectId == pid })
        #expect(!testStore.quoteItems.contains { $0.projectId == pid })
        #expect(!testStore.laborRecords.contains { $0.projectId == pid })
        #expect(!testStore.dailyLogs.contains { $0.projectId == pid })
        #expect(!testStore.progressTasks.contains { $0.projectId == pid })
        #expect(!testStore.lightingCircuitPlans.contains { $0.projectId == pid })
        #expect(!testStore.siteTodos.contains { $0.projectId == pid })
        #expect(!testStore.projectDrawings.contains { $0.projectId == pid })
        #expect(!testStore.projectContacts.contains { $0.projectId == pid })
        #expect(!testStore.projectFinancialRecords.contains { $0.projectId == pid })
        #expect(!testStore.projectDocuments.contains { $0.projectId == pid })
        #expect(!testStore.quickNotes.contains { $0.projectId == pid })
        #expect(!testStore.projectWarehouseMovements.contains { $0.projectId == pid })
    }

    @Test func deleteProjectDoesNotAffectOtherProjects() async throws {
        testStore.importSampleData(replacingExisting: true)
        try #require(testStore.projects.count >= 2)
        let firstPid = testStore.projects[0].id
        let secondPid = testStore.projects[1].id
        let otherMaterialCount = testStore.materialItems.filter { $0.projectId == secondPid }.count

        testStore.deleteProject(firstPid)

        #expect(testStore.projects.contains { $0.id == secondPid })
        #expect(testStore.materialItems.filter { $0.projectId == secondPid }.count == otherMaterialCount)
    }

    @Test func deleteProjectRemovesOnlyMaterialSheetDraftsUnderProject() async throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let first = Project(name: "A", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        let second = Project(name: "B", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        testStore.replaceProjects([first, second])
        testStore.replaceMaterialSheetDrafts([
            MaterialSheetDraft(title: "A 草稿", projectId: first.id),
            MaterialSheetDraft(title: "B 草稿", projectId: second.id),
            MaterialSheetDraft(title: "无归属草稿", projectId: nil)
        ])

        testStore.deleteProject(first.id)

        #expect(!testStore.materialSheetDrafts.contains { $0.projectId == first.id })
        #expect(testStore.materialSheetDrafts.contains { $0.projectId == second.id })
        #expect(testStore.materialSheetDrafts.contains { $0.projectId == nil })
    }

    @Test func deleteProjectPrunesSharedContactLinksForOtherProjects() async throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)

        let projectA = Project(name: "A", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        let projectB = Project(name: "B", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        let projectC = Project(name: "C", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        testStore.replaceProjects([projectA, projectB, projectC])

        let sharedContact = ProjectContact(
            projectId: projectB.id,
            relatedProjectIds: [projectA.id, projectC.id],
            name: "共享联系人"
        )
        let deletedPrimaryContact = ProjectContact(
            projectId: projectA.id,
            relatedProjectIds: [projectB.id],
            name: "被删主联系人"
        )
        testStore.replaceProjectContacts([sharedContact, deletedPrimaryContact])

        testStore.deleteProject(projectA.id)

        let remainingShared = try #require(testStore.projectContacts.first { $0.id == sharedContact.id })
        #expect(remainingShared.projectId == projectB.id)
        #expect(!remainingShared.relatedProjectIds.contains(projectA.id))
        #expect(remainingShared.relatedProjectIds.contains(projectC.id))
        #expect(!testStore.projectContacts.contains { $0.id == deletedPrimaryContact.id })
    }

    @Test func removeProjectCascadeDefersStoredFileDeletionUntilCommit() throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let project = Project(name: "文件项目", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        let photoFile = try PhotoStorage.saveOrThrow(
            original: Self.makeJPEGData(),
            fileName: "project-delete-photo-\(UUID().uuidString).jpg"
        )
        let todoPhotoFile = try PhotoStorage.saveOrThrow(
            original: Self.makeJPEGData(),
            fileName: "project-delete-todo-\(UUID().uuidString).jpg"
        )
        let documentFile = try ProjectDocumentStorage.savePDFOrThrow(data: Data([0x01, 0x02]), projectId: project.id)
        let drawing = try DrawingStorage.saveImportedDataOrThrow(
            data: Data([0x03, 0x04]),
            sourceFileName: "project-delete-drawing.pdf",
            projectId: project.id
        )
        let attachmentFile = try QuickNoteAttachmentStorage.saveDataOrThrow(
            Data([0x05, 0x06]),
            fileName: "project-delete-attachment-\(UUID().uuidString).bin"
        )
        defer {
            PhotoStorage.delete(fileNames: [photoFile, todoPhotoFile])
            ProjectDocumentStorage.delete(fileName: documentFile)
            DrawingStorage.delete(fileName: drawing.fileName)
            QuickNoteAttachmentStorage.delete(fileName: attachmentFile)
        }

        testStore.replaceProjects([project])
        testStore.replaceDailyLogs([
            DailyLog(
                date: "2026-05-16",
                weather: "晴",
                content: "日志",
                workers: "2",
                photos: [LogPhoto(fileName: photoFile)],
                projectId: project.id
            )
        ])
        testStore.replaceSiteTodos([
            SiteTodo(title: "整改", rectificationBeforePhotoFileName: todoPhotoFile, projectId: project.id)
        ])
        testStore.replaceProjectDrawings([drawing])
        testStore.replaceProjectDocuments([
            ProjectDocument(projectId: project.id, title: "票据", fileName: documentFile)
        ])
        testStore.replaceQuickNotes([
            QuickNote(
                title: "随手记",
                projectId: project.id,
                attachments: [QuickNoteAttachment(kind: .file, fileName: attachmentFile)]
            )
        ])

        let deletion = testStore.removeProjectCascade(project.id)

        #expect(!testStore.projects.contains { $0.id == project.id })
        #expect(PhotoStorage.exists(fileName: photoFile))
        #expect(PhotoStorage.exists(fileName: todoPhotoFile))
        #expect(ProjectDocumentStorage.exists(fileName: documentFile))
        #expect(DrawingStorage.exists(fileName: drawing.fileName))
        #expect(QuickNoteAttachmentStorage.exists(fileName: attachmentFile))
        #expect(deletion.deferredFileCleanup?.fileCount == 5)

        deletion.performDeferredFileCleanup()

        #expect(!PhotoStorage.exists(fileName: photoFile))
        #expect(!PhotoStorage.exists(fileName: todoPhotoFile))
        #expect(!ProjectDocumentStorage.exists(fileName: documentFile))
        #expect(!DrawingStorage.exists(fileName: drawing.fileName))
        #expect(!QuickNoteAttachmentStorage.exists(fileName: attachmentFile))
    }

    @Test func removeProjectCascadeCanRestoreDeletedProjectDataAndContactLinks() throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let projectA = Project(name: "A", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        let projectB = Project(name: "B", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        let material = MaterialItem(name: "水泥", quantity: "1", unit: "袋", projectId: projectA.id)
        let quote = QuoteItem(
            name: "报价",
            unitPrice: "10",
            quantity: "1",
            unit: "项",
            notes: "",
            taxRate: "0",
            discountRate: "0",
            projectId: projectA.id
        )
        let labor = LaborRecord(date: "2026-05-16", workers: "2", hours: "1", note: "", projectId: projectA.id)
        let log = DailyLog(date: "2026-05-16", weather: "晴", content: "日志", workers: "2", projectId: projectA.id)
        let progress = ProgressTask(
            projectId: projectA.id,
            title: "进度",
            startDate: "2026-05-16",
            dueDate: "2026-05-20",
            completion: 0.3,
            note: ""
        )
        let plan = LightingCircuitPlan(
            name: "照明",
            projectId: projectA.id,
            supplyType: .singlePhase,
            voltage: "220",
            powerFactor: "0.9",
            demandFactor: "1",
            breakerFactor: "1",
            wireFactor: "1",
            isCopper: true,
            loads: [],
            updatedAt: "2026-05-16 10:00"
        )
        let todo = SiteTodo(title: "待办", projectId: projectA.id)
        let drawing = ProjectDrawing(projectId: projectA.id, name: "图纸", fileName: "restore-drawing.pdf", fileType: "pdf")
        let financial = ProjectFinancialRecord(projectId: projectA.id, amount: "100")
        let document = ProjectDocument(projectId: projectA.id, title: "资料", fileName: "restore-doc.pdf")
        let note = QuickNote(title: "随手记", projectId: projectA.id)
        let movement = ProjectWarehouseMovement(projectId: projectA.id, materialName: "水泥", unit: "袋", quantity: "1")
        let draft = MaterialSheetDraft(title: "材料单", projectId: projectA.id)
        let sharedContact = ProjectContact(projectId: projectB.id, relatedProjectIds: [projectA.id], name: "共享联系人")
        let deletedPrimaryContact = ProjectContact(projectId: projectA.id, relatedProjectIds: [projectB.id], name: "项目联系人")
        testStore.replaceProjects([projectA, projectB])
        testStore.replaceMaterialItems([material])
        testStore.replaceQuoteItems([quote])
        testStore.replaceLaborRecords([labor])
        testStore.replaceDailyLogs([log])
        testStore.replaceProgressTasks([progress])
        testStore.replaceLightingCircuitPlans([plan])
        testStore.replaceSiteTodos([todo])
        testStore.replaceProjectDrawings([drawing])
        testStore.replaceProjectFinancialRecords([financial])
        testStore.replaceProjectDocuments([document])
        testStore.replaceQuickNotes([note])
        testStore.replaceProjectWarehouseMovements([movement])
        testStore.replaceMaterialSheetDrafts([draft])
        testStore.replaceProjectContacts([sharedContact, deletedPrimaryContact])

        let deletion = testStore.removeProjectCascade(projectA.id)
        let prunedSharedContact = try #require(testStore.projectContacts.first { $0.id == sharedContact.id })
        #expect(!testStore.projects.contains { $0.id == projectA.id })
        #expect(!testStore.projectContacts.contains { $0.id == deletedPrimaryContact.id })
        #expect(!prunedSharedContact.relatedProjectIds.contains(projectA.id))

        testStore.restoreProjectCascade(deletion)

        #expect(testStore.projects.contains { $0.id == projectA.id })
        #expect(testStore.materialItems.contains { $0.id == material.id })
        #expect(testStore.quoteItems.contains { $0.id == quote.id })
        #expect(testStore.laborRecords.contains { $0.id == labor.id })
        #expect(testStore.dailyLogs.contains { $0.id == log.id })
        #expect(testStore.progressTasks.contains { $0.id == progress.id })
        #expect(testStore.lightingCircuitPlans.contains { $0.id == plan.id })
        #expect(testStore.siteTodos.contains { $0.id == todo.id })
        #expect(testStore.projectDrawings.contains { $0.id == drawing.id })
        #expect(testStore.projectFinancialRecords.contains { $0.id == financial.id })
        #expect(testStore.projectDocuments.contains { $0.id == document.id })
        #expect(testStore.quickNotes.contains { $0.id == note.id })
        #expect(testStore.projectWarehouseMovements.contains { $0.id == movement.id })
        #expect(testStore.materialSheetDrafts.contains { $0.id == draft.id })
        #expect(testStore.projectContacts.contains { $0.id == deletedPrimaryContact.id })
        let restoredSharedContact = try #require(testStore.projectContacts.first { $0.id == sharedContact.id })
        #expect(restoredSharedContact.relatedProjectIds.contains(projectA.id))
    }

    @Test func projectPhotoCleanupClearsReferencesAndKeepsSharedFiles() throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let projectA = UUID()
        let projectB = UUID()
        let targetLog = DailyLog(
            date: "2026-05-16",
            weather: "晴",
            content: "日志",
            workers: "2",
            photoFileName: "legacy.jpg",
            photos: [
                LogPhoto(fileName: "target.jpg"),
                LogPhoto(fileName: "shared.jpg")
            ],
            projectId: projectA
        )
        let otherLog = DailyLog(
            date: "2026-05-17",
            weather: "晴",
            content: "其他",
            workers: "1",
            photos: [LogPhoto(fileName: "shared.jpg")],
            projectId: projectB
        )
        let targetTodo = SiteTodo(
            title: "整改",
            rectificationBeforePhotoFileName: "before.jpg",
            rectificationAfterPhotoFileName: "after.jpg",
            projectId: projectA
        )
        let otherTodo = SiteTodo(
            title: "其他整改",
            rectificationBeforePhotoFileName: "other-before.jpg",
            projectId: projectB
        )
        testStore.replaceDailyLogs([targetLog, otherLog])
        testStore.replaceSiteTodos([targetTodo, otherTodo])

        let result = testStore.clearProjectPhotoReferences(projectId: projectA)

        let cleanedLog = try #require(testStore.dailyLogs.first { $0.id == targetLog.id })
        let untouchedLog = try #require(testStore.dailyLogs.first { $0.id == otherLog.id })
        let cleanedTodo = try #require(testStore.siteTodos.first { $0.id == targetTodo.id })
        let untouchedTodo = try #require(testStore.siteTodos.first { $0.id == otherTodo.id })
        #expect(cleanedLog.photoFileName == nil)
        #expect(cleanedLog.photos.isEmpty)
        #expect(untouchedLog.allPhotoFileNames == ["shared.jpg"])
        #expect(cleanedTodo.rectificationBeforePhotoFileName == nil)
        #expect(cleanedTodo.rectificationAfterPhotoFileName == nil)
        #expect(untouchedTodo.rectificationBeforePhotoFileName == "other-before.jpg")
        #expect(result.photoFileNames == Set(["legacy.jpg", "target.jpg", "before.jpg", "after.jpg"]))
    }

    @Test func projectFileCleanupRemovesDocumentsDrawingsAndUnlinksReferences() throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let projectA = UUID()
        let projectB = UUID()
        let targetNote = QuickNote(
            title: "现场视频",
            projectId: projectA,
            attachments: [
                QuickNoteAttachment(kind: .video, fileName: "site.mov"),
                QuickNoteAttachment(kind: .video, fileName: "shared.mov"),
                QuickNoteAttachment(kind: .photo, fileName: "keep.jpg")
            ]
        )
        let otherNote = QuickNote(
            title: "其他项目",
            projectId: projectB,
            attachments: [
                QuickNoteAttachment(kind: .video, fileName: "shared.mov")
            ]
        )
        let videoDocument = ProjectDocument(
            projectId: projectA,
            title: "视频资料",
            category: .construction,
            fileName: "clip.mp4",
            fileType: "mp4"
        )
        let ticketDocument = ProjectDocument(
            projectId: projectA,
            title: "收据",
            category: .receipt,
            fileName: "receipt.pdf"
        )
        let otherDocument = ProjectDocument(
            projectId: projectB,
            title: "其他资料",
            category: .construction,
            fileName: "other.mp4",
            fileType: "mp4"
        )
        let targetDrawing = ProjectDrawing(projectId: projectA, name: "CAD", fileName: "target.dwg", fileType: "dwg")
        let sharedDrawing = ProjectDrawing(projectId: projectA, name: "共享 CAD", fileName: "shared.dwg", fileType: "dwg")
        let otherSharedDrawing = ProjectDrawing(projectId: projectB, name: "其他 CAD", fileName: "shared.dwg", fileType: "dwg")
        let financial = ProjectFinancialRecord(
            projectId: projectA,
            amount: "100",
            linkedDocumentIds: [videoDocument.id, ticketDocument.id]
        )
        let movement = ProjectWarehouseMovement(
            projectId: projectA,
            materialName: "电线",
            unit: "卷",
            quantity: "1",
            linkedDocumentIds: [videoDocument.id, ticketDocument.id]
        )
        testStore.replaceQuickNotes([targetNote, otherNote])
        testStore.replaceProjectDocuments([videoDocument, ticketDocument, otherDocument])
        testStore.replaceProjectDrawings([targetDrawing, sharedDrawing, otherSharedDrawing])
        testStore.replaceProjectFinancialRecords([financial])
        testStore.replaceProjectWarehouseMovements([movement])

        let videoResult = testStore.clearProjectVideoReferences(
            projectId: projectA,
            videoFileExtensions: ["mov", "mp4"]
        )
        let cleanedNote = try #require(testStore.quickNotes.first { $0.id == targetNote.id })
        let untouchedNote = try #require(testStore.quickNotes.first { $0.id == otherNote.id })
        #expect(cleanedNote.attachments.map(\.fileName) == ["keep.jpg"])
        #expect(untouchedNote.attachments.map(\.fileName) == ["shared.mov"])
        #expect(!testStore.projectDocuments.contains { $0.id == videoDocument.id })
        #expect(testStore.projectDocuments.contains { $0.id == ticketDocument.id })
        #expect(testStore.projectDocuments.contains { $0.id == otherDocument.id })
        #expect(testStore.projectFinancialRecords.first?.linkedDocumentIds == [ticketDocument.id])
        #expect(testStore.projectWarehouseMovements.first?.linkedDocumentIds == [ticketDocument.id])
        #expect(videoResult.quickNoteAttachmentFileNames == Set(["site.mov"]))
        #expect(videoResult.projectDocumentFileNames == Set(["clip.mp4"]))

        let cadResult = testStore.clearProjectCADReferences(
            projectId: projectA,
            cadFileExtensions: ["dwg", "dxf"]
        )
        #expect(!testStore.projectDrawings.contains { $0.id == targetDrawing.id })
        #expect(!testStore.projectDrawings.contains { $0.id == sharedDrawing.id })
        #expect(testStore.projectDrawings.contains { $0.id == otherSharedDrawing.id })
        #expect(cadResult.drawingFileNames == Set(["target.dwg"]))

        let ticketResult = testStore.clearProjectTicketDocumentReferences(projectId: projectA)
        #expect(!testStore.projectDocuments.contains { $0.id == ticketDocument.id })
        #expect(testStore.projectDocuments.contains { $0.id == otherDocument.id })
        #expect(testStore.projectFinancialRecords.first?.linkedDocumentIds.isEmpty == true)
        #expect(testStore.projectWarehouseMovements.first?.linkedDocumentIds.isEmpty == true)
        #expect(ticketResult.projectDocumentFileNames == Set(["receipt.pdf"]))
    }

    @Test func relatedDataCountIncludesMaterialSheetDrafts() {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let project = Project(name: "草稿项目", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        testStore.replaceProjects([project])
        testStore.replaceMaterialSheetDrafts([
            MaterialSheetDraft(title: "D1", projectId: project.id),
            MaterialSheetDraft(title: "D2", projectId: project.id),
            MaterialSheetDraft(title: "No Project", projectId: nil)
        ])

        #expect(testStore.relatedDataCount(for: project.id) == 2)
    }

    // MARK: - flushSave

    @Test func flushSaveWritesToDisk() async throws {
        testStore.clearAllBusinessData(deleteStoredFiles: true)
        let project = Project(name: "flush test", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        testStore.appendProject(project)
        await testStore.flushSave()

        let restored = DataStore(storageDirectory: storageDirectory)
        await restored.awaitInitialLoad()
        #expect(restored.projects.contains { $0.name == "flush test" })
    }

    @Test func flushSaveReplacesPendingScheduleSave() async throws {
        testStore.clearAllBusinessData(deleteStoredFiles: true)
        testStore.appendProject(Project(name: "flush pending", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01"))
        testStore.scheduleSave()
        await testStore.flushSave()

        let restored = DataStore(storageDirectory: storageDirectory)
        await restored.awaitInitialLoad()
        #expect(restored.projects.contains { $0.name == "flush pending" })
    }

    private static func makeJPEGData() throws -> Data {
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
}
