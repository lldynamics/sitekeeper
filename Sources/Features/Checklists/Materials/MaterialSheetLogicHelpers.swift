import Foundation

struct MaterialSheetTotals {
    let estimate: MoneyValue
    let labor: MoneyValue

    var grand: MoneyValue {
        estimate + labor
    }

    var estimateText: String {
        ReportBuilder.money(estimate)
    }

    var laborText: String {
        ReportBuilder.money(labor)
    }

    var grandText: String {
        ReportBuilder.money(grand)
    }
}

enum MaterialSheetLogicHelpers {
    struct DraftArchiveContext {
        let previousDrafts: [MaterialSheetDraft]
        let previousSelectedDraftID: UUID?
        let archivedDraft: MaterialSheetDraft
        let updatedDrafts: [MaterialSheetDraft]
    }

    struct DraftEditorState {
        let sheetItems: [MaterialSheetItem]
        let exportProjectName: String
        let exportPreparer: String
    }

    static func activeDrafts(from drafts: [MaterialSheetDraft]) -> [MaterialSheetDraft] {
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

    static func selectedDraft(
        selectedDraftID: UUID?,
        activeDrafts: [MaterialSheetDraft]
    ) -> MaterialSheetDraft? {
        guard let selectedDraftID else { return nil }
        return activeDrafts.first(where: { $0.id == selectedDraftID })
    }

    static func priceSuggestions(
        keyword: String,
        entries: [MaterialPriceEntry],
        limit: Int = 10
    ) -> [MaterialPriceEntry] {
        guard !keyword.isEmpty else { return [] }
        return Array(SearchMatcher.filter(entries, keyword: keyword).prefix(limit))
    }

    static func librarySuggestions(
        keyword: String,
        materials: [CommonMaterial],
        limit: Int = 10
    ) -> [CommonMaterial] {
        guard !keyword.isEmpty else { return [] }
        return Array(SearchMatcher.filter(materials, keyword: keyword).prefix(limit))
    }

    static func totals(for items: [MaterialSheetItem]) -> MaterialSheetTotals {
        let estimate = items.reduce(MoneyValue.zero) { total, item in
            total + lineTotalValue(for: item)
        }
        let labor = items.reduce(MoneyValue.zero) { total, item in
            total + item.draftItem.laborCost
        }
        return MaterialSheetTotals(estimate: estimate, labor: labor)
    }

    static func lineTotalValue(for item: MaterialSheetItem) -> MoneyValue {
        item.draftItem.quantity * item.draftItem.unitPrice
    }

    static func draftDisplayName(_ draft: MaterialSheetDraft) -> String {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "未命名材料单" : title
    }

    static func projectName(for projectId: UUID, projects: [Project]) -> String? {
        projects.first(where: { $0.id == projectId })?.name
    }

    static func defaultDraftTitle(projectId: UUID?, projects: [Project], now: Date = Date()) -> String {
        if let projectId,
           let projectName = projectName(for: projectId, projects: projects),
           !projectName.isEmpty {
            return "\(projectName)-材料单"
        }
        return "材料单-\(Formatters.date.string(from: now))"
    }

    static func resolvedDraftTitle(input: String, projectId: UUID?, projects: [Project]) -> String {
        let normalizedTitle = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedTitle.isEmpty {
            return normalizedTitle
        }
        return defaultDraftTitle(projectId: projectId, projects: projects)
    }

    static func makeDraft(
        title: String,
        projectId: UUID?,
        projects: [Project],
        now: BusinessDateValue,
        items: [MaterialSheetDraftItem]
    ) -> MaterialSheetDraft {
        MaterialSheetDraft(
            title: resolvedDraftTitle(input: title, projectId: projectId, projects: projects),
            projectId: projectId,
            exportProjectName: projectId.flatMap { projectName(for: $0, projects: projects) } ?? "",
            items: items,
            createdAt: now,
            updatedAt: now
        )
    }

    static func createDraftSheetInput(
        selectedDraft: MaterialSheetDraft?,
        projects: [Project]
    ) -> (title: String, projectID: UUID?) {
        let projectID = selectedDraft?.projectId
        return (
            title: defaultDraftTitle(projectId: projectID, projects: projects),
            projectID: projectID
        )
    }

    static func insertingDraftAtTop(_ draft: MaterialSheetDraft, drafts: [MaterialSheetDraft]) -> [MaterialSheetDraft] {
        var updated = drafts
        updated.insert(draft, at: 0)
        return updated
    }

    static func renamedDrafts(
        selectedDraftID: UUID?,
        title: String,
        drafts: [MaterialSheetDraft],
        now: BusinessDateValue
    ) -> [MaterialSheetDraft]? {
        guard let selectedDraftID,
              let index = drafts.firstIndex(where: { $0.id == selectedDraftID }) else {
            return nil
        }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }
        var updated = drafts
        updated[index].title = normalizedTitle
        updated[index].updatedAt = now
        return updated
    }

    static func archiveContext(
        selectedDraftID: UUID?,
        drafts: [MaterialSheetDraft],
        now: BusinessDateValue
    ) -> DraftArchiveContext? {
        guard let selectedDraftID,
              let index = drafts.firstIndex(where: { $0.id == selectedDraftID }) else {
            return nil
        }
        var updated = drafts
        updated[index].isArchived = true
        updated[index].updatedAt = now
        return DraftArchiveContext(
            previousDrafts: drafts,
            previousSelectedDraftID: selectedDraftID,
            archivedDraft: drafts[index],
            updatedDrafts: updated
        )
    }

    static func resolvedSelectedDraftID(
        currentSelectedDraftID: UUID?,
        activeDraftIDs: [UUID]
    ) -> UUID? {
        guard !activeDraftIDs.isEmpty else { return nil }
        if let currentSelectedDraftID, activeDraftIDs.contains(currentSelectedDraftID) {
            return currentSelectedDraftID
        }
        return activeDraftIDs.first
    }

    static func draftEditorState(
        draft: MaterialSheetDraft,
        projects: [Project]
    ) -> DraftEditorState {
        let exportProjectName: String
        if draft.exportProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let projectID = draft.projectId,
           let projectName = projectName(for: projectID, projects: projects) {
            exportProjectName = projectName
        } else {
            exportProjectName = draft.exportProjectName
        }
        return DraftEditorState(
            sheetItems: draft.items.map(MaterialSheetItem.init(draftItem:)),
            exportProjectName: exportProjectName,
            exportPreparer: draft.exportPreparer
        )
    }

    static func persistingDrafts(
        selectedDraftID: UUID?,
        drafts: [MaterialSheetDraft],
        sheetItems: [MaterialSheetItem],
        exportProjectName: String,
        exportPreparer: String,
        exportDate: String,
        now: BusinessDateValue
    ) -> [MaterialSheetDraft]? {
        guard let selectedDraftID,
              let index = drafts.firstIndex(where: { $0.id == selectedDraftID }) else {
            return nil
        }
        var updated = drafts
        updated[index].items = sheetItems.map(\.draftItem)
        updated[index].exportProjectName = exportProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated[index].exportPreparer = exportPreparer.trimmingCharacters(in: .whitespacesAndNewlines)
        updated[index].exportDate = BusinessDateValue(legacyText: exportDate)
        updated[index].updatedAt = now
        return updated
    }

    static func normalizedDeleteIDs(_ ids: [UUID]) -> Set<UUID> {
        Set(ids)
    }

    static func deletedItemCount(ids: Set<UUID>, sheetItems: [MaterialSheetItem]) -> Int {
        sheetItems.filter { ids.contains($0.id) }.count
    }

    static func suggestedUnitPrice(
        for item: MaterialSheetItem,
        entries: [MaterialPriceEntry]
    ) -> String? {
        let name = MaterialIdentity.normalizedComponent(item.name)
        let specification = MaterialIdentity.normalizedComponent(item.specification)
        let unit = MaterialIdentity.normalizedComponent(item.unit)
        guard !name.isEmpty, !unit.isEmpty else { return nil }
        let match = entries.first { entry in
            MaterialIdentity.normalizedComponent(entry.name) == name &&
                MaterialIdentity.normalizedComponent(entry.specification) == specification &&
                MaterialIdentity.normalizedComponent(entry.unit) == unit
        }
        let price = match?.referencePrice.wireText ?? ""
        return price.isEmpty ? nil : price
    }

    static func materialItemAccessibilityLabel(_ item: MaterialSheetItem, isExpanded: Bool) -> String {
        var parts = [item.name]
        if !item.specification.isEmpty { parts.append("规格 \(item.specification)") }
        parts.append("数量 \(item.quantity)\(item.unit)")
        if !item.unitPrice.isEmpty { parts.append("估价 \(item.unitPrice) 元") }
        parts.append(isExpanded ? "已展开" : "已收起")
        return parts.joined(separator: "，")
    }

    static func normalizedMaterialListQuantity(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return NumericInputSupport.quantity(trimmed).isPositive ? trimmed : "1"
    }

    static func materialSheetItemAuditDetail(_ items: [MaterialSheetItem]) -> String {
        ListFormatter.localizedString(
            byJoining: items.map { item in
                let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let specification = item.specification.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { return AppLocalization.string("未命名材料") }
                return specification.isEmpty ? name : "\(name) \(specification)"
            }
        )
    }
}
