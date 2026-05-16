import Foundation

extension SiteKeeperCADKernel {
    struct CADMatrix: Equatable, Codable {
        var a: Double
        var b: Double
        var c: Double
        var d: Double
        var tx: Double
        var ty: Double

        static let identity = CADMatrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

        static func translation(x: Double, y: Double) -> CADMatrix {
            CADMatrix(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
        }

        static func scale(_ value: Double) -> CADMatrix {
            CADMatrix(a: value, b: 0, c: 0, d: value, tx: 0, ty: 0)
        }

        static func scale(x: Double, y: Double) -> CADMatrix {
            CADMatrix(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
        }

        static func rotation(_ radians: Double) -> CADMatrix {
            CADMatrix(a: cos(radians), b: sin(radians), c: -sin(radians), d: cos(radians), tx: 0, ty: 0)
        }

        func transform(_ point: CADPoint) -> CADPoint {
            CADPoint(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
        }

        func concatenating(_ other: CADMatrix) -> CADMatrix {
            CADMatrix(
                a: a * other.a + c * other.b,
                b: b * other.a + d * other.b,
                c: a * other.c + c * other.d,
                d: b * other.c + d * other.d,
                tx: a * other.tx + c * other.ty + tx,
                ty: b * other.tx + d * other.ty + ty
            )
        }

        func inverted() -> CADMatrix? {
            let determinant = a * d - b * c
            guard determinant.isFinite, abs(determinant) > 0.000000000001 else { return nil }
            return CADMatrix(
                a: d / determinant,
                b: -b / determinant,
                c: -c / determinant,
                d: a / determinant,
                tx: (c * ty - d * tx) / determinant,
                ty: (b * tx - a * ty) / determinant
            )
        }
    }
}
