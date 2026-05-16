import CoreGraphics

extension SiteKeeperCADKernel {
    struct CADPoint: Equatable, Codable, Hashable {
        var x: Double
        var y: Double

        init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        init(_ point: CGPoint) {
            x = point.x
            y = point.y
        }

        var cgPoint: CGPoint {
            CGPoint(x: x, y: y)
        }

        static let zero = CADPoint(x: 0, y: 0)

        func distance(to other: CADPoint) -> Double {
            hypot(other.x - x, other.y - y)
        }

        func offset(dx: Double, dy: Double) -> CADPoint {
            CADPoint(x: x + dx, y: y + dy)
        }
    }
}
