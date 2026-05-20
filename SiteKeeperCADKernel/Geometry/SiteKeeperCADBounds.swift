extension SiteKeeperCADKernel {
    struct CADBounds: Equatable, Codable, Hashable {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double

        static let empty = CADBounds(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)

        enum CodingKeys: String, CodingKey {
            case isEmpty
            case minX
            case minY
            case maxX
            case maxY
        }

        init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let isEmpty = try container.decodeIfPresent(Bool.self, forKey: .isEmpty) ?? false
            if isEmpty {
                self = .empty
                return
            }
            minX = try container.decode(Double.self, forKey: .minX)
            minY = try container.decode(Double.self, forKey: .minY)
            maxX = try container.decode(Double.self, forKey: .maxX)
            maxY = try container.decode(Double.self, forKey: .maxY)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(isEmpty, forKey: .isEmpty)
            guard !isEmpty else { return }
            try container.encode(minX, forKey: .minX)
            try container.encode(minY, forKey: .minY)
            try container.encode(maxX, forKey: .maxX)
            try container.encode(maxY, forKey: .maxY)
        }

        var isEmpty: Bool {
            minX > maxX || minY > maxY
        }

        var width: Double {
            isEmpty ? 0 : maxX - minX
        }

        var height: Double {
            isEmpty ? 0 : maxY - minY
        }

        var center: CADPoint {
            guard !isEmpty else { return .zero }
            return CADPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        }

        func contains(_ point: CADPoint) -> Bool {
            !isEmpty && point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }

        func intersects(_ other: CADBounds) -> Bool {
            guard !isEmpty, !other.isEmpty else { return false }
            return maxX >= other.minX && minX <= other.maxX && maxY >= other.minY && minY <= other.maxY
        }

        func union(_ other: CADBounds) -> CADBounds {
            guard !isEmpty else { return other }
            guard !other.isEmpty else { return self }
            return CADBounds(
                minX: min(minX, other.minX),
                minY: min(minY, other.minY),
                maxX: max(maxX, other.maxX),
                maxY: max(maxY, other.maxY)
            )
        }

        func including(_ point: CADPoint) -> CADBounds {
            union(CADBounds(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y))
        }

        func expanded(by value: Double) -> CADBounds {
            guard !isEmpty else { return self }
            let amount = max(0, value)
            return CADBounds(
                minX: minX - amount,
                minY: minY - amount,
                maxX: maxX + amount,
                maxY: maxY + amount
            )
        }

        func applying(_ transform: CADTransform) -> CADBounds {
            guard !isEmpty else { return .empty }
            return [
                CADPoint(x: minX, y: minY),
                CADPoint(x: minX, y: maxY),
                CADPoint(x: maxX, y: minY),
                CADPoint(x: maxX, y: maxY)
            ].reduce(CADBounds.empty) { partial, point in
                partial.including(transform.apply(to: point))
            }
        }
    }
}
