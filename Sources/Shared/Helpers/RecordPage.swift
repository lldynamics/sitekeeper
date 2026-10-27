import Foundation

/// A bounded UI page; totals and exports continue to use the complete dataset.
struct RecordPage<Element> {
    let items: [Element]
    let index: Int
    let count: Int

    init(_ records: [Element], index: Int, size: Int = 50) {
        let size = max(size, 1)
        count = max(1, (records.count / size) + (records.count % size == 0 ? 0 : 1))
        self.index = min(max(index, 0), count - 1)
        let start = self.index * size
        items = Array(records[start ..< min(start + size, records.count)])
    }
}
