import Foundation

extension SiteKeeperCADKernel {
    struct CADBlock: Identifiable, Equatable, Codable {
        var id: String
        var name: String
        var basePoint: CADPoint
        var entities: [CADEntity]
        var bounds: CADBounds
        var sourceHandle: String?

        init(
            id: String = UUID().uuidString,
            name: String,
            basePoint: CADPoint = .zero,
            entities: [CADEntity] = [],
            bounds: CADBounds = .empty,
            sourceHandle: String? = nil
        ) {
            self.id = id
            self.name = name
            self.basePoint = basePoint
            self.entities = entities
            self.bounds = bounds
            self.sourceHandle = sourceHandle
        }
    }
}
