import Foundation

extension SiteKeeperCADKernel {
    struct CADTransform: Equatable, Codable {
        var matrix: CADMatrix

        init(matrix: CADMatrix = .identity) {
            self.matrix = matrix
        }

        static let identity = CADTransform()

        static func translation(x: Double, y: Double) -> CADTransform {
            CADTransform(matrix: .translation(x: x, y: y))
        }

        static func scale(_ value: Double) -> CADTransform {
            CADTransform(matrix: .scale(value))
        }

        static func scale(x: Double, y: Double) -> CADTransform {
            CADTransform(matrix: .scale(x: x, y: y))
        }

        static func rotation(_ radians: Double) -> CADTransform {
            CADTransform(matrix: .rotation(radians))
        }

        func apply(to point: CADPoint) -> CADPoint {
            matrix.transform(point)
        }

        var approximateScale: Double {
            let xScale = hypot(matrix.a, matrix.b)
            let yScale = hypot(matrix.c, matrix.d)
            let scale = (xScale + yScale) / 2
            return scale.isFinite && scale > 0 ? scale : 1
        }

        func concatenating(_ other: CADTransform) -> CADTransform {
            CADTransform(matrix: matrix.concatenating(other.matrix))
        }

        func inverted() -> CADTransform? {
            matrix.inverted().map(CADTransform.init(matrix:))
        }
    }
}
