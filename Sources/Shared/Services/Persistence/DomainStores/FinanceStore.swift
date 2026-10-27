import Foundation
import Observation

struct MaterialPriceSpikeDetail: Identifiable, Hashable {
    let id: String
    let projectId: UUID
    let materialName: String
    let specification: String
    let unit: String
    let latestPrice: MoneyValue
    let previousPrice: MoneyValue
    let latestDate: BusinessDateValue
    let previousDate: BusinessDateValue
    let ratio: Decimal
    let isIgnored: Bool
}

@MainActor
@Observable
final class FinanceStore {
    var dashboardCollectionVersions: [String: UInt64] { mutationSink.versions }
    @ObservationIgnored private let mutationSink: DomainStoreMutationSink
    private(set) var materialItems: [MaterialItem] = [] {
        didSet {
            mutationSink.didMutate("materialItems")
            materialItemsByProjectID = Self.groupedByProjectID(materialItems) { $0.projectId }
            rebuildMaterialPriceSpikeIndex()
        }
    }
    private(set) var quoteItems: [QuoteItem] = [] {
        didSet {
            mutationSink.didMutate("quoteItems")
            quoteItemsByProjectID = Self.groupedByProjectID(quoteItems) { $0.projectId }
        }
    }
    private(set) var laborRecords: [LaborRecord] = [] {
        didSet {
            mutationSink.didMutate("laborRecords")
            laborRecordsByProjectID = Self.groupedByProjectID(laborRecords) { $0.projectId }
            latestLaborDateByProjectID = Self.buildLatestDateMap(
                laborRecordsByProjectID,
                dateText: { $0.date }
            )
        }
    }

    private(set) var materialItemsByProjectID: [UUID: [MaterialItem]] = [:]
    private(set) var quoteItemsByProjectID: [UUID: [QuoteItem]] = [:]
    private(set) var laborRecordsByProjectID: [UUID: [LaborRecord]] = [:]
    private(set) var materialPriceSpikeCountByProjectID: [UUID: Int] = [:]
    private(set) var latestLaborDateByProjectID: [UUID: Date] = [:]
    private(set) var materialPriceSpikeDetailsByProjectID: [UUID: [MaterialPriceSpikeDetail]] = [:]
    private(set) var totalMaterialPriceSpikeCount = 0

    private(set) var materialPriceSpikeThreshold: Double
    private(set) var ignoredMaterialPriceSpikeKeys: Set<String>

    init(mutationSink: DomainStoreMutationSink? = nil) {
        self.mutationSink = mutationSink ?? DomainStoreMutationSink()
        materialPriceSpikeThreshold = Self.loadMaterialPriceSpikeThreshold()
        ignoredMaterialPriceSpikeKeys = Self.loadMaterialPriceSpikeIgnoredKeys()
    }

    func materialItems(for projectId: UUID) -> [MaterialItem] {
        materialItemsByProjectID[projectId] ?? []
    }

    func quoteItems(for projectId: UUID) -> [QuoteItem] {
        quoteItemsByProjectID[projectId] ?? []
    }

    func laborRecords(for projectId: UUID) -> [LaborRecord] {
        laborRecordsByProjectID[projectId] ?? []
    }

    func latestLaborDate(for projectId: UUID) -> Date? {
        latestLaborDateByProjectID[projectId]
    }

    func materialPriceSpikeCount(for projectId: UUID) -> Int {
        materialPriceSpikeCountByProjectID[projectId] ?? 0
    }

    func materialPriceSpikeDetails(for projectId: UUID, includeIgnored: Bool = false) -> [MaterialPriceSpikeDetail] {
        let details = materialPriceSpikeDetailsByProjectID[projectId] ?? []
        if includeIgnored { return details }
        return details.filter { !$0.isIgnored }
    }

    func materialPriceSpikeDetails(for projectIDs: Set<UUID>, includeIgnored: Bool = false) -> [MaterialPriceSpikeDetail] {
        let details = projectIDs.flatMap { materialPriceSpikeDetailsByProjectID[$0] ?? [] }
        let visibleDetails: [MaterialPriceSpikeDetail]
        if includeIgnored {
            visibleDetails = details
        } else {
            visibleDetails = details.filter { !$0.isIgnored }
        }
        return visibleDetails.sorted(by: Self.compareMaterialPriceSpikeDetails)
    }

    func setMaterialPriceSpikeThreshold(_ value: Double) {
        let clamped = Self.clampedMaterialPriceSpikeThreshold(value)
        guard abs(materialPriceSpikeThreshold - clamped) > 0.0001 else { return }
        materialPriceSpikeThreshold = clamped
        UserPreferencesStore.shared.set(clamped, for: UserPreferenceKeys.materialPriceSpikeThreshold)
        rebuildMaterialPriceSpikeIndex()
    }

    func setMaterialPriceSpikeIgnored(_ ignored: Bool, for detailKey: String) {
        var nextIgnoredKeys = ignoredMaterialPriceSpikeKeys
        if ignored {
            nextIgnoredKeys.insert(detailKey)
        } else {
            nextIgnoredKeys.remove(detailKey)
        }
        setMaterialPriceSpikeIgnoredKeys(nextIgnoredKeys)
    }

    private func setMaterialPriceSpikeIgnoredKeys(_ keys: Set<String>) {
        guard keys != ignoredMaterialPriceSpikeKeys else { return }
        ignoredMaterialPriceSpikeKeys = keys
        let rawValue = keys.sorted().joined(separator: "\n")
        UserPreferencesStore.shared.set(rawValue, for: UserPreferenceKeys.materialPriceSpikeIgnoredKeys)
        rebuildMaterialPriceSpikeIndex()
    }

    private static func groupedByProjectID<Value>(
        _ values: [Value],
        projectID: (Value) -> UUID?
    ) -> [UUID: [Value]] {
        var grouped: [UUID: [Value]] = [:]
        grouped.reserveCapacity(32)
        for value in values {
            guard let id = projectID(value) else { continue }
            grouped[id, default: []].append(value)
        }
        return grouped
    }

    private static func buildLatestDateMap<Value>(
        _ groupedValues: [UUID: [Value]],
        dateText: (Value) -> BusinessDateValue
    ) -> [UUID: Date] {
        var latestMap: [UUID: Date] = [:]
        latestMap.reserveCapacity(groupedValues.count)
        for (projectId, values) in groupedValues {
            let latestDate = values
                .compactMap { Formatters.parseDateOrDateTime(dateText($0)) }
                .max()
            if let latestDate {
                latestMap[projectId] = latestDate
            }
        }
        return latestMap
    }

    private func rebuildMaterialPriceSpikeIndex() {
        var countsByProjectID: [UUID: Int] = [:]
        countsByProjectID.reserveCapacity(materialItemsByProjectID.count)
        var detailsByProjectID: [UUID: [MaterialPriceSpikeDetail]] = [:]
        detailsByProjectID.reserveCapacity(materialItemsByProjectID.count)
        var totalCount = 0

        for (projectId, items) in materialItemsByProjectID {
            let details = Self.materialPriceSpikeDetails(
                in: items,
                projectId: projectId,
                ignoredDetailKeys: ignoredMaterialPriceSpikeKeys,
                threshold: materialPriceSpikeThreshold
            )
            if !details.isEmpty {
                detailsByProjectID[projectId] = details
                let activeCount = details.reduce(into: 0) { partial, detail in
                    if !detail.isIgnored {
                        partial += 1
                    }
                }
                if activeCount > 0 {
                    countsByProjectID[projectId] = activeCount
                    totalCount += activeCount
                }
            }
        }

        materialPriceSpikeCountByProjectID = countsByProjectID
        materialPriceSpikeDetailsByProjectID = detailsByProjectID
        totalMaterialPriceSpikeCount = totalCount
    }

    private static func materialPriceSpikeDetails(
        in items: [MaterialItem],
        projectId: UUID,
        ignoredDetailKeys: Set<String>,
        threshold: Double
    ) -> [MaterialPriceSpikeDetail] {
        let keyedGroups = Dictionary(grouping: items.filter { $0.unitPrice > 0 }) {
            materialPriceKey(for: $0)
        }

        var details: [MaterialPriceSpikeDetail] = []
        details.reserveCapacity(keyedGroups.count)

        for (materialKey, groupItems) in keyedGroups {
            let detailKey = materialPriceSpikeDetailKey(projectId: projectId, materialKey: materialKey)
            let records = groupItems.sorted { lhs, rhs in
                compareMaterialPurchaseDate(lhs.arrivalDate, rhs.arrivalDate) == .orderedDescending
            }
            guard records.count >= 2 else { continue }

            let latestRecord = records[0]
            let previousRecord = records[1]
            let latest = latestRecord.unitPrice
            let previous = previousRecord.unitPrice
            guard previous > 0 else { continue }
            let ratio = (latest - previous) / previous
            guard ratio >= Decimal(threshold) else { continue }

            let latestName = latestRecord.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousName = previousRecord.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let latestSpec = latestRecord.specification.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousSpec = previousRecord.specification.trimmingCharacters(in: .whitespacesAndNewlines)
            let latestUnit = latestRecord.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousUnit = previousRecord.unit.trimmingCharacters(in: .whitespacesAndNewlines)

            details.append(
                MaterialPriceSpikeDetail(
                    id: detailKey,
                    projectId: projectId,
                    materialName: latestName.isEmpty ? previousName : latestName,
                    specification: latestSpec.isEmpty ? previousSpec : latestSpec,
                    unit: latestUnit.isEmpty ? previousUnit : latestUnit,
                    latestPrice: latest,
                    previousPrice: previous,
                    latestDate: latestRecord.arrivalDate,
                    previousDate: previousRecord.arrivalDate,
                    ratio: ratio,
                    isIgnored: ignoredDetailKeys.contains(detailKey)
                )
            )
        }

        return details.sorted(by: compareMaterialPriceSpikeDetails)
    }

    private static func compareMaterialPriceSpikeDetails(
        _ lhs: MaterialPriceSpikeDetail,
        _ rhs: MaterialPriceSpikeDetail
    ) -> Bool {
        if lhs.ratio != rhs.ratio { return lhs.ratio > rhs.ratio }
        if lhs.latestDate != rhs.latestDate {
            return lhs.latestDate > rhs.latestDate
        }
        if lhs.materialName != rhs.materialName {
            return lhs.materialName.localizedStandardCompare(rhs.materialName) == .orderedAscending
        }
        return lhs.projectId.uuidString < rhs.projectId.uuidString
    }

    private static func materialPriceSpikeDetailKey(projectId: UUID, materialKey: String) -> String {
        "\(projectId.uuidString.lowercased())|\(materialKey)"
    }

    private static func clampedMaterialPriceSpikeThreshold(_ value: Double) -> Double {
        min(max(value, 0.01), 1.0)
    }

    private static func loadMaterialPriceSpikeThreshold() -> Double {
        let value = UserPreferencesStore.shared.double(
            UserPreferenceKeys.materialPriceSpikeThreshold,
            default: 0.1
        )
        return clampedMaterialPriceSpikeThreshold(value)
    }

    private static func loadMaterialPriceSpikeIgnoredKeys() -> Set<String> {
        let rawValue = UserPreferencesStore.shared.string(
            UserPreferenceKeys.materialPriceSpikeIgnoredKeys,
            default: "",
            trimWhitespace: false
        )
        let keys = rawValue
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(keys)
    }

    private static func materialPriceKey(for item: MaterialItem) -> String {
        [
            item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            item.specification.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            item.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ]
            .joined(separator: "|")
    }

    private static func compareMaterialPurchaseDate(_ lhs: BusinessDateValue, _ rhs: BusinessDateValue) -> ComparisonResult {
        let leftDate = Formatters.parseDateOrDateTime(lhs) ?? .distantPast
        let rightDate = Formatters.parseDateOrDateTime(rhs) ?? .distantPast
        if leftDate == rightDate { return .orderedSame }
        return leftDate > rightDate ? .orderedDescending : .orderedAscending
    }

    func setMaterialItems(_ value: [MaterialItem]) { materialItems = value }
    func setQuoteItems(_ value: [QuoteItem]) { quoteItems = value }
    func setLaborRecords(_ value: [LaborRecord]) { laborRecords = value }
}
