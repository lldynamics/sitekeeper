import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct BackupContractCompatibilityTests {
    @Test func legacyBackupWithoutSchemaVersionIsRejected() throws {
        let legacyJSON = """
        {
          "projects": [
            {
              "id": "\(UUID().uuidString)",
              "name": "旧备份项目",
              "status": "进行中"
            }
          ],
          "paymentRecords": []
        }
        """

        do {
            _ = try JSONDecoder().decode(BackupSnapshot.self, from: Data(legacyJSON.utf8))
            Issue.record("预期应拒绝缺少 schemaVersion 的旧备份")
        } catch is DecodingError {
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    @Test func currentBackupIgnoresRemovedPaymentRecordsAndKeepsDrawingReference() throws {
        let projectID = UUID()
        let drawingID = UUID()
        let currentJSON = """
        {
          "schemaVersion": 2,
          "projects": [
            {
              "id": "\(projectID.uuidString)",
              "name": "当前备份项目",
              "status": "进行中"
            }
          ],
          "projectDrawings": [
            {
              "id": "\(drawingID.uuidString)",
              "projectId": "\(projectID.uuidString)",
              "name": "图纸",
              "fileName": "plan.pdf",
              "fileType": "pdf"
            }
          ],
          "paymentRecords": [
            {
              "projectId": "\(projectID.uuidString)",
              "date": "2025-04-09",
              "amount": "100",
              "method": "bankTransfer",
              "note": "首款",
              "isInvoiced": false
            }
          ]
        }
        """

        let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: Data(currentJSON.utf8))
        #expect(snapshot.schemaVersion == BackupSnapshot.currentSchemaVersion)

        let store = makeStore()
        store.applyLoadedSnapshot(snapshot)

        #expect(store.projects.count == 1)
        #expect(store.projectDrawings.count == 1)
        #expect(store.projectDrawings.first?.fileName == "plan.pdf")
        #expect(store.projectDrawings.first?.fileAvailabilityStatus == .unknown)
        #expect(store.projectFinancialRecords.isEmpty)
    }

    @Test func backupImportIgnoresFutureFieldsAndPreservesKnownDrawingFields() throws {
        let projectID = UUID()
        let drawingID = UUID()
        let futureJSON = """
        {
          "schemaVersion": 2,
          "futureTopLevelField": {
            "engine": "native-v3"
          },
          "projects": [
            {
              "id": "\(projectID.uuidString)",
              "name": "未来字段项目",
              "status": "进行中",
              "futureProjectField": "ignored"
            }
          ],
          "projectDrawings": [
            {
              "id": "\(drawingID.uuidString)",
              "projectId": "\(projectID.uuidString)",
              "name": "总平图",
              "fileName": "p0-floor.dwg",
              "fileType": "dwg",
              "futureDrawingField": {
                "atlasVersion": 3
              }
            }
          ],
          "drawingFiles": [
            {
              "fileName": "p0-floor.dwg",
              "data": "AQID",
              "futureChecksum": "sha256:123"
            }
          ]
        }
        """

        let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: Data(futureJSON.utf8))
        #expect(snapshot.projects.count == 1)
        #expect(snapshot.projectDrawings.count == 1)
        #expect(snapshot.projectDrawings.first?.fileName == "p0-floor.dwg")
        #expect(snapshot.drawingFiles.count == 1)
        #expect(snapshot.drawingFiles.first?.data == Data([0x01, 0x02, 0x03]))

        let store = makeStore()
        store.applyLoadedSnapshot(snapshot)

        let drawing = try #require(store.projectDrawings.first)
        #expect(drawing.projectId == projectID)
        #expect(drawing.fileName == "p0-floor.dwg")
        #expect(drawing.fileType == "dwg")
        #expect(drawing.drawingNumber.isEmpty)
        #expect(drawing.discipline.isEmpty)
        #expect(drawing.floorArea.isEmpty)
        #expect(drawing.issuedAt.isEmpty)
        #expect(drawing.receiver.isEmpty)
        #expect(drawing.linkedTodoIDs.isEmpty)
        #expect(drawing.linkedLogIDs.isEmpty)
        #expect(drawing.linkedDocumentIDs.isEmpty)
        #expect(drawing.fileAvailabilityStatus == .unknown)
        #expect(drawing.externalOpenFailureReason.isEmpty)
    }

    @Test func overwriteImportReplacesDrawingFileReferences() {
        let projectID = UUID()
        let store = makeStore()
        let project = Project(
            id: projectID,
            name: "图纸覆盖项目",
            location: "",
            status: .active,
            startDate: "2025-01-01",
            expectedEndDate: "2025-12-31"
        )

        let oldDrawing = ProjectDrawing(
            projectId: projectID,
            name: "旧版本",
            fileName: "old-version.dwg",
            fileType: "dwg"
        )
        store.replaceProjects([project])
        store.replaceProjectDrawings([oldDrawing])

        let importedDrawing = ProjectDrawing(
            projectId: projectID,
            name: "新版本",
            fileName: "new-version.dwg",
            fileType: "dwg"
        )
        let importedSnapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [project],
            dailyLogs: [],
            historyRecords: [],
            projectDrawings: [importedDrawing],
            templates: []
        )

        BackupImportCoordinator.applyImportMetadata(
            snapshot: importedSnapshot,
            mode: .overwrite,
            store: store
        )

        #expect(store.projectDrawings.count == 1)
        #expect(store.projectDrawings.first?.fileName == "new-version.dwg")
        #expect(!store.projectDrawings.contains { $0.fileName == "old-version.dwg" })
    }

    private func makeStore() -> DataStore {
        TransferLimitPolicy.setRuntimeProfileOverride(.development)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupContractCompatibilityTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        store.clearAllBusinessData(deleteStoredFiles: false)
        return store
    }
}
