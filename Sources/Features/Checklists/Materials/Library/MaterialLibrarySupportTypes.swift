import SwiftUI

enum MaterialSheetTargetMode: String, CaseIterable, Hashable {
    case existing
    case create
}

enum AppendMaterialField: Hashable {
    case quantity
    case unitPrice
    case note
}

enum MaterialPriceFilter: CaseIterable {
    case all
    case priced
    case unpriced

    var title: String {
        switch self {
        case .all:
            return AppLocalization.string("全部价格")
        case .priced:
            return AppLocalization.string("已标价")
        case .unpriced:
            return AppLocalization.string("未标价")
        }
    }
}

struct MaterialPriceEditorContext: Identifiable {
    let id: UUID
    let entry: MaterialPriceEntry?
    let name: String
    let specification: String
    let unit: String
    let category: String

    init(existing entry: MaterialPriceEntry) {
        id = entry.id
        self.entry = entry
        name = entry.name
        specification = entry.specification
        unit = entry.unit
        category = entry.category
    }

    init(name: String, specification: String, unit: String, category: String) {
        id = UUID()
        entry = nil
        self.name = name
        self.specification = specification
        self.unit = unit
        self.category = category
    }
}

struct PendingMaterialAppendContext: Identifiable {
    let id = UUID()
    let name: String
    let specification: String
    let unit: String
    let key: String
    let defaultBrand: String
    let defaultSupplier: String
    let defaultUnitPrice: String

    var displayName: String {
        let trimmedSpec = specification.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSpec.isEmpty {
            return name
        }
        return "\(name) \(trimmedSpec)"
    }
}

struct PendingBatchMaterialAppendContext: Identifiable {
    let id = UUID()
    let materials: [PendingMaterialAppendContext]
}

struct MaterialLibraryCategoryState {
    var selectedCategory: String?
    var showCategoryManager = false
}

struct MaterialLibraryAppendState {
    var pendingAddContext: PendingMaterialAppendContext?
    var pendingAddQuantity = "1"
    var selectedDefaultMaterialSheetDraftID: UUID?
    var pendingAddProjectId: UUID?
    var pendingAddUnitPrice = ""
    var pendingAddNote = ""
    var pendingAddTargetMode: MaterialSheetTargetMode = .existing
    var pendingAddDraftId: UUID?
    var pendingAddDraftTitle = ""
    var recentlyAddedDraftID: UUID?
    var recentlyAddedDraftTitle = ""
    var recentlyAddedItemCount = 0
    var showOpenMaterialSheetPrompt = false
    var navigateToMaterialSheet = false
    var deferredOperationMessage: String?
}

struct MaterialLibraryBatchSelectionState {
    var isBatchSelectionMode = false
    var selectedMaterialContextsByKey: [String: PendingMaterialAppendContext] = [:]
    var pendingBatchAddContext: PendingBatchMaterialAppendContext?
    var pendingBatchAddQuantity = "1"
}

enum MaterialLibraryPendingDeleteTarget {
    case preset(CommonMaterial)
    case user(UserMaterial)
}

struct RecentMaterialItem: Identifiable {
    enum Source {
        case preset(CommonMaterial)
        case user(UserMaterial)
    }

    let key: String
    let source: Source

    var id: String { key }
}
