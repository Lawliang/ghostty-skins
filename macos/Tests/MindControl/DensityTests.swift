#if os(macOS)
import Metal
import Testing
@testable import Ghostty

/// Large, lopsided projects must stay readable: no blown-out white blobs.
@MainActor
struct DensityTests {
    /// Shaped like the Lostty repo: one folder holding most files, a few smaller ones.
    private static let lopsidedTree: MindControl.FileTree = {
        var files: [String] = []
        for i in 0..<4_000 { files.append("test/fixtures/case\(i % 12)/f\(i).txt") }
        for i in 0..<850 { files.append("src/mod\(i % 20)/f\(i).zig") }
        for i in 0..<300 { files.append("macos/Sources/f\(i).swift") }
        return MindControl.FileTree(rootName: "lopsided", rootPath: "/tmp/lopsided", files: files.sorted(), totalFileCount: files.count)
    }()

    /// Fraction of pixels whose every channel is ≥ 250 (blown out).
    private func whiteFraction(_ graph: MindControl.Graph, width: Int = 320, height: Int = 200) throws -> Double {
        let renderer = try MindControl.Renderer()
        renderer.setGraph(graph)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MindControl.Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        let texture = try #require(renderer.device.makeTexture(descriptor: desc))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].storeAction = .store
        let cmd = try #require(renderer.device.makeCommandQueue()?.makeCommandBuffer())
        renderer.encodeFrame(into: cmd, output: pass, width: width, height: height, pixelScale: 1, time: 2.3)
        let blit = try #require(cmd.makeBlitCommandEncoder())
        blit.synchronize(resource: texture)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        var white = 0
        for p in stride(from: 0, to: bytes.count, by: 4) where bytes[p] >= 250 && bytes[p + 1] >= 250 && bytes[p + 2] >= 250 {
            white += 1
        }
        return Double(white) / Double(width * height)
    }

    @Test func lopsidedProjectDoesNotBlowOut() throws {
        let fraction = try whiteFraction(MindControl.TreeLayout.graph(for: Self.lopsidedTree))
        #expect(fraction < 0.03, "\(Int(fraction * 100))% of pixels are blown out")
    }

    @Test func glowScaleFallsWithNodeCount() {
        let scale = MindControl.Renderer.glowScale(nodeCount:)
        #expect(scale(0) == 1)
        #expect(scale(400) == 1)
        #expect(abs(scale(1_600) - 0.5) < 1e-6)
        #expect(scale(1_000_000) == 0.2)
        #expect(scale(800) > scale(3_000))
    }
}
#endif
