#if os(macOS)
import Foundation
import Testing
import simd
@testable import Ghostty

private typealias Relaxation = MindControl.Relaxation
private typealias Graph = MindControl.Graph
private typealias GraphNode = MindControl.GraphNode
private typealias GraphEdge = MindControl.GraphEdge

struct RelaxationTests {
    /// `count` files packed into a cube of half-size `radius` around `center`, plus a root at the origin.
    private func crowd(count: Int, radius: Float, center: SIMD3<Float> = SIMD3(5, 0, 0)) -> Graph {
        var rng = MindControl.SplitMix64(seed: 1)
        var nodes = [GraphNode(id: ".", label: "root", kind: .root, position: .zero)]
        for i in 0..<count {
            let offset = SIMD3<Float>(Float.random(in: -radius...radius, using: &rng),
                                      Float.random(in: -radius...radius, using: &rng),
                                      Float.random(in: -radius...radius, using: &rng))
            nodes.append(GraphNode(id: "f\(i)", label: "f\(i)", kind: .source, position: center + offset))
        }
        return Graph(nodes: nodes, edges: [])
    }

    private func minimumDistance(_ graph: Graph) -> Float {
        let p = graph.nodes.map(\.position)
        var best = Float.infinity
        for i in p.indices { for j in p.indices where j > i { best = min(best, simd_distance(p[i], p[j])) } }
        return best
    }

    @Test func separatesCrowdedNodes() throws {
        let relaxed = try Relaxation.relax(crowd(count: 150, radius: 0.5))
        #expect(minimumDistance(relaxed) >= 0.9 * Relaxation.minSpacing)
    }

    @Test func rootNeverMoves() throws {
        let relaxed = try Relaxation.relax(crowd(count: 60, radius: 0.3, center: .zero))
        #expect(relaxed.nodes[0].position == .zero)
    }

    @Test func foldersMoveLessThanFiles() throws {
        let graph = Graph(nodes: [
            GraphNode(id: ".", label: "root", kind: .root, position: SIMD3(20, 20, 20)),
            GraphNode(id: "d", label: "d", kind: .folder, position: .zero),
            GraphNode(id: "d/f", label: "f", kind: .source, position: SIMD3(0.1, 0, 0)),
        ], edges: [])
        let relaxed = try Relaxation.relax(graph)
        let folderMove = simd_length(relaxed.nodes[1].position - graph.nodes[1].position)
        let fileMove = simd_length(relaxed.nodes[2].position - graph.nodes[2].position)
        #expect(folderMove < fileMove)
    }

    @Test func usesEdgesPullFilesTogether() throws {
        let nodes = [
            GraphNode(id: ".", label: "root", kind: .root, position: SIMD3(0, 30, 0)),
            GraphNode(id: "a", label: "a", kind: .source, position: SIMD3(-6, 0, 0)),
            GraphNode(id: "b", label: "b", kind: .source, position: SIMD3(6, 0, 0)),
        ]
        let apart = try Relaxation.relax(Graph(nodes: nodes, edges: []))
        let linked = try Relaxation.relax(Graph(nodes: nodes, edges: [GraphEdge(from: "a", to: "b", kind: .uses)]))
        let gap = { (g: Graph) in simd_distance(g.nodes[1].position, g.nodes[2].position) }
        #expect(gap(apart) == 12)
        #expect(gap(linked) < 12)
    }

    @Test func isDeterministic() throws {
        let graph = crowd(count: 120, radius: 0.5)
        #expect(try Relaxation.relax(graph).nodes.map(\.position) == Relaxation.relax(graph).nodes.map(\.position))
    }

    @Test func keepsNodesAndEdges() throws {
        let graph = MindControl.Graph.sample
        let relaxed = try Relaxation.relax(graph)
        #expect(relaxed.nodes.map(\.id) == graph.nodes.map(\.id))
        #expect(relaxed.edges.count == graph.edges.count)
    }

    @Test func tenThousandNodesRelaxQuickly() throws {
        let files = (0..<10_000).map { "d\($0 % 50)/e\($0 % 7)/f\($0).swift" }
        let tree = MindControl.FileTree(rootName: "p", rootPath: "/tmp/p", files: files.sorted(), totalFileCount: files.count)
        let graph = MindControl.ConeTreeLayout.graph(for: tree)
        let clock = ContinuousClock()
        let elapsed = try clock.measure { _ = try Relaxation.relax(graph) }
        #expect(elapsed < .milliseconds(1_500))
    }

    @Test func stopRequestCancels() {
        #expect(throws: CancellationError.self) {
            try Relaxation.relax(.sample, shouldStop: { true })
        }
    }

    /// A folder whose files all reference each other must keep its shape, not collapse into a pile.
    @Test func denselyLinkedFilesKeepTheirSpread() throws {
        var rng = MindControl.SplitMix64(seed: 5)
        var nodes = [GraphNode(id: ".", label: "root", kind: .root, position: SIMD3(0, 40, 0))]
        for i in 0..<200 {
            let direction = simd_normalize(SIMD3<Float>(Float.random(in: -1...1, using: &rng),
                                                        Float.random(in: -1...1, using: &rng),
                                                        Float.random(in: -1...1, using: &rng)))
            nodes.append(GraphNode(id: "f\(i)", label: "f\(i)", kind: .source,
                                   position: direction * Float.random(in: 2...6, using: &rng)))
        }
        var edges: [GraphEdge] = []
        for i in 0..<200 {
            for _ in 0..<40 {
                let j = Int.random(in: 0..<200, using: &rng)
                if j != i { edges.append(GraphEdge(from: "f\(i)", to: "f\(j)", kind: .uses)) }
            }
        }
        func spread(_ g: Graph) -> Float {
            let files = g.nodes.dropFirst().map(\.position)
            let centre = files.reduce(.zero, +) / Float(files.count)
            return (files.map { simd_length_squared($0 - centre) }.reduce(0, +) / Float(files.count)).squareRoot()
        }
        let graph = Graph(nodes: nodes, edges: edges)
        let relaxed = try Relaxation.relax(graph)
        #expect(spread(relaxed) >= 0.75 * spread(graph))
    }
}
#endif
