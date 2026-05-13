import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct MaterialDomainLogicTests {
    @Test func materialSheetDraftIndexBuildsPerProject() {
        let store = MaterialLibraryStore()
        let projectA = UUID()
        let projectB = UUID()

        store.setMaterialSheetDrafts([
            MaterialSheetDraft(title: "A-1", projectId: projectA),
            MaterialSheetDraft(title: "A-2", projectId: projectA),
            MaterialSheetDraft(title: "B-1", projectId: projectB),
            MaterialSheetDraft(title: "No Project", projectId: nil)
        ])

        #expect(store.materialSheetDraftCount(for: projectA) == 2)
        #expect(store.materialSheetDraftCount(for: projectB) == 1)
        #expect(store.materialSheetDrafts(for: projectA).count == 2)
        #expect(store.materialSheetDrafts(for: UUID()).isEmpty)
    }

    @Test func materialSheetDraftIndexRebuildsAfterReplacement() {
        let store = MaterialLibraryStore()
        let projectA = UUID()
        let projectB = UUID()

        store.setMaterialSheetDrafts([
            MaterialSheetDraft(title: "A", projectId: projectA),
            MaterialSheetDraft(title: "B", projectId: projectB)
        ])
        store.setMaterialSheetDrafts([
            MaterialSheetDraft(title: "B-2", projectId: projectB)
        ])

        #expect(store.materialSheetDraftCount(for: projectA) == 0)
        #expect(store.materialSheetDrafts(for: projectA).isEmpty)
        #expect(store.materialSheetDraftCount(for: projectB) == 1)
    }

    @Test func financeStorePriceSpikeIgnoreToggleAffectsVisibleRiskCount() throws {
        let projectId = UUID()
        let financeStore = FinanceStore()
        financeStore.setMaterialItems([
            MaterialItem(
                name: "BV 线",
                quantity: "1",
                unit: "卷",
                unitPrice: "100",
                arrivalDate: "2026-05-01",
                projectId: projectId
            ),
            MaterialItem(
                name: "BV 线",
                quantity: "1",
                unit: "卷",
                unitPrice: "250",
                arrivalDate: "2026-05-10",
                projectId: projectId
            )
        ])

        #expect(financeStore.materialPriceSpikeCount(for: projectId) == 1)
        let detail = try #require(financeStore.materialPriceSpikeDetails(for: projectId, includeIgnored: true).first)
        #expect(!detail.isIgnored)

        financeStore.setMaterialPriceSpikeIgnored(true, for: detail.id)
        #expect(financeStore.materialPriceSpikeCount(for: projectId) == 0)
        #expect(financeStore.materialPriceSpikeDetails(for: projectId).isEmpty)
        let ignoredDetail = try #require(financeStore.materialPriceSpikeDetails(for: projectId, includeIgnored: true).first)
        #expect(ignoredDetail.isIgnored)

        financeStore.setMaterialPriceSpikeIgnored(false, for: detail.id)
        #expect(financeStore.materialPriceSpikeCount(for: projectId) == 1)
    }
}
