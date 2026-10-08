import Metal

extension MindControl {
    /// Every render pipeline the renderer uses, built once at startup.
    struct Pipelines {
        let composite: MTLRenderPipelineState
        let bloomPrefilter: MTLRenderPipelineState
        let bloomDownsample: MTLRenderPipelineState
        let bloomUpsample: MTLRenderPipelineState

        init(device: MTLDevice, library: MTLLibrary) throws {
            let hdr = Renderer.hdrFormat
            composite = try Self.make(device, library, "mcFullscreenVertex", "mcCompositeFragment", format: Renderer.outputFormat, additive: false)
            bloomPrefilter = try Self.make(device, library, "mcFullscreenVertex", "mcBloomPrefilter", format: hdr, additive: false)
            bloomDownsample = try Self.make(device, library, "mcFullscreenVertex", "mcBloomDownsample", format: hdr, additive: false)
            bloomUpsample = try Self.make(device, library, "mcFullscreenVertex", "mcBloomUpsample", format: hdr, additive: true)
        }

        static func make(_ device: MTLDevice, _ library: MTLLibrary, _ vertex: String, _ fragment: String,
                         format: MTLPixelFormat, additive: Bool) throws -> MTLRenderPipelineState {
            guard let v = library.makeFunction(name: vertex), let f = library.makeFunction(name: fragment) else {
                throw RendererError.pipeline("Missing shader function \(vertex) or \(fragment)")
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "\(vertex)/\(fragment)"
            descriptor.vertexFunction = v
            descriptor.fragmentFunction = f
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = format
            if additive {
                attachment.isBlendingEnabled = true
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceRGBBlendFactor = .one
                attachment.destinationRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .one
            }
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                throw RendererError.pipeline("\(vertex)/\(fragment): \(error.localizedDescription)")
            }
        }
    }
}
