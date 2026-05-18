import Foundation

extension DXFBasic2DParser {
    static func dimensionGeometry(
        start: Kernel.CADPoint,
        end: Kernel.CADPoint,
        dimensionLinePoint: Kernel.CADPoint?,
        textPoint: Kernel.CADPoint?,
        axisAngle: Double?,
        textHeight: Double
    ) -> DimensionGeometry {
        let measuredLength = distance(from: start, to: end)
        guard measuredLength > 0.000001 else {
            let path = Kernel.CADPath(elements: [.move(to: start), .line(to: end)])
            return DimensionGeometry(
                path: path,
                dimensionStart: start,
                dimensionEnd: end,
                defaultTextPoint: midpoint(start, end)
            )
        }

        let axis: Kernel.CADPoint
        if let axisAngle, axisAngle.isFinite {
            axis = Kernel.CADPoint(x: cos(axisAngle), y: sin(axisAngle))
        } else {
            axis = Kernel.CADPoint(
                x: (end.x - start.x) / measuredLength,
                y: (end.y - start.y) / measuredLength
            )
        }

        let reference = dimensionLinePoint ?? textPoint ?? midpoint(start, end)
        let dimensionStart = projectedPoint(start, ontoLineThrough: reference, axis: axis)
        let dimensionEnd = projectedPoint(end, ontoLineThrough: reference, axis: axis)
        let dimensionLength = distance(from: dimensionStart, to: dimensionEnd)
        guard dimensionLength > 0.000001 else {
            let path = Kernel.CADPath(elements: [.move(to: start), .line(to: end)])
            return DimensionGeometry(
                path: path,
                dimensionStart: start,
                dimensionEnd: end,
                defaultTextPoint: midpoint(start, end)
            )
        }

        let path = Kernel.CADPath(elements: [
            .move(to: start),
            .line(to: dimensionStart),
            .line(to: dimensionEnd),
            .line(to: end)
        ])
        let normal = Kernel.CADPoint(x: -axis.y, y: axis.x)
        let labelOffset = max(textHeight * 0.35, 0)
        let defaultTextPoint = Kernel.CADPoint(
            x: (dimensionStart.x + dimensionEnd.x) / 2 + normal.x * labelOffset,
            y: (dimensionStart.y + dimensionEnd.y) / 2 + normal.y * labelOffset
        )
        return DimensionGeometry(
            path: path,
            dimensionStart: dimensionStart,
            dimensionEnd: dimensionEnd,
            defaultTextPoint: defaultTextPoint
        )
    }


    static func projectedPoint(
        _ point: Kernel.CADPoint,
        ontoLineThrough linePoint: Kernel.CADPoint,
        axis: Kernel.CADPoint
    ) -> Kernel.CADPoint {
        let dx = point.x - linePoint.x
        let dy = point.y - linePoint.y
        let distanceAlongAxis = dx * axis.x + dy * axis.y
        return Kernel.CADPoint(
            x: linePoint.x + axis.x * distanceAlongAxis,
            y: linePoint.y + axis.y * distanceAlongAxis
        )
    }


    static func textBounds(
        for text: Kernel.CADTextRun,
        insertion: Kernel.CADPoint,
        height: Double
    ) -> Kernel.CADBounds {
        let widthFactor = text.widthFactor ?? 1
        let measuredWidth = text.boxWidth.flatMap { $0 > 0 ? $0 : nil }
            ?? Double(text.displayText.count) * max(height * 0.6 * widthFactor, 0.6)
        let width = max(measuredWidth, max(height, 0.6))
        let boxHeight = max(text.boxHeight ?? height, height, 0.6)
        let anchorX = textHorizontalOffset(width: width, text: text)
        let anchorY = textVerticalOffset(height: boxHeight, text: text)
        return rotatedTextBounds(
            insertion: insertion,
            width: width,
            height: boxHeight,
            anchorX: anchorX,
            anchorY: anchorY,
            rotationRadians: text.rotationRadians
        )
    }


    static func textHorizontalOffset(width: Double, text: Kernel.CADTextRun) -> Double {
        if text.boxWidth != nil, let alignmentCode = text.horizontalAlignmentCode {
            switch alignmentCode {
            case 2, 5, 8:
                return width / 2
            case 3, 6, 9:
                return width
            default:
                return 0
            }
        }

        switch text.horizontalAlignmentCode {
        case 1, 3, 4, 5:
            return width / 2
        case 2:
            return width
        default:
            return 0
        }
    }


    static func textVerticalOffset(height: Double, text: Kernel.CADTextRun) -> Double {
        if text.boxHeight != nil, let alignmentCode = text.verticalAlignmentCode {
            switch alignmentCode {
            case 1, 2, 3:
                return height
            case 4, 5, 6:
                return height / 2
            default:
                return 0
            }
        }

        switch text.verticalAlignmentCode {
        case 2:
            return height / 2
        case 3:
            return height
        default:
            return 0
        }
    }


    static func rotatedTextBounds(
        insertion: Kernel.CADPoint,
        width: Double,
        height: Double,
        anchorX: Double,
        anchorY: Double,
        rotationRadians: Double
    ) -> Kernel.CADBounds {
        let cosine = cos(rotationRadians)
        let sine = sin(rotationRadians)
        let corners = [
            (0.0, 0.0),
            (width, 0.0),
            (width, height),
            (0.0, height)
        ].map { localX, localY in
            let x = localX - anchorX
            let y = localY - anchorY
            return Kernel.CADPoint(
                x: insertion.x + x * cosine - y * sine,
                y: insertion.y + x * sine + y * cosine
            )
        }
        return corners.reduce(Kernel.CADBounds.empty) { partial, point in
            partial.including(point)
        }
    }


    static func midpoint(_ first: Kernel.CADPoint, _ second: Kernel.CADPoint) -> Kernel.CADPoint {
        Kernel.CADPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }


    static func distance(from start: Kernel.CADPoint, to end: Kernel.CADPoint) -> Double {
        hypot(end.x - start.x, end.y - start.y)
    }


    static func formattedMeasurement(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if abs(rounded - rounded.rounded()) < 0.0001 {
            return String(Int(rounded.rounded()))
        }
        var text = String(format: "%.3f", rounded)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }


    static func makePath(from points: [Kernel.CADPoint], closed: Bool) -> Kernel.CADPath {
        guard let first = points.first else { return Kernel.CADPath() }
        var elements: [Kernel.CADPath.Element] = [.move(to: first)]
        elements.append(contentsOf: points.dropFirst().map { .line(to: $0) })
        if closed {
            elements.append(.close)
        }
        return Kernel.CADPath(elements: elements)
    }


    static func orderedPolylineVertices(
        in pairs: [Pair],
        xCode: Int,
        yCode: Int,
        bulgeCode: Int
    ) -> [PolylineVertex] {
        var vertices: [PolylineVertex] = []
        var index = 0
        while index < pairs.count {
            guard pairs[index].code == xCode,
                  let x = Double(pairs[index].value.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                index += 1
                continue
            }

            var y: Double?
            var bulge: Double = 0
            var cursor = index + 1
            while cursor < pairs.count, pairs[cursor].code != xCode {
                if pairs[cursor].code == yCode {
                    y = Double(pairs[cursor].value.trimmingCharacters(in: .whitespacesAndNewlines))
                } else if pairs[cursor].code == bulgeCode {
                    bulge = Double(pairs[cursor].value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                }
                cursor += 1
            }

            if let y {
                vertices.append(PolylineVertex(point: Kernel.CADPoint(x: x, y: y), bulge: bulge))
            }
            index += 1
        }
        return vertices
    }


    static func tessellatedPolylinePoints(
        vertices: [PolylineVertex],
        closed: Bool
    ) -> [Kernel.CADPoint] {
        guard let first = vertices.first else { return [] }
        var points = [first.point]
        guard vertices.count >= 2 else { return points }

        for index in 0..<(vertices.count - 1) {
            appendBulgeSegment(
                from: vertices[index],
                to: vertices[index + 1].point,
                into: &points
            )
        }
        if closed, vertices.count > 2 {
            appendBulgeSegment(
                from: vertices[vertices.count - 1],
                to: first.point,
                into: &points
            )
        }
        return points
    }


    static func appendBulgeSegment(
        from startVertex: PolylineVertex,
        to end: Kernel.CADPoint,
        into points: inout [Kernel.CADPoint]
    ) {
        let start = startVertex.point
        let bulge = startVertex.bulge
        guard abs(bulge) > 0.000001 else {
            appendDistinct(end, into: &points)
            return
        }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let chord = hypot(dx, dy)
        guard chord.isFinite, chord > .ulpOfOne else {
            return
        }

        let theta = 4 * atan(bulge)
        let radius = chord * (1 + bulge * bulge) / (4 * abs(bulge))
        let centerOffset = chord * (1 - bulge * bulge) / (4 * bulge)
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let normalX = -dy / chord
        let normalY = dx / chord
        let center = Kernel.CADPoint(
            x: midX + normalX * centerOffset,
            y: midY + normalY * centerOffset
        )
        guard radius.isFinite, radius > 0, center.x.isFinite, center.y.isFinite else {
            appendDistinct(end, into: &points)
            return
        }

        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var sweep = endAngle - startAngle
        if theta > 0 {
            while sweep <= 0 {
                sweep += 2 * .pi
            }
        } else {
            while sweep >= 0 {
                sweep -= 2 * .pi
            }
        }

        let segmentCount = min(max(Int(ceil(abs(sweep) / (.pi / 24))), 4), 96)
        for index in 1...segmentCount {
            let t = Double(index) / Double(segmentCount)
            let angle = startAngle + sweep * t
            appendDistinct(
                Kernel.CADPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                ),
                into: &points
            )
        }
    }


    static func appendDistinct(_ point: Kernel.CADPoint, into points: inout [Kernel.CADPoint]) {
        guard point.x.isFinite, point.y.isFinite else { return }
        if let previous = points.last,
           abs(previous.x - point.x) < 0.000001,
           abs(previous.y - point.y) < 0.000001 {
            return
        }
        points.append(point)
    }


    static func tessellatedArcPath(
        center: Kernel.CADPoint,
        radius: Double,
        startDegrees: Double,
        endDegrees: Double,
        closed: Bool
    ) -> Kernel.CADPath {
        var resolvedEnd = endDegrees
        while resolvedEnd < startDegrees {
            resolvedEnd += 360
        }
        let sweep = max(resolvedEnd - startDegrees, 0.001)
        let segmentCount = max(8, min(96, Int(ceil(sweep / 8))))
        let points = (0...segmentCount).map { index -> Kernel.CADPoint in
            let t = Double(index) / Double(segmentCount)
            let degrees = startDegrees + sweep * t
            let radians = degrees * .pi / 180
            return Kernel.CADPoint(
                x: center.x + cos(radians) * radius,
                y: center.y + sin(radians) * radius
            )
        }
        guard let first = points.first else { return Kernel.CADPath() }
        var elements: [Kernel.CADPath.Element] = [.move(to: first)]
        elements.append(contentsOf: points.dropFirst().map { .line(to: $0) })
        if closed {
            elements.append(.close)
        }
        return Kernel.CADPath(elements: elements)
    }


    static func rotationRadians(from transform: Kernel.CADTransform) -> Double {
        atan2(transform.matrix.b, transform.matrix.a)
    }


    static func orderedPoints(in pairs: [Pair], xCode: Int, yCode: Int) -> [Kernel.CADPoint] {
        var points: [Kernel.CADPoint] = []
        var index = 0
        while index < pairs.count {
            guard pairs[index].code == xCode,
                  let x = Double(pairs[index].value.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                index += 1
                continue
            }

            var y: Double?
            var cursor = index + 1
            while cursor < pairs.count, pairs[cursor].code != xCode {
                if pairs[cursor].code == yCode {
                    y = Double(pairs[cursor].value.trimmingCharacters(in: .whitespacesAndNewlines))
                    break
                }
                cursor += 1
            }
            if let y {
                points.append(Kernel.CADPoint(x: x, y: y))
            }
            index += 1
        }
        return points
    }


    static func point(in pairs: [Pair], xCode: Int, yCode: Int) -> Kernel.CADPoint? {
        guard let x = firstDouble(code: xCode, in: pairs),
              let y = firstDouble(code: yCode, in: pairs) else {
            return nil
        }
        return Kernel.CADPoint(x: x, y: y)
    }

}
