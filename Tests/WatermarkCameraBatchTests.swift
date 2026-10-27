import Foundation
import PDFKit
import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct WatermarkCameraBatchTests {
    @Test func logGroupingUsesCapturedProjectIDsAndRejectsMixedSelection() throws {
        let projectA = UUID()
        let projectB = UUID()
        var context = CameraWatermarkContext(projectName: "Frozen Project A", tag: "Before", workSection: "Section One")
        let first = photo(context: context, projectId: projectA)
        context.projectName = "Later Project B"
        context.tag = "After"
        context.workSection = "Section Two"
        let sameCapturedProject = photo(context: context, projectId: projectA)
        let otherProject = photo(context: context, projectId: projectB)
        let unassigned = photo(context: context, projectId: nil)

        #expect(first.context.projectName == "Frozen Project A")
        #expect(first.context.tag == "Before")
        #expect(first.context.workSection == "Section One")
        #expect(try WatermarkCameraBatchService.logProject(for: [first, sameCapturedProject]) == projectA)
        #expect(try WatermarkCameraBatchService.logProject(for: [unassigned]) == nil)
        #expect(throws: WatermarkCameraBatchError.self) { try WatermarkCameraBatchService.logProject(for: [first, otherProject]) }
        #expect(throws: WatermarkCameraBatchError.self) { try WatermarkCameraBatchService.logProject(for: [first, unassigned]) }
        #expect(throws: WatermarkCameraBatchError.self) { try WatermarkCameraBatchService.logProject(for: []) }
    }

    @Test func zipUsesFrozenProjectDateAndSectionWithUniquePhotoNames() throws {
        let dayOne = Date(timeIntervalSince1970: 1_770_000_000)
        let dayTwo = dayOne.addingTimeInterval(86_400)
        var context = CameraWatermarkContext(projectName: "Project/A", workSection: "Level\\2")
        let first = photo(context: context, capturedAt: dayOne)
        let second = photo(context: context, capturedAt: dayOne)
        context.projectName = "Project B"
        context.workSection = "Section B"
        let third = photo(context: context, capturedAt: dayTwo)
        let data = try WatermarkCameraBatchService.zip([first, second, third], compression: 0.9)
        let entries = try SimpleZipArchiveReader.read(data)
        let prefix = "Project_A/\(Formatters.date.string(from: dayOne))/Level_2_"
        #expect(Set(entries.filter { $0.path != "metadata.json" }.map(\.path)) == [
            "\(prefix)\(first.id.uuidString).jpg",
            "\(prefix)\(second.id.uuidString).jpg",
            "Project B/\(Formatters.date.string(from: dayTwo))/Section B_\(third.id.uuidString).jpg"
        ])
        #expect(entries.count == 4)
        let manifest = try #require(entries.first { $0.path == "metadata.json" })
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([WatermarkCameraBatchService.ExportRecord].self, from: manifest.data)
        #expect(records.count == 3)
        #expect(records.first?.context.projectName == "Project/A")
        #expect(records.first?.context.workSection == "Level\\2")
        for entry in entries where entry.path != "metadata.json" {
            #expect(entry.path.split(separator: "/").count == 3)
            #expect(UIImage(data: entry.data)?.size == CGSize(width: 480, height: 320))
        }
    }

    @Test func zipUntrustedLabelsCannotCreateTraversalPaths() throws {
        let dangerous = CameraWatermarkContext(projectName: "../Folder\\Sub:\nName", workSection: "../../\tEscape")
        let entries = try SimpleZipArchiveReader.read(WatermarkCameraBatchService.zip([photo(context: dangerous)], compression: 0.9))
        let entry = try #require(entries.first { $0.path != "metadata.json" })
        let components = entry.path.split(separator: "/")
        #expect(components.count == 3)
        #expect(!components.contains(".."))
        #expect(!components.contains("."))
        #expect(!entry.path.contains("\\"))
        #expect(!entry.path.contains("\n"))
        #expect(!entry.path.contains("\t"))
        #expect(WatermarkCameraBatchService.safeName("..") != "..")
        #expect(!WatermarkCameraBatchService.safeName(" \n ").isEmpty)
    }

    @Test func pdfContainsOnePagePerPhotoWithFrozenTitlesInSelectionOrder() throws {
        let first = photo(context: CameraWatermarkContext(projectName: "Frozen Project A"))
        let second = photo(context: CameraWatermarkContext(projectName: "Frozen Project B"))
        let data = try WatermarkCameraBatchService.pdf([second, first])
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)
        let firstPage = try #require(document.page(at: 0))
        let secondPage = try #require(document.page(at: 1))
        #expect(firstPage.string?.contains("Frozen Project B") == true)
        #expect(secondPage.string?.contains("Frozen Project A") == true)
        #expect(firstPage.string?.contains("1 / 2") == true)
        #expect(secondPage.string?.contains("2 / 2") == true)
        #expect(firstPage.bounds(for: .mediaBox).size == CGSize(width: 595, height: 842))
        #expect(secondPage.bounds(for: .mediaBox).size == CGSize(width: 595, height: 842))
    }

    @Test func missingPersistedImageFailsJPEGZIPAndPDFInsteadOfUsingThumbnail() throws {
        let nonexistent = FileManager.default.temporaryDirectory.appendingPathComponent("Missing-Watermark-\(UUID().uuidString)")
        let missing = WatermarkCapturedPhoto(
            image: image(), capturedAt: .now,
            context: CameraWatermarkContext(projectName: "Missing Original"),
            originalURL: nonexistent.appendingPathComponent("original.jpg"),
            watermarkedURL: nonexistent.appendingPathComponent("watermarked.jpg")
        )
        let valid = photo(context: CameraWatermarkContext(projectName: "Healthy"))
        #expect(throws: WatermarkDraftImageError.self) { try WatermarkCameraBatchService.jpeg(missing, compression: 0.9) }
        #expect(throws: WatermarkDraftImageError.self) { try WatermarkCameraBatchService.zip([valid, missing], compression: 0.9) }
        #expect(throws: WatermarkDraftImageError.self) { try WatermarkCameraBatchService.pdf([valid, missing]) }
    }

    @Test func emptySelectionCannotProduceEmptyDeliverable() throws {
        #expect(throws: WatermarkCameraBatchError.self) { try WatermarkCameraBatchService.zip([], compression: 0.9) }
        #expect(throws: WatermarkCameraBatchError.self) { try WatermarkCameraBatchService.pdf([]) }
    }

    @MainActor @Test func archiveIsIdempotentAndKeepsFrozenProjectAndCategory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WatermarkArchive-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Project(name: "Capture Site", location: "A")
        let other = Project(name: "Other Site", location: "B")
        store.replaceProjects([first, other])
        let source = photo(context: CameraWatermarkContext(projectName: first.name, template: .receipt), projectId: first.id)
        try await WatermarkCameraBatchService.archive(source, in: store)
        let document = try #require(store.projectDocuments.first { $0.id == source.id })
        defer { try? FileManager.default.removeItem(at: ProjectDocumentStorage.fileURL(for: document.fileName)) }
        try await WatermarkCameraBatchService.archive(source, in: store)
        #expect(store.projectDocuments.filter { $0.id == source.id }.count == 1)
        #expect(document.projectId == first.id)
        #expect(document.category == .receipt)
        #expect(ProjectDocumentStorage.exists(fileName: document.fileName))
        let reopened = DataStore(storageDirectory: directory)
        await reopened.awaitInitialLoad()
        #expect(reopened.projectDocuments.contains { $0.id == source.id && $0.projectId == first.id })
    }

    @MainActor @Test func archiveRejectsMissingProjectAndMissingExistingAttachment() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WatermarkArchiveMissing-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = Project(name: "Deleted Site", location: "")
        let source = photo(context: CameraWatermarkContext(projectName: project.name), projectId: project.id)
        await #expect(throws: WatermarkCameraBatchError.self) { try await WatermarkCameraBatchService.archive(source, in: store) }
        store.replaceProjects([project])
        store.appendProjectDocument(ProjectDocument(id: source.id, projectId: project.id, title: "Missing", fileName: "missing-\(UUID()).jpg"))
        await #expect(throws: WatermarkCameraBatchError.self) { try await WatermarkCameraBatchService.archive(source, in: store) }
    }

    private func photo(context: CameraWatermarkContext, projectId: UUID? = nil, capturedAt: Date = Date(timeIntervalSince1970: 1_770_000_000)) -> WatermarkCapturedPhoto {
        WatermarkCapturedPhoto(image: image(), capturedAt: capturedAt, context: context, projectId: projectId)
    }

    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 480, height: 320), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 480, height: 320))
        }
    }
}
