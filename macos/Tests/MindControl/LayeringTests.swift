#if os(macOS)
import Testing
@testable import Ghostty

private typealias Layering = MindControl.Layering
private typealias Edge = MindControl.Layering.Edge

struct LayeringTests {
    @Test func chainRanksLeftToRight() {
        let result = Layering.layout(nodes: ["c", "a", "b"], edges: [Edge(from: "a", to: "b"), Edge(from: "b", to: "c")])
        #expect(result.rank == ["a": 0, "b": 1, "c": 2])
        #expect(result.layers == [["a"], ["b"], ["c"]])
    }

    @Test func cycleIsBrokenFromTheSource() {
        let result = Layering.layout(nodes: ["a", "b", "x"],
                                     edges: [Edge(from: "a", to: "b"), Edge(from: "b", to: "a"), Edge(from: "x", to: "a")])
        #expect(result.rank == ["x": 0, "a": 1, "b": 2])
        #expect(result.reversed == [Edge(from: "b", to: "a")])
    }

    @Test func pinnedSendersFirstAndReceiversLast() {
        let result = Layering.layout(nodes: ["s", "a", "b", "r"],
                                     edges: [Edge(from: "s", to: "a"), Edge(from: "a", to: "b"), Edge(from: "a", to: "r")],
                                     pinFirst: ["s"], pinLast: ["r"])
        #expect(result.rank["s"] == 0)
        #expect(result.rank["r"] == 3)
        #expect(result.rank["b"] == 2)
    }

    @Test func orderingRemovesACrossing() {
        let result = Layering.layout(nodes: ["a", "b", "c", "d"], edges: [Edge(from: "a", to: "d"), Edge(from: "b", to: "c")])
        #expect(result.layers[0] == ["a", "b"])
        #expect(result.layers[1] == ["d", "c"])
        #expect(result.order["d"] == 0)
    }

    @Test func sameResultForShuffledInput() {
        let nodes = ["a", "b", "c", "d", "e"]
        let edges = [Edge(from: "a", to: "c"), Edge(from: "b", to: "c"), Edge(from: "c", to: "d"), Edge(from: "d", to: "b"), Edge(from: "a", to: "e")]
        let first = Layering.layout(nodes: nodes, edges: edges)
        let second = Layering.layout(nodes: nodes.reversed(), edges: edges.reversed())
        #expect(first == second)
    }

    @Test func selfLoopsUnknownNodesAndEmptyInputAreIgnored() {
        let result = Layering.layout(nodes: ["a"], edges: [Edge(from: "a", to: "a"), Edge(from: "a", to: "ghost")])
        #expect(result.rank == ["a": 0])
        #expect(Layering.layout(nodes: [], edges: []).layers.isEmpty)
    }
}
#endif
