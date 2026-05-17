import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct QuickNoteImportTests {

    // 干净安装首次导入 — 目录不存在时应自动创建
    @Test func freshInstallDirectoryCreatedOnFileImport() throws {
        // 先删除附件目录模拟干净安装
        QuickNoteAttachmentStorage.clearAttachmentsDirectory()

        let tmpDir = FileManager.default.temporaryDirectory
        let source = tmpDir.appendingPathComponent("test_import_\(UUID().uuidString).txt")
        try "hello world".write(to: source, atomically: true, encoding: .utf8)

        let attachment = try QuickNoteAttachmentStorage.importFileOrThrow(from: source)
        #expect(!attachment.fileName.isEmpty)
        #expect(attachment.attachmentKind == .file)
        #expect(attachment.originalName == source.lastPathComponent)

        // 验证文件确实存在
        let targetURL = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
        #expect(FileManager.default.fileExists(atPath: targetURL.path))
    }

    @Test func freshInstallDirectoryCreatedOnVideoImport() async throws {
        QuickNoteAttachmentStorage.clearAttachmentsDirectory()

        let tmpDir = FileManager.default.temporaryDirectory
        let source = tmpDir.appendingPathComponent("test_video_\(UUID().uuidString).mov")
        try Data([0x00, 0x01, 0x02]).write(to: source)

        let result = try await QuickNoteAttachmentStorage.importVideoOrThrow(from: source)
        #expect(!result.fileName.isEmpty)
        #expect(result.originalName == source.lastPathComponent)

        let targetURL = QuickNoteAttachmentStorage.fileURL(for: result.fileName)
        #expect(FileManager.default.fileExists(atPath: targetURL.path))
    }

    // 重复导入不冲突
    @Test func duplicateImportCreatesUniqueFiles() throws {
        QuickNoteAttachmentStorage.clearAttachmentsDirectory()

        let tmpDir = FileManager.default.temporaryDirectory
        let source = tmpDir.appendingPathComponent("test_dup_\(UUID().uuidString).txt")
        try "content".write(to: source, atomically: true, encoding: .utf8)

        let a1 = try QuickNoteAttachmentStorage.importFileOrThrow(from: source)
        let a2 = try QuickNoteAttachmentStorage.importFileOrThrow(from: source)

        #expect(a1.fileName != a2.fileName)
        #expect(a1.originalName == a2.originalName)

        let u1 = QuickNoteAttachmentStorage.fileURL(for: a1.fileName)
        let u2 = QuickNoteAttachmentStorage.fileURL(for: a2.fileName)
        #expect(u1 != u2)
        #expect(FileManager.default.fileExists(atPath: u1.path))
        #expect(FileManager.default.fileExists(atPath: u2.path))
    }

    @Test func quickNoteRemovalDefersAttachmentDeletionUntilCommit() throws {
        QuickNoteAttachmentStorage.clearAttachmentsDirectory()
        defer { QuickNoteAttachmentStorage.clearAttachmentsDirectory() }

        let fileName = try QuickNoteAttachmentStorage.saveDataOrThrow(
            Data([0x01, 0x02, 0x03]),
            fileName: "delete-deferred-\(UUID().uuidString).bin"
        )
        let attachment = QuickNoteAttachment(kind: .file, fileName: fileName)
        let note = QuickNote(title: "待删除", attachments: [attachment])
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: false)
        store.replaceQuickNotes([note])

        let deletion = store.removeQuickNotes(
            ids: Set([note.id]),
            deferredFileCleanup: DataStoreDeferredFileCleanup.quickNoteAttachments(
                [attachment],
                summary: "quickNote.attachments"
            )
        )

        #expect(store.quickNotes.isEmpty)
        #expect(QuickNoteAttachmentStorage.exists(fileName: fileName))
        #expect(deletion.restoredItems(current: store.quickNotes, id: \.id).map(\.id) == [note.id])

        deletion.performDeferredFileCleanup()
        #expect(!QuickNoteAttachmentStorage.exists(fileName: fileName))
    }

    @Test func quickNoteAttachmentThrowingCleanupDeletesFile() throws {
        QuickNoteAttachmentStorage.clearAttachmentsDirectory()
        defer { QuickNoteAttachmentStorage.clearAttachmentsDirectory() }

        let fileName = try QuickNoteAttachmentStorage.saveDataOrThrow(
            Data([0x0D, 0x0E, 0x0F]),
            fileName: "quick-note-throwing-cleanup-\(UUID().uuidString).bin"
        )
        #expect(QuickNoteAttachmentStorage.exists(fileName: fileName))

        try DataStoreDeferredFileCleanup.deleteQuickNoteAttachmentFilesOrThrow(
            [fileName],
            summary: "quickNoteImportTests.throwingCleanup"
        )

        #expect(!QuickNoteAttachmentStorage.exists(fileName: fileName))
    }
}
