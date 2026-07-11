import Foundation
import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct ProjectPackageArchiveTests {
    @Test func packageSizeDecisionWarnsWithoutRejectingLargeExports() {
        #expect(ProjectDetailImportExportActions.packageSizeDecision(for: 0) == .normal)
        #expect(ProjectDetailImportExportActions.packageSizeDecision(for: ProjectDetailImportExportActions.largePackageWarningBytes) == .warn)
        #expect(ProjectDetailImportExportActions.packageSizeDecision(for: 10 * 1024 * 1024 * 1024) == .warn)
        #expect(StreamingZipArchiveWriter.requiresZip64ForTesting(
            entrySize: UInt64(UInt32.max) + 1,
            entryOffset: 0,
            entryCount: 1,
            centralSize: 128,
            centralOffset: 128
        ))
    }

    @Test func missingProjectPackageFilesReportsMissingAssets() {
        let projectId = UUID()
        let documents = [ProjectDocument(projectId: projectId, title: "发票", fileName: "missing-doc.pdf")]
        let drawings = [ProjectDrawing(projectId: projectId, name: "图纸A", fileName: "missing-drawing.pdf", fileType: "pdf")]
        let logs = [DailyLog(date: "2026-05-03", weather: "晴", content: "巡检", workers: "2", photos: [LogPhoto(fileName: "missing-photo.jpg", tag: .general)], projectId: projectId)]
        let quickNotes = [QuickNote(title: "补充资料", attachments: [QuickNoteAttachment(kind: .file, fileName: "missing-attachment.bin")])]

        let issues = ProjectDetailImportExportActions.missingProjectPackageFiles(
            documents: documents,
            drawings: drawings,
            logs: logs,
            quickNotes: quickNotes
        )

        #expect(issues.contains("资料 发票"))
        #expect(issues.contains("图纸 图纸A"))
        #expect(issues.contains("照片 2026-05-03 现场"))
        #expect(issues.contains(where: { $0.contains("随手记附件 补充资料") }))
    }

    @Test func projectPackageManifestUsesStableMachineKeys() throws {
        let preferenceStore = UserPreferencesStore.shared
        let backupKeys = [
            UserPreferenceKeys.localBackupLastSuccessAt,
            UserPreferenceKeys.cloudBackupLastSuccessAt,
            UserPreferenceKeys.backupHealthReminderDays
        ]
        let previousBackupValues = backupKeys.map { ($0, preferenceStore.object(for: $0)) }
        defer {
            for (key, value) in previousBackupValues {
                if let value {
                    if let boolValue = value as? Bool {
                        preferenceStore.set(boolValue, for: key)
                    } else if let intValue = value as? Int {
                        preferenceStore.set(intValue, for: key)
                    } else if let doubleValue = value as? Double {
                        preferenceStore.set(doubleValue, for: key)
                    } else if let stringValue = value as? String {
                        preferenceStore.set(stringValue, for: key)
                    } else if let stringArrayValue = value as? [String] {
                        preferenceStore.set(stringArrayValue, for: key)
                    } else if let dataValue = value as? Data {
                        preferenceStore.set(dataValue, for: key)
                    } else {
                        preferenceStore.removeObject(for: key)
                    }
                } else {
                    preferenceStore.removeObject(for: key)
                }
            }
        }
        preferenceStore.set(Date().timeIntervalSince1970, for: UserPreferenceKeys.localBackupLastSuccessAt)
        preferenceStore.removeObject(for: UserPreferenceKeys.cloudBackupLastSuccessAt)
        preferenceStore.set(7, for: UserPreferenceKeys.backupHealthReminderDays)

        let project = Project(name: "项目交付测试", location: "工地", status: .active)
        let archiveURL = try ReportBuilder.makeProjectPackageZIP(
            project: project,
            materials: [],
            quotes: [],
            labor: [],
            logs: [],
            tasks: [],
            todos: []
        )
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let entries = try SimpleZipArchiveReader.read(Data(contentsOf: archiveURL))
        let folder = "项目交付测试"
        let readmeEntry = try #require(entries.first { $0.path == "\(folder)/README.txt" })
        let readmeText = try #require(String(data: readmeEntry.data, encoding: .utf8))

        #expect(readmeText.contains("schema_version\t1"))
        #expect(readmeText.contains("package_type\tproject_delivery_package"))
        #expect(readmeText.contains("delivery_health_score\t80"))
        #expect(readmeText.contains("delivery_health_verdict\tnot_deliverable"))
        #expect(readmeText.contains("delivery_health_failed_checks\tdrawings"))
        #expect(readmeText.contains("delivery_health_backup_fresh\ttrue"))
        #expect(readmeText.contains("[contents]"))
        #expect(readmeText.contains("path\tkind_raw\tkind_display"))
        #expect(readmeText.contains("00-delivery/\(folder)_project_delivery_package.pdf\tproject_delivery_pdf\t"))
        #expect(readmeText.contains("00-delivery/delivery_checklist.txt\tdelivery_checklist\t"))
        #expect(readmeText.contains("00-delivery/pre_delivery_inspection.tsv\tpre_delivery_inspection\t"))
        #expect(readmeText.contains("00-delivery/document_checklist.tsv\tdocument_checklist\t"))
        #expect(readmeText.contains("document_checklist_missing_categories\t8"))
        let checklistEntry = try #require(entries.first { $0.path == "\(folder)/00-delivery/delivery_checklist.txt" })
        let checklistText = try #require(String(data: checklistEntry.data, encoding: .utf8))
        #expect(checklistText.contains("检查结论: 不可交付"))
        #expect(checklistText.contains("交付健康分: 80/100"))
        #expect(checklistText.contains("未通过项: 缺图纸"))
        #expect(checklistText.contains("4. 施工资料清单"))
        let documentChecklistEntry = try #require(entries.first { $0.path == "\(folder)/00-delivery/document_checklist.tsv" })
        let documentChecklistText = try #require(String(data: documentChecklistEntry.data, encoding: .utf8))
        #expect(documentChecklistText.contains("category_key\tcategory_display\tstatus_raw\tstatus_display\tdocument_count\taction_count\treturned_count\tarchived_count"))
        #expect(documentChecklistText.contains("construction_technical"))

        let inspectionEntry = try #require(entries.first { $0.path == "\(folder)/00-delivery/pre_delivery_inspection.tsv" })
        let inspectionText = try #require(String(data: inspectionEntry.data, encoding: .utf8))
        #expect(inspectionText.contains("check_key\tcheck_display\tstatus_raw\tstatus_display\tseverity"))
        #expect(inspectionText.contains("backup_freshness\t未备份\tpassed\t通过\tok"))
    }

    @Test func projectPackageOutputsDrawingDeliveryFiles() throws {
        let project = Project(name: "图纸交付测试", location: "工地", status: .active)
        var currentDrawing = try DrawingStorage.saveImportedDataOrThrow(
            data: Data([0x01, 0x02, 0x03]),
            sourceFileName: "A-101.pdf",
            projectId: project.id
        )
        var historicalDrawing = try DrawingStorage.saveImportedDataOrThrow(
            data: Data([0x04, 0x05]),
            sourceFileName: "A-101-old.pdf",
            projectId: project.id
        )
        defer {
            DrawingStorage.delete(fileName: currentDrawing.fileName)
            DrawingStorage.delete(fileName: historicalDrawing.fileName)
        }

        let todo = SiteTodo(
            title: "确认洞口尺寸",
            owner: "李工",
            dueDate: "2026-05-20",
            priority: .high,
            issueType: .quality,
            drawingIssueLocation: "一层 A/3 轴洞口",
            drawingIssueLayerOrPage: "PDF 第 3 页 / A-WALL",
            drawingIssueMeasurement: "洞口 900x2100，现场偏差 40mm",
            drawingIssueCloseEvidence: "复测合格后监理签字",
            projectId: project.id
        )
        currentDrawing.name = "一层平面"
        currentDrawing.drawingNumber = "A-101"
        currentDrawing.discipline = "建筑"
        currentDrawing.floorArea = "一层"
        currentDrawing.version = "V2"
        currentDrawing.isCurrentVersion = true
        currentDrawing.issueStatus = .open
        currentDrawing.issueNote = "洞口尺寸需确认"
        currentDrawing.linkedTodoIDs = [todo.id]
        historicalDrawing.name = "一层平面"
        historicalDrawing.drawingNumber = "A-101"
        historicalDrawing.discipline = "建筑"
        historicalDrawing.floorArea = "一层"
        historicalDrawing.version = "V1"
        historicalDrawing.isCurrentVersion = false
        let missingDrawing = ProjectDrawing(
            projectId: project.id,
            name: "缺失图纸",
            fileName: "missing-drawing-\(UUID().uuidString).pdf",
            fileType: "pdf",
            version: "V1",
            isCurrentVersion: true
        )

        let archiveURL = try ReportBuilder.makeProjectPackageZIP(
            project: project,
            materials: [],
            quotes: [],
            labor: [],
            logs: [],
            tasks: [],
            todos: [todo],
            drawings: [historicalDrawing, currentDrawing, missingDrawing]
        )
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let entries = try SimpleZipArchiveReader.read(Data(contentsOf: archiveURL))
        let folder = "图纸交付测试"
        let readmeEntry = try #require(entries.first { $0.path == "\(folder)/README.txt" })
        let readmeText = try #require(String(data: readmeEntry.data, encoding: .utf8))
        #expect(readmeText.contains("drawing_register_current_count\t2"))
        #expect(readmeText.contains("drawing_original_count\t3"))
        #expect(readmeText.contains("drawing_missing_original_count\t1"))
        #expect(readmeText.contains("drawing_open_issue_count\t1"))
        #expect(readmeText.contains("00-delivery/current_drawings.tsv\tcurrent_drawing_register\t"))
        #expect(readmeText.contains("00-delivery/drawing_missing_check.tsv\tdrawing_missing_check\t"))
        #expect(readmeText.contains("00-delivery/open_drawing_issues.tsv\topen_drawing_issues\t"))

        let currentEntry = try #require(entries.first { $0.path == "\(folder)/00-delivery/current_drawings.tsv" })
        let currentText = try #require(String(data: currentEntry.data, encoding: .utf8))
        #expect(currentText.contains("drawing_id\tdrawing_number\tname\tdiscipline\tfloor_area\tversion"))
        #expect(currentText.contains("A-101\t一层平面\t建筑\t一层\tV2"))
        #expect(!currentText.contains(historicalDrawing.fileName))

        let missingEntry = try #require(entries.first { $0.path == "\(folder)/00-delivery/drawing_missing_check.tsv" })
        let missingText = try #require(String(data: missingEntry.data, encoding: .utf8))
        #expect(missingText.contains("缺失图纸"))
        #expect(missingText.contains("\tmissing\t原件缺失\t"))

        let issueEntry = try #require(entries.first { $0.path == "\(folder)/00-delivery/open_drawing_issues.tsv" })
        let issueText = try #require(String(data: issueEntry.data, encoding: .utf8))
        #expect(issueText.contains("issue_location\tlayer_or_page\tmeasurement_result\tclose_evidence\tscreenshot_file_names\tclosing_evidence_file_names"))
        #expect(issueText.contains("洞口尺寸需确认"))
        #expect(issueText.contains("确认洞口尺寸"))
        #expect(issueText.contains("一层 A/3 轴洞口"))
        #expect(issueText.contains("PDF 第 3 页 / A-WALL"))
        #expect(issueText.contains("洞口 900x2100，现场偏差 40mm"))
        #expect(issueText.contains("复测合格后监理签字"))
        #expect(issueText.contains("李工"))

        #expect(entries.contains { $0.path == "\(folder)/02-drawings/一层平面-\(currentDrawing.fileName)" })
        #expect(entries.contains { $0.path == "\(folder)/02-drawings/一层平面-\(historicalDrawing.fileName)" })
    }

    @Test func projectPackageAuxiliaryTSVUsesMachineAndDisplayColumns() throws {
        let project = Project(name: "交付字段测试", location: "工地", status: .active)
        let contact = ProjectContact(projectId: project.id, name: "张工", role: .owner, company: "甲方", phone: "13800000000")
        let note = QuickNote(
            title: "现场备注",
            content: "",
            projectId: project.id,
            attachments: [
                QuickNoteAttachment(kind: .photo, fileName: "missing-photo.jpg"),
                QuickNoteAttachment(kind: .file, fileName: "missing-file.bin")
            ]
        )

        let archiveURL = try ReportBuilder.makeProjectPackageZIP(
            project: project,
            materials: [],
            quotes: [],
            labor: [],
            logs: [],
            tasks: [],
            todos: [],
            contacts: [contact],
            quickNotes: [note]
        )
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let entries = try SimpleZipArchiveReader.read(Data(contentsOf: archiveURL))
        let folder = "交付字段测试"
        let contactsEntry = try #require(entries.first { $0.path == "\(folder)/05-contacts/contacts.tsv" })
        let contactsText = try #require(String(data: contactsEntry.data, encoding: .utf8))
        #expect(contactsText.contains("name\trole_key\trole_display\tcompany\tphone\tnote"))
        #expect(contactsText.contains("\towner\t"))

        let quickNotesEntry = try #require(entries.first { $0.path == "\(folder)/04-quick-notes/quick_notes.tsv" })
        let quickNotesText = try #require(String(data: quickNotesEntry.data, encoding: .utf8))
        #expect(quickNotesText.contains("created_at\tcontent\tattachment_summary_raw\tattachment_summary_display"))
        #expect(quickNotesText.contains("photo:1,file:1"))
    }
}
