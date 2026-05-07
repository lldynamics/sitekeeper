import Foundation
import Observation

struct WidgetProjectSummary: Codable {
    let id: UUID
    let name: String
    let status: String
    let progress: Double
    let todoCount: Int
}

struct WidgetExportData: Codable {
    let projects: [WidgetProjectSummary]
    let pendingTodos: Int
    let materialStockCount: Int
    let lowStockCount: Int
}

@MainActor
@Observable
final class DataStore {
    // 清单
    var materialItems: [MaterialItem] = []
    var quoteItems: [QuoteItem] = []
    var laborRecords: [LaborRecord] = []
    // 项目
    var projects: [Project] = []
    var dailyLogs: [DailyLog] = []
    var historyRecords: [HistoryRecord] = []
    var progressTasks: [ProgressTask] = []
    var lightingCircuitPlans: [LightingCircuitPlan] = []
    var siteTodos: [SiteTodo] = []
    var paymentRecords: [PaymentRecord] = []
    var projectDrawings: [ProjectDrawing] = []
    var projectContacts: [ProjectContact] = []
    var projectFinancialRecords: [ProjectFinancialRecord] = []
    var projectDocuments: [ProjectDocument] = []
    var quickNotes: [QuickNote] = []
    var projectWarehouseMovements: [ProjectWarehouseMovement] = []
    // 模板
    var templates: [ProjectTemplate] = []
    // 材料库增强
    var materialPriceEntries: [MaterialPriceEntry] = []
    var supplierProfiles: [SupplierProfile] = []
    var constructionMethods: [ConstructionMethod] = []
    var favoriteMaterialKeys: [String] = []
    var recentMaterialKeys: [String] = []
    var userMaterials: [UserMaterial] = []
    var deletedUserMaterials: [UserMaterial] = []
    var hiddenPresetKeys: Set<String> = []
    var persistenceErrorMessage: String?

    /// 版本签名：任何数据变化时递增，观察者可据此判定数据是否已过期
    var searchIndexVersion = 0
    var dataVersion = UUID()

    private let persistenceActor = DataStorePersistenceActor(storeURL: DataStore.storeURL)
    private var latestPersistToken = 0
    private var persistTask: Task<Void, Never>?

    private static var documentsDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        StorageIssueLog.record("无法访问应用文档目录，已回退到临时目录")
        return FileManager.default.temporaryDirectory
    }

    private static let primaryStoreURL: URL = documentsDirectory.appendingPathComponent("sitekeeper.json")
    private static let legacyStoreURL: URL = documentsDirectory.appendingPathComponent("construction_toolbox.json")
    private static let storeURL: URL = primaryStoreURL

    private static func resolveLoadURL() -> URL? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: primaryStoreURL.path) {
            return primaryStoreURL
        }
        if fileManager.fileExists(atPath: legacyStoreURL.path) {
            return legacyStoreURL
        }
        return nil
    }

    init() {
        load()
    }

    private func seedDefaults() {
        materialItems = [
            MaterialItem(name: "BV 2.5mm² 电线", quantity: "3", unit: "卷", unitPrice: "280", projectId: nil),
            MaterialItem(name: "86 型底盒", quantity: "20", unit: "个", unitPrice: "2.5", projectId: nil),
        ]
        quoteItems = [
            QuoteItem(name: "电缆敷设", unitPrice: "45", quantity: "200", unit: "米", notes: "", taxRate: "0", discountRate: "0", projectId: nil),
            QuoteItem(name: "配电箱安装", unitPrice: "800", quantity: "2", unit: "台", notes: "", taxRate: "0", discountRate: "0", projectId: nil),
        ]
        laborRecords = [
            LaborRecord(date: "2026-05-01", workers: "3", hours: "8", unitRate: "120", note: "布线", projectId: nil),
        ]
        projects = [
            Project(name: "阳光花园 3# 楼", location: "城东区", status: "进行中", customerName: "示例客户", customerPhone: "", startDate: "2026-05-01", expectedEndDate: "2026-05-20", managerName: "示例负责人", contractAmount: "68000", paidAmount: "20000", paymentStatus: PaymentStatus.partial.rawValue, materialCost: "26000", laborCost: "12000"),
            Project(name: "科技园配电改造", location: "高新区", status: "已完成", customerName: "示例物业公司", customerPhone: "", startDate: "2026-04-10", expectedEndDate: "2026-04-30", managerName: "示例负责人", contractAmount: "42000", paidAmount: "42000", paymentStatus: PaymentStatus.paid.rawValue, materialCost: "18000", laborCost: "9000"),
        ]
        dailyLogs = [
            DailyLog(date: "2026-05-01", weather: "晴", content: "完成 3 层布线，配电箱安装", workers: "5人", photoFileName: nil, safety: "班前安全交底完成", materials: "BV线进场", tomorrowPlan: "复核配电箱回路编号", projectId: nil),
        ]
        historyRecords = [
            HistoryRecord(tool: "电流计算", input: "10kW / 220V", result: "45.45 A", date: "2026-05-01 14:30"),
            HistoryRecord(tool: "照明估算", input: "6×4m, 300lux", result: "5 盏", date: "2026-05-01 10:15"),
        ]
        if let firstProjectId = projects.first?.id {
            progressTasks = [
                ProgressTask(projectId: firstProjectId, title: "三层布线", startDate: "2026-05-01", dueDate: "2026-05-05", completion: 0.6, note: "完成主管线，待穿线复核"),
                ProgressTask(projectId: firstProjectId, title: "配电箱安装", startDate: "2026-05-03", dueDate: "2026-05-06", completion: 0.3, note: "")
            ]
            lightingCircuitPlans = [
                LightingCircuitPlan(
                    name: "三层公共照明回路",
                    projectId: firstProjectId,
                    supplyType: .singlePhase,
                    voltage: "220",
                    powerFactor: "0.90",
                    demandFactor: "0.90",
                    breakerFactor: "1.25",
                    wireFactor: "1.15",
                    isCopper: true,
                    loads: [
                        LightingCircuitLoad(name: "走廊照明", powerKW: "2.5"),
                        LightingCircuitLoad(name: "楼梯间照明", powerKW: "1.2"),
                    ],
                    updatedAt: "2026-05-01 09:20"
                )
            ]
            siteTodos = [
                SiteTodo(title: "复核三层配电箱回路编号", owner: "示例负责人", dueDate: "2026-05-02", projectId: firstProjectId),
                SiteTodo(title: "补齐公共照明报价单价", owner: "材料负责人", dueDate: "2026-05-02", projectId: firstProjectId)
            ]
            paymentRecords = [
                PaymentRecord(projectId: firstProjectId, date: "2026-05-03", amount: "20000", method: "转账", note: "首付款", isInvoiced: false)
            ]
        }
        templates = [
            ProjectTemplate(name: "住宅电气改造", category: .quotation, content: "布线 ¥45/m\n插座安装 ¥25/个\n配电箱 ¥800/台"),
            ProjectTemplate(name: "标准施工日志", category: .dailyLog, content: "日期:\n天气:\n出勤人数:\n施工内容:\n安全问题:\n材料进场:"),
            ProjectTemplate(name: "住宅布线材料", category: .material, content: "BV 2.5mm² 电线 × 3卷\nBV 4mm² 电线 × 2卷\n线管 Φ20 × 50m\n86盒 × 20个"),
        ]
        materialPriceEntries = [
            MaterialPriceEntry(name: "BV 铜芯线", specification: "2.5mm²", brand: "常用", unit: "卷(100m)", referencePrice: "280", supplier: "默认供应商", category: "电线"),
            MaterialPriceEntry(name: "PVC 线管", specification: "Φ20", brand: "常用", unit: "米", referencePrice: "1.8", supplier: "默认供应商", category: "线管")
        ]
        supplierProfiles = [
            SupplierProfile(name: "默认供应商", category: "电气材料", contact: "材料员", phone: "", address: "", note: "可替换为常用供应商")
        ]
        constructionMethods = [
            ConstructionMethod(title: "电线穿管施工", trade: "电气", steps: "1. 清理管路\n2. 穿引线\n3. 分色穿线\n4. 绝缘测试", qualityStandard: "线色正确，管内无接头，绝缘测试合格", safetyNotes: "断电作业，穿线时防止划伤绝缘层")
        ]
    }

    private func load() {
        guard let sourceURL = Self.resolveLoadURL() else {
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            persistenceErrorMessage = "读取本地数据失败：\(error.localizedDescription)"
            return
        }
        let decoder = JSONDecoder()
        let snapshot: BackupSnapshot
        do {
            snapshot = try decoder.decode(BackupSnapshot.self, from: data)
        } catch {
            let backupName = "sitekeeper_corrupt_\(Formatters.now().replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "_")).json"
            let backupURL = Self.storeURL.deletingLastPathComponent().appendingPathComponent(backupName)
            try? data.write(to: backupURL, options: .atomic)
            persistenceErrorMessage = "本地数据解析失败，已保留异常文件：\(backupName)。可从备份页重新导入最近备份。"
            return
        }
        materialItems = snapshot.materialItems
        quoteItems = snapshot.quoteItems
        laborRecords = snapshot.laborRecords
        projects = snapshot.projects
        dailyLogs = snapshot.dailyLogs
        historyRecords = snapshot.historyRecords
        progressTasks = snapshot.progressTasks
        lightingCircuitPlans = snapshot.lightingCircuitPlans
        siteTodos = snapshot.siteTodos
        paymentRecords = snapshot.paymentRecords
        projectDrawings = snapshot.projectDrawings
        projectContacts = snapshot.projectContacts
        projectFinancialRecords = snapshot.projectFinancialRecords
        projectDocuments = snapshot.projectDocuments
        quickNotes = snapshot.quickNotes
        projectWarehouseMovements = snapshot.projectWarehouseMovements
        templates = snapshot.templates
        materialPriceEntries = snapshot.materialPriceEntries
        supplierProfiles = snapshot.supplierProfiles
        constructionMethods = snapshot.constructionMethods
        favoriteMaterialKeys = snapshot.favoriteMaterialKeys
        recentMaterialKeys = snapshot.recentMaterialKeys
        userMaterials = snapshot.userMaterials
        deletedUserMaterials = snapshot.deletedUserMaterials
        hiddenPresetKeys = snapshot.hiddenPresetKeys

        if sourceURL == Self.legacyStoreURL {
            do {
                try data.write(to: Self.storeURL, options: .atomic)
                try? FileManager.default.removeItem(at: Self.legacyStoreURL)
            } catch {
                StorageIssueLog.record("旧数据文件迁移失败：\(error.localizedDescription)")
            }
        }
    }

    func makeSnapshot(includePhotoFiles: Bool) -> BackupSnapshot {
        BackupSnapshot(
            materialItems: materialItems,
            quoteItems: quoteItems,
            laborRecords: laborRecords,
            projects: projects,
            dailyLogs: dailyLogs,
            historyRecords: historyRecords,
            progressTasks: progressTasks,
            lightingCircuitPlans: lightingCircuitPlans,
            siteTodos: siteTodos,
            paymentRecords: paymentRecords,
            projectDrawings: projectDrawings,
            projectContacts: projectContacts,
            projectFinancialRecords: projectFinancialRecords,
            projectDocuments: projectDocuments,
            quickNotes: quickNotes,
            projectWarehouseMovements: projectWarehouseMovements,
            templates: templates,
            materialPriceEntries: materialPriceEntries,
            supplierProfiles: supplierProfiles,
            constructionMethods: constructionMethods,
            favoriteMaterialKeys: favoriteMaterialKeys,
            recentMaterialKeys: recentMaterialKeys,
            userMaterials: userMaterials,
            deletedUserMaterials: deletedUserMaterials,
            hiddenPresetKeys: hiddenPresetKeys,
            photoFiles: includePhotoFiles ? (PhotoStorage.backupFiles(for: dailyLogs) + PhotoStorage.backupFiles(for: siteTodos)) : [],
            drawingFiles: includePhotoFiles ? DrawingStorage.backupFiles(for: projectDrawings) : [],
            documentFiles: includePhotoFiles ? ProjectDocumentStorage.backupFiles(for: projectDocuments) : [],
            quickNoteAttachmentFiles: includePhotoFiles ? QuickNoteAttachmentStorage.backupFiles(for: quickNotes) : []
        )
    }

    func flushSave() async {
        saveTask?.cancel()
        let snapshot = makeSnapshot(includePhotoFiles: false)
        do {
            try await persistenceActor.persist(snapshot: snapshot)
        } catch {
            persistenceErrorMessage = "保存本地数据失败：\(error.localizedDescription)"
        }
        publishWidgetData()
    }

    func save(includePhotoFiles: Bool = false) {
        let snapshot = makeSnapshot(includePhotoFiles: includePhotoFiles)
        latestPersistToken += 1
        let persistToken = latestPersistToken
        let persistenceActor = self.persistenceActor

        persistTask?.cancel()
        persistTask = Task(priority: .utility) {
            do {
                try await persistenceActor.persist(snapshot: snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          persistToken == self.latestPersistToken else { return }
                    self.persistenceErrorMessage = "保存本地数据失败：\(error.localizedDescription)"
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.publishWidgetData()
        }
    }

    private var saveTask: Task<Void, Never>?

    func scheduleSave() {
        searchIndexVersion &+= 1
        dataVersion = UUID()
        guard UserPreferences.bool(UserPreferenceKeys.autoSave, default: true) else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            save(includePhotoFiles: false)
        }
    }

    var hasAnyBusinessData: Bool {
        !materialItems.isEmpty ||
        !quoteItems.isEmpty ||
        !laborRecords.isEmpty ||
        !projects.isEmpty ||
        !dailyLogs.isEmpty ||
        !historyRecords.isEmpty ||
        !progressTasks.isEmpty ||
        !lightingCircuitPlans.isEmpty ||
        !siteTodos.isEmpty ||
        !paymentRecords.isEmpty ||
        !projectDrawings.isEmpty ||
        !projectContacts.isEmpty ||
        !projectFinancialRecords.isEmpty ||
        !projectDocuments.isEmpty ||
        !quickNotes.isEmpty ||
        !projectWarehouseMovements.isEmpty ||
        !templates.isEmpty ||
        !materialPriceEntries.isEmpty ||
        !supplierProfiles.isEmpty ||
        !constructionMethods.isEmpty ||
        !userMaterials.isEmpty ||
        !deletedUserMaterials.isEmpty
    }

    func importSampleData(replacingExisting: Bool) {
        guard AppFeatureFlags.allowsSampleDataImport else {
            persistenceErrorMessage = "当前发布环境已关闭示例数据导入。"
            return
        }
        if replacingExisting {
            clearAllBusinessData(deleteStoredFiles: true)
        }
        seedDefaults()
        save(includePhotoFiles: false)
    }

    func deleteProject(_ projectId: UUID) {
        // 照片（日志 + 待办整改前后）
        let logPhotos = dailyLogs.filter { $0.projectId == projectId }.flatMap(\.allPhotoFileNames)
        let projectTodos = siteTodos.filter { $0.projectId == projectId }
        let todoPhotos = projectTodos.compactMap(\.rectificationBeforePhotoFileName) +
            projectTodos.compactMap(\.rectificationAfterPhotoFileName)
        PhotoStorage.delete(fileNames: logPhotos + todoPhotos)

        // 图纸文件
        for drawing in projectDrawings where drawing.projectId == projectId {
            DrawingStorage.delete(fileName: drawing.fileName)
        }

        // 文档文件
        for document in projectDocuments where document.projectId == projectId {
            ProjectDocumentStorage.delete(fileName: document.fileName)
        }

        // 随手记附件
        let quickNoteAttachments = quickNotes.filter { $0.projectId == projectId }.flatMap(\.attachments)
        QuickNoteAttachmentStorage.delete(attachments: quickNoteAttachments)

        // 数据记录
        materialItems.removeAll { $0.projectId == projectId }
        quoteItems.removeAll { $0.projectId == projectId }
        laborRecords.removeAll { $0.projectId == projectId }
        dailyLogs.removeAll { $0.projectId == projectId }
        progressTasks.removeAll { $0.projectId == projectId }
        lightingCircuitPlans.removeAll { $0.projectId == projectId }
        siteTodos.removeAll { $0.projectId == projectId }
        paymentRecords.removeAll { $0.projectId == projectId }
        projectDrawings.removeAll { $0.projectId == projectId }
        projectContacts.removeAll { $0.projectId == projectId }
        projectFinancialRecords.removeAll { $0.projectId == projectId }
        projectDocuments.removeAll { $0.projectId == projectId }
        quickNotes.removeAll { $0.projectId == projectId }
        projectWarehouseMovements.removeAll { $0.projectId == projectId }
        projects.removeAll { $0.id == projectId }
        scheduleSave()
    }

    func clearAllBusinessData(deleteStoredFiles: Bool = true) {
        saveTask?.cancel()
        if deleteStoredFiles {
            PhotoStorage.delete(fileNames: PhotoStorage.allStoredFileNames())
            DrawingStorage.delete(fileNames: DrawingStorage.allStoredFileNames())
            ProjectDocumentStorage.delete(fileNames: ProjectDocumentStorage.allStoredFileNames())
            QuickNoteAttachmentStorage.delete(fileNames: QuickNoteAttachmentStorage.allStoredFileNames())
            StorageIssueLog.clear()
        }
        clearAllData()
        save(includePhotoFiles: false)
    }

    func clearAllBusinessDataAsync(
        deleteStoredFiles: Bool = true,
        onProgress: (@MainActor (String) -> Void)? = nil
    ) async {
        saveTask?.cancel()
        if deleteStoredFiles {
            let photoNames = PhotoStorage.allStoredFileNames()
            let drawingNames = DrawingStorage.allStoredFileNames()
            let documentNames = ProjectDocumentStorage.allStoredFileNames()
            let attachmentNames = QuickNoteAttachmentStorage.allStoredFileNames()

            onProgress?("正在删除照片")
            await Task.detached(priority: .userInitiated) {
                PhotoStorage.delete(fileNames: photoNames)
            }.value

            onProgress?("正在删除图纸")
            await Task.detached(priority: .userInitiated) {
                DrawingStorage.delete(fileNames: drawingNames)
            }.value

            onProgress?("正在删除资料")
            await Task.detached(priority: .userInitiated) {
                ProjectDocumentStorage.delete(fileNames: documentNames)
            }.value

            onProgress?("正在删除附件")
            await Task.detached(priority: .userInitiated) {
                QuickNoteAttachmentStorage.delete(fileNames: attachmentNames)
            }.value

            onProgress?("正在清理日志")
            await Task.detached(priority: .utility) {
                StorageIssueLog.clear()
            }.value
        }

        onProgress?("正在写入空数据")
        clearAllData()
        save(includePhotoFiles: false)
        onProgress?("清空完成")
    }

    private func clearAllData() {
        materialItems = []
        quoteItems = []
        laborRecords = []
        projects = []
        dailyLogs = []
        historyRecords = []
        progressTasks = []
        lightingCircuitPlans = []
        siteTodos = []
        paymentRecords = []
        projectDrawings = []
        projectContacts = []
        projectFinancialRecords = []
        projectDocuments = []
        quickNotes = []
        projectWarehouseMovements = []
        templates = []
        materialPriceEntries = []
        supplierProfiles = []
        constructionMethods = []
        favoriteMaterialKeys = []
        recentMaterialKeys = []
        userMaterials = []
        deletedUserMaterials = []
        hiddenPresetKeys = []
        searchIndexVersion &+= 1
        dataVersion = UUID()
        publishWidgetData()
    }

    func publishWidgetData() {
        guard let defaults = UserDefaults(suiteName: "group.com.chengjinfang.sitekeeper") else { return }
        let activeProjects = projects.filter { $0.status == "进行中" || $0.status == "已暂停" }
        let pendingTodosCount = siteTodos.filter { !$0.isDone }.count
        let inCount = projectWarehouseMovements.filter { $0.movementType == "入库" }.count
        let outCount = projectWarehouseMovements.filter { $0.movementType == "出库" }.count
        let widgetData = WidgetExportData(
            projects: activeProjects.prefix(5).map { p in
                let projectTasks = progressTasks.filter { $0.projectId == p.id }
                let avgProgress: Double = projectTasks.isEmpty ? 0 : projectTasks.map(\.completion).reduce(0, +) / Double(projectTasks.count)
                return WidgetProjectSummary(
                    id: p.id,
                    name: p.name,
                    status: p.status,
                    progress: avgProgress,
                    todoCount: siteTodos.filter { $0.projectId == p.id && !$0.isDone }.count
                )
            },
            pendingTodos: pendingTodosCount,
            materialStockCount: inCount,
            lowStockCount: materialItems.filter { $0.purchaseStatus == MaterialPurchaseStatus.notPurchased.rawValue }.count
        )
        if let data = try? JSONEncoder().encode(widgetData) {
            defaults.set(data, forKey: "widget_data")
        }
    }
}

actor DataStorePersistenceActor {
    private let storeURL: URL

    init(storeURL: URL) {
        self.storeURL = storeURL
    }

    func persist(snapshot: BackupSnapshot) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        try data.write(to: storeURL, options: .atomic)
    }
}
