import Foundation
import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct ProjectPackageAndStorageTests {
    @Test func projectDocumentRecommendationFollowsProjectStage() throws {
        let referenceDate = try #require(Formatters.date.date(from: "2026-05-17"))
        let futureProject = Project(
            name: "开工前项目",
            location: "",
            status: .active,
            startDate: "2026-06-01"
        )
        let startedProject = Project(
            name: "施工中项目",
            location: "",
            status: .active,
            startDate: "2026-05-01"
        )
        let nearlyDoneTask = ProgressTask(
            projectId: startedProject.id,
            title: "收尾",
            startDate: "2026-05-01",
            dueDate: "2026-05-20",
            completion: 0.9,
            note: ""
        )
        let completedProject = Project(name: "完工项目", location: "", status: .completed)

        #expect(ProjectDocumentCategory.recommendedStage(
            for: futureProject,
            referenceDate: referenceDate
        ) == .preConstruction)
        #expect(ProjectDocumentCategory.recommendedStage(
            for: startedProject,
            referenceDate: referenceDate
        ) == .construction)
        #expect(ProjectDocumentCategory.recommendedStage(
            for: startedProject,
            progressTasks: [nearlyDoneTask],
            referenceDate: referenceDate
        ) == .acceptance)
        #expect(ProjectDocumentCategory.recommendedStage(
            for: completedProject,
            referenceDate: referenceDate
        ) == .acceptance)
    }

    @Test func projectDocumentRecommendationCategoriesMatchConstructionStages() {
        #expect(ProjectDocumentCategory.recommendedConstructionArchiveRequirements(for: .preConstruction) == [
            .constructionTechnical,
            .constructionManagement
        ])
        #expect(ProjectDocumentCategory.recommendedConstructionArchiveRequirements(for: .construction) == [
            .constructionMaterial,
            .constructionSurvey,
            .constructionRecord,
            .constructionTest
        ])
        #expect(ProjectDocumentCategory.recommendedConstructionArchiveRequirements(for: .acceptance) == [
            .processAcceptance,
            .completionAcceptance
        ])
    }

    @Test func projectDocumentChecklistPresetsProvideReusableProjectTypeTemplates() {
        let presets = ProjectDocumentChecklistTemplate.builtInPresets

        #expect(presets.map(\.name) == ["土建", "装饰", "机电", "消防"])
        #expect(presets.first(where: { $0.name == "土建" })?.categories == ProjectDocumentCategory.defaultConstructionArchiveRequirements)
        #expect(presets.first(where: { $0.name == "装饰" })?.categories.contains(.constructionSurvey) == false)
        #expect(presets.allSatisfy { !$0.categories.isEmpty })
    }

    @Test func projectDocumentChecklistTemplateParsesSavedProjectTemplate() throws {
        let template = ProjectTemplate.documentChecklistTemplate(
            name: "机电复用模板",
            categories: [.completionAcceptance, .constructionMaterial, .constructionRecord]
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(ProjectTemplate.self, from: data)

        #expect(decoded.category == .projectDocumentChecklist)
        #expect(decoded.documentChecklistCategories == [
            .constructionMaterial,
            .constructionRecord,
            .completionAcceptance
        ])
        let customTemplates = ProjectDocumentChecklistTemplate.customTemplates(from: [decoded])
        let customTemplate = try #require(customTemplates.first)
        #expect(customTemplate.name == "机电复用模板")
        #expect(customTemplate.categories == decoded.documentChecklistCategories)
    }

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

    @Test func projectDeliveryInspectionReportsChecklistAndLedgerIssues() {
        let projectId = UUID()
        let project = Project(
            id: projectId,
            name: "交付项目",
            location: "",
            requiredDocumentCategories: [.constructionTechnical, .completionAcceptance]
        )
        let returnedDocument = ProjectDocument(
            projectId: projectId,
            title: "施工方案",
            category: .constructionTechnical,
            fileName: "missing-\(UUID().uuidString).pdf",
            submissionStatus: .returned,
            createdAt: "2026-05-17 10:00"
        )
        let unarchivedDocument = ProjectDocument(
            projectId: projectId,
            title: "材料报验",
            category: .constructionMaterial,
            fileName: "",
            submissionStatus: .submitted,
            responsiblePerson: "王工",
            formedAt: "2026-05-01",
            createdAt: "2026-05-17 09:00"
        )

        let inspection = ProjectDocumentDeliveryInspection(
            project: project,
            documents: [returnedDocument, unarchivedDocument],
            drawings: [],
            logs: [],
            quickNotes: []
        )

        #expect(inspection.missingCategories == [.completionAcceptance])
        #expect(inspection.missingFiles.contains("资料 施工方案"))
        #expect(inspection.returnedDocuments.map(\.title) == ["施工方案"])
        #expect(inspection.unarchivedDocuments.map(\.title) == ["施工方案", "材料报验"])
        #expect(inspection.missingResponsibleDocuments.map(\.title) == ["施工方案"])
        #expect(inspection.missingFormedDateDocuments.map(\.title) == ["施工方案"])
        #expect(inspection.issues.map(\.kind) == [
            .missingCategories,
            .missingFiles,
            .returnedDocuments,
            .unarchivedDocuments,
            .missingResponsiblePerson,
            .missingFormedDate
        ])
        #expect(ProjectDocumentDeliveryInspectionIssueKind.missingFormedDate.preferredHealthFilter == .incompleteDocumentLedger)
        #expect(ProjectDocumentDeliveryInspectionIssueKind.returnedDocuments.preferredCategory == .documents)

        let csv = String(decoding: ProjectDocumentDeliveryInspectionExport.csvData(for: [inspection]), as: UTF8.self)
        #expect(csv.contains("缺类别"))
        #expect(csv.contains("文件丢失"))
        #expect(csv.contains("退回修改"))
        #expect(csv.contains("未归档"))
        #expect(csv.contains("缺责任人"))
        #expect(csv.contains("缺形成日期"))
        #expect(ProjectDocumentDeliveryInspectionExport.pdfData(for: [inspection]).starts(with: Data("%PDF".utf8)))

        let todoTitles = inspection.remediationTodoDrafts.map(\.title)
        #expect(todoTitles.contains("补齐交付缺失文件：资料 施工方案"))
        #expect(todoTitles.contains("处理退回资料：施工方案"))
        #expect(todoTitles.contains("归档项目资料：材料报验"))
        #expect(todoTitles.contains("补录资料责任人：施工方案"))
        #expect(todoTitles.contains("补录资料形成日期：施工方案"))
    }

    @Test func projectFileHealthFilterMatchesIncompleteDocumentLedger() {
        let item = ProjectFileItem(
            id: "document-ledger",
            title: "施工方案",
            subtitle: "施工技术",
            fileType: "pdf",
            url: URL(fileURLWithPath: "/tmp/document-ledger.pdf"),
            exists: true,
            size: 1_024,
            category: .documents,
            systemImage: "doc.richtext",
            thumbnailToken: nil,
            sortDate: Date(),
            documentStatus: .submitted,
            documentLedgerIssueCount: 1
        )

        #expect(ProjectFileHealthFilter.incompleteDocumentLedger.matches(item))
        #expect(!ProjectFileHealthFilter.missing.matches(item))
    }

    @Test func projectDocumentStatusHistoryPersistsAndLegacyDecodeDefaultsEmpty() throws {
        let projectId = UUID()
        let entryId = UUID()
        let changedAt = "2026-05-17 10:30"
        let document = ProjectDocument(
            projectId: projectId,
            title: "施工方案",
            fileName: "method.pdf",
            submissionStatus: .submitted,
            statusHistory: [
                ProjectDocumentStatusHistoryEntry(
                    id: entryId,
                    fromStatus: .pending,
                    toStatus: .submitted,
                    operatorName: "张工",
                    changedAt: changedAt,
                    reason: "报验完成"
                )
            ],
            versionNumber: 2,
            versionState: .superseded,
            replacesDocumentId: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            replacedByDocumentId: UUID(uuidString: "00000000-0000-0000-0000-000000000003")
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: data)

        #expect(decoded.versionNumber == 2)
        #expect(decoded.versionState == .superseded)
        #expect(decoded.replacesDocumentId == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        #expect(decoded.replacedByDocumentId == UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        #expect(decoded.statusHistory.count == 1)
        let entry = try #require(decoded.statusHistory.first)
        #expect(entry.id == entryId)
        #expect(entry.fromStatus == .pending)
        #expect(entry.toStatus == .submitted)
        #expect(entry.operatorName == "张工")
        #expect(entry.changedAt == changedAt)
        #expect(entry.reason == "报验完成")

        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "projectId": "\(projectId.uuidString)",
          "title": "旧资料",
          "category": "施工记录",
          "fileName": "legacy.pdf"
        }
        """
        let legacyDocument = try JSONDecoder().decode(ProjectDocument.self, from: Data(legacyJSON.utf8))
        #expect(legacyDocument.statusHistory.isEmpty)
        #expect(legacyDocument.versionNumber == 1)
        #expect(legacyDocument.versionState == .current)
        #expect(legacyDocument.replacesDocumentId == nil)
        #expect(legacyDocument.replacedByDocumentId == nil)
    }

    @Test func projectDocumentVersionReplacementMarksPreviousVersion() throws {
        let store = DataStore()
        let projectId = UUID()
        let original = ProjectDocument(
            projectId: projectId,
            title: "施工方案",
            fileName: "method-v1.pdf",
            versionNumber: 1
        )
        let replacement = ProjectDocument(
            projectId: projectId,
            title: "施工方案",
            fileName: "method-v2.pdf",
            versionNumber: 1,
            replacesDocumentId: original.id
        )
        store.replaceProjectDocuments([original, replacement])

        ProjectDetailFinanceDocumentActions.saveDocumentEdit(replacement, store: store)

        let savedOriginal = try #require(store.projectDocuments.first { $0.id == original.id })
        let savedReplacement = try #require(store.projectDocuments.first { $0.id == replacement.id })
        #expect(savedReplacement.versionNumber == 2)
        #expect(savedReplacement.replacesDocumentId == original.id)
        #expect(savedOriginal.replacedByDocumentId == replacement.id)
        #expect(savedOriginal.versionState == .superseded)

        var detachedReplacement = savedReplacement
        detachedReplacement.replacesDocumentId = nil
        ProjectDetailFinanceDocumentActions.saveDocumentEdit(detachedReplacement, store: store)

        let detachedOriginal = try #require(store.projectDocuments.first { $0.id == original.id })
        let savedDetachedReplacement = try #require(store.projectDocuments.first { $0.id == replacement.id })
        #expect(savedDetachedReplacement.replacesDocumentId == nil)
        #expect(detachedOriginal.replacedByDocumentId == nil)
        #expect(detachedOriginal.versionState == .current)
    }

    @Test func projectDeliveryHealthSummarizesDeliverabilityBlockers() throws {
        let referenceDate = try #require(Formatters.dateTime.date(from: "2026-05-16 12:00"))
        let backupState = ProjectDeliveryBackupState(
            latestBackupDate: nil,
            reminderDays: 7,
            referenceDate: referenceDate
        )

        let health = ProjectDeliveryHealth(
            missingReceiptCount: 2,
            drawingCount: 0,
            openTodoCount: 3,
            backupState: backupState,
            missingOriginalCount: 1,
            drawingWithoutCurrentCount: 1
        )

        #expect(health.score == 0)
        #expect(!health.isDeliverable)
        #expect(health.failedIssues == ProjectDeliveryHealth.Issue.allCases)
        #expect(health.summary.contains("缺票据"))
        #expect(health.summary.contains("未备份"))
    }

    @Test func projectDeliveryHealthPassesWhenCoreDeliveryChecksPass() throws {
        let referenceDate = try #require(Formatters.dateTime.date(from: "2026-05-16 12:00"))
        let latestBackup = try #require(Formatters.dateTime.date(from: "2026-05-15 09:00"))
        let backupState = ProjectDeliveryBackupState(
            latestBackupDate: latestBackup,
            reminderDays: 7,
            referenceDate: referenceDate
        )

        let health = ProjectDeliveryHealth(
            missingReceiptCount: 0,
            drawingCount: 2,
            openTodoCount: 0,
            backupState: backupState,
            missingOriginalCount: 0,
            drawingWithoutCurrentCount: 0
        )

        #expect(health.score == 100)
        #expect(health.isDeliverable)
        #expect(health.failedIssues.isEmpty)
    }

    @Test func photoStorageThrowsForInvalidImageData() {
        do {
            _ = try PhotoStorage.saveOrThrow(original: Data([0x00, 0x11]), fileName: "invalid-\(UUID().uuidString).jpg")
            Issue.record("无效图片数据不应保存成功")
        } catch let error as FileStorageError {
            #expect(error == .invalidImageData)
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    @Test func photoStorageKeepsOriginalFileAndThumbnail() throws {
        let original = try Self.makeJPEGData()
        let fileName = "original-\(UUID().uuidString).jpg"
        let saved = try PhotoStorage.saveOrThrow(original: original, fileName: fileName)
        defer { PhotoStorage.delete(fileName: saved) }

        let stored = try Data(contentsOf: PhotoStorage.fileURL(for: saved))
        #expect(stored == original)
        #expect(PhotoStorage.fileSize(for: saved) == original.count)
        #expect(FileManager.default.fileExists(atPath: PhotoStorage.thumbnailURL(for: saved).path))
    }

    @Test func estimatedProjectPackageBytesUsesStoredFileSizes() throws {
        let projectId = UUID()
        let documentFile = try ProjectDocumentStorage.savePDFOrThrow(data: Data([0x01, 0x02, 0x03, 0x04]), projectId: projectId)
        let drawingSourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-\(UUID().uuidString).pdf")
        try Data([0x05, 0x06, 0x07]).write(to: drawingSourceURL, options: .atomic)
        let drawing = try DrawingStorage.saveImportedFileOrThrow(from: drawingSourceURL, projectId: projectId)
        let photoFile = try PhotoStorage.saveOrThrow(original: Self.makeJPEGData(), fileName: "photo-\(UUID().uuidString).jpg")
        let attachmentFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x08, 0x09, 0x0A, 0x0B, 0x0C]), fileName: "attachment-\(UUID().uuidString).bin")

        defer {
            ProjectDocumentStorage.delete(fileName: documentFile)
            DrawingStorage.delete(fileName: drawing.fileName)
            PhotoStorage.delete(fileName: photoFile)
            QuickNoteAttachmentStorage.delete(fileName: attachmentFile)
            try? FileManager.default.removeItem(at: drawingSourceURL)
        }

        let documents = [ProjectDocument(projectId: projectId, title: "票据", fileName: documentFile)]
        let drawings = [drawing]
        let logs = [DailyLog(date: "2026-05-03", weather: "晴", content: "完成", workers: "1", photos: [LogPhoto(fileName: photoFile)], projectId: projectId)]
        let quickNotes = [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: attachmentFile)])]

        let estimated = ProjectDetailImportExportActions.estimatedProjectPackageBytes(
            documents: documents,
            drawings: drawings,
            logs: logs,
            quickNotes: quickNotes
        )
        let expected = ProjectDocumentStorage.fileSize(for: documentFile)
            + DrawingStorage.fileSize(for: drawing.fileName)
            + PhotoStorage.fileSize(for: photoFile)
            + QuickNoteAttachmentStorage.fileSize(for: attachmentFile)

        #expect(estimated == expected)
        #expect(estimated > 0)
    }

    @Test func projectPackageManifestUsesStableMachineKeys() throws {
        let defaults = UserDefaults.standard
        let backupKeys = [
            UserPreferenceKeys.localBackupLastSuccessAt,
            UserPreferenceKeys.cloudBackupLastSuccessAt,
            UserPreferenceKeys.backupHealthReminderDays
        ]
        let previousBackupValues = backupKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in previousBackupValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set(Date().timeIntervalSince1970, forKey: UserPreferenceKeys.localBackupLastSuccessAt)
        defaults.removeObject(forKey: UserPreferenceKeys.cloudBackupLastSuccessAt)
        defaults.set(7, forKey: UserPreferenceKeys.backupHealthReminderDays)

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

    @Test func siteTodoDecodesLegacyDrawingIssueFieldsAsEmpty() throws {
        let data = Data("""
        {
          "title": "旧待办",
          "owner": "李工",
          "dueDate": "2026-05-20",
          "priority": "高",
          "issueType": "质量"
        }
        """.utf8)

        let todo = try JSONDecoder().decode(SiteTodo.self, from: data)

        #expect(todo.drawingIssueLocation.isEmpty)
        #expect(todo.drawingIssueLayerOrPage.isEmpty)
        #expect(todo.drawingIssueMeasurement.isEmpty)
        #expect(todo.drawingIssueCloseEvidence.isEmpty)
    }

    @Test func preDeliveryInspectionTSVListsActionableIssues() throws {
        let project = Project(name: "交付体检", location: "工地", status: .active)
        let missingDrawing = ProjectDrawing(
            projectId: project.id,
            name: "一层平面",
            fileName: "missing-current-\(UUID().uuidString).pdf",
            fileType: "pdf",
            version: "V1",
            isCurrentVersion: false
        )
        let todo = SiteTodo(
            title: "整改收口",
            owner: "李工",
            dueDate: "2026-05-20",
            priority: .high,
            issueType: .quality,
            projectId: project.id
        )
        let financialRecord = ProjectFinancialRecord(
            projectId: project.id,
            date: "2026-05-19",
            direction: .expense,
            category: .material,
            amount: "1200",
            counterparty: "材料商"
        )
        let backupState = ReportBuilder.ProjectDeliveryPackageBackupState(
            latestBackupDate: nil,
            reminderDays: 7,
            referenceDate: Date()
        )

        let text = ReportBuilder.projectPreDeliveryInspectionTSVText(
            project: project,
            financialRecords: [financialRecord],
            documents: [],
            drawings: [missingDrawing],
            todos: [todo],
            logs: [],
            quickNotes: [],
            backupState: backupState
        )

        #expect(text.contains("missing_drawing_original\t缺图纸原件\tfailed\t未通过\tblocker\tdrawing"))
        #expect(text.contains("open_todo\t未结待办\tfailed\t未通过\tblocker\ttodo"))
        #expect(text.contains("missing_receipt\t缺票据\tfailed\t未通过\twarning\tfinancial_record"))
        #expect(text.contains("backup_freshness\t未备份\tfailed\t未通过\twarning\tproject"))
        #expect(text.contains("missing_current_drawing_version\t当前版缺失\tfailed\t未通过\twarning\tdrawing_group"))
        #expect(text.contains("在图纸台账中确认最终版本"))
    }

    @Test func projectPackageAuxiliaryTSVUsesMachineAndDisplayColumns() throws {
        let project = Project(name: "交付字段测试", location: "工地", status: .active)
        let contact = ProjectContact(projectId: project.id, name: "张工", role: .owner, company: "甲方", phone: "00000000000")
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

    @Test func warehouseMovementLinkedDocumentsAreBackwardCompatible() throws {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "projectId": "00000000-0000-0000-0000-000000000002",
          "date": "2026-05-03",
          "movementType": "入库",
          "materialName": "电线",
          "specification": "BV 2.5",
          "unit": "卷",
          "quantity": "10",
          "counterparty": "供应商",
          "handler": "张三",
          "note": "旧数据",
          "createdAt": "2026-05-03 10:00"
        }
        """.data(using: .utf8)!

        let legacyMovement = try JSONDecoder().decode(ProjectWarehouseMovement.self, from: legacyJSON)
        #expect(legacyMovement.linkedDocumentIds.isEmpty)

        var movement = legacyMovement
        let documentId = UUID()
        movement.linkedDocumentIds = [documentId]
        let data = try JSONEncoder().encode(movement)
        let restored = try JSONDecoder().decode(ProjectWarehouseMovement.self, from: data)

        #expect(restored.linkedDocumentIds == [documentId])
    }

    @Test func warehouseAttachmentImportRejectsOversizedFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("warehouse-oversize-\(UUID().uuidString).bin")
        _ = FileManager.default.createFile(atPath: tempURL.path, contents: Data([0x01]))
        let handle = try FileHandle(forWritingTo: tempURL)
        try handle.truncate(atOffset: UInt64(ImportLimitPolicy.maxImportBytes + 1))
        try handle.close()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let movement = ProjectWarehouseMovement(
            projectId: UUID(),
            movementType: .inbound,
            materialName: "测试材料",
            unit: "个",
            quantity: "1"
        )
        let draft = ProjectWarehouseAttachmentDraft(fileURL: tempURL, title: "超大附件")

        let result = ProjectWarehouseAttachmentImporter.importAttachments(
            [draft],
            movement: movement,
            store: DataStore()
        )

        #expect(result.documents.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].contains("文件"))
        #expect(result.failures[0].contains("过大"))
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
