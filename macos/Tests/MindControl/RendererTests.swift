#if os(macOS)
import Testing
import Metal
@testable import Ghostty

private typealias Graph = MindControl.Graph
private typealias GraphNode = MindControl.GraphNode
private typealias GraphEdge = MindControl.GraphEdge
private typealias NodeKind = MindControl.NodeKind
private typealias GraphBuffers = MindControl.GraphBuffers
private typealias NodeStyle = MindControl.NodeStyle
private typealias OrbitCamera = MindControl.OrbitCamera
private typealias Renderer = MindControl.Renderer
private typealias BloomPass = MindControl.BloomPass

@MainActor
struct RendererTests {
    private func renderAverage(_ graph: Graph, width: Int = 96, height: Int = 64) throws -> Double {
        let renderer = try Renderer()
        renderer.setGraph(graph)
        return try renderAverage(using: renderer, width: width, height: height)
    }

    private func renderAverage(using renderer: Renderer, width: Int = 96, height: Int = 64) throws -> Double {
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

    @Test func rendersEmptyGraph() throws {
        let average = try renderAverage(Graph(nodes: [], edges: []))
        #expect(average > 0)        // background is never pure black (alpha alone guarantees > 0)
        #expect(average < 0.4)
    }

    @Test func sampleGraphIsBrighterThanEmpty() throws {
        let empty = try renderAverage(Graph(nodes: [], edges: []))
        let sample = try renderAverage(.sample)
        #expect(sample > empty + 0.005)
    }

    @Test func rendersOnePixelTarget() throws {
        _ = try renderAverage(.sample, width: 1, height: 1)
    }

    @Test func rendersSingleNode() throws {
        let graph = Graph(nodes: [GraphNode(id: "only", label: "only", kind: .root, position: .zero)], edges: [])
        _ = try renderAverage(graph)
    }

    @Test func bloomBrightensSample() throws {
        // Same graph, bloom on vs off: bloom only adds light.
        let renderer = try Renderer()
        renderer.setGraph(.sample)
        renderer.bloomStrength = 0
        let off = try renderAverage(using: renderer)
        renderer.bloomStrength = 1
        let on = try renderAverage(using: renderer)
        #expect(on > off)
    }

    @Test func signalsAddLight() throws {
        let renderer = try Renderer()
        renderer.setGraph(.stress(nodeCount: 400))
        renderer.bloomStrength = 0
        renderer.signalsEnabled = false
        let off = try renderAverage(using: renderer)
        renderer.signalsEnabled = true
        let on = try renderAverage(using: renderer)
        #expect(on > off)
    }
}
#endif
