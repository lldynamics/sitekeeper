extension SiteKeeperCADKernel {
    struct CADSelectionEngine {
        func select(point: CADPoint, in database: CADDatabase) -> CADEntity? {
            database.entities.first { $0.bounds.contains(point) }
        }

        func select(bounds: CADBounds, in database: CADDatabase) -> [CADEntity] {
            database.entities.filter { $0.bounds.intersects(bounds) }
        }
    }
}
