import Foundation
import Testing
@testable import sitekeeper

struct RepositoryTestFixture {
    let directory: URL
    let source: URL
    let snapshot: BackupSnapshot
    let raw: Data
    let assets: [RepositoryAssetFamily: URL]

    init(snapshot: BackupSnapshot? = nil, version: Int = 3) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("repository-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("sitekeeper.json")
        var value = snapshot ?? Self.sample()
        value.schemaVersion = version
        self.snapshot = value
        raw = try JSONEncoder().encode(value)
        try raw.write(to: source)
        var roots: [RepositoryAssetFamily: URL] = [:]
        for family in RepositoryAssetFamily.allCases {
            let root = directory.appendingPathComponent(family.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            roots[family] = root
        }
        assets = roots
        // Synthetic file content only; no real app storage is read or changed.
        let dataset = try RepositoryDataset(snapshot: value)
        for row in dataset.records.values.flatMap({ $0 }) {
            for reference in try RepositoryDataset.attachments(for: row) {
                try Data("fixture-\(reference.family.rawValue)-\(reference.fileName)".utf8)
                    .write(to: roots[reference.family]!.appendingPathComponent(reference.fileName))
            }
        }
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }

    func candidate(options: SQLiteCandidateOptions = SQLiteCandidateOptions()) async throws -> SQLiteCandidateBuilder.Result {
        try await SQLiteCandidateBuilder().build(sourceURL: source, assetDirectories: assets, options: options)
    }

    func repository(sqlite: Bool) async throws -> any BusinessRepository {
        if sqlite { return try SQLiteBusinessRepository(candidateDirectory: try await candidate().directory) }
        return try JSONSnapshotRepository(snapshot: snapshot)
    }

    static func sample() -> BackupSnapshot {
        let project = Project(name: "候选库项目", location: "合成数据", startDate: BusinessDateValue(legacyText: "2026-10-24"), contractAmount: NumericInputSupport.money("123456.78"))
        let other = Project(name: "另一个项目", location: "")
        let document = ProjectDocument(projectId: project.id, title: "票据", fileName: "receipt.pdf")
        let method = ConstructionMethod(title: "工法", attachments: [QuickNoteAttachment(kind: .file, fileName: "method.pdf")])
        let logs = (0..<5).map { index in
            DailyLog(date: BusinessDateValue(legacyText: "2026-10-24"), weather: "晴", content: "日志 \(index) " + String(repeating: "正文", count: 100), workers: NumericInputSupport.quantity("2"),
                     photoFileName: "shared.jpg", linkedConstructionMethodIDs: [method.id], projectId: project.id)
        }
        var result = BackupSnapshot(materialItems: [MaterialItem(name: "线缆", quantity: NumericInputSupport.quantity("2.5"), unit: "米", unitPrice: NumericInputSupport.money("3.12"), projectId: project.id)],
            quoteItems: [QuoteItem(name: "报价", unitPrice: NumericInputSupport.money("2.35"), quantity: NumericInputSupport.quantity("3"), unit: "项", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("0"), projectId: project.id)],
            laborRecords: [LaborRecord(date: BusinessDateValue(legacyText: "2026-10-24"), workers: NumericInputSupport.quantity("2"), hours: NumericInputSupport.quantity("8"), unitRate: NumericInputSupport.money("12.34"), note: "", projectId: project.id)],
            projects: [project, other], dailyLogs: logs,
            historyRecords: [HistoryRecord(tool: "工具", input: "输入", result: "历史", date: BusinessDateValue(legacyText: "2026-10-24"), projectId: UUID())],
            progressTasks: [ProgressTask(projectId: project.id, title: "进度", startDate: BusinessDateValue(legacyText: "2026-10-24"), dueDate: BusinessDateValue(legacyText: "2026-10-25"), completion: 0, note: "")],
            siteTodos: [SiteTodo(title: "验收", projectId: project.id)],
            projectContacts: [ProjectContact(projectId: project.id, relatedProjectIds: [other.id], name: "共享往来单位")],
            projectFinancialRecords: [
                ProjectFinancialRecord(projectId: project.id, direction: .income, amount: NumericInputSupport.money("0.10"), linkedDocumentIds: [document.id]),
                ProjectFinancialRecord(projectId: project.id, direction: .income, amount: NumericInputSupport.money("0.20")),
                ProjectFinancialRecord(projectId: project.id, direction: .expense, amount: NumericInputSupport.money("100.01"))
            ], projectDocuments: [document],
            quickNotes: [QuickNote(content: "随手记", projectId: project.id, attachments: [QuickNoteAttachment(kind: .file, fileName: "note.pdf")])],
            projectWarehouseMovements: [ProjectWarehouseMovement(projectId: project.id, materialName: "线缆", quantity: NumericInputSupport.quantity("2.5"), linkedDocumentIds: [document.id])],
            templates: [ProjectTemplate(name: "模板", category: .dailyLog, content: "模板内容")],
            materialPriceEntries: [MaterialPriceEntry(name: "线缆", referencePrice: NumericInputSupport.money("3.12"))],
            materialSheetDrafts: [MaterialSheetDraft(title: "材料单", projectId: project.id)],
            supplierProfiles: [SupplierProfile(name: "供应商")], constructionMethods: [method],
            favoriteMaterialKeys: ["收藏"], recentMaterialKeys: ["最近"], userMaterials: [UserMaterial(name: "自定义材料")],
            deletedUserMaterials: [UserMaterial(name: "已删除材料")], hiddenPresetKeys: ["隐藏"])
        result.projectDrawings = [ProjectDrawing(projectId: project.id, name: "图纸", fileName: "drawing.pdf", fileType: "pdf")]
        return result
    }
}
