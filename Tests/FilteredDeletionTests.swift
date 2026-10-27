import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct FilteredDeletionTests {
    // 模拟：过滤后的列表删除不应影响原数组中其他元素
    @Test func filteredDeleteById() {
        let items: [MaterialItem] = [
            MaterialItem(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000000")!, name: "A", quantity: NumericInputSupport.quantity("1"), unit: "个", projectId: nil),
            MaterialItem(id: UUID(uuidString: "B0000000-0000-0000-0000-000000000000")!, name: "B", quantity: NumericInputSupport.quantity("2"), unit: "个", projectId: nil),
            MaterialItem(id: UUID(uuidString: "C0000000-0000-0000-0000-000000000000")!, name: "C", quantity: NumericInputSupport.quantity("3"), unit: "个", projectId: nil),
        ]
        let searchText = "B"
        let filtered = items.filter { $0.name.localizedStandardContains(searchText) }
        #expect(filtered.count == 1)

        let deleteId = filtered[0].id
        var mutable = items
        mutable.removeAll { $0.id == deleteId }
        #expect(mutable.count == 2)
        #expect(mutable[0].name == "A")
        #expect(mutable[1].name == "C")
    }

    // 空搜索删除所有
    @Test func emptySearchDeleteAll() {
        var items: [MaterialItem] = [
            MaterialItem(name: "A", quantity: NumericInputSupport.quantity(""), unit: "", projectId: nil),
            MaterialItem(name: "B", quantity: NumericInputSupport.quantity(""), unit: "", projectId: nil),
        ]
        let filtered = items.filter { _ in true }
        let ids = filtered.map { $0.id }
        items.removeAll { ids.contains($0.id) }
        #expect(items.isEmpty)
    }
}
