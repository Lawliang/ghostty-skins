#if os(macOS)
import Testing
@testable import Ghostty

private typealias Inspector = MindControl.Inspector
private typealias NodeDetails = MindControl.NodeDetails

@MainActor
struct InspectorTests {
    @Test func hoverSetsFocus() {
        let inspector = Inspector()
        var changes: [Int?] = []
        inspector.onFocusChange = { changes.append($0) }
        inspector.hover(3)
        inspector.hover(3)                 // no change, no callback
        #expect(inspector.focus == 3)
        #expect(changes == [3])
    }

    @Test func hoverEmptyClearsFocus() {
        let inspector = Inspector()
        inspector.hover(3)
        inspector.hover(nil)
        #expect(inspector.focus == nil)
    }

    @Test func clickPinsAndHoverDoesNotMoveAPin() {
        let inspector = Inspector()
        inspector.click(5)
        inspector.hover(2)
        #expect(inspector.pinned == 5)
        #expect(inspector.focus == 5)
        inspector.click(5)                 // clicking the pinned node again unpins
        #expect(inspector.pinned == nil)
        #expect(inspector.focus == 2)
    }

    @Test func clickEmptySpaceUnpins() {
        let inspector = Inspector()
        inspector.click(5)
        inspector.click(nil)
        #expect(inspector.pinned == nil)
    }

    @Test func escapeUnpinsFirstThenReportsNothingToDo() {
        let inspector = Inspector()
        inspector.click(1)
        #expect(inspector.escape())
        #expect(inspector.pinned == nil)
        #expect(!inspector.escape())
    }

    @Test func resetClearsEverything() {
        let inspector = Inspector()
        var last: Int?? = .none
        inspector.onFocusChange = { last = $0 }
        inspector.hover(1)
        inspector.click(2)
        inspector.reset()
        #expect(inspector.hovered == nil && inspector.pinned == nil)
        #expect(last == .some(nil))
    }

    @Test func nodeDetailsCountUses() {
        let graph = MindControl.Graph.sample
        let views0 = NodeDetails.make(graph: graph, nodeID: "Views/0")
        #expect(views0?.name == "Views 1")
        #expect(views0?.path == "Views/0")
        #expect(views0?.uses == 1)          // Views/0 → Graph/1
        #expect(views0?.usedBy == 0)
        let graph1 = NodeDetails.make(graph: graph, nodeID: "Graph/1")
        #expect(graph1?.usedBy == 1)
        let folder = NodeDetails.make(graph: MindControl.ConeTreeLayout.graph(for: MindControl.FileTree(
            rootName: "p", rootPath: "/p", files: ["src/a.swift", "src/b.swift"], totalFileCount: 2)), nodeID: "src")
        #expect(folder?.files == 2)
        #expect(NodeDetails.make(graph: graph, nodeID: "missing") == nil)
    }
}
#endif
