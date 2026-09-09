import Foundation

protocol Searchable {
    var searchableFields: [String] { get }
}

enum SearchMatcher {
    static func filter<Item>(
        _ items: [Item],
        keyword rawKeyword: String,
        sort: ((Item, Item) -> Bool)? = nil,
        extraFields: ((Item) -> [String])? = nil
    ) -> [Item] where Item: Searchable {
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        var scopedItems = keyword.isEmpty ? items : items.filter { item in
            if item.searchableFields.contains(where: { $0.localizedStandardContains(keyword) }) {
                return true
            }
            guard let extraFields else { return false }
            return extraFields(item).contains { $0.localizedStandardContains(keyword) }
        }
        if let sort { scopedItems.sort(by: sort) }
        return scopedItems
    }
}

extension SupplierProfile: Searchable {
    var searchableFields: [String] {
        [name, category, contact, phone, note]
    }
}

extension MaterialPriceEntry: Searchable {
    var searchableFields: [String] {
        [name, specification, brand, supplier, category]
    }
}

extension ProjectContact: Searchable {
    var searchableFields: [String] {
        [name, roleDisplayName, company, phone, note]
    }
}

extension ConstructionMethod: Searchable {
    var searchableFields: [String] {
        [title, trade, tutorialBody, steps, qualityStandard, safetyNotes]
    }
}

extension QuoteItem: Searchable {
    var searchableFields: [String] {
        [name]
    }
}

extension LaborRecord: Searchable {
    var searchableFields: [String] {
        [date, note, workType, teamName]
    }
}

extension MaterialItem: Searchable {
    var searchableFields: [String] {
        [name, specification, brand, supplier]
    }
}

extension ProjectTemplate: Searchable {
    var searchableFields: [String] {
        [name, content]
    }
}

extension SiteTodo: Searchable {
    var searchableFields: [String] {
        [title, owner, dueDate, note]
    }
}

extension Project: Searchable {
    var searchableFields: [String] {
        [name, location]
    }
}

extension ProjectFileItem: Searchable {
    var searchableFields: [String] {
        [title, subtitle]
    }
}

extension DailyLog: Searchable {
    var searchableFields: [String] {
        [date, weather, content, workers, safety, materials, tomorrowPlan, qualityIssue, rectification, confirmer]
    }
}

extension QuickNote: Searchable {
    var searchableFields: [String] {
        [title, content, createdAt, updatedAt, QuickNoteText.attachmentSummary(attachments)]
    }
}

extension CommonMaterial: Searchable {
    var searchableFields: [String] {
        [name, specification, unit, category.displayName]
    }
}

extension UserMaterial: Searchable {
    var searchableFields: [String] {
        [name, specification, unit, category]
    }
}
