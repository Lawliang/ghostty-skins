#if os(macOS)
import Testing
import simd
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

struct GraphBuffersTests {
    private func node(_ id: String, _ kind: NodeKind = .source, _ p: SIMD3<Float> = .zero) -> GraphNode {
        GraphNode(id: id, label: id, kind: kind, position: p)
    }

    @Test func emptyGraphProducesNothing() {
        let buffers = GraphBuffers(graph: Graph(nodes: [], edges: []))
        #expect(buffers.nodes.isEmpty)
        #expect(buffers.edges.isEmpty)
        #expect(buffers.boundingRadius == 0)
        #expect(buffers.center == .zero)
    }

    @Test func sampleGraphCounts() {
        let graph = Graph.sample
        let buffers = GraphBuffers(graph: graph)
        #expect(buffers.nodes.count == graph.nodes.count)
        #expect(buffers.edges.count == graph.edges.count)
    }

    @Test func stylesByKind() {
        let graph = Graph(nodes: [node("r", .root), node("f", .folder), node("s", .source), node("d", .document)], edges: [])
        let n = GraphBuffers(graph: graph).nodes
        #expect(n[0].radius > n[1].radius)
        #expect(n[1].radius > n[2].radius)
        #expect(n[2].radius == n[3].radius)
        #expect(n[1].color == NodeStyle.color(for: .folder))
        #expect(n[3].color == NodeStyle.color(for: .document))
        #expect(n[2].color != n[3].color)
    }

    @Test func edgesIndexNodes() {
        let graph = Graph(nodes: [node("a"), node("b"), node("c")], edges: [GraphEdge(from: "c", to: "a")])
        let e = GraphBuffers(graph: graph).edges
        #expect(e.count == 1)
        #expect(e[0].a == 2)
        #expect(e[0].b == 0)
        #expect(e[0].signalSeed >= 0 && e[0].signalSeed < 1)
    }

    @Test func dropsInvalidEdges() {
        let graph = Graph(
            nodes: [node("a"), node("b")],
            edges: [GraphEdge(from: "a", to: "missing"), GraphEdge(from: "ghost", to: "b"), GraphEdge(from: "a", to: "a"), GraphEdge(from: "a", to: "b")]
        )
        let e = GraphBuffers(graph: graph).edges
        #expect(e.count == 1)
        #expect(e[0].a == 0 && e[0].b == 1)
    }

    @Test func firstDuplicateIDWins() {
        let graph = Graph(nodes: [node("a", .folder, SIMD3(1, 0, 0)), node("a", .source, SIMD3(9, 9, 9)), node("b")], edges: [GraphEdge(from: "b", to: "a")])
        let buffers = GraphBuffers(graph: graph)
        #expect(buffers.nodes.count == 2)
        #expect(buffers.nodes[0].position == SIMD3(1, 0, 0))
        #expect(buffers.edges[0].b == 0)
    }

    @Test func boundsCoverAllNodes() {
        let graph = Graph(nodes: [node("a", .source, SIMD3(-4, 0, 0)), node("b", .source, SIMD3(6, 0, 0))], edges: [])
        let buffers = GraphBuffers(graph: graph)
        #expect(buffers.center == SIMD3(1, 0, 0))
        #expect(abs(buffers.boundingRadius - (5 + NodeStyle.radius(for: .source))) < 1e-5)
    }

    @Test func phasesAreStableAndInRange() {
        let a = GraphBuffers(graph: .sample).nodes.map(\.phase)
        let b = GraphBuffers(graph: .sample).nodes.map(\.phase)
        #expect(a == b)
        #expect(a.allSatisfy { $0 >= 0 && $0 < 2 * .pi })
        #expect(Set(a).count > a.count / 2)
    }

    @Test func intensityComesFromWeight() {
        var dim = node("dim")
        dim.weight = 0.25
        let n = GraphBuffers(graph: Graph(nodes: [node("bright"), dim], edges: [])).nodes
        #expect(n[0].intensity == 1)
        #expect(n[1].intensity == 0.25)
    }

    @Test func edgesSplitByKind() {
        let graph = Graph(nodes: [node("a"), node("b"), node("c")],
                          edges: [GraphEdge(from: "a", to: "b"), GraphEdge(from: "b", to: "c", kind: .uses)])
        let buffers = GraphBuffers(graph: graph)
        #expect(buffers.edges.count == 2)
        #expect(buffers.containsEdges.count == 1)
        #expect(buffers.usesEdges.count == 1)
        #expect(buffers.usesEdges[0].a == 1 && buffers.usesEdges[0].b == 2)
        #expect(buffers.usesEdges[0].kind == 1)
        #expect(buffers.containsEdges[0].kind == 0)
    }

    @Test func sampleGraphHasUsesEdges() {
        #expect(GraphBuffers(graph: .sample).usesEdges.count == 3)
    }

    @Test func highlightStartsAtOneAndSourceNodesMatchBufferOrder() {
        let graph = Graph(nodes: [node("a"), node("a"), node("b")], edges: [])
        let buffers = GraphBuffers(graph: graph)
        #expect(buffers.nodes.allSatisfy { $0.highlight == 1 })
        #expect(buffers.sourceNodes.map(\.id) == ["a", "b"])
    }
}
#endif
