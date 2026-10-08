#if os(macOS)
import Testing
import Metal
@testable import Ghostty

private typealias Renderer = MindControl.Renderer

@MainActor
struct RendererTests {
    /// Renders one frame offscreen and returns the average channel value, 0...1.
    fileprivate static func renderAverage(using renderer: Renderer, width: Int = 96, height: Int = 64) throws -> Double {
        let device = renderer.device
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        let texture = try #require(device.makeTexture(descriptor: desc))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        let queue = try #require(device.makeCommandQueue())
        let cmd = try #require(queue.makeCommandBuffer())
        renderer.encodeFrame(into: cmd, output: pass, width: width, height: height, pixelScale: 1, time: 1.5)
        let blit = try #require(cmd.makeBlitCommandEncoder())
        blit.synchronize(resource: texture)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        #expect(cmd.error == nil)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return Double(bytes.reduce(0) { $0 + Int($1) }) / Double(bytes.count) / 255
    }

    @Test func createsRenderer() throws {
        _ = try Renderer()
    }

    @Test func rendersBackground() throws {
        let average = try Self.renderAverage(using: try Renderer())
        #expect(average > 0)
        #expect(average < 0.4)
    }

    @Test func rendersOnePixelTarget() throws {
        _ = try Self.renderAverage(using: try Renderer(), width: 1, height: 1)
    }
}
#endif
