import Foundation

@MainActor
extension DataStore {
    func loadSampleFixtureSnapshot() -> BackupSnapshot? {
#if DEBUG
        do {
            // Keep the Codable boundary exercised without a disk or bundle fixture.
            let data = try JSONEncoder().encode(SyntheticSampleFixtureBuilder.makeSnapshot())
            return try JSONDecoder().decode(BackupSnapshot.self, from: data)
        } catch {
            StorageIssueLog.recordEvent(
                "sample_data.decode_failed",
                category: .dataStore,
                details: ["recipe": SyntheticSampleFixtureBuilder.recipeVersion],
                error: error
            )
            return nil
        }
#else
        return nil
#endif
    }

    func applySampleFixtureSnapshot(_ snapshot: BackupSnapshot) {
        applyLoadedSnapshot(snapshot)
        restoreSampleFixtureFiles(snapshot)
    }

    private func restoreSampleFixtureFiles(_ snapshot: BackupSnapshot) {
        PhotoStorage.restore(snapshot.photoFiles)
        DrawingStorage.restore(snapshot.drawingFiles)
        ProjectDocumentStorage.restore(snapshot.documentFiles)
        QuickNoteAttachmentStorage.restore(snapshot.quickNoteAttachmentFiles)
    }
}

#if DEBUG
/// Fully artificial data. No source files, app state, clock or external assets are inputs.
/// Kept in the existing source file so the checked-in Xcode project needs no new file reference.
enum SyntheticSampleFixtureBuilder {
    static let recipeVersion = "synthetic-fixture-v1"
    static let seed: UInt32 = 0x5EED2026
    private static let day = BusinessDateValue.day(CalendarDay(year: 2042, month: 3, day: 4)!)

    static func identifier(_ kind: Int, _ index: Int) -> UUID {
        precondition((1...65535).contains(kind) && (1...65535).contains(index))
        return UUID(uuidString: String(format: "%08x-%04x-4000-8000-%012x", seed, kind, index))!
    }

    static func makeSnapshot() -> BackupSnapshot {
        func project(_ i: Int) -> UUID { identifier(1, (i - 1) % 5 + 1) }
        func method(_ i: Int) -> UUID { identifier(18, (i - 1) % 5 + 1) }
        func label(_ name: String, _ i: Int) -> String { "虚构\(name)-\(i)" }
        func money(_ i: Int) -> MoneyValue { MoneyValue(Decimal(17 + 3 * i)) }
        func quantity(_ i: Int) -> QuantityValue { QuantityValue(Decimal(2 + i % 4)) }
        func phone(_ i: Int) -> String { "NON-DIALABLE-\(i)" }
        func file(_ category: String, _ i: Int, _ ext: String) -> String { "synth-v1-\(category)-\(i).\(ext)" }

        let photoFiles = (1...4).map { PhotoBackupFile(fileName: file("photo", $0, "png"), data: png($0)) }
        let drawingFiles = (1...3).map { DrawingBackupFile(fileName: file("drawing", $0, "pdf"), data: pdf($0)) }
        let documentFiles = (1...5).map { ProjectDocumentBackupFile(fileName: file("document", $0, "pdf"), data: pdf($0 + 3)) }
        let attachmentFiles = (1...3).map { QuickNoteAttachmentBackupFile(fileName: file("note", $0, "png"), data: png($0 + 4)) }

        let projects = (1...5).map { i in
            Project(id: project(i), name: label("项目", i), location: label("区域", i),
                    customerName: label("客户", i), customerPhone: phone(i), startDate: day,
                    expectedEndDate: .day(CalendarDay(year: 2042, month: 4, day: 4)!),
                    managerName: label("负责人", i), contractAmount: money(i + 20),
                    paidAmount: .zero, paymentStatus: .unpaid, materialCost: .zero, laborCost: .zero,
                    requiredDocumentCategories: [.constructionRecord], paymentPlans: [])
        }
        let materials = (1...10).map { i in
            MaterialItem(id: identifier(2, i), name: label("材料", i), quantity: quantity(i), unit: "件",
                         unitPrice: money(i), specification: "人工规格", brand: "虚构品牌",
                         supplier: label("供货方", (i - 1) % 6 + 1), arrivalDate: day, projectId: project(i))
        }
        let quotes = (1...8).map { i in
            QuoteItem(id: identifier(3, i), name: label("报价", i), unitPrice: money(i), quantity: quantity(i),
                      unit: "件", notes: "人工报价示例", taxRate: .zero, discountRate: .zero,
                      customerConfirmedDate: .empty, contractAmount: .zero, projectId: project(i))
        }
        let labor = (1...8).map { i in
            LaborRecord(id: identifier(4, i), date: day, workers: quantity(i), hours: 2,
                        workloadUnit: .hour, unitRate: money(i), workType: "人工工种",
                        teamName: label("班组", i), note: "人工用工示例", projectId: project(i))
        }
        let logs = (1...8).map { i in
            DailyLog(id: identifier(5, i), date: day, weather: "人工天气", content: label("施工记录", i),
                     workers: quantity(i), photoFileName: nil,
                     photos: [LogPhoto(id: identifier(20, i), fileName: photoFiles[(i - 1) % 4].fileName,
                                       note: "人工色块", tag: .general)],
                     linkedConstructionMethodIDs: [method(i)], projectId: project(i))
        }
        let tasks = (1...8).map { i in
            ProgressTask(id: identifier(6, i), projectId: project(i), title: label("进度", i),
                         startDate: day, dueDate: day, completion: Double(i % 3) / 2, note: "人工进度示例")
        }
        let todos = (1...8).map { i in
            SiteTodo(id: identifier(7, i), title: label("待办", i), owner: label("负责人", i), dueDate: day,
                     isDone: false, completedAt: nil, note: "人工待办示例",
                     linkedConstructionMethodIDs: [method(i)], projectId: project(i))
        }
        let drawings = (1...3).map { i in
            ProjectDrawing(id: identifier(8, i), projectId: project(i), name: label("图纸", i),
                           drawingNumber: "SYNTH-\(i)", fileName: drawingFiles[i - 1].fileName, fileType: "pdf",
                           issuedAt: day, relatedLogDate: day, linkedTodoIDs: [identifier(7, i)],
                           linkedLogIDs: [identifier(5, i)], linkedDocumentIDs: [identifier(10, i)],
                           fileAvailabilityStatus: .available, fileAvailabilityCheckedAt: day,
                           externalOpenFailedAt: .empty, importedAt: day, note: "人工矢量矩形，无真实图纸")
        }
        let contacts = (1...8).map { i in
            ProjectContact(id: identifier(9, i), projectId: project(i), relatedProjectIds: [],
                           name: label("联系人", i), role: .other, company: label("单位", i),
                           phone: phone(i), note: "actor-\(i)@example.invalid")
        }
        let documents = (1...5).map { i in
            ProjectDocument(id: identifier(10, i), projectId: project(i), title: label("文档", i),
                            category: .constructionRecord, fileName: documentFiles[i - 1].fileName,
                            fileType: "pdf", pageCount: 1, amount: money(i),
                            linkedFinancialRecordId: identifier(11, i), linkedConstructionMethodIDs: [method(i)],
                            responsiblePerson: label("负责人", i), formedAt: day,
                            archiveNumber: "SYNTH-DOC-\(i)", createdAt: day, note: "人工单页示例",
                            statusHistory: [], versionNumber: 1, versionState: .current,
                            replacesDocumentId: nil, replacedByDocumentId: nil)
        }
        let financial = (1...8).map { i in
            ProjectFinancialRecord(id: identifier(11, i), projectId: project(i), date: day,
                                   direction: .expense, category: .other, amount: money(i),
                                   counterparty: label("交易方", i), invoiceNumber: "",
                                   linkedDocumentIds: i <= 5 ? [identifier(10, i)] : [],
                                   status: .active, dueDate: .empty, reminderStatus: .none,
                                   note: "人工金额，不对应真实交易", origin: nil, paymentAllocation: nil)
        }
        let notes = (1...8).map { i in
            QuickNote(id: identifier(12, i), title: label("便签", i), content: "人工示例 https://fixture.example.invalid/notes/\(i)",
                      projectId: project(i), createdAt: day, updatedAt: day,
                      attachments: i <= 3 ? [QuickNoteAttachment(id: identifier(21, i), kind: .photo,
                                                              fileName: attachmentFiles[i - 1].fileName,
                                                              originalName: "人工色块-\(i).png", createdAt: day,
                                                              durationSeconds: nil)] : [])
        }
        let movements = (1...8).map { i in
            ProjectWarehouseMovement(id: identifier(13, i), projectId: project(i), date: day,
                                     movementType: .inbound, materialName: label("材料", i),
                                     specification: "人工规格", unit: "件", quantity: quantity(i),
                                     counterparty: label("供货方", (i - 1) % 6 + 1), handler: label("经办人", i),
                                     note: "人工入库示例", createdAt: day, origin: nil)
        }
        let prices = (1...9).map { i in
            MaterialPriceEntry(id: identifier(14, i), name: label("参考材料", i), unit: "件",
                               referencePrice: money(i), supplier: label("供货方", (i - 1) % 6 + 1),
                               note: "人工参考价", updatedAt: day)
        }
        let drafts = (1...4).map { i in
            MaterialSheetDraft(id: identifier(15, i), title: label("材料单", i), projectId: project(i),
                               exportProjectName: label("项目", i), exportPreparer: label("编制人", i), exportDate: day,
                               items: [MaterialSheetDraftItem(id: identifier(22, i), name: label("材料", i),
                                                              unit: "件", quantity: quantity(i), unitPrice: money(i),
                                                              laborCost: .zero, note: "人工草稿条目",
                                                              attachmentData: nil, attachmentFileName: nil)],
                               createdAt: day, updatedAt: day)
        }
        let suppliers = (1...6).map { i in
            SupplierProfile(id: identifier(16, i), name: label("供货方", i), contact: label("联系人", i),
                            phone: phone(i), address: label("区域", i), note: "人工供应商示例", updatedAt: day)
        }
        let methods = (1...5).map { i in
            ConstructionMethod(id: method(i), title: label("工法", i), trade: "人工工种", tutorialBody: "人工演示",
                               procedureSteps: ["演示步骤"], qualityChecklist: ["演示检查"], safetyChecklist: ["演示确认"],
                               sourceID: "synth-method-\(i)", sourceURL: "https://fixture.example.invalid/methods/\(i)",
                               sourceVersion: recipeVersion, sourceUpdatedAt: day, updatedAt: day)
        }
        return BackupSnapshot(
            schemaVersion: BackupSnapshot.currentSchemaVersion, appVersion: recipeVersion, appBuild: "0",
            backupCreatedAt: "2042-03-04T05:06:07Z", materialItems: materials, quoteItems: quotes, laborRecords: labor,
            projects: projects, dailyLogs: logs, historyRecords: [], progressTasks: tasks, siteTodos: todos,
            projectDrawings: drawings, projectContacts: contacts, projectFinancialRecords: financial,
            projectDocuments: documents, quickNotes: notes, projectWarehouseMovements: movements, templates: [],
            materialPriceEntries: prices, materialSheetDrafts: drafts, supplierProfiles: suppliers,
            constructionMethods: methods, favoriteMaterialKeys: [], recentMaterialKeys: [], userMaterials: [],
            deletedUserMaterials: [], hiddenPresetKeys: [], photoFiles: photoFiles, drawingFiles: drawingFiles,
            documentFiles: documentFiles, quickNoteAttachmentFiles: attachmentFiles, legacyDateProvenance: []
        )
    }

    /// PNG with uncompressed zlib/DEFLATE: reproducible bytes without encoder metadata or dependencies.
    private static func png(_ index: Int) -> Data {
        func word(_ value: UInt32) -> [UInt8] {
            [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
             UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        }
        func crc(_ bytes: [UInt8]) -> UInt32 {
            var value: UInt32 = 0xffffffff
            for byte in bytes {
                value ^= UInt32(byte)
                for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xedb88320 : 0) }
            }
            return value ^ 0xffffffff
        }
        func chunk(_ kind: String, _ bytes: [UInt8]) -> [UInt8] {
            let body = Array(kind.utf8) + bytes
            return word(UInt32(bytes.count)) + body + word(crc(body))
        }
        var raw: [UInt8] = []
        for y in 0..<8 {
            raw.append(0)
            for x in 0..<8 { raw += [UInt8((31 * index + 17 * x) % 256), UInt8((61 + 23 * y) % 256), (x+y)%2 == 0 ? 40 : 220, 255] }
        }
        let count = UInt16(raw.count)
        let complement = ~count
        var compressed: [UInt8] = [0x78, 0x01, 0x01, UInt8(truncatingIfNeeded: count), UInt8(count >> 8),
                                   UInt8(truncatingIfNeeded: complement), UInt8(complement >> 8)] + raw
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        compressed += word((b << 16) | a)
        return Data([137,80,78,71,13,10,26,10] + chunk("IHDR", word(8) + word(8) + [8,6,0,0,0])
                    + chunk("IDAT", compressed) + chunk("IEND", []))
    }

    /// Single-page vector PDF, generated from new integer coordinates with no imported content.
    private static func pdf(_ index: Int) -> Data {
        let stream = "0 0 1 RG 2 w \(12+index) 16 64 40 re S 12 16 m 76 56 l S\n"
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 96 80] /Resources << >> /Contents 4 0 R >>",
                       "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream"]
        var data = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(data.count)
            data.append(Data("\(index+1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let start = data.count
        data.append(Data("xref\n0 5\n0000000000 65535 f \n".utf8))
        for offset in offsets { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
        data.append(Data("trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n".utf8))
        return data
    }
}
#endif
