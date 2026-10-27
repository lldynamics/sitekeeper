import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct MaterialLibraryAppendTests {
    @Test(arguments: ["", "0", "-2", "abc", "1abc2", "1.2.3"])
    func invalidQuantityCannotAppendSingleOrBatch(_ input: String) {
        let draft = MaterialSheetDraft(title: "已有材料单", items: [MaterialSheetDraftItem(name: "原材料", quantity: NumericInputSupport.quantity("2"))])
        for count in [1, 3] {
            for mode in [MaterialSheetTargetMode.existing, .create] {
                let result = compute(input, count: count, mode: mode, draft: draft)
                guard case .failure(let message, let nextMode, let nextID) = result else {
                    Issue.record("非法数量不应产生材料单：\(input)，条数：\(count)")
                    continue
                }
                #expect(!message.isEmpty)
                #expect(nextMode == mode)
                #expect(nextID == draft.id)
            }
        }
        #expect(!MaterialLibraryLogicHelpers.appendQuantityValidation(input).isValid)
        #expect(draft.items.count == 1)
    }

    @Test(arguments: [1, 3])
    func validQuantityPreservesAmountForExistingAndNewDrafts(_ count: Int) throws {
        let draft = MaterialSheetDraft(title: "已有材料单")
        for mode in [MaterialSheetTargetMode.existing, .create] {
            let result = compute("1.234,56", count: count, mode: mode, draft: draft)
            guard case .success(let output) = result else {
                Issue.record("有效数量应保存成功")
                continue
            }
            let saved = try #require(output.drafts.first { $0.id == output.targetDraftID })
            let restored = try JSONDecoder().decode(MaterialSheetDraft.self, from: JSONEncoder().encode(saved))
            #expect(restored.items.count == count)
            #expect(restored.items.allSatisfy { $0.quantity.wireText == "1234.56" })
            let total = MaterialSheetLogicHelpers.totals(for: restored.items.map(MaterialSheetItem.init(draftItem:)))
            #expect(total.estimate.decimal == Decimal(123456) / 10 * Decimal(count))
            #expect(output.drafts.count == (mode == .create ? 2 : 1))
        }
    }

    @Test func fractionalQuantityIsNotRoundedOrReplacedWithOne() throws {
        let result = compute("0.0125", count: 1, mode: .create, draft: MaterialSheetDraft())
        guard case .success(let output) = result else {
            Issue.record("正小数数量应保存成功")
            return
        }
        let draft = try #require(output.drafts.first)
        let item = try #require(draft.items.first)
        #expect(item.quantity.wireText == "0.0125")
        #expect(MaterialSheetLogicHelpers.lineTotalValue(for: MaterialSheetItem(draftItem: item)).decimal == Decimal(string: "0.125"))
    }

    private func compute(
        _ quantity: String,
        count: Int,
        mode: MaterialSheetTargetMode,
        draft: MaterialSheetDraft
    ) -> MaterialLibraryLogicHelpers.AppendComputationResult {
        let contexts = (0..<count).map { index in
            PendingMaterialAppendContext(name: "材料\(index)", specification: "", unit: "吨", key: "\(index)",
                                         defaultBrand: "", defaultSupplier: "", defaultUnitPrice: "10")
        }
        return MaterialLibraryLogicHelpers.computeAppendComputation(
            contexts: contexts, quantityText: quantity, noteText: "备注", targetMode: mode,
            targetDraftID: draft.id, targetProjectID: nil, draftTitleInput: "新材料单",
            drafts: [draft], projects: [], now: BusinessDateValue(legacyText: "2026-10-15 10:00"),
            unitPriceResolver: { $0.defaultUnitPrice }
        )
    }
}
