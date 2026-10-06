#if os(macOS)
import Testing
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

struct BloomPassTests {
    @Test func halvesEachLevel() {
        let sizes = BloomPass.levelSizes(width: 1920, height: 1080)
        #expect(sizes == [SIMD2(960, 540), SIMD2(480, 270), SIMD2(240, 135), SIMD2(120, 67), SIMD2(60, 33)])
    }

    @Test func clampsTinyViewport() {
        let sizes = BloomPass.levelSizes(width: 1, height: 1)
        #expect(sizes.count == BloomPass.levelCount)
        #expect(sizes.allSatisfy { $0 == SIMD2(1, 1) })
    }

    @Test func clampsThinViewport() {
        let sizes = BloomPass.levelSizes(width: 3000, height: 3)
        #expect(sizes.allSatisfy { $0.x >= 1 && $0.y >= 1 })
        #expect(sizes.last == SIMD2(93, 1))
    }
}
#endif
