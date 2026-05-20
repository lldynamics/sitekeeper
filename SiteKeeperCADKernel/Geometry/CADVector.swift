import Foundation

extension SiteKeeperCADKernel {
    struct CADVector: Equatable, Codable, Hashable {
        var dx: Double
        var dy: Double

        var length: Double {
            sqrt(dx * dx + dy * dy)
        }

        var normalized: CADVector {
            let value = length
            guard value > 0 else { return CADVector(dx: 0, dy: 0) }
            return CADVector(dx: dx / value, dy: dy / value)
        }
    }
}
