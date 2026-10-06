import MetalKit
import QuartzCore

extension MindControl {
    enum RendererError: LocalizedError {
        case metalUnavailable
        case pipeline(String)

        var errorDescription: String? {
            switch self {
            case .metalUnavailable: "Metal is unavailable on this Mac."
            case .pipeline(let detail): "The renderer failed to start: \(detail)"
            }
        }
    }

    /// Draws a `Graph` with Metal: HDR scene pass → composite into the drawable.
    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        nonisolated static let hdrFormat: MTLPixelFormat = .rgba16Float
        nonisolated static let outputFormat: MTLPixelFormat = .bgra8Unorm

        let device: MTLDevice
        var camera = OrbitCamera()

        private let queue: MTLCommandQueue
        private let pipelines: Pipelines
        private let bloom: BloomPass

        private var nodeBuffer: MTLBuffer?
        private var edgeBuffer: MTLBuffer?
        private var dustBuffer: MTLBuffer?
        private var nodeCount = 0
        private var edgeCount = 0
        private var dustCount = 0
        private var graphRadius: Float = 1

        private var hdrTexture: MTLTexture?
        private let startTime = CACurrentMediaTime()
        private var lastFrameTime = CACurrentMediaTime()

        var bloomStrength: Float = 0.22

        var signalsEnabled = true
        var exposure: Float = 1

        init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
            guard let device, let queue = device.makeCommandQueue() else {
                throw RendererError.metalUnavailable
            }
            let library: MTLLibrary
            do {
                library = try device.makeDefaultLibrary(bundle: Bundle(for: Renderer.self))
            } catch {
                throw RendererError.pipeline(error.localizedDescription)
            }
            self.device = device
            self.queue = queue
            self.pipelines = try Pipelines(device: device, library: library)
            self.bloom = BloomPass(device: device)
            super.init()
        }

        func setGraph(_ graph: Graph) {
            let buffers = GraphBuffers(graph: graph)
            nodeCount = buffers.nodes.count
            edgeCount = buffers.edges.count
            nodeBuffer = makeBuffer(buffers.nodes)
            edgeBuffer = makeBuffer(buffers.edges)
            graphRadius = max(buffers.boundingRadius, 1)

            let dust = Self.dustField(center: buffers.center, radius: graphRadius)
            dustCount = dust.count
            dustBuffer = makeBuffer(dust)

            camera.frame(center: buffers.center, radius: buffers.boundingRadius)
        }

        // MARK: MTKViewDelegate

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            let width = Int(view.drawableSize.width)
            let height = Int(view.drawableSize.height)
            guard width > 0, height > 0,
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = queue.makeCommandBuffer() else { return }

            let now = CACurrentMediaTime()
            camera.update(dt: min(now - lastFrameTime, 0.1))
            lastFrameTime = now

            let scale = Float(view.window?.backingScaleFactor ?? 2)
            encodeFrame(into: commandBuffer, output: pass, width: width, height: height, pixelScale: scale, time: Float(now - startTime))
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        // MARK: Frame encoding

        func encodeFrame(into commandBuffer: MTLCommandBuffer, output: MTLRenderPassDescriptor, width: Int, height: Int, pixelScale: Float, time: Float) {
            guard width > 0, height > 0, let hdr = hdrTarget(width: width, height: height) else { return }

            let aspect = Float(width) / Float(height)
            let projection = camera.projectionMatrix(aspect: aspect)
            var frame = MCFrameUniforms(
                viewProjection: projection * camera.viewMatrix,
                view: camera.viewMatrix,
                viewportSize: SIMD2(Float(width), Float(height)),
                time: time,
                pixelScale: pixelScale,
                fogDensity: 1.1 / (graphRadius * 2),
                fogStart: max(0, camera.distance - graphRadius * 0.4),
                projScaleY: projection.columns.1.y
            )

            encodeScene(commandBuffer, target: hdr, frame: &frame)
            let bloomTexture = bloom.encode(commandBuffer: commandBuffer, source: hdr, pipelines: pipelines) ?? hdr
            encodeComposite(commandBuffer, output: output, scene: hdr, bloom: bloomTexture, width: width, height: height, time: time)
        }

        private func encodeScene(_ commandBuffer: MTLCommandBuffer, target: MTLTexture, frame: inout MCFrameUniforms) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.label = "Scene"

            let frameIndex = Int(MC_BUFFER_FRAME)
            encoder.setVertexBytes(&frame, length: MemoryLayout<MCFrameUniforms>.stride, index: frameIndex)
            encoder.setFragmentBytes(&frame, length: MemoryLayout<MCFrameUniforms>.stride, index: frameIndex)

            if let dustBuffer {
                encoder.setRenderPipelineState(pipelines.dust)
                encoder.setVertexBuffer(dustBuffer, offset: 0, index: Int(MC_BUFFER_INSTANCES))
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: dustCount)
            }

            if let nodeBuffer, let edgeBuffer {
                encoder.setVertexBuffer(edgeBuffer, offset: 0, index: Int(MC_BUFFER_INSTANCES))
                encoder.setVertexBuffer(nodeBuffer, offset: 0, index: Int(MC_BUFFER_NODES))
                encoder.setRenderPipelineState(pipelines.edges)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: edgeCount)
                if signalsEnabled {
                    encoder.setRenderPipelineState(pipelines.signals)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: edgeCount)
                }
            }

            if let nodeBuffer {
                encoder.setRenderPipelineState(pipelines.nodes)
                encoder.setVertexBuffer(nodeBuffer, offset: 0, index: Int(MC_BUFFER_INSTANCES))
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: nodeCount)
            }

            encoder.endEncoding()
        }

        private func encodeComposite(_ commandBuffer: MTLCommandBuffer, output: MTLRenderPassDescriptor, scene: MTLTexture, bloom: MTLTexture, width: Int, height: Int, time: Float) {
            output.colorAttachments[0].loadAction = .dontCare
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: output) else { return }
            encoder.label = "Composite"
            var uniforms = MCCompositeUniforms(
                viewportSize: SIMD2(Float(width), Float(height)),
                time: time,
                bloomStrength: bloomStrength,
                exposure: exposure
            )
            encoder.setRenderPipelineState(pipelines.composite)
            encoder.setFragmentTexture(scene, index: 0)
            encoder.setFragmentTexture(bloom, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MCCompositeUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        // MARK: Resources

        private func hdrTarget(width: Int, height: Int) -> MTLTexture? {
            if let hdrTexture, hdrTexture.width == width, hdrTexture.height == height { return hdrTexture }
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.hdrFormat, width: width, height: height, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            hdrTexture = device.makeTexture(descriptor: desc)
            hdrTexture?.label = "HDR scene"
            return hdrTexture
        }

        private func makeBuffer<T>(_ array: [T]) -> MTLBuffer? {
            guard !array.isEmpty else { return nil }
            return array.withUnsafeBytes { bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
            }
        }

        /// Faint motes in a shell well outside the graph, so they read as distant depth.
        private static func dustField(center: SIMD3<Float>, radius: Float, count: Int = 2_000) -> [SIMD4<Float>] {
            var rng = SplitMix64(seed: 7)
            let inner = radius * 2.5 + 10
            let outer = radius * 5 + 30
            return (0..<count).map { _ in
                let z = Float.random(in: -1...1, using: &rng)
                let theta = Float.random(in: 0..<(2 * .pi), using: &rng)
                let r = (1 - z * z).squareRoot()
                let direction = SIMD3(r * cos(theta), r * sin(theta), z)
                let p = center + direction * Float.random(in: inner...outer, using: &rng)
                return SIMD4(p, Float.random(in: 0.2...1, using: &rng))
            }
        }
    }
}
