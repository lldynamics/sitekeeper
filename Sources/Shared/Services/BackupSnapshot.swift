import Foundation

struct BackupArchiveManifest: Codable, Equatable {
    var schemaVersion: Int
    var appVersion: String
    var appBuild: String
    var appName: String
    var exportedAt: String
    var metadataPath: String

    init(
        schemaVersion: Int = BackupSnapshot.currentSchemaVersion,
        appVersion: String = AppBrand.appVersion,
        appBuild: String = AppBrand.appBuild,
        appName: String = AppBrand.displayName,
        exportedAt: String = Formatters.now(),
        metadataPath: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.appName = appName
        self.exportedAt = exportedAt
        self.metadataPath = metadataPath
    }
}

struct BackupSnapshot: Codable {
    static let legacySchemaVersion = 1
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var appVersion: String
    var appBuild: String
    var backupCreatedAt: String
    var materialItems: [MaterialItem]
    var quoteItems: [QuoteItem]
    var laborRecords: [LaborRecord]
    var projects: [Project]
    var dailyLogs: [DailyLog]
    var historyRecords: [HistoryRecord]
    var progressTasks: [ProgressTask]
    var siteTodos: [SiteTodo]
    var projectDrawings: [ProjectDrawing]
    var projectContacts: [ProjectContact]
    var projectFinancialRecords: [ProjectFinancialRecord]
    var projectDocuments: [ProjectDocument]
    var quickNotes: [QuickNote]
    var projectWarehouseMovements: [ProjectWarehouseMovement] = []
    var templates: [ProjectTemplate]
    var materialPriceEntries: [MaterialPriceEntry] = []
    var materialSheetDrafts: [MaterialSheetDraft] = []
    var supplierProfiles: [SupplierProfile] = []
    var constructionMethods: [ConstructionMethod] = []
    var favoriteMaterialKeys: [String] = []
    var recentMaterialKeys: [String] = []
    var userMaterials: [UserMaterial] = []
    var deletedUserMaterials: [UserMaterial] = []
    var hiddenPresetKeys: Set<String> = []
    var photoFiles: [PhotoBackupFile] = []
    var drawingFiles: [DrawingBackupFile] = []
    var documentFiles: [ProjectDocumentBackupFile] = []
    var quickNoteAttachmentFiles: [QuickNoteAttachmentBackupFile] = []

    init(
        schemaVersion: Int = BackupSnapshot.currentSchemaVersion,
        appVersion: String = AppBrand.appVersion,
        appBuild: String = AppBrand.appBuild,
        backupCreatedAt: String = Formatters.now(),
        materialItems: [MaterialItem],
        quoteItems: [QuoteItem],
        laborRecords: [LaborRecord],
        projects: [Project],
        dailyLogs: [DailyLog],
        historyRecords: [HistoryRecord],
        progressTasks: [ProgressTask] = [],
        siteTodos: [SiteTodo] = [],
        projectDrawings: [ProjectDrawing] = [],
        projectContacts: [ProjectContact] = [],
        projectFinancialRecords: [ProjectFinancialRecord] = [],
        projectDocuments: [ProjectDocument] = [],
        quickNotes: [QuickNote] = [],
        projectWarehouseMovements: [ProjectWarehouseMovement] = [],
        templates: [ProjectTemplate],
        materialPriceEntries: [MaterialPriceEntry] = [],
        materialSheetDrafts: [MaterialSheetDraft] = [],
        supplierProfiles: [SupplierProfile] = [],
        constructionMethods: [ConstructionMethod] = [],
        favoriteMaterialKeys: [String] = [],
        recentMaterialKeys: [String] = [],
        userMaterials: [UserMaterial] = [],
        deletedUserMaterials: [UserMaterial] = [],
        hiddenPresetKeys: Set<String> = [],
        photoFiles: [PhotoBackupFile] = [],
        drawingFiles: [DrawingBackupFile] = [],
        documentFiles: [ProjectDocumentBackupFile] = [],
        quickNoteAttachmentFiles: [QuickNoteAttachmentBackupFile] = []
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.backupCreatedAt = backupCreatedAt
        self.materialItems = materialItems
        self.quoteItems = quoteItems
        self.laborRecords = laborRecords
        self.projects = projects
        self.dailyLogs = dailyLogs
        self.historyRecords = historyRecords
        self.progressTasks = progressTasks
        self.siteTodos = siteTodos
        self.projectDrawings = projectDrawings
        self.projectContacts = projectContacts
        self.projectFinancialRecords = projectFinancialRecords
        self.projectDocuments = projectDocuments
        self.quickNotes = quickNotes
        self.projectWarehouseMovements = projectWarehouseMovements
        self.templates = templates
        self.materialPriceEntries = materialPriceEntries
        self.materialSheetDrafts = materialSheetDrafts
        self.supplierProfiles = supplierProfiles
        self.constructionMethods = constructionMethods
        self.favoriteMaterialKeys = favoriteMaterialKeys
        self.recentMaterialKeys = recentMaterialKeys
        self.userMaterials = userMaterials
        self.deletedUserMaterials = deletedUserMaterials
        self.hiddenPresetKeys = hiddenPresetKeys
        self.photoFiles = photoFiles
        self.drawingFiles = drawingFiles
        self.documentFiles = documentFiles
        self.quickNoteAttachmentFiles = quickNoteAttachmentFiles
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, appVersion, appBuild, backupCreatedAt
        case materialItems, quoteItems, laborRecords, projects, dailyLogs, historyRecords
        case progressTasks, siteTodos, projectDrawings
        case projectContacts, projectFinancialRecords, projectDocuments, quickNotes, projectWarehouseMovements
        case templates, materialPriceEntries, materialSheetDrafts, supplierProfiles, constructionMethods
        case favoriteMaterialKeys, recentMaterialKeys, userMaterials, deletedUserMaterials, hiddenPresetKeys, photoFiles, drawingFiles, documentFiles
        case quickNoteAttachmentFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? BackupSnapshot.legacySchemaVersion
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        appBuild = try container.decodeIfPresent(String.self, forKey: .appBuild) ?? ""
        backupCreatedAt = try container.decodeIfPresent(String.self, forKey: .backupCreatedAt) ?? ""
        materialItems = try container.decodeIfPresent([MaterialItem].self, forKey: .materialItems) ?? []
        quoteItems = try container.decodeIfPresent([QuoteItem].self, forKey: .quoteItems) ?? []
        laborRecords = try container.decodeIfPresent([LaborRecord].self, forKey: .laborRecords) ?? []
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        dailyLogs = try container.decodeIfPresent([DailyLog].self, forKey: .dailyLogs) ?? []
        historyRecords = try container.decodeIfPresent([HistoryRecord].self, forKey: .historyRecords) ?? []
        progressTasks = try container.decodeIfPresent([ProgressTask].self, forKey: .progressTasks) ?? []
        siteTodos = try container.decodeIfPresent([SiteTodo].self, forKey: .siteTodos) ?? []
        projectDrawings = try container.decodeIfPresent([ProjectDrawing].self, forKey: .projectDrawings) ?? []
        projectContacts = try container.decodeIfPresent([ProjectContact].self, forKey: .projectContacts) ?? []
        projectFinancialRecords = try container.decodeIfPresent([ProjectFinancialRecord].self, forKey: .projectFinancialRecords) ?? []
        projectDocuments = try container.decodeIfPresent([ProjectDocument].self, forKey: .projectDocuments) ?? []
        quickNotes = try container.decodeIfPresent([QuickNote].self, forKey: .quickNotes) ?? []
        projectWarehouseMovements = try container.decodeIfPresent([ProjectWarehouseMovement].self, forKey: .projectWarehouseMovements) ?? []
        templates = try container.decodeIfPresent([ProjectTemplate].self, forKey: .templates) ?? []
        materialPriceEntries = try container.decodeIfPresent([MaterialPriceEntry].self, forKey: .materialPriceEntries) ?? []
        materialSheetDrafts = try container.decodeIfPresent([MaterialSheetDraft].self, forKey: .materialSheetDrafts) ?? []
        supplierProfiles = try container.decodeIfPresent([SupplierProfile].self, forKey: .supplierProfiles) ?? []
        constructionMethods = try container.decodeIfPresent([ConstructionMethod].self, forKey: .constructionMethods) ?? []
        favoriteMaterialKeys = try container.decodeIfPresent([String].self, forKey: .favoriteMaterialKeys) ?? []
        recentMaterialKeys = try container.decodeIfPresent([String].self, forKey: .recentMaterialKeys) ?? []
        userMaterials = try container.decodeIfPresent([UserMaterial].self, forKey: .userMaterials) ?? []
        deletedUserMaterials = try container.decodeIfPresent([UserMaterial].self, forKey: .deletedUserMaterials) ?? []
        hiddenPresetKeys = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenPresetKeys) ?? []
        photoFiles = try container.decodeIfPresent([PhotoBackupFile].self, forKey: .photoFiles) ?? []
        drawingFiles = try container.decodeIfPresent([DrawingBackupFile].self, forKey: .drawingFiles) ?? []
        documentFiles = try container.decodeIfPresent([ProjectDocumentBackupFile].self, forKey: .documentFiles) ?? []
        quickNoteAttachmentFiles = try container.decodeIfPresent([QuickNoteAttachmentBackupFile].self, forKey: .quickNoteAttachmentFiles) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(appBuild, forKey: .appBuild)
        try container.encode(backupCreatedAt, forKey: .backupCreatedAt)
        try container.encode(materialItems, forKey: .materialItems)
        try container.encode(quoteItems, forKey: .quoteItems)
        try container.encode(laborRecords, forKey: .laborRecords)
        try container.encode(projects, forKey: .projects)
        try container.encode(dailyLogs, forKey: .dailyLogs)
        try container.encode(historyRecords, forKey: .historyRecords)
        try container.encode(progressTasks, forKey: .progressTasks)
        try container.encode(siteTodos, forKey: .siteTodos)
        try container.encode(projectDrawings, forKey: .projectDrawings)
        try container.encode(projectContacts, forKey: .projectContacts)
        try container.encode(projectFinancialRecords, forKey: .projectFinancialRecords)
        try container.encode(projectDocuments, forKey: .projectDocuments)
        try container.encode(quickNotes, forKey: .quickNotes)
        try container.encode(projectWarehouseMovements, forKey: .projectWarehouseMovements)
        try container.encode(templates, forKey: .templates)
        try container.encode(materialPriceEntries, forKey: .materialPriceEntries)
        try container.encode(materialSheetDrafts, forKey: .materialSheetDrafts)
        try container.encode(supplierProfiles, forKey: .supplierProfiles)
        try container.encode(constructionMethods, forKey: .constructionMethods)
        try container.encode(favoriteMaterialKeys, forKey: .favoriteMaterialKeys)
        try container.encode(recentMaterialKeys, forKey: .recentMaterialKeys)
        try container.encode(userMaterials, forKey: .userMaterials)
        try container.encode(deletedUserMaterials, forKey: .deletedUserMaterials)
        try container.encode(hiddenPresetKeys, forKey: .hiddenPresetKeys)
        try container.encode(photoFiles, forKey: .photoFiles)
        try container.encode(drawingFiles, forKey: .drawingFiles)
        try container.encode(documentFiles, forKey: .documentFiles)
        try container.encode(quickNoteAttachmentFiles, forKey: .quickNoteAttachmentFiles)
    }
}
