extension SiteKeeperCADKernel {
    enum CADRenderInteractionPhase: String, Equatable, Codable {
        case stable
        case zooming
    }

    struct CADRenderBudget: Equatable, Codable, Hashable {
        var maxRenderCommands: Int
        var maxFrameTimeMilliseconds: Double

        init(maxRenderCommands: Int = 20_000, maxFrameTimeMilliseconds: Double = 250) {
            self.maxRenderCommands = max(1, maxRenderCommands)
            self.maxFrameTimeMilliseconds = max(1, maxFrameTimeMilliseconds)
        }

        static let standard = CADRenderBudget()
        static let interactive = CADRenderBudget(maxRenderCommands: 4_000, maxFrameTimeMilliseconds: 16)
    }

    struct CADRenderOptions: Equatable, Codable {
        var layoutID: String?
        var visibleLayerIDs: Set<String>?
        var viewportBounds: CADBounds
        var deviceScale: Double
        var lodPolicy: CADLODPolicy
        var interactionPhase: CADRenderInteractionPhase
        var renderBudget: CADRenderBudget
        var enableCache: Bool

        init(
            layoutID: String? = nil,
            visibleLayerIDs: Set<String>? = nil,
            viewportBounds: CADBounds = .empty,
            deviceScale: Double = 1,
            lodPolicy: CADLODPolicy = .standard,
            interactionPhase: CADRenderInteractionPhase = .stable,
            renderBudget: CADRenderBudget = .standard,
            enableCache: Bool = true
        ) {
            self.layoutID = layoutID
            self.visibleLayerIDs = visibleLayerIDs
            self.viewportBounds = viewportBounds
            self.deviceScale = deviceScale
            self.lodPolicy = lodPolicy
            self.interactionPhase = interactionPhase
            self.renderBudget = renderBudget
            self.enableCache = enableCache
        }
    }
}
