import SwiftUI

struct ProjectWarehouseMaterialSuggestion: Identifiable {
    let name: String
    let specification: String
    let unit: String
    let source: String
    let usageCount: Int
    let projectMatched: Bool

    var id: String {
        [name, specification, unit].joined(separator: "|").lowercased()
    }

    var detailText: String {
        [specification, unit].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func suggestions(
        input: String,
        projectId: UUID?,
        warehouseMovements: [ProjectWarehouseMovement],
        materialItems: [MaterialItem],
        priceEntries: [MaterialPriceEntry]
    ) -> [ProjectWarehouseMaterialSuggestion] {
        var buckets: [String: ProjectWarehouseMaterialSuggestionBucket] = [:]
        for movement in warehouseMovements {
            mergeSuggestion(
                name: movement.materialName,
                specification: movement.specification,
                unit: movement.unit,
                source: AppLocalization.string("仓库"),
                sourceRank: 0,
                count: 1,
                projectMatched: movement.projectId == projectId, buckets: &buckets
            )
        }

        for item in materialItems {
            mergeSuggestion(
                name: item.name,
                specification: item.specification,
                unit: item.unit,
                source: AppLocalization.string("材料"),
                sourceRank: 1,
                count: 1,
                projectMatched: item.projectId == projectId, buckets: &buckets
            )
        }

        for entry in priceEntries {
            mergeSuggestion(
                name: entry.name,
                specification: entry.specification,
                unit: entry.unit,
                source: AppLocalization.string("材料库"),
                sourceRank: 2,
                count: 0,
                projectMatched: false, buckets: &buckets
            )
        }

        for material in MaterialLibrary.all {
            mergeSuggestion(
                name: material.name,
                specification: material.specification,
                unit: material.unit,
                source: AppLocalization.string("预置材料"),
                sourceRank: 3,
                count: 0,
                projectMatched: false, buckets: &buckets
            )
        }

        return rankedSuggestions(buckets: buckets, input: input)
    }

    private static func mergeSuggestion(
        name: String, specification: String, unit: String, source: String,
        sourceRank: Int, count: Int, projectMatched: Bool,
        buckets: inout [String: ProjectWarehouseMaterialSuggestionBucket]
    ) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let specification = specification.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = [name.lowercased(), specification.lowercased(), unit.lowercased()].joined(separator: "|")
        var bucket = buckets[key] ?? ProjectWarehouseMaterialSuggestionBucket(
            name: name,
            specification: specification,
            unit: unit,
            source: source,
            sourceRank: sourceRank,
            usageCount: 0,
            projectMatched: false
        )
        bucket.usageCount += count
        bucket.projectMatched = bucket.projectMatched || projectMatched
        if sourceRank < bucket.sourceRank {
            bucket.source = source
            bucket.sourceRank = sourceRank
        }
        buckets[key] = bucket
    }

    private static func rankedSuggestions(
        buckets: [String: ProjectWarehouseMaterialSuggestionBucket], input: String
    ) -> [ProjectWarehouseMaterialSuggestion] {
        let keyword = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return buckets.values
            .filter { keyword.isEmpty || $0.matches(keyword) }
            .sorted { lhs, rhs in
                if !keyword.isEmpty {
                    let lhsPrefix = lhs.hasNamePrefix(keyword)
                    let rhsPrefix = rhs.hasNamePrefix(keyword)
                    if lhsPrefix != rhsPrefix { return lhsPrefix }
                }
                if lhs.projectMatched != rhs.projectMatched { return lhs.projectMatched }
                if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
                if lhs.sourceRank != rhs.sourceRank { return lhs.sourceRank < rhs.sourceRank }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(8)
            .map { bucket in
                ProjectWarehouseMaterialSuggestion(
                    name: bucket.name,
                    specification: bucket.specification,
                    unit: bucket.unit,
                    source: bucket.source,
                    usageCount: bucket.usageCount,
                    projectMatched: bucket.projectMatched
                )
            }
    }
}

private struct ProjectWarehouseMaterialSuggestionBucket {
    var name: String
    var specification: String
    var unit: String
    var source: String
    var sourceRank: Int
    var usageCount: Int
    var projectMatched: Bool

    func matches(_ keyword: String) -> Bool {
        name.localizedStandardContains(keyword)
            || specification.localizedStandardContains(keyword)
            || unit.localizedStandardContains(keyword)
    }

    func hasNamePrefix(_ keyword: String) -> Bool {
        name.lowercased().hasPrefix(keyword.lowercased())
    }
}

struct ProjectWarehouseMaterialSuggestionRow: View {
    let suggestion: ProjectWarehouseMaterialSuggestion
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(Color.appPrimaryAction)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !suggestion.detailText.isEmpty {
                        Text(suggestion.detailText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(sourceText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: AppLocalization.string("%@，%@"), suggestion.name, suggestion.detailText.isEmpty ? sourceText : suggestion.detailText))
        .accessibilityHint(AppLocalization.string("双击填充材料信息"))
    }

    private var sourceText: String {
        if suggestion.projectMatched {
            return suggestion.source == AppLocalization.string("仓库") ? AppLocalization.string("本项目常用") : AppLocalization.string("本项目")
        }
        if suggestion.usageCount > 1 {
            return String(format: AppLocalization.string("%@ %lld"), suggestion.source, Int64(suggestion.usageCount))
        }
        return suggestion.source
    }
}
