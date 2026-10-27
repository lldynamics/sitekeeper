import Foundation
import SwiftUI

enum MaterialLibraryLogicHelpers {
    struct AppendComputation {
        let drafts: [MaterialSheetDraft]
        let targetDraftID: UUID
        let targetTitle: String
        let lastProjectIDRaw: String
        let nextPendingTargetMode: MaterialSheetTargetMode
        let nextPendingDraftID: UUID?
        let nextSelectedDefaultDraftID: UUID?
    }

    enum AppendComputationResult {
        case success(AppendComputation)
        case failure(message: String, nextPendingTargetMode: MaterialSheetTargetMode, nextPendingDraftID: UUID?)
    }

    static func activeMaterialSheetDrafts(from drafts: [MaterialSheetDraft]) -> [MaterialSheetDraft] {
        drafts
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let lhsDate = Formatters.parseDateOrDateTime(lhs.updatedAt) ?? .distantPast
                let rhsDate = Formatters.parseDateOrDateTime(rhs.updatedAt) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    static func defaultTargetDraft(
        activeDrafts: [MaterialSheetDraft],
        selectedDefaultDraftID: UUID?,
        rememberedDraftIDRaw: String
    ) -> MaterialSheetDraft? {
        guard !activeDrafts.isEmpty else { return nil }
        if let selectedDefaultDraftID,
           let selected = activeDrafts.first(where: { $0.id == selectedDefaultDraftID }) {
            return selected
        }
        if let rememberedId = UUID(uuidString: rememberedDraftIDRaw),
           let remembered = activeDrafts.first(where: { $0.id == rememberedId }) {
            return remembered
        }
        return activeDrafts.first
    }

    static func rememberedTargetState(
        lastModeRaw: String,
        lastDraftIDRaw: String,
        lastProjectIDRaw: String,
        activeDrafts: [MaterialSheetDraft],
        projects: [Project]
    ) -> (mode: MaterialSheetTargetMode, draftID: UUID?, projectID: UUID?) {
        let rememberedMode = MaterialSheetTargetMode(rawValue: lastModeRaw) ?? .existing
        let rememberedDraftID = UUID(uuidString: lastDraftIDRaw)
        let rememberedProjectID = normalizedRememberedProjectID(UUID(uuidString: lastProjectIDRaw), projects: projects)

        switch rememberedMode {
        case .existing:
            if let rememberedDraftID,
               activeDrafts.contains(where: { $0.id == rememberedDraftID }) {
                return (.existing, rememberedDraftID, nil)
            }
            if let firstDraftID = activeDrafts.first?.id {
                return (.existing, firstDraftID, nil)
            }
            return (.create, nil, rememberedProjectID)
        case .create:
            return (.create, activeDrafts.first?.id, rememberedProjectID)
        }
    }

    static func ensureDefaultSelection(
        selectedDefaultDraftID: UUID?,
        rememberedDraftIDRaw: String,
        activeDrafts: [MaterialSheetDraft]
    ) -> UUID? {
        if let selectedDefaultDraftID,
           activeDrafts.contains(where: { $0.id == selectedDefaultDraftID }) {
            return selectedDefaultDraftID
        }
        if let rememberedId = UUID(uuidString: rememberedDraftIDRaw),
           activeDrafts.contains(where: { $0.id == rememberedId }) {
            return rememberedId
        }
        return activeDrafts.first?.id
    }

    static func projectName(for projectID: UUID?, projects: [Project]) -> String? {
        guard let projectID else { return nil }
        return projects.first(where: { $0.id == projectID })?.name
    }

    static func materialSheetDraftPickerTitle(_ draft: MaterialSheetDraft, projects: [Project]) -> String {
        let resolvedTitle = draft.title.isEmpty ? "未命名材料单" : draft.title
        let projectPart = projectName(for: draft.projectId, projects: projects) ?? "无归属"
        return "\(resolvedTitle) · \(projectPart)"
    }

    static func recentlyAddedSummary(
        for draft: MaterialSheetDraft,
        recentlyAddedDraftID: UUID?,
        recentlyAddedItemCount: Int
    ) -> String {
        guard recentlyAddedDraftID == draft.id, recentlyAddedItemCount > 0 else { return "" }
        return " · 最近添加 \(recentlyAddedItemCount) 项"
    }

    static func defaultMaterialSheetDraftTitle(
        projectId: UUID?,
        projects: [Project],
        now: Date = Date()
    ) -> String {
        if let name = projectName(for: projectId, projects: projects), !name.isEmpty {
            return "\(name)-材料单"
        }
        return "材料单-\(Formatters.date.string(from: now))"
    }

    static func resolvedMaterialSheetDraftTitle(
        inputTitle: String,
        projectId: UUID?,
        projects: [Project]
    ) -> String {
        let input = inputTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            return input
        }
        return defaultMaterialSheetDraftTitle(projectId: projectId, projects: projects)
    }

    static func materialDisplayName(_ item: UserMaterial) -> String {
        item.specification.isEmpty ? item.name : "\(item.name) \(item.specification)"
    }

    static func materialKey(_ item: CommonMaterial) -> String {
        materialKey(name: item.name, specification: item.specification, unit: item.unit)
    }

    static func legacyMaterialKey(_ item: CommonMaterial) -> String {
        legacyMaterialKey(name: item.name, specification: item.specification, unit: item.unit)
    }

    static func materialKey(name: String, specification: String, unit: String) -> String {
        MaterialIdentity.key(name: name, specification: specification, unit: unit)
    }

    static func legacyMaterialKey(name: String, specification: String, unit: String) -> String {
        "\(name)|\(specification)|\(unit)"
    }

    static func isPresetHidden(_ item: CommonMaterial, hiddenPresetKeys: Set<String>) -> Bool {
        hiddenPresetKeys.contains(materialKey(item)) || hiddenPresetKeys.contains(legacyMaterialKey(item))
    }

    static func normalizedCategory(_ value: String) -> String {
        MaterialIdentity.normalizedCategory(value)
    }

    static func normalizedRememberedProjectID(_ projectID: UUID?, projects: [Project]) -> UUID? {
        guard let projectID,
              projects.contains(where: { $0.id == projectID }) else {
            return nil
        }
        return projectID
    }

    static func matchesPriceFilter(_ entry: MaterialPriceEntry?, priceFilter: MaterialPriceFilter) -> Bool {
        switch priceFilter {
        case .all:
            return true
        case .priced:
            return !(entry?.referencePrice.isEmpty ?? true)
        case .unpriced:
            return entry?.referencePrice.isEmpty ?? true
        }
    }

    static func matchesSearch<Item: Searchable>(
        item: Item,
        normalizedKeyword: String,
        extraFields: [String]
    ) -> Bool {
        SearchMatcher.filter(
            [item],
            keyword: normalizedKeyword,
            extraFields: { _ in extraFields }
        ).isEmpty == false
    }
}

extension MaterialLibraryLogicHelpers {
    static func appendSuccessMessage(itemCount: Int, draftTitle: String) -> String {
        let resolvedTitle = draftTitle.isEmpty ? "未命名材料单" : draftTitle
        if itemCount > 1 {
            return "已添加 \(itemCount) 项到「\(resolvedTitle)」"
        }
        return "已添加到「\(resolvedTitle)」"
    }

    static func toggledBatchSelection(
        selectedByKey: [String: PendingMaterialAppendContext],
        context: PendingMaterialAppendContext
    ) -> [String: PendingMaterialAppendContext] {
        var selected = selectedByKey
        if selected[context.key] != nil {
            selected.removeValue(forKey: context.key)
        } else {
            selected[context.key] = context
        }
        return selected
    }

    static func appendingRecentMaterialKey(
        _ key: String,
        to keys: [String],
        maxCount: Int = 20
    ) -> [String] {
        var items = keys
        items.removeAll { $0 == key }
        items.insert(key, at: 0)
        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
        }
        return items
    }

    static func removingRecentMaterialKey(_ key: String, from keys: [String]) -> [String] {
        keys.filter { $0 != key }
    }

    static func recentSearchKeywords(from raw: String) -> [String] {
        raw.split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func rememberRecentSearchKeyword(
        searchText: String,
        currentRaw: String,
        maxCount: Int = 8
    ) -> String {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return currentRaw }
        var items = recentSearchKeywords(from: currentRaw).filter { $0 != term }
        items.insert(term, at: 0)
        return items.prefix(maxCount).joined(separator: "\n")
    }

    static func removeRecentSearchKeyword(term: String, from raw: String) -> String {
        recentSearchKeywords(from: raw)
            .filter { $0 != term }
            .joined(separator: "\n")
    }

    static func deleteConfirmMessage(for target: MaterialLibraryPendingDeleteTarget?) -> String {
        switch target {
        case .preset(let item):
            return "确认删除材料「\(resolvedMaterialTitle(name: item.name, specification: item.specification))」吗？可在回收站恢复。"
        case .user(let item):
            return "确认删除自定义材料「\(resolvedMaterialTitle(name: item.name, specification: item.specification))」吗？可在回收站恢复。"
        case .none:
            return "确认删除所选材料吗？"
        }
    }

    @MainActor
    static func hidePresetMaterial(_ item: CommonMaterial, store: DataStore) {
        let normalizedKey = materialKey(item)
        let legacyKey = legacyMaterialKey(item)
        store.hiddenPresetKeys.insert(normalizedKey)
        store.hiddenPresetKeys.remove(legacyKey)
        store.scheduleSave()
    }

    @MainActor
    static func deleteUserMaterial(
        _ item: UserMaterial,
        store: DataStore,
        undoableDeletion: UndoableDeletionCoordinator,
        notice: Binding<OperationToastNotice?>
    ) {
        let deletion = store.removeUserMaterials(
            ids: Set([item.id]),
            audit: DataStoreDeletionAuditContext(
                summary: AppLocalization.string("materials.library.deleteCustom.summary"),
                detail: materialDisplayName(item),
                source: "MaterialLibraryView"
            )
        )
        guard !deletion.isEmpty else { return }

        let deletedIDs = deletion.removedIDs(\.id)
        store.prependDeletedUserMaterials(deletion.removed, maxCount: 50)

        undoableDeletion.queue(
            notice: notice,
            message: String(
                format: AppLocalization.string("materials.library.deletedCustom.message.format"),
                materialDisplayName(item)
            ),
            undoMessage: AppLocalization.string("materials.library.restoredCustom.message"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreUserMaterials(from: deletion)
                store.removeDeletedUserMaterials(ids: deletedIDs)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    @MainActor
    static func deleteMaterialPriceEntryWithUndo(
        _ entry: MaterialPriceEntry,
        store: DataStore,
        undoableDeletion: UndoableDeletionCoordinator,
        notice: Binding<OperationToastNotice?>
    ) {
        let targets = store.materialPriceEntries.filter { $0.id == entry.id }
        guard !targets.isEmpty else { return }

        let deletion = store.removeMaterialPriceEntries(
            ids: Set([entry.id]),
            audit: DataStoreDeletionAuditContext(
                summary: String(
                    format: AppLocalization.string("materials.library.deletePrice.summary.format"),
                    Int64(targets.count)
                ),
                detail: ListFormatter.localizedString(byJoining: targets.map(\.name)),
                source: "MaterialLibraryView"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: notice,
            message: String(
                format: AppLocalization.string("materials.library.deletedPrice.message.format"),
                Int64(deletion.deletedCount)
            ),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreMaterialPriceEntries(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private static func resolvedMaterialTitle(name: String, specification: String) -> String {
        let trimmedSpec = specification.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSpec.isEmpty {
            return name
        }
        return "\(name) \(trimmedSpec)"
    }
}
