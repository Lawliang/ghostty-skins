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

    /// Draws the flow map with Metal: HDR scene pass → bloom → composite into the drawable.
    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        nonisolated static let hdrFormat: MTLPixelFormat = .rgba16Float
        nonisolated static let outputFormat: MTLPixelFormat = .bgra8Unorm

        let device: MTLDevice
        private let queue: MTLCommandQueue
        private let pipelines: Pipelines
        private let bloom: BloomPass
        private var hdrTexture: MTLTexture?
        private let startTime = CACurrentMediaTime()

        var bloomStrength: Float = 0.22
        var exposure: Float = 1
        /// Called after each on-screen frame (not for offscreen renders).
        var onFrame: (() -> Void)?
        var camera = PanZoomCamera()
        /// Called at the start of each on-screen frame with the frame time (drives view transitions).
        var beforeFrame: ((CFTimeInterval) -> Void)?
        private var cameraAnimation: (from: PanZoomCamera, to: PanZoomCamera, start: CFTimeInterval, duration: CFTimeInterval)?
        private var boxBuffer: MTLBuffer?
        private var arrowBuffer: MTLBuffer?
        private var markerBuffer: MTLBuffer?
        private var boxCount = 0
        private var arrowCount = 0
        private var markerCount = 0
        private var fixedLevel = false
        private static let arrowVertexCount = (Int(MC_ARROW_SEGMENTS) + 1) * 2

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

        // MARK: Scene and camera

        func setScene(_ scene: FlowScene) {
            boxBuffer = makeBuffer(scene.boxes)
            arrowBuffer = makeBuffer(scene.arrows)
            markerBuffer = makeBuffer(scene.markers)
            boxCount = scene.boxes.count
            arrowCount = scene.arrows.count
            markerCount = scene.markers.count
            fixedLevel = scene.fixedLevel
        }

        var isAnimatingCamera: Bool { cameraAnimation != nil }

        func animateCamera(to target: PanZoomCamera, duration: CFTimeInterval = 0.45) {
            // Anything but a positive finite duration jumps: a negative, NaN or infinite one would never finish,
            // pinning the camera where it started.
            guard duration > 0, duration.isFinite else {
                cameraAnimation = nil
                camera = target
                return
            }
            cameraAnimation = (camera, target, CACurrentMediaTime(), duration)
        }

        /// Moves an animating camera to where it should be at `now`.
        func advanceCamera(to now: CFTimeInterval) {
            guard let animation = cameraAnimation else { return }
            let raw = min(1, max(0, (now - animation.start) / animation.duration))
            let eased = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
            camera = PanZoomCamera.interpolate(animation.from, animation.to, t: CGFloat(eased))
            if raw >= 1 { cameraAnimation = nil }
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
            let scale = Float(view.window?.backingScaleFactor ?? 2)
            let now = CACurrentMediaTime()
            beforeFrame?(now)
            advanceCamera(to: now)
            encodeFrame(into: commandBuffer, output: pass, width: width, height: height, pixelScale: scale,
                        time: Float(now - startTime))
            commandBuffer.present(drawable)
            commandBuffer.commit()
            onFrame?()
        }

        // MARK: Frame encoding

        func encodeFrame(into commandBuffer: MTLCommandBuffer, output: MTLRenderPassDescriptor, width: Int, height: Int, pixelScale: Float, time: Float) {
            guard width > 0, height > 0, let hdr = hdrTarget(width: width, height: height) else { return }
            encodeScene(commandBuffer, target: hdr, width: width, height: height, pixelScale: pixelScale, time: time)
            let bloomTexture = bloom.encode(commandBuffer: commandBuffer, source: hdr, pipelines: pipelines) ?? hdr
            encodeComposite(commandBuffer, output: output, scene: hdr, bloom: bloomTexture, width: width, height: height, time: time)
        }

        private func encodeScene(_ commandBuffer: MTLCommandBuffer, target: MTLTexture, width: Int, height: Int, pixelScale: Float, time: Float) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.label = "Scene"

            var frame = MCFrameUniforms(viewportSize: SIMD2(Float(width), Float(height)),
                                        center: SIMD2(Float(camera.center.x), Float(camera.center.y)),
                                        zoom: Float(camera.zoom), pixelScale: pixelScale, time: time,
                                        fixedLevel: fixedLevel ? 1 : 0)
            let frameIndex = Int(MC_BUFFER_FRAME)
            encoder.setVertexBytes(&frame, length: MemoryLayout<MCFrameUniforms>.stride, index: frameIndex)
            encoder.setFragmentBytes(&frame, length: MemoryLayout<MCFrameUniforms>.stride, index: frameIndex)
            let instances = Int(MC_BUFFER_INSTANCES)

            if let boxBuffer {
                encoder.setRenderPipelineState(pipelines.boxes)
                encoder.setVertexBuffer(boxBuffer, offset: 0, index: instances)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: boxCount)
            }
            if let arrowBuffer {
                encoder.setVertexBuffer(arrowBuffer, offset: 0, index: instances)
                encoder.setRenderPipelineState(pipelines.arrows)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: Self.arrowVertexCount, instanceCount: arrowCount)
                encoder.setRenderPipelineState(pipelines.pulses)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: Self.arrowVertexCount, instanceCount: arrowCount)
            }
            if let markerBuffer {
                encoder.setRenderPipelineState(pipelines.markers)
                encoder.setVertexBuffer(markerBuffer, offset: 0, index: instances)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: markerCount)
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

        func makeBuffer<T>(_ array: [T]) -> MTLBuffer? {
            guard !array.isEmpty else { return nil }
            return array.withUnsafeBytes { bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
            }
        }
    }
}
