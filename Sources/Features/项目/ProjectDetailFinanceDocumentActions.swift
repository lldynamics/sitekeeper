import Foundation

enum ProjectDetailActionResult<Value> {
    case success(Value)
    case failure(String)
}

enum ProjectDetailFinanceDocumentActions {
    static let maxImportedDocumentBytes = ImportLimitPolicy.maxImportBytes

    enum LinkedDocumentCleanupMode {
        case deferred
        case immediate
    }

    struct FinancialRecordDeletionExecution {
        let financialDeletion: DataStoreRemovalResult<ProjectFinancialRecord>
        let removableDocumentFileNames: [String]
        let linkedDocumentCount: Int
    }

    struct DocumentDeletionExecution {
        let documentDeletion: DataStoreRemovalResult<ProjectDocument>
        let removableDocumentFileNames: [String]
    }
}
