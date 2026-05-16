extension CADPoC {
    struct CADQuadTree<Element> {
        private var entries: [(bounds: SiteKeeperCADKernel.CADBounds, value: Element)]

        init() {
            entries = []
        }

        var count: Int {
            entries.count
        }

        mutating func insert(_ value: Element, bounds: SiteKeeperCADKernel.CADBounds) {
            entries.append((bounds: bounds, value: value))
        }

        mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
            entries.removeAll(keepingCapacity: keepCapacity)
        }

        func query(_ bounds: SiteKeeperCADKernel.CADBounds) -> [Element] {
            entries.compactMap { entry in
                entry.bounds.intersects(bounds) ? entry.value : nil
            }
        }
    }
}
