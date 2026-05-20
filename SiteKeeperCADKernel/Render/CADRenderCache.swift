import Foundation

extension SiteKeeperCADKernel {
    final class CADRenderCache {
        private var layoutResolutions: [String: CADLayoutResolution] = [:]
        private var viewportTiles: [String: CADRenderFrame] = [:]
        private var textLayouts: [String: CADTextRun] = [:]
        private var blockResolutions: [String: [CADEntity]] = [:]

        func frame(for key: String) -> CADRenderFrame? {
            viewportTile(for: key)
        }

        func store(_ frame: CADRenderFrame, for key: String) {
            storeViewportTile(frame, for: key)
        }

        func layoutResolution(for key: String) -> CADLayoutResolution? {
            layoutResolutions[key]
        }

        func storeLayoutResolution(_ resolution: CADLayoutResolution, for key: String) {
            layoutResolutions[key] = resolution
        }

        func viewportTile(for key: String) -> CADRenderFrame? {
            viewportTiles[key]
        }

        func storeViewportTile(_ frame: CADRenderFrame, for key: String) {
            viewportTiles[key] = frame
        }

        func textLayout(for key: String) -> CADTextRun? {
            textLayouts[key]
        }

        func storeTextLayout(_ run: CADTextRun, for key: String) {
            textLayouts[key] = run
        }

        func blockResolution(for key: String) -> [CADEntity]? {
            blockResolutions[key]
        }

        func storeBlockResolution(_ entities: [CADEntity], for key: String) {
            blockResolutions[key] = entities
        }

        func removeAll() {
            layoutResolutions.removeAll()
            viewportTiles.removeAll()
            textLayouts.removeAll()
            blockResolutions.removeAll()
        }

        var layoutCacheCount: Int {
            layoutResolutions.count
        }

        var viewportTileCacheCount: Int {
            viewportTiles.count
        }

        var textLayoutCacheCount: Int {
            textLayouts.count
        }

        var blockResolutionCacheCount: Int {
            blockResolutions.count
        }

        static func layoutKey(
            databaseID: UUID,
            layoutID: String?,
            viewportID: String?,
            viewportBounds: CADBounds
        ) -> String {
            [
                "layout",
                databaseID.uuidString,
                layoutID ?? "current",
                viewportID ?? "none",
                boundsKey(viewportBounds)
            ].joined(separator: "|")
        }

        static func blockResolutionKey(databaseID: UUID, layoutKey: String) -> String {
            "block|\(databaseID.uuidString)|\(layoutKey)"
        }

        static func viewportTileKey(
            databaseID: UUID,
            layoutID: String?,
            viewportID: String?,
            viewportBounds: CADBounds,
            visibleLayerIDs: Set<String>?,
            deviceScale: Double,
            phase: CADRenderInteractionPhase,
            budget: CADRenderBudget
        ) -> String {
            [
                "tile",
                databaseID.uuidString,
                layoutID ?? "current",
                viewportID ?? "none",
                boundsKey(viewportBounds),
                layerKey(visibleLayerIDs),
                String(format: "%.6f", deviceScale),
                phase.rawValue,
                "\(budget.maxRenderCommands)",
                String(format: "%.1f", budget.maxFrameTimeMilliseconds)
            ].joined(separator: "|")
        }

        static func textLayoutKey(entity: CADEntity, style: CADTextStyle) -> String {
            [
                "text",
                entity.id.uuidString,
                entity.text?.rawText ?? "",
                style.id,
                entity.text.map { String(format: "%.4f", $0.height) } ?? "0",
                entity.text.map { String(format: "%.4f", $0.rotationRadians) } ?? "0"
            ].joined(separator: "|")
        }

        private static func layerKey(_ layerIDs: Set<String>?) -> String {
            layerIDs?.sorted().joined(separator: ",") ?? "database"
        }

        private static func boundsKey(_ bounds: CADBounds) -> String {
            guard !bounds.isEmpty else { return "empty" }
            return [
                bounds.minX,
                bounds.minY,
                bounds.maxX,
                bounds.maxY
            ].map { String(format: "%.3f", $0) }.joined(separator: ",")
        }
    }
}
