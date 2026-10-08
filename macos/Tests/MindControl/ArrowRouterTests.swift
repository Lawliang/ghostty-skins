#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias MapLayout = MindControl.MapLayout
private typealias ArrowRouter = MindControl.ArrowRouter

struct ArrowRouterTests {
    private func box(_ id: String, _ rect: CGRect) -> MapLayout.Box {
        MapLayout.Box(id: id, kind: .system, rect: rect, title: id, subtitle: nil, external: false, tint: -1, partCount: 0)
    }

    private func arrow(_ id: String, _ from: String, _ to: String) -> MapLayout.ArrowSpec {
        MapLayout.ArrowSpec(id: id, level: .part, from: from, to: to, kind: .data, flowIDs: [id], label: id, conditional: false, weight: 1)
    }

    @Test func rightwardArrowLeavesTheRightEdge() throws {
        let layout = MapLayout(boxes: [box("a", CGRect(x: 0, y: 0, width: 100, height: 60)), box("b", CGRect(x: 300, y: 0, width: 100, height: 60))],
                               arrows: [arrow("f", "a", "b")])
        let curve = try #require(ArrowRouter.curves(for: layout)["f"])
        #expect(curve.p0 == CGPoint(x: 100, y: 30))
        #expect(curve.p3 == CGPoint(x: 300, y: 30))
        #expect(curve.point(at: 0) == curve.p0)
        #expect(curve.point(at: 1) == curve.p3)
        #expect(curve.distance(to: curve.mid) < 0.5)
    }

    @Test func returnArrowIsOffsetFromItsPartner() throws {
        let layout = MapLayout(boxes: [box("a", CGRect(x: 0, y: 0, width: 100, height: 60)), box("b", CGRect(x: 300, y: 0, width: 100, height: 60))],
                               arrows: [arrow("go", "a", "b"), arrow("back", "b", "a")])
        let curves = ArrowRouter.curves(for: layout)
        let go = try #require(curves["go"]), back = try #require(curves["back"])
        #expect(go.p0.y != back.p3.y)
        #expect(back.p0.x == 300)
    }

    @Test func stackedBoxesUseVerticalEdges() throws {
        let layout = MapLayout(boxes: [box("a", CGRect(x: 0, y: 0, width: 100, height: 60)), box("b", CGRect(x: 20, y: 200, width: 100, height: 60))],
                               arrows: [arrow("f", "a", "b")])
        let curve = try #require(ArrowRouter.curves(for: layout)["f"])
        #expect(curve.p0.y == 60)
        #expect(curve.p3.y == 200)
    }
}
#endif
