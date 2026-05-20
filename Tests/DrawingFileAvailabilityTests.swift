import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct DrawingFileAvailabilityTests {
    @Test func projectDrawingDecodesLegacyAvailabilityDefaults() throws {
        let projectID = UUID()
        let drawingID = UUID()
        let json = """
        {
          "id": "\(drawingID.uuidString)",
          "projectId": "\(projectID.uuidString)",
          "name": "总平图",
          "fileName": "site-plan.dwg",
          "fileType": "dwg"
        }
        """

        let drawing = try JSONDecoder().decode(ProjectDrawing.self, from: Data(json.utf8))

        #expect(drawing.fileAvailabilityStatus == .unknown)
        #expect(drawing.fileAvailabilityCheckedAt.isEmpty)
        #expect(drawing.externalOpenFailureReason.isEmpty)
        #expect(drawing.externalOpenFailedAt.isEmpty)
    }

    @Test func missingDrawingOpenPersistsAvailabilityFailure() throws {
        let store = DataStore()
        let drawing = ProjectDrawing(
            projectId: UUID(),
            name: "缺失图纸",
            fileName: "missing-\(UUID().uuidString).dwg",
            fileType: "dwg"
        )
        store.replaceProjectDrawings([drawing])

        let result = ProjectDetailAssetActions.previewDrawingURL(for: drawing, store: store)

        guard case .failure(let message) = result else {
            Issue.record("预期缺失图纸应打开失败")
            return
        }
        let updated = try #require(store.projectDrawings.first)
        #expect(updated.fileAvailabilityStatus == .missing)
        #expect(!updated.fileAvailabilityCheckedAt.isEmpty)
        #expect(updated.externalOpenFailureReason == message)
        #expect(!updated.externalOpenFailedAt.isEmpty)
    }

    @Test func externalOpenResultPersistsAndClearsFailureReason() throws {
        let store = DataStore()
        let drawing = ProjectDrawing(
            projectId: UUID(),
            name: "外部图纸",
            fileName: "external-\(UUID().uuidString).dxf",
            fileType: "dxf"
        )
        store.replaceProjectDrawings([drawing])

        ProjectDetailAssetActions.recordDrawingExternalOpenResult(
            completed: false,
            drawingID: drawing.id,
            store: store
        )

        var updated = try #require(store.projectDrawings.first)
        #expect(updated.fileAvailabilityStatus == .available)
        #expect(!updated.fileAvailabilityCheckedAt.isEmpty)
        #expect(!updated.externalOpenFailureReason.isEmpty)
        #expect(!updated.externalOpenFailedAt.isEmpty)

        ProjectDetailAssetActions.recordDrawingExternalOpenResult(
            completed: true,
            drawingID: drawing.id,
            store: store
        )

        updated = try #require(store.projectDrawings.first)
        #expect(updated.fileAvailabilityStatus == .available)
        #expect(updated.externalOpenFailureReason.isEmpty)
        #expect(updated.externalOpenFailedAt.isEmpty)
    }

    @Test func drawingAvailabilityFiltersRespectProjectAndSearchScope() throws {
        let projectID = UUID()
        let otherProjectID = UUID()
        let projects = [
            Project(id: projectID, name: "A 项目", location: ""),
            Project(id: otherProjectID, name: "B 项目", location: "")
        ]
        let missing = ProjectDrawing(
            projectId: projectID,
            name: "总平图",
            fileName: "site-plan.dwg",
            fileType: "dwg",
            fileAvailabilityStatus: .missing
        )
        let failedExternalOpen = ProjectDrawing(
            projectId: projectID,
            name: "消防图",
            fileName: "fire.dxf",
            fileType: "dxf",
            fileAvailabilityStatus: .available,
            externalOpenFailureReason: "未选择外部软件"
        )
        let unchecked = ProjectDrawing(
            projectId: projectID,
            name: "结构图",
            fileName: "structure.pdf",
            fileType: "pdf"
        )
        let historical = ProjectDrawing(
            projectId: projectID,
            name: "历史平面图",
            fileName: "old-plan.pdf",
            fileType: "pdf",
            isCurrentVersion: false,
            fileAvailabilityStatus: .available
        )
        let otherProjectMissing = ProjectDrawing(
            projectId: otherProjectID,
            name: "其他项目图纸",
            fileName: "other.dwg",
            fileType: "dwg",
            fileAvailabilityStatus: .missing
        )

        var model = DrawingListViewModel(
            projects: projects,
            drawings: [missing, failedExternalOpen, unchecked, historical, otherProjectMissing],
            selectedProjectID: projectID,
            searchText: "",
            recentDrawingIDs: [],
            availabilityFilter: .missing
        )

        #expect(model.count(for: .all) == 4)
        #expect(model.count(for: .current) == 3)
        #expect(model.count(for: .missing) == 1)
        #expect(model.count(for: .externalOpenFailed) == 1)
        #expect(model.count(for: .unchecked) == 1)
        #expect(model.filteredDrawings.map(\.id) == [missing.id])

        model.availabilityFilter = .externalOpenFailed
        #expect(model.filteredDrawings.map(\.id) == [failedExternalOpen.id])

        model.searchText = "总平"
        #expect(model.count(for: .all) == 1)
        #expect(model.count(for: .missing) == 1)
        #expect(model.count(for: .externalOpenFailed) == 0)
    }
}
