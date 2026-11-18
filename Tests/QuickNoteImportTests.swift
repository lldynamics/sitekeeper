import Testing
import Foundation
import AVFoundation
import UIKit
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

    @Test func videoThumbnailCachePreservesLegacyCollisionAndImportedBusinessAttachment() async throws {
        let manager = FileManager.default
        let namespace = "test-\(UUID().uuidString)"
        let temporary = manager.temporaryDirectory.appendingPathComponent(namespace, isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        let cacheDirectory = try QuickNoteAttachmentStorage.videoThumbnailCacheDirectory(cacheNamespace: namespace)
        let videoName = "video-cache-\(UUID().uuidString).mov"
        let legacyName = QuickNoteAttachmentStorage.videoThumbnailFileName(for: videoName)
        var createdAttachments: [URL] = []
        defer {
            createdAttachments.forEach { try? manager.removeItem(at: $0) }
            try? manager.removeItem(at: cacheDirectory)
            try? manager.removeItem(at: temporary)
        }

        let videoURL = temporary.appendingPathComponent("fixture.mov")
        try await writeThumbnailTestVideo(at: videoURL)
        let videoData = try Data(contentsOf: videoURL)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(videoData, fileName: videoName)
        createdAttachments.append(try QuickNoteAttachmentStorage.validatedFileURL(for: videoName))

        // A valid image under the old derived name must neither be used nor overwritten.
        let legacyImage = UIGraphicsImageRenderer(size: CGSize(width: 9, height: 7)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 9, height: 7))
        }
        let legacyData = try #require(legacyImage.jpegData(compressionQuality: 0.8))
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(legacyData, fileName: legacyName)
        createdAttachments.append(try QuickNoteAttachmentStorage.validatedFileURL(for: legacyName))
        let contractData = Data("%PDF-1.4 business attachment".utf8)
        let contractSource = temporary.appendingPathComponent("thumb-contract.pdf")
        try contractData.write(to: contractSource)
        let contract = try QuickNoteAttachmentStorage.importFileOrThrow(from: contractSource)
        createdAttachments.append(try QuickNoteAttachmentStorage.validatedFileURL(for: contract.fileName))
        #expect(contract.originalName == "thumb-contract.pdf")
        let prefixedBusinessName = "thumb-contract-\(UUID().uuidString).pdf"
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(contractData, fileName: prefixedBusinessName)
        createdAttachments.append(try QuickNoteAttachmentStorage.validatedFileURL(for: prefixedBusinessName))
        #expect(QuickNoteAttachmentStorage.thumbnailCacheUsageBytes(cacheNamespace: namespace) == 0)

        let thumbnail = try #require(QuickNoteAttachmentStorage.videoThumbnail(for: videoName, cacheNamespace: namespace))
        #expect(thumbnail.cgImage?.width == 32)
        #expect(thumbnail.cgImage?.height == 32)
        let cachedURL = try QuickNoteAttachmentStorage.validatedVideoThumbnailCacheURL(for: videoName, cacheNamespace: namespace)
        #expect(cachedURL.deletingLastPathComponent() == cacheDirectory)
        let cachedData = try Data(contentsOf: cachedURL)
        #expect(UIImage(data: cachedData) != nil)
        #expect(QuickNoteAttachmentStorage.thumbnailCacheUsageBytes(cacheNamespace: namespace) == cachedData.count)
        #expect(QuickNoteAttachmentStorage.data(for: legacyName) == legacyData)
        #expect(QuickNoteAttachmentStorage.data(for: contract.fileName) == contractData)

        let videoKey = ThumbnailCacheKey(resourceURL: QuickNoteAttachmentStorage.fileURL(for: videoName),
                                         maxPixelSize: 512, variant: "video")
        let decoded = DecodedThumbnail(image: try #require(thumbnail.cgImage))
        #expect(await StorageThumbnailCache.image(for: videoKey) { decoded } != nil)
        #expect(StorageThumbnailCache.cachedImage(for: videoKey) != nil)
        QuickNoteAttachmentStorage.clearThumbnailCache(cacheNamespace: namespace)
        #expect(StorageThumbnailCache.cachedImage(for: videoKey) == nil)
        #expect(!manager.fileExists(atPath: cachedURL.path))
        #expect(QuickNoteAttachmentStorage.thumbnailCacheUsageBytes(cacheNamespace: namespace) == 0)
        #expect(QuickNoteAttachmentStorage.data(for: videoName) == videoData)
        #expect(QuickNoteAttachmentStorage.data(for: legacyName) == legacyData)
        #expect(QuickNoteAttachmentStorage.data(for: contract.fileName) == contractData)
        #expect(QuickNoteAttachmentStorage.data(for: prefixedBusinessName) == contractData)

        // A cache-file symlink cannot redirect reads, writes or deletion into an attachment.
        let legacyURL = try QuickNoteAttachmentStorage.validatedFileURL(for: legacyName)
        try manager.createSymbolicLink(at: cachedURL, withDestinationURL: legacyURL)
        let uncachedThumbnail = try #require(QuickNoteAttachmentStorage.videoThumbnail(for: videoName, cacheNamespace: namespace))
        #expect(uncachedThumbnail.cgImage?.width == 32)
        QuickNoteAttachmentStorage.clearThumbnailCache(cacheNamespace: namespace)
        #expect(try manager.destinationOfSymbolicLink(atPath: cachedURL.path) == legacyURL.path)
        #expect(QuickNoteAttachmentStorage.data(for: legacyName) == legacyData)
        try manager.removeItem(at: cachedURL)
        // Rendering can repopulate the isolated cache after a purge.
        #expect(QuickNoteAttachmentStorage.videoThumbnail(for: videoName, cacheNamespace: namespace) != nil)
        #expect(manager.fileExists(atPath: cachedURL.path))
    }

    @Test func videoThumbnailCacheVersionsSameNameAtomicVideoReplacements() async throws {
        let manager = FileManager.default
        let namespace = "test-\(UUID().uuidString)"
        let temporary = manager.temporaryDirectory.appendingPathComponent(namespace, isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        let cacheDirectory = try QuickNoteAttachmentStorage.videoThumbnailCacheDirectory(cacheNamespace: namespace)
        let fileName = "versioned-video-\(UUID().uuidString).mov"
        let sourceURL = try QuickNoteAttachmentStorage.validatedFileURL(for: fileName)
        defer {
            try? manager.removeItem(at: sourceURL)
            try? manager.removeItem(at: cacheDirectory)
            try? manager.removeItem(at: temporary)
        }
        let firstVideo = temporary.appendingPathComponent("first.mov")
        try await writeThumbnailTestVideo(at: firstVideo)
        let originalData = try Data(contentsOf: firstVideo)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(originalData, fileName: fileName)
        let originalAttributes = try manager.attributesOfItem(atPath: sourceURL.path)
        let originalDate = try #require(originalAttributes[.modificationDate] as? Date)
        let originalInode = try #require(originalAttributes[.systemFileNumber] as? NSNumber)
        let originalThumbnail = try #require(QuickNoteAttachmentStorage.videoThumbnail(for: fileName, cacheNamespace: namespace))
        let originalKey = try QuickNoteAttachmentStorage.validatedVideoThumbnailCacheURL(for: fileName, cacheNamespace: namespace)

        // Backup replacement can preserve both file size and modification time. Its new
        // inode must still select a new key, without hashing the entire video on reads.
        try originalData.write(to: sourceURL, options: .atomic)
        try manager.setAttributes([.modificationDate: originalDate], ofItemAtPath: sourceURL.path)
        let replacementAttributes = try manager.attributesOfItem(atPath: sourceURL.path)
        #expect(replacementAttributes[.systemFileNumber] as? NSNumber != originalInode)
        #expect(replacementAttributes[.size] as? NSNumber == originalAttributes[.size] as? NSNumber)
        let sameContentKey = try QuickNoteAttachmentStorage.validatedVideoThumbnailCacheURL(for: fileName, cacheNamespace: namespace)
        #expect(sameContentKey != originalKey)
        #expect(QuickNoteAttachmentStorage.videoThumbnail(for: fileName, cacheNamespace: namespace) != nil)
        #expect(manager.fileExists(atPath: sameContentKey.path))

        let secondVideo = temporary.appendingPathComponent("second.mov")
        try await writeThumbnailTestVideo(at: secondVideo, width: 64, height: 48, channel: 0xFF)
        let secondData = try Data(contentsOf: secondVideo)
        try secondData.write(to: sourceURL, options: .atomic)
        try manager.setAttributes([.modificationDate: originalDate], ofItemAtPath: sourceURL.path)
        let changedKey = try QuickNoteAttachmentStorage.validatedVideoThumbnailCacheURL(for: fileName, cacheNamespace: namespace)
        #expect(changedKey != sameContentKey)
        let changedThumbnail = try #require(QuickNoteAttachmentStorage.videoThumbnail(for: fileName, cacheNamespace: namespace))
        #expect(changedThumbnail.cgImage?.width == 64)
        #expect(changedThumbnail.cgImage?.height == 48)
        #expect(try thumbnailTestPixel(changedThumbnail) != thumbnailTestPixel(originalThumbnail))
        #expect(manager.fileExists(atPath: changedKey.path))

        try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: sourceURL.path)
        #expect(QuickNoteAttachmentStorage.videoThumbnail(for: fileName, cacheNamespace: namespace) == nil)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sourceURL.path)
        // Removing the source must not resurrect an old cached image.
        try manager.removeItem(at: sourceURL)
        #expect(QuickNoteAttachmentStorage.videoThumbnail(for: fileName, cacheNamespace: namespace) == nil)
        #expect(throws: (any Error).self) {
            try QuickNoteAttachmentStorage.validatedVideoThumbnailCacheURL(for: fileName, cacheNamespace: namespace)
        }
        // Neither a source symlink nor a non-video replacement may reuse the earlier key.
        try manager.createSymbolicLink(at: sourceURL, withDestinationURL: secondVideo)
        #expect(QuickNoteAttachmentStorage.videoThumbnail(for: fileName, cacheNamespace: namespace) == nil)
        try manager.removeItem(at: sourceURL)
        try Data("ordinary document".utf8).write(to: sourceURL, options: .atomic)
        #expect(QuickNoteAttachmentStorage.videoThumbnail(for: fileName, cacheNamespace: namespace) == nil)
        #expect(QuickNoteAttachmentStorage.data(for: fileName) == Data("ordinary document".utf8))
    }

    @Test func videoThumbnailCacheRejectsTraversalAndSymlinkEntries() throws {
        let manager = FileManager.default
        let namespace = "test-\(UUID().uuidString)"
        let temporary = manager.temporaryDirectory.appendingPathComponent(namespace, isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        let cacheDirectory = try QuickNoteAttachmentStorage.videoThumbnailCacheDirectory(cacheNamespace: namespace)
        try manager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: cacheDirectory)
            try? manager.removeItem(at: temporary)
        }
        let outside = temporary.appendingPathComponent("business.pdf")
        let data = Data("preserve external business data".utf8)
        try data.write(to: outside)
        let sourceName = "cache-boundary-\(UUID().uuidString).mov"
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(data, fileName: sourceName)
        let sourceURL = try QuickNoteAttachmentStorage.validatedFileURL(for: sourceName)
        defer { try? manager.removeItem(at: sourceURL) }
        // A regular attachment containing non-video bytes cannot produce a video preview.
        #expect(QuickNoteAttachmentStorage.videoThumbnail(for: sourceName, cacheNamespace: namespace) == nil)
        let cacheEntry = try QuickNoteAttachmentStorage.validatedVideoThumbnailCacheURL(for: sourceName, cacheNamespace: namespace)
        try manager.createSymbolicLink(at: cacheEntry, withDestinationURL: outside)
        #expect(throws: (any Error).self) {
            try QuickNoteAttachmentStorage.validatedVideoThumbnailCacheURL(for: sourceName, cacheNamespace: namespace)
        }
        #expect(QuickNoteAttachmentStorage.thumbnailCacheUsageBytes(cacheNamespace: namespace) == 0)
        QuickNoteAttachmentStorage.clearThumbnailCache(cacheNamespace: namespace)
        #expect(try Data(contentsOf: outside) == data)
        #expect(try manager.destinationOfSymbolicLink(atPath: cacheEntry.path) == outside.path)

        for invalid in ["..", "../outside", "/tmp/outside", "nested/cache", "nested\\cache"] {
            #expect(throws: (any Error).self) {
                try QuickNoteAttachmentStorage.videoThumbnailCacheDirectory(cacheNamespace: invalid)
            }
            #expect(throws: (any Error).self) {
                try QuickNoteAttachmentStorage.validatedVideoThumbnailCacheURL(for: invalid, cacheNamespace: namespace)
            }
        }

        // Replacing a namespace directory with a symlink must also fail closed.
        let linkedNamespace = "test-link-\(UUID().uuidString)"
        let linkedDirectory = try QuickNoteAttachmentStorage.videoThumbnailCacheDirectory(cacheNamespace: linkedNamespace)
        try manager.createSymbolicLink(at: linkedDirectory, withDestinationURL: temporary)
        defer { try? manager.removeItem(at: linkedDirectory) }
        #expect(throws: (any Error).self) {
            try QuickNoteAttachmentStorage.videoThumbnailCacheDirectory(cacheNamespace: linkedNamespace)
        }
        #expect(QuickNoteAttachmentStorage.thumbnailCacheUsageBytes(cacheNamespace: linkedNamespace) == 0)
        QuickNoteAttachmentStorage.clearThumbnailCache(cacheNamespace: linkedNamespace)
        #expect(try Data(contentsOf: outside) == data)
    }

    @Test func audioRecorderRejectsDeniedMicrophonePermission() async {
        let session = FakeQuickNoteAudioSession()
        session.permissionAllowed = false
        let recorderFactory = FakeQuickNoteAudioRecorderFactory()
        let fileStore = FakeQuickNoteAudioFileStore()
        let recorder = QuickNoteAudioRecorder(
            session: session,
            recorderFactory: recorderFactory,
            fileStore: fileStore
        )

        do {
            _ = try await recorder.toggleRecording()
            Issue.record("拒绝麦克风权限时不应开始录音")
        } catch QuickNoteAudioRecorderError.permissionDenied {
            #expect(!recorder.isRecording)
            #expect(session.permissionRequestCount == 1)
            #expect(session.configureCount == 0)
            #expect(recorderFactory.makeCount == 0)
            #expect(fileStore.preparedURLs.isEmpty)
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    @Test func audioRecorderStopsWhenInputIsUnavailable() async {
        let session = FakeQuickNoteAudioSession()
        session.inputAvailable = false
        let recorderFactory = FakeQuickNoteAudioRecorderFactory()
        let fileStore = FakeQuickNoteAudioFileStore()
        let recorder = QuickNoteAudioRecorder(
            session: session,
            recorderFactory: recorderFactory,
            fileStore: fileStore
        )

        do {
            _ = try await recorder.toggleRecording()
            Issue.record("没有音频输入时不应开始录音")
        } catch QuickNoteAudioRecorderError.inputUnavailable {
            #expect(!recorder.isRecording)
            #expect(session.configureCount == 1)
            #expect(session.deactivateCount == 1)
            #expect(recorderFactory.makeCount == 0)
            #expect(fileStore.preparedURLs.isEmpty)
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    @Test func audioRecorderCleansTemporaryFileWhenStartFails() async {
        let session = FakeQuickNoteAudioSession()
        let fakeRecording = FakeQuickNoteAudioRecording()
        fakeRecording.recordResult = false
        let recorderFactory = FakeQuickNoteAudioRecorderFactory(recording: fakeRecording)
        let fileStore = FakeQuickNoteAudioFileStore(fileName: "failed-recording.m4a")
        let recorder = QuickNoteAudioRecorder(
            session: session,
            recorderFactory: recorderFactory,
            fileStore: fileStore
        )

        do {
            _ = try await recorder.toggleRecording()
            Issue.record("录音启动失败时不应进入录音状态")
        } catch QuickNoteAudioRecorderError.startFailed {
            #expect(!recorder.isRecording)
            #expect(session.deactivateCount == 1)
            #expect(fakeRecording.prepareCount == 1)
            #expect(fakeRecording.recordCount == 1)
            #expect(fakeRecording.stopCount == 0)
            #expect(fileStore.deletedRecordings.map { $0.fileName } == ["failed-recording.m4a"])
            #expect(fileStore.deletedRecordings.first?.summary == "quickNoteAudioRecorder.failedRecording")
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    @Test func audioRecorderStopReturnsAudioAttachment() async throws {
        let session = FakeQuickNoteAudioSession()
        let fakeRecording = FakeQuickNoteAudioRecording()
        fakeRecording.currentTime = 8.25
        let recorderFactory = FakeQuickNoteAudioRecorderFactory(recording: fakeRecording)
        let fileStore = FakeQuickNoteAudioFileStore(fileName: "site-voice-note.m4a")
        let recorder = QuickNoteAudioRecorder(
            session: session,
            recorderFactory: recorderFactory,
            fileStore: fileStore
        )

        let firstToggle = try await recorder.toggleRecording()
        #expect(firstToggle == nil)
        #expect(recorder.isRecording)
        #expect(fakeRecording.isMeteringEnabled)
        #expect(fakeRecording.prepareCount == 1)
        #expect(fakeRecording.recordCount == 1)

        let stoppedAttachment = try await recorder.toggleRecording()
        let attachment = try #require(stoppedAttachment)
        #expect(!recorder.isRecording)
        #expect(attachment.attachmentKind == .audio)
        #expect(attachment.fileName == "site-voice-note.m4a")
        #expect(attachment.durationSeconds == Optional(8.25))
        #expect(fakeRecording.stopCount == 1)
        #expect(session.deactivateCount == 1)
        #expect(fileStore.deletedRecordings.isEmpty)
    }
}

private final class FakeQuickNoteAudioSession: QuickNoteAudioSessionControlling {
    var permissionAllowed = true
    var inputAvailable = true
    var configureError: Error?
    private(set) var permissionRequestCount = 0
    private(set) var configureCount = 0
    private(set) var deactivateCount = 0

    var isInputAvailable: Bool {
        inputAvailable
    }

    func requestRecordPermission() async -> Bool {
        permissionRequestCount += 1
        return permissionAllowed
    }

    func configureForRecording() throws {
        configureCount += 1
        if let configureError {
            throw configureError
        }
    }

    func deactivateAfterRecording() {
        deactivateCount += 1
    }
}

private final class FakeQuickNoteAudioRecorderFactory: QuickNoteAudioRecorderCreating {
    var makeError: Error?
    private let recording: FakeQuickNoteAudioRecording
    private(set) var makeCount = 0
    private(set) var requestedURL: URL?
    private(set) var requestedSettings: [String: Any] = [:]

    init(recording: FakeQuickNoteAudioRecording = FakeQuickNoteAudioRecording()) {
        self.recording = recording
    }

    func makeRecorder(url: URL, settings: [String: Any]) throws -> any QuickNoteAudioRecording {
        makeCount += 1
        requestedURL = url
        requestedSettings = settings
        if let makeError {
            throw makeError
        }
        return recording
    }
}

private final class FakeQuickNoteAudioRecording: QuickNoteAudioRecording {
    var isMeteringEnabled = false
    var currentTime: TimeInterval = 0
    var prepareResult = true
    var recordResult = true
    private(set) var prepareCount = 0
    private(set) var recordCount = 0
    private(set) var stopCount = 0

    func prepareToRecord() -> Bool {
        prepareCount += 1
        return prepareResult
    }

    func record() -> Bool {
        recordCount += 1
        return recordResult
    }

    func stop() {
        stopCount += 1
    }
}

private final class FakeQuickNoteAudioFileStore: QuickNoteAudioRecordingFileStoring {
    let fileName: String
    var prepareError: Error?
    private(set) var preparedURLs: [URL] = []
    private(set) var deletedRecordings: [(fileName: String, summary: String)] = []

    init(fileName: String = "quick-note-audio-test.m4a") {
        self.fileName = fileName
    }

    func makeFileName(extension ext: String) -> String {
        fileName
    }

    func fileURL(for fileName: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    func prepareDirectory(for recordingURL: URL) throws {
        preparedURLs.append(recordingURL)
        if let prepareError {
            throw prepareError
        }
    }

    func deleteRecording(fileName: String, summary: String) {
        deletedRecordings.append((fileName, summary))
    }
}

// Generate a real, short H.264 video instead of accepting invalid bytes as thumbnail coverage.
@MainActor
private func writeThumbnailTestVideo(at url: URL, width: Int = 32, height: Int = 32, channel: UInt8 = 0x7F) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ])
    try #require(writer.canAdd(input))
    writer.add(input)
    try #require(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &buffer)
    try #require(status == kCVReturnSuccess)
    let pixels = try #require(buffer)
    CVPixelBufferLockBaseAddress(pixels, [])
    let base = try #require(CVPixelBufferGetBaseAddress(pixels))
    base.initializeMemory(as: UInt8.self, repeating: channel, count: CVPixelBufferGetBytesPerRow(pixels) * height)
    CVPixelBufferUnlockBaseAddress(pixels, [])
    for frame in 0..<2 {
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData, Date() < deadline, writer.status == .writing {
            await Task.yield()
        }
        try #require(input.isReadyForMoreMediaData)
        try #require(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    try #require(writer.status == .completed)
}

private func thumbnailTestPixel(_ image: UIImage) throws -> [UInt8] {
    let cgImage = try #require(image.cgImage)
    var pixel = [UInt8](repeating: 0, count: 4)
    try pixel.withUnsafeMutableBytes { bytes in
        let context = try #require(CGContext(
            data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return pixel
}
