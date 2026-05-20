extension SiteKeeperCADKernel {
    struct CADPath: Equatable, Codable {
        enum Element: Equatable, Codable {
            case move(to: CADPoint)
            case line(to: CADPoint)
            case curve(to: CADPoint, control1: CADPoint, control2: CADPoint)
            case close
        }

        var elements: [Element]

        init(elements: [Element] = []) {
            self.elements = elements
        }

        var bounds: CADBounds {
            elements.reduce(.empty) { partial, element in
                switch element {
                case let .move(point), let .line(point):
                    return partial.including(point)
                case let .curve(point, control1, control2):
                    return partial.including(point).including(control1).including(control2)
                case .close:
                    return partial
                }
            }
        }

        var points: [CADPoint] {
            elements.compactMap { element in
                switch element {
                case let .move(point), let .line(point):
                    return point
                case let .curve(point, _, _):
                    return point
                case .close:
                    return nil
                }
            }
        }

        func applying(_ transform: CADTransform) -> CADPath {
            CADPath(
                elements: elements.map { element in
                    switch element {
                    case let .move(point):
                        return .move(to: transform.apply(to: point))
                    case let .line(point):
                        return .line(to: transform.apply(to: point))
                    case let .curve(point, control1, control2):
                        return .curve(
                            to: transform.apply(to: point),
                            control1: transform.apply(to: control1),
                            control2: transform.apply(to: control2)
                        )
                    case .close:
                        return .close
                    }
                }
            )
        }
    }
}
