import Foundation

extension CADPoC {
    struct CADRenderPipeline {
        var lodPolicy: SiteKeeperCADKernel.CADLODPolicy

        init(lodPolicy: SiteKeeperCADKernel.CADLODPolicy = .standard) {
            self.lodPolicy = lodPolicy
        }

        struct Output {
            var commands: [SiteKeeperCADKernel.CADRenderCommand]
            var performance: SiteKeeperCADKernel.CADPerformanceTrace
        }

        func commands(
            from entities: [SiteKeeperCADKernel.CADEntity],
            layersByID: [String: SiteKeeperCADKernel.CADLayer] = [:],
            totalEntityCount: Int? = nil,
            zoomScale: Double = 1,
            interactionPhase: SiteKeeperCADKernel.CADRenderInteractionPhase = .stable
        ) -> [SiteKeeperCADKernel.CADRenderCommand] {
            renderOutput(
                from: entities,
                layersByID: layersByID,
                totalEntityCount: totalEntityCount,
                zoomScale: zoomScale,
                interactionPhase: interactionPhase
            ).commands
        }

        func renderOutput(
            from entities: [SiteKeeperCADKernel.CADEntity],
            layersByID: [String: SiteKeeperCADKernel.CADLayer] = [:],
            totalEntityCount: Int? = nil,
            visibleEntityCount: Int? = nil,
            zoomScale: Double = 1,
            interactionPhase: SiteKeeperCADKernel.CADRenderInteractionPhase = .stable,
            renderBudget: SiteKeeperCADKernel.CADRenderBudget = .standard
        ) -> Output {
            let renderStart = Date()
            var commands: [SiteKeeperCADKernel.CADRenderCommand] = []
            var skippedEntityCount = 0
            var warnings: [String] = []
            let resolvedEntityCount = totalEntityCount ?? entities.count
            let renderEntities = prioritizedEntities(entities, interactionPhase: interactionPhase)

            for (offset, entity) in renderEntities.enumerated() {
                if commands.count >= renderBudget.maxRenderCommands {
                    skippedEntityCount += renderEntities.count - offset
                    warnings.append("CAD_POC_RENDER_BUDGET_EXCEEDED")
                    break
                }

                let decision = lodPolicy.decision(
                    for: entity,
                    totalEntityCount: resolvedEntityCount,
                    zoomScale: zoomScale,
                    interactionPhase: interactionPhase
                )
                guard decision == .render else {
                    skippedEntityCount += 1
                    continue
                }

                let entityCommands = renderCommands(for: entity, layersByID: layersByID)
                guard !entityCommands.isEmpty else {
                    skippedEntityCount += 1
                    continue
                }

                let remainingBudget = renderBudget.maxRenderCommands - commands.count
                if entityCommands.count <= remainingBudget {
                    commands.append(contentsOf: entityCommands)
                } else {
                    commands.append(contentsOf: entityCommands.prefix(remainingBudget))
                    skippedEntityCount += renderEntities.count - offset
                    warnings.append("CAD_POC_RENDER_BUDGET_EXCEEDED")
                    break
                }
            }

            let renderMs = Date().timeIntervalSince(renderStart) * 1000
            return Output(
                commands: commands,
                performance: SiteKeeperCADKernel.CADPerformanceTrace(
                    entityCount: resolvedEntityCount,
                    visibleEntityCount: visibleEntityCount ?? entities.count,
                    renderCommandCount: commands.count,
                    drawCallCount: commands.reduce(0) { $0 + $1.drawCallCost },
                    renderMs: renderMs,
                    frameTimeMilliseconds: renderMs,
                    skippedEntityCount: skippedEntityCount,
                    warnings: warnings
                )
            )
        }

        private func prioritizedEntities(
            _ entities: [SiteKeeperCADKernel.CADEntity],
            interactionPhase: SiteKeeperCADKernel.CADRenderInteractionPhase
        ) -> [SiteKeeperCADKernel.CADEntity] {
            guard interactionPhase == .stable else { return entities }
            return entities.stablePartitioned { entity in
                entity.kind == .text
                    || entity.kind == .mtext
                    || entity.kind == .attrib
                    || (entity.kind == .dimension && entity.text != nil)
            }
        }

        private func renderCommands(
            for entity: SiteKeeperCADKernel.CADEntity,
            layersByID: [String: SiteKeeperCADKernel.CADLayer]
        ) -> [SiteKeeperCADKernel.CADRenderCommand] {
            let style = resolvedStyle(for: entity, layersByID: layersByID)

            switch entity.kind {
            case .point:
                return [.marker(entity.bounds.center, label: nil, style: style)]
            case .text, .mtext, .attrib:
                guard let text = entity.text else { return [] }
                return [.text(text, style: style)]
            case .image:
                guard !entity.bounds.isEmpty else { return [] }
                var commands: [SiteKeeperCADKernel.CADRenderCommand] = []
                if let path = entity.path, path.points.count >= 2 {
                    commands.append(.polyline(path.points, closed: path.isClosed, style: style))
                }
                commands.append(
                    .imagePlaceholder(
                        entityID: entity.id.uuidString,
                        bounds: entity.bounds,
                        reason: entity.unsupportedReason ?? "Image rendering is not implemented in the CAD Metal PoC."
                    )
                )
                return commands
            case .dimension:
                var commands: [SiteKeeperCADKernel.CADRenderCommand] = []
                if let path = entity.path {
                    let points = path.points
                    if points.count >= 2 {
                        commands.append(.polyline(points, closed: path.isClosed, style: style))
                        commands.append(contentsOf: dimensionArrowCommands(for: entity, path: path, style: style))
                    }
                }
                if let text = entity.text {
                    commands.append(.text(text, style: style))
                }
                return commands
            case .line:
                guard let path = entity.path else { return [] }
                let points = path.points
                guard points.count >= 2 else { return [] }
                return [.polyline(points, closed: false, style: style)]
            case .hatch:
                guard let path = entity.path else { return [] }
                return hatchCommands(for: entity, path: path, style: style)
            case .polyline, .lwPolyline, .circle, .arc, .ellipse, .spline:
                guard let path = entity.path else { return [] }
                let points = path.points
                guard points.count >= 2 else { return [] }
                return [.polyline(points, closed: path.isClosed, style: style)]
            case .xref:
                return []
            case .table, .proxy, .unsupported, .insert, .blockReference:
                if let path = entity.path {
                    let points = path.points
                    guard points.count >= 2 else { return [] }
                    return [.polyline(points, closed: path.isClosed, style: style)]
                }
                guard !entity.bounds.isEmpty else { return [] }
                return [
                    .unsupportedPlaceholder(
                        entityID: entity.id.uuidString,
                        bounds: entity.bounds,
                        reason: entity.unsupportedReason
                            ?? entity.diagnostics.entries.first?.message
                            ?? "Entity has no renderable geometry."
                    )
                ]
            }
        }

        private func resolvedStyle(
            for entity: SiteKeeperCADKernel.CADEntity,
            layersByID: [String: SiteKeeperCADKernel.CADLayer]
        ) -> SiteKeeperCADKernel.CADRenderStyle {
            let layer = layersByID[entity.layerID] ?? .default
            let color = entity.color == 0x00000000 ? layer.colorARGB : entity.color
            let lineWidth = entity.lineWeight > 0 ? entity.lineWeight : layer.lineWeight
            let entityLineType = entity.lineType.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineType: String
            if entityLineType.isEmpty ||
                entityLineType.caseInsensitiveCompare("ByLayer") == .orderedSame ||
                entityLineType.caseInsensitiveCompare("ByBlock") == .orderedSame {
                lineType = layer.lineType
            } else {
                lineType = entityLineType
            }
            return SiteKeeperCADKernel.CADRenderStyle(
                layerID: entity.layerID,
                colorARGB: color,
                lineWidth: max(lineWidth, 0.25),
                lineType: lineType
            )
        }

        private func hatchCommands(
            for entity: SiteKeeperCADKernel.CADEntity,
            path: SiteKeeperCADKernel.CADPath,
            style: SiteKeeperCADKernel.CADRenderStyle
        ) -> [SiteKeeperCADKernel.CADRenderCommand] {
            let points = path.points
            guard points.count >= 3 else {
                return points.count >= 2 ? [.polyline(points, closed: path.isClosed, style: style)] : []
            }

            guard shouldFillHatch(entity, path: path) else {
                return [.polyline(points, closed: path.isClosed, style: style)]
            }
            return [.hatch(path, style: style)]
        }

        private func shouldFillHatch(
            _ entity: SiteKeeperCADKernel.CADEntity,
            path: SiteKeeperCADKernel.CADPath
        ) -> Bool {
            let points = path.points
            guard path.isClosed, points.count >= 3, points.count <= 64 else {
                return false
            }
            guard !path.containsCurve else {
                return false
            }

            let boundaryOnlyCodes: Set<String> = [
                "CAD_POC_HATCH_BOUNDARY_ONLY",
                "CAD_POC_HATCH_COMPLEX_BOUNDARY_DEGRADED",
                "CAD_POC_HATCH_BOUNDARY_UNRESOLVED",
                "CAD_POC_HATCH_COMPLEX_BOUNDARY_UNRESOLVED",
                "CAD_HATCH_DEGRADED_TO_BOUNDARY",
                "CAD_LOD_COMPLEX_HATCH_SKIPPED",
                "CAD_POC_WIPEOUT_DEGRADED_TO_BOUNDARY"
            ]
            let diagnosticCodes = Set(entity.diagnostics.entries.map(\.code))
            guard diagnosticCodes.isDisjoint(with: boundaryOnlyCodes) else {
                return false
            }

            return isConvexPolygon(points)
        }

        private func isConvexPolygon(_ points: [SiteKeeperCADKernel.CADPoint]) -> Bool {
            guard points.count >= 3 else { return false }
            var sign = 0
            for index in points.indices {
                let previous = points[(index + points.count - 1) % points.count]
                let current = points[index]
                let next = points[(index + 1) % points.count]
                let cross = ((current.x - previous.x) * (next.y - current.y))
                    - ((current.y - previous.y) * (next.x - current.x))
                guard abs(cross) > 0.000001 else { continue }
                let currentSign = cross > 0 ? 1 : -1
                if sign == 0 {
                    sign = currentSign
                } else if sign != currentSign {
                    return false
                }
            }
            return sign != 0
        }

        private func dimensionArrowCommands(
            for entity: SiteKeeperCADKernel.CADEntity,
            path: SiteKeeperCADKernel.CADPath,
            style: SiteKeeperCADKernel.CADRenderStyle
        ) -> [SiteKeeperCADKernel.CADRenderCommand] {
            guard let (start, end) = dimensionLineSegment(from: path) else { return [] }
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length.isFinite, length > 0.000001 else { return [] }

            let baseArrowLength = max(entity.text?.height ?? length * 0.04, 0.8) * 1.35
            let arrowLength = min(max(baseArrowLength, length * 0.025), max(length * 0.12, 1.2))
            let arrowWidth = max(arrowLength * 0.42, max(arrowLength * 0.28, 0.4))
            let unit = SiteKeeperCADKernel.CADPoint(x: dx / length, y: dy / length)

            return [
                .hatch(
                    dimensionArrowPath(tip: start, inward: unit, length: arrowLength, width: arrowWidth),
                    style: style
                ),
                .hatch(
                    dimensionArrowPath(
                        tip: end,
                        inward: SiteKeeperCADKernel.CADPoint(x: -unit.x, y: -unit.y),
                        length: arrowLength,
                        width: arrowWidth
                    ),
                    style: style
                )
            ]
        }

        private func dimensionLineSegment(
            from path: SiteKeeperCADKernel.CADPath
        ) -> (SiteKeeperCADKernel.CADPoint, SiteKeeperCADKernel.CADPoint)? {
            let points = path.points
            if points.count >= 4 {
                return (points[1], points[2])
            }
            guard let start = points.first, let end = points.last else { return nil }
            return (start, end)
        }

        private func dimensionArrowPath(
            tip: SiteKeeperCADKernel.CADPoint,
            inward: SiteKeeperCADKernel.CADPoint,
            length: Double,
            width: Double
        ) -> SiteKeeperCADKernel.CADPath {
            let normal = SiteKeeperCADKernel.CADPoint(x: -inward.y, y: inward.x)
            let base = SiteKeeperCADKernel.CADPoint(
                x: tip.x + inward.x * length,
                y: tip.y + inward.y * length
            )
            let halfWidth = width / 2
            let left = SiteKeeperCADKernel.CADPoint(
                x: base.x + normal.x * halfWidth,
                y: base.y + normal.y * halfWidth
            )
            let right = SiteKeeperCADKernel.CADPoint(
                x: base.x - normal.x * halfWidth,
                y: base.y - normal.y * halfWidth
            )
            return SiteKeeperCADKernel.CADPath(elements: [
                .move(to: tip),
                .line(to: left),
                .line(to: right),
                .close
            ])
        }

        func commandCount(in frame: SiteKeeperCADKernel.CADRenderFrame) -> Int {
            frame.commands.count
        }
    }
}

private extension Array {
    func stablePartitioned(_ isFirstGroup: (Element) -> Bool) -> [Element] {
        var first: [Element] = []
        var second: [Element] = []
        first.reserveCapacity(count)
        second.reserveCapacity(count)
        for element in self {
            if isFirstGroup(element) {
                first.append(element)
            } else {
                second.append(element)
            }
        }
        return first + second
    }
}

private extension SiteKeeperCADKernel.CADPath {
    var containsCurve: Bool {
        elements.contains {
            if case .curve = $0 {
                return true
            }
            return false
        }
    }

    var isClosed: Bool {
        elements.contains {
            if case .close = $0 {
                return true
            }
            return false
        }
    }
}
