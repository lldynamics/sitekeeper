extension NativeCAD {
    struct CADQuadTree<Element> {
        fileprivate typealias Bounds = SiteKeeperCADKernel.CADBounds

        fileprivate struct Entry {
            var bounds: Bounds
            var value: Element
        }

        fileprivate final class Node {
            let bounds: Bounds
            let depth: Int
            var entries: [Entry]
            var children: [Node]?

            init(bounds: Bounds, depth: Int) {
                self.bounds = bounds
                self.depth = depth
                self.entries = []
                self.children = nil
            }
        }

        private var root: Node?
        private var overflowEntries: [Entry]
        private let capacity: Int
        private let maxDepth: Int

        init(
            bounds: SiteKeeperCADKernel.CADBounds = .empty,
            capacity: Int = 16,
            maxDepth: Int = 8
        ) {
            root = bounds.isEmpty ? nil : Node(bounds: bounds, depth: 0)
            overflowEntries = []
            self.capacity = max(4, capacity)
            self.maxDepth = max(1, maxDepth)
        }

        var count: Int {
            (root?.entryCount ?? 0) + overflowEntries.count
        }

        mutating func insert(_ value: Element, bounds: SiteKeeperCADKernel.CADBounds) {
            let entry = Entry(bounds: bounds, value: value)
            guard let root, !bounds.isEmpty, root.bounds.intersects(bounds) else {
                overflowEntries.append(entry)
                return
            }
            root.insert(entry, capacity: capacity, maxDepth: maxDepth)
        }

        mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
            root?.removeAll(keepingCapacity: keepCapacity)
            overflowEntries.removeAll(keepingCapacity: keepCapacity)
        }

        func query(_ bounds: SiteKeeperCADKernel.CADBounds) -> [Element] {
            if bounds.isEmpty {
                return allValues
            }
            var values: [Element] = []
            root?.query(bounds, into: &values)
            values.append(contentsOf: overflowEntries.compactMap { entry in
                entry.bounds.intersects(bounds) ? entry.value : nil
            })
            return values
        }

        private var allValues: [Element] {
            var values: [Element] = []
            root?.collectValues(into: &values)
            values.append(contentsOf: overflowEntries.map(\.value))
            return values
        }
    }
}

private extension NativeCAD.CADQuadTree.Node {
    var entryCount: Int {
        entries.count + (children ?? []).reduce(0) { $0 + $1.entryCount }
    }

    func insert(
        _ entry: NativeCAD.CADQuadTree<Element>.Entry,
        capacity: Int,
        maxDepth: Int
    ) {
        if let child = child(containing: entry.bounds) {
            child.insert(entry, capacity: capacity, maxDepth: maxDepth)
            return
        }

        entries.append(entry)
        guard entries.count > capacity, depth < maxDepth else { return }
        subdivideIfNeeded()
        redistributeEntries(capacity: capacity, maxDepth: maxDepth)
    }

    func query(
        _ queryBounds: SiteKeeperCADKernel.CADBounds,
        into values: inout [Element]
    ) {
        guard bounds.intersects(queryBounds) else { return }
        for entry in entries where entry.bounds.intersects(queryBounds) {
            values.append(entry.value)
        }
        children?.forEach { $0.query(queryBounds, into: &values) }
    }

    func collectValues(into values: inout [Element]) {
        values.append(contentsOf: entries.map(\.value))
        children?.forEach { $0.collectValues(into: &values) }
    }

    func removeAll(keepingCapacity keepCapacity: Bool) {
        entries.removeAll(keepingCapacity: keepCapacity)
        children?.forEach { $0.removeAll(keepingCapacity: keepCapacity) }
        if !keepCapacity {
            children = nil
        }
    }

    private func subdivideIfNeeded() {
        guard children == nil, bounds.width > 0, bounds.height > 0 else { return }

        let midX = (bounds.minX + bounds.maxX) / 2
        let midY = (bounds.minY + bounds.maxY) / 2
        children = [
            NativeCAD.CADQuadTree<Element>.Node(
                bounds: SiteKeeperCADKernel.CADBounds(
                    minX: bounds.minX,
                    minY: bounds.minY,
                    maxX: midX,
                    maxY: midY
                ),
                depth: depth + 1
            ),
            NativeCAD.CADQuadTree<Element>.Node(
                bounds: SiteKeeperCADKernel.CADBounds(
                    minX: midX,
                    minY: bounds.minY,
                    maxX: bounds.maxX,
                    maxY: midY
                ),
                depth: depth + 1
            ),
            NativeCAD.CADQuadTree<Element>.Node(
                bounds: SiteKeeperCADKernel.CADBounds(
                    minX: bounds.minX,
                    minY: midY,
                    maxX: midX,
                    maxY: bounds.maxY
                ),
                depth: depth + 1
            ),
            NativeCAD.CADQuadTree<Element>.Node(
                bounds: SiteKeeperCADKernel.CADBounds(
                    minX: midX,
                    minY: midY,
                    maxX: bounds.maxX,
                    maxY: bounds.maxY
                ),
                depth: depth + 1
            )
        ]
    }

    private func redistributeEntries(capacity: Int, maxDepth: Int) {
        guard children != nil else { return }
        let pendingEntries = entries
        entries.removeAll(keepingCapacity: true)

        for entry in pendingEntries {
            if let child = child(containing: entry.bounds) {
                child.insert(entry, capacity: capacity, maxDepth: maxDepth)
            } else {
                entries.append(entry)
            }
        }
    }

    private func child(containing entryBounds: SiteKeeperCADKernel.CADBounds) -> NativeCAD.CADQuadTree<Element>.Node? {
        children?.first { child in
            child.bounds.fullyContains(entryBounds)
        }
    }
}

private extension SiteKeeperCADKernel.CADBounds {
    func fullyContains(_ other: SiteKeeperCADKernel.CADBounds) -> Bool {
        guard !isEmpty, !other.isEmpty else { return false }
        return other.minX >= minX
            && other.maxX <= maxX
            && other.minY >= minY
            && other.maxY <= maxY
    }
}
