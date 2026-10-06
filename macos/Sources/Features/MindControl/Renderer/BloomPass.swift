import Metal

extension MindControl {
    /// Owns the bloom mip chain and encodes the down/up passes.
    @MainActor
    final class BloomPass {
        nonisolated static let levelCount = 5

        var threshold: Float = 1.0
        var knee: Float = 0.5

        private let device: MTLDevice
        private var levels: [MTLTexture] = []

        init(device: MTLDevice) {
            self.device = device
        }

        /// Successive half sizes of the source, never smaller than 1×1.
        nonisolated static func levelSizes(width: Int, height: Int, count: Int = levelCount) -> [SIMD2<Int>] {
            var size = SIMD2(max(width, 1), max(height, 1))
            return (0..<count).map { _ in
                size = SIMD2(max(1, size.x / 2), max(1, size.y / 2))
                return size
            }
        }

        /// Returns the half-resolution bloom texture, or nil if it couldn't allocate.
        func encode(commandBuffer: MTLCommandBuffer, source: MTLTexture, pipelines: Pipelines) -> MTLTexture? {
            resizeIfNeeded(width: source.width, height: source.height)
            guard let first = levels.first else { return nil }

            var input = source
            for (i, level) in levels.enumerated() {
                draw(commandBuffer, into: level, from: input, pipeline: i == 0 ? pipelines.bloomPrefilter : pipelines.bloomDownsample, load: .dontCare, label: "Bloom down \(i)")
                input = level
            }
            for i in stride(from: levels.count - 2, through: 0, by: -1) {
                draw(commandBuffer, into: levels[i], from: levels[i + 1], pipeline: pipelines.bloomUpsample, load: .load, label: "Bloom up \(i)")
            }
            return first
        }

        private func draw(_ commandBuffer: MTLCommandBuffer, into target: MTLTexture, from source: MTLTexture, pipeline: MTLRenderPipelineState, load: MTLLoadAction, label: String) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = load
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.label = label
            var uniforms = MCBloomUniforms(
                sourceTexelSize: SIMD2(1 / Float(source.width), 1 / Float(source.height)),
                threshold: threshold,
                knee: knee
            )
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MCBloomUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        private func resizeIfNeeded(width: Int, height: Int) {
            let sizes = Self.levelSizes(width: width, height: height)
            if levels.count == sizes.count, zip(levels, sizes).allSatisfy({ $0.width == $1.x && $0.height == $1.y }) { return }
            levels = sizes.compactMap { size in
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.hdrFormat, width: size.x, height: size.y, mipmapped: false)
                desc.usage = [.renderTarget, .shaderRead]
                desc.storageMode = .private
                return device.makeTexture(descriptor: desc)
            }
            if levels.count != sizes.count { levels = [] }
        }
    }
}
