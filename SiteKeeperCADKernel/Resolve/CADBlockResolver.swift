import Foundation

extension SiteKeeperCADKernel {
    struct CADBlockResolver {
        var maxDepth: Int = 16

        func resolve(database: CADDatabase) -> CADDatabase {
            var copy = database
            copy.entities = resolve(entities: database.entities, in: database)
            copy.extents = copy.entities.reduce(CADBounds.empty) { $0.union($1.bounds) }
            return copy
        }

        func resolve(entities: [CADEntity], in database: CADDatabase) -> [CADEntity] {
            entities.flatMap {
                resolve(
                    entity: $0,
                    insertContext: nil,
                    parentTransform: .identity,
                    database: database,
                    blockStack: [],
                    depth: 0
                )
            }
        }

        private func resolve(
            entity: CADEntity,
            insertContext: CADEntity?,
            parentTransform: CADTransform,
            database: CADDatabase,
            blockStack: [String],
            depth: Int
        ) -> [CADEntity] {
            guard entity.kind == .insert || entity.kind == .blockReference else {
                return [transform(entity, by: parentTransform, insertContext: insertContext)]
            }

            guard let blockName = entity.blockName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !blockName.isEmpty else {
                return [
                    degradedInsert(
                        entity,
                        reason: "INSERT has no block name.",
                        code: "CAD_BLOCK_NAME_MISSING"
                    )
                ]
            }

            guard depth < maxDepth else {
                return [
                    degradedInsert(
                        entity,
                        reason: "Nested block depth exceeded resolver limit.",
                        code: "CAD_BLOCK_DEPTH_EXCEEDED",
                        detail: blockName
                    )
                ]
            }

            guard !blockStack.contains(blockName) else {
                return [
                    degradedInsert(
                        entity,
                        reason: "Nested block cycle detected.",
                        code: "CAD_BLOCK_CYCLE_DETECTED",
                        detail: (blockStack + [blockName]).joined(separator: " -> ")
                    )
                ]
            }

            guard let block = database.block(named: blockName) else {
                return [
                    degradedInsert(
                        entity,
                        reason: "Referenced block is missing.",
                        code: "CAD_BLOCK_MISSING",
                        detail: blockName
                    )
                ]
            }

            let effectiveInsertContext = inheritedInsertContext(entity, parent: insertContext)
            let blockBaseTransform = CADTransform.translation(x: -block.basePoint.x, y: -block.basePoint.y)
            let localTransform = entity.transform.concatenating(blockBaseTransform)
            let combinedTransform = parentTransform.concatenating(localTransform)

            var resolved = block.entities.flatMap {
                resolve(
                    entity: $0,
                    insertContext: effectiveInsertContext,
                    parentTransform: combinedTransform,
                    database: database,
                    blockStack: blockStack + [blockName],
                    depth: depth + 1
                )
            }

            if let attrib = entity.text {
                var attribEntity = effectiveInsertContext
                attribEntity.id = UUID()
                attribEntity.kind = .attrib
                attribEntity.blockName = nil
                attribEntity.path = nil
                attribEntity.text = attrib
                attribEntity.transform = .identity
                resolved.append(transform(attribEntity, by: parentTransform.concatenating(entity.transform), insertContext: nil))
            }

            if resolved.isEmpty {
                return [
                    degradedInsert(
                        entity,
                        reason: "Referenced block has no drawable entities.",
                        code: "CAD_BLOCK_EMPTY",
                        detail: blockName
                    )
                ]
            }

            return resolved
        }

        private func inheritedInsertContext(_ entity: CADEntity, parent: CADEntity?) -> CADEntity {
            guard let parent else { return entity }
            var copy = entity
            copy.layoutID = parent.layoutID
            if copy.layerID == CADLayer.default.id {
                copy.layerID = parent.layerID
            }
            if copy.color == 0x00000000 {
                copy.color = parent.color
            }
            if copy.lineType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                copy.lineType.caseInsensitiveCompare("ByBlock") == .orderedSame {
                copy.lineType = parent.lineType
            }
            if copy.lineWeight < 0 {
                copy.lineWeight = parent.lineWeight
            }
            copy.diagnostics = copy.diagnostics.merging(parent.diagnostics)
            return copy
        }

        private func transform(
            _ entity: CADEntity,
            by transform: CADTransform,
            insertContext: CADEntity?
        ) -> CADEntity {
            guard transform != .identity || entity.transform != .identity || insertContext != nil else { return entity }

            var copy = entity
            let geometryTransform = transform.concatenating(entity.transform)
            copy.id = UUID()
            if let insertContext {
                copy.layoutID = insertContext.layoutID
                if copy.layerID == CADLayer.default.id {
                    copy.layerID = insertContext.layerID
                }
                if copy.color == 0x00000000 {
                    copy.color = insertContext.color
                }
                if copy.lineType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    copy.lineType.caseInsensitiveCompare("ByBlock") == .orderedSame {
                    copy.lineType = insertContext.lineType
                }
                if copy.lineWeight < 0 {
                    copy.lineWeight = insertContext.lineWeight
                }
                copy.diagnostics = copy.diagnostics
                    .merging(insertContext.diagnostics)
                    .appending(
                        CADDrawingDiagnostics.Entry(
                            severity: .info,
                            code: "CAD_BLOCK_ENTITY_RESOLVED",
                            message: "Entity resolved from INSERT.",
                            detail: insertContext.blockName
                        )
                )
            }

            copy.transform = geometryTransform
            if let path = copy.path {
                let transformedPath = path.applying(geometryTransform)
                copy.path = transformedPath
                copy.bounds = transformedPath.bounds
            } else {
                copy.bounds = copy.bounds.applying(geometryTransform)
            }

            if let text = copy.text {
                var transformedText = text
                transformedText.insertionPoint = geometryTransform.apply(to: text.insertionPoint)
                transformedText.height = text.height * geometryTransform.approximateScale
                transformedText.rotationRadians = text.rotationRadians + geometryTransform.rotationRadians
                copy.text = transformedText
                if copy.bounds.isEmpty {
                    copy.bounds = CADBounds(
                        minX: transformedText.insertionPoint.x,
                        minY: transformedText.insertionPoint.y,
                        maxX: transformedText.insertionPoint.x,
                        maxY: transformedText.insertionPoint.y
                    )
                }
            }

            return copy
        }

        private func degradedInsert(
            _ entity: CADEntity,
            reason: String,
            code: String,
            detail: String? = nil
        ) -> CADEntity {
            var copy = entity
            copy.id = UUID()
            copy.kind = .unsupported
            copy.path = nil
            copy.text = nil
            copy.unsupportedReason = reason
            copy.diagnostics = copy.diagnostics.appending(
                CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: code,
                    message: reason,
                    detail: detail ?? entity.blockName
                )
            )
            return copy
        }
    }
}

private extension SiteKeeperCADKernel.CADDatabase {
    func block(named name: String) -> SiteKeeperCADKernel.CADBlock? {
        blocks.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
                || $0.id.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
