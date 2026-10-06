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

struct StressGraphTests {
    @Test(arguments: [0, 1, 2, 30, 1_000, 10_000])
    func producesExactNodeCount(count: Int) {
        #expect(Graph.stress(nodeCount: count).nodes.count == count)
    }

    @Test func isDeterministic() {
        let a = Graph.stress(nodeCount: 500)
        let b = Graph.stress(nodeCount: 500)
        #expect(a.nodes.map(\.position) == b.nodes.map(\.position))
        #expect(a.edges.map(\.to) == b.edges.map(\.to))
    }

    @Test func edgesReferenceExistingNodes() {
        let g = Graph.stress(nodeCount: 2_000)
        let ids = Set(g.nodes.map(\.id))
        #expect(g.edges.allSatisfy { ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to })
        #expect(g.edges.count >= g.nodes.count - 1)   // tree plus cross-links
    }

    @Test func idsAreUnique() {
        let g = Graph.stress(nodeCount: 3_000)
        #expect(Set(g.nodes.map(\.id)).count == g.nodes.count)
    }

    @Test func crossLinksAreUsesEdges() {
        let g = Graph.stress(nodeCount: 2_000)
        let uses = g.edges.filter { $0.kind == .uses }
        #expect(!uses.isEmpty)
        #expect(uses.allSatisfy { $0.from.hasPrefix("l") && $0.to.hasPrefix("l") })
        #expect(g.edges.filter { $0.kind == .contains }.count == g.nodes.count - 1)
    }
}
#endif
