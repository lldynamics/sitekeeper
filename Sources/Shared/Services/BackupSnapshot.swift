import Foundation

struct BackupSnapshot: Codable {
    var materialItems: [MaterialItem]
    var quoteItems: [QuoteItem]
    var laborRecords: [LaborRecord]
    var projects: [Project]
    var dailyLogs: [DailyLog]
    var historyRecords: [HistoryRecord]
    var progressTasks: [ProgressTask]
    var lightingCircuitPlans: [LightingCircuitPlan]
    var siteTodos: [SiteTodo]
    var paymentRecords: [PaymentRecord]
    var projectDrawings: [ProjectDrawing]
    var projectContacts: [ProjectContact]
    var projectFinancialRecords: [ProjectFinancialRecord]
    var projectDocuments: [ProjectDocument]
    var quickNotes: [QuickNote]
    var projectWarehouseMovements: [ProjectWarehouseMovement] = []
    var templates: [ProjectTemplate]
    var materialPriceEntries: [MaterialPriceEntry] = []
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
        materialItems: [MaterialItem],
        quoteItems: [QuoteItem],
        laborRecords: [LaborRecord],
        projects: [Project],
        dailyLogs: [DailyLog],
        historyRecords: [HistoryRecord],
        progressTasks: [ProgressTask] = [],
        lightingCircuitPlans: [LightingCircuitPlan] = [],
        siteTodos: [SiteTodo] = [],
        paymentRecords: [PaymentRecord] = [],
        projectDrawings: [ProjectDrawing] = [],
        projectContacts: [ProjectContact] = [],
        projectFinancialRecords: [ProjectFinancialRecord] = [],
        projectDocuments: [ProjectDocument] = [],
        quickNotes: [QuickNote] = [],
        projectWarehouseMovements: [ProjectWarehouseMovement] = [],
        templates: [ProjectTemplate],
        materialPriceEntries: [MaterialPriceEntry] = [],
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
        self.materialItems = materialItems
        self.quoteItems = quoteItems
        self.laborRecords = laborRecords
        self.projects = projects
        self.dailyLogs = dailyLogs
        self.historyRecords = historyRecords
        self.progressTasks = progressTasks
        self.lightingCircuitPlans = lightingCircuitPlans
        self.siteTodos = siteTodos
        self.paymentRecords = paymentRecords
        self.projectDrawings = projectDrawings
        self.projectContacts = projectContacts
        self.projectFinancialRecords = projectFinancialRecords
        self.projectDocuments = projectDocuments
        self.quickNotes = quickNotes
        self.projectWarehouseMovements = projectWarehouseMovements
        self.templates = templates
        self.materialPriceEntries = materialPriceEntries
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
        case materialItems, quoteItems, laborRecords, projects, dailyLogs, historyRecords
        case progressTasks, lightingCircuitPlans, siteTodos, paymentRecords, projectDrawings
        case projectContacts, projectFinancialRecords, projectDocuments, quickNotes, projectWarehouseMovements
        case templates, materialPriceEntries, supplierProfiles, constructionMethods
        case favoriteMaterialKeys, recentMaterialKeys, userMaterials, deletedUserMaterials, hiddenPresetKeys, photoFiles, drawingFiles, documentFiles
        case quickNoteAttachmentFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        materialItems = try container.decodeIfPresent([MaterialItem].self, forKey: .materialItems) ?? []
        quoteItems = try container.decodeIfPresent([QuoteItem].self, forKey: .quoteItems) ?? []
        laborRecords = try container.decodeIfPresent([LaborRecord].self, forKey: .laborRecords) ?? []
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        dailyLogs = try container.decodeIfPresent([DailyLog].self, forKey: .dailyLogs) ?? []
        historyRecords = try container.decodeIfPresent([HistoryRecord].self, forKey: .historyRecords) ?? []
        progressTasks = try container.decodeIfPresent([ProgressTask].self, forKey: .progressTasks) ?? []
        lightingCircuitPlans = try container.decodeIfPresent([LightingCircuitPlan].self, forKey: .lightingCircuitPlans) ?? []
        siteTodos = try container.decodeIfPresent([SiteTodo].self, forKey: .siteTodos) ?? []
        paymentRecords = try container.decodeIfPresent([PaymentRecord].self, forKey: .paymentRecords) ?? []
        projectDrawings = try container.decodeIfPresent([ProjectDrawing].self, forKey: .projectDrawings) ?? []
        projectContacts = try container.decodeIfPresent([ProjectContact].self, forKey: .projectContacts) ?? []
        projectFinancialRecords = try container.decodeIfPresent([ProjectFinancialRecord].self, forKey: .projectFinancialRecords) ?? []
        projectDocuments = try container.decodeIfPresent([ProjectDocument].self, forKey: .projectDocuments) ?? []
        quickNotes = try container.decodeIfPresent([QuickNote].self, forKey: .quickNotes) ?? []
        projectWarehouseMovements = try container.decodeIfPresent([ProjectWarehouseMovement].self, forKey: .projectWarehouseMovements) ?? []
        templates = try container.decodeIfPresent([ProjectTemplate].self, forKey: .templates) ?? []
        materialPriceEntries = try container.decodeIfPresent([MaterialPriceEntry].self, forKey: .materialPriceEntries) ?? []
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
}
