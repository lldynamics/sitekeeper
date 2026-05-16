#if canImport(MetalKit)
import Metal
import MetalKit
import simd

extension CADPoC {
    final class CADMetalRenderer: NSObject, MTKViewDelegate {
        typealias Kernel = SiteKeeperCADKernel

        let device: MTLDevice?
        let deviceName: String?
        let colorPixelFormat: MTLPixelFormat = .bgra8Unorm

        private let commandQueue: MTLCommandQueue?
        private let renderPipelineState: MTLRenderPipelineState?
        private var entities: [Kernel.CADEntity]
        private var commands: [Kernel.CADRenderCommand]
        private var modelBounds: Kernel.CADBounds

        private var userZoom: Double = 1
        private var panOffsetPixels = SIMD2<Double>(0, 0)

        override init() {
            let device = MTLCreateSystemDefaultDevice()
            self.device = device
            self.deviceName = device?.name
            self.commandQueue = device?.makeCommandQueue()
            self.entities = []
            self.commands = []
            self.modelBounds = .empty
            self.renderPipelineState = Self.makeRenderPipelineState(
                device: device,
                colorPixelFormat: .bgra8Unorm
            )
            super.init()
        }

        var isAvailable: Bool {
            device != nil && commandQueue != nil && renderPipelineState != nil
        }

        func resetView() {
            userZoom = 1
            panOffsetPixels = SIMD2<Double>(0, 0)
        }

        func updateEntities(_ importedEntities: [Kernel.CADEntity]) {
            entities = importedEntities.filter { $0.kind == .line && $0.isRenderable }
            commands = CADRenderPipeline().commands(from: entities)
            modelBounds = entities.reduce(Kernel.CADBounds.empty) { $0.union($1.bounds) }
            resetView()
        }

        func applyPan(deltaPoints: CGPoint, contentScale: CGFloat) {
            panOffsetPixels.x += Double(deltaPoints.x * contentScale)
            panOffsetPixels.y += Double(deltaPoints.y * contentScale)
        }

        func applyZoom(scale: CGFloat) {
            guard scale.isFinite, scale > 0 else { return }
            userZoom = min(max(userZoom * Double(scale), 0.2), 20)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            view.setNeedsDisplay()
        }

        func draw(in view: MTKView) {
            guard
                isAvailable,
                let drawable = view.currentDrawable,
                let renderPassDescriptor = view.currentRenderPassDescriptor,
                let commandQueue,
                let renderPipelineState,
                view.drawableSize.width > 1,
                view.drawableSize.height > 1
            else {
                return
            }

            let vertices = makeVertices(
                drawableSize: view.drawableSize,
                viewSize: view.bounds.size,
                contentScale: view.contentScaleFactor
            )
            guard !vertices.isEmpty else { return }

            let vertexBuffer = vertices.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return nil as MTLBuffer? }
                return device?.makeBuffer(
                    bytes: baseAddress,
                    length: rawBuffer.count,
                    options: [.storageModeShared]
                )
            }
            guard let vertexBuffer else { return }

            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0.972,
                green: 0.976,
                blue: 0.984,
                alpha: 1
            )
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store

            guard
                let commandBuffer = commandQueue.makeCommandBuffer(),
                let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            else {
                return
            }

            encoder.setRenderPipelineState(renderPipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

private extension CADPoC.CADMetalRenderer {
    struct CADMetalVertex {
        var position: SIMD2<Float>
        var color: SIMD4<Float>
    }

    static func makeRenderPipelineState(
        device: MTLDevice?,
        colorPixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        guard let device else { return nil }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "CAD Metal PoC Pipeline"
            descriptor.vertexFunction = library.makeFunction(name: "cad_vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "cad_fragment_main")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            assertionFailure("CAD Metal pipeline failed: \(error)")
            return nil
        }
    }

    static var shaderSource: String {
        """
        #include <metal_stdlib>
        using namespace metal;

        struct CADMetalVertex {
            float2 position;
            float4 color;
        };

        struct CADVertexOut {
            float4 position [[position]];
            float4 color;
        };

        vertex CADVertexOut cad_vertex_main(
            uint vertexID [[vertex_id]],
            const device CADMetalVertex *vertices [[buffer(0)]]
        ) {
            CADVertexOut out;
            out.position = float4(vertices[vertexID].position, 0.0, 1.0);
            out.color = vertices[vertexID].color;
            return out;
        }

        fragment half4 cad_fragment_main(CADVertexOut in [[stage_in]]) {
            return half4(in.color);
        }
        """
    }

    func makeVertices(
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [CADMetalVertex] {
        commands.flatMap { command -> [CADMetalVertex] in
            switch command {
            case let .polyline(points, closed, style):
                return makePolylineVertices(
                    points: points,
                    closed: closed,
                    style: style,
                    drawableSize: drawableSize,
                    viewSize: viewSize,
                    contentScale: contentScale
                )
            default:
                return []
            }
        }
    }

    func makePolylineVertices(
        points: [Kernel.CADPoint],
        closed: Bool,
        style: Kernel.CADRenderStyle,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [CADMetalVertex] {
        guard points.count >= 2 else { return [] }
        var vertices: [CADMetalVertex] = []
        for index in 0..<(points.count - 1) {
            appendSegment(
                from: points[index],
                to: points[index + 1],
                style: style,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale,
                to: &vertices
            )
        }
        if closed, let first = points.first, let last = points.last, first != last {
            appendSegment(
                from: last,
                to: first,
                style: style,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale,
                to: &vertices
            )
        }
        return vertices
    }

    func appendSegment(
        from start: Kernel.CADPoint,
        to end: Kernel.CADPoint,
        style: Kernel.CADRenderStyle,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat,
        to vertices: inout [CADMetalVertex]
    ) {
        let startScreen = screenPoint(
            for: start,
            drawableSize: drawableSize,
            viewSize: viewSize
        )
        let endScreen = screenPoint(
            for: end,
            drawableSize: drawableSize,
            viewSize: viewSize
        )
        let dx = endScreen.x - startScreen.x
        let dy = endScreen.y - startScreen.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return }

        let halfWidth = max(style.lineWidth * Double(contentScale), 2) / 2
        let normal = SIMD2<Double>(-dy / length * halfWidth, dx / length * halfWidth)
        let color = rgbaVector(fromARGB: style.colorARGB)

        let a = SIMD2<Double>(startScreen.x + normal.x, startScreen.y + normal.y)
        let b = SIMD2<Double>(startScreen.x - normal.x, startScreen.y - normal.y)
        let c = SIMD2<Double>(endScreen.x + normal.x, endScreen.y + normal.y)
        let d = SIMD2<Double>(endScreen.x - normal.x, endScreen.y - normal.y)

        vertices.append(CADMetalVertex(position: ndcPoint(fromScreen: a, drawableSize: drawableSize), color: color))
        vertices.append(CADMetalVertex(position: ndcPoint(fromScreen: b, drawableSize: drawableSize), color: color))
        vertices.append(CADMetalVertex(position: ndcPoint(fromScreen: c, drawableSize: drawableSize), color: color))
        vertices.append(CADMetalVertex(position: ndcPoint(fromScreen: c, drawableSize: drawableSize), color: color))
        vertices.append(CADMetalVertex(position: ndcPoint(fromScreen: b, drawableSize: drawableSize), color: color))
        vertices.append(CADMetalVertex(position: ndcPoint(fromScreen: d, drawableSize: drawableSize), color: color))
    }

    func screenPoint(
        for point: Kernel.CADPoint,
        drawableSize: CGSize,
        viewSize: CGSize
    ) -> SIMD2<Double> {
        let scale = fitScale(drawableSize: drawableSize, viewSize: viewSize) * userZoom
        let center = modelBounds.center
        let x = (point.x - center.x) * scale + Double(drawableSize.width) / 2 + panOffsetPixels.x
        let y = Double(drawableSize.height) / 2 - (point.y - center.y) * scale + panOffsetPixels.y
        return SIMD2<Double>(x, y)
    }

    func fitScale(drawableSize: CGSize, viewSize: CGSize) -> Double {
        guard !modelBounds.isEmpty, modelBounds.width > 0, modelBounds.height > 0 else { return 1 }
        let viewScale = Double(max(drawableSize.width / max(viewSize.width, 1), 1))
        let padding = 28 * viewScale
        let availableWidth = max(Double(drawableSize.width) - padding * 2, 1)
        let availableHeight = max(Double(drawableSize.height) - padding * 2, 1)
        return max(min(availableWidth / modelBounds.width, availableHeight / modelBounds.height), 0.0001)
    }

    func ndcPoint(fromScreen point: SIMD2<Double>, drawableSize: CGSize) -> SIMD2<Float> {
        let x = point.x / Double(drawableSize.width) * 2 - 1
        let y = 1 - point.y / Double(drawableSize.height) * 2
        return SIMD2<Float>(Float(x), Float(y))
    }

    func rgbaVector(fromARGB argb: UInt32) -> SIMD4<Float> {
        let alpha = Float((argb >> 24) & 0xFF) / 255
        let red = Float((argb >> 16) & 0xFF) / 255
        let green = Float((argb >> 8) & 0xFF) / 255
        let blue = Float(argb & 0xFF) / 255
        return SIMD4<Float>(red, green, blue, max(alpha, 1))
    }
}

#else
extension CADPoC {
    final class CADMetalRenderer {
        let deviceName: String? = nil
        var isAvailable: Bool { false }
    }
}
#endif
