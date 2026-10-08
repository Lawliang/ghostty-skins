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

    // MARK: - Bend

    private let left = CGRect(x: 0, y: 0, width: 100, height: 60)
    private let right = CGRect(x: 300, y: 0, width: 100, height: 60)

    @Test func noBendGivesThePlainCurve() {
        let plain = MindControl.Curve(p0: CGPoint(x: 100, y: 30), p1: CGPoint(x: 190, y: 30),
                                      p2: CGPoint(x: 210, y: 30), p3: CGPoint(x: 300, y: 30))
        #expect(ArrowRouter.route(from: left, to: right, offset: 0) == plain)
        #expect(ArrowRouter.route(from: left, to: right, offset: 0, bend: 0) == plain)
        #expect(MapLayout.ArrowSpec(id: "f", level: .part, from: "a", to: "b", kind: .data, flowIDs: ["f"], label: "f",
                                    conditional: false, weight: 1).bend == 0)
    }

    @Test func positiveBendPushesTheMiddleDownAndNegativeUp() {
        let plain = ArrowRouter.route(from: left, to: right, offset: 0)
        let down = ArrowRouter.route(from: left, to: right, offset: 0, bend: 40)
        let up = ArrowRouter.route(from: left, to: right, offset: 0, bend: -40)
        for curve in [down, up] {
            #expect(curve.p0 == plain.p0 && curve.p3 == plain.p3)
        }
        #expect(down.mid.y > plain.mid.y)
        #expect(up.mid.y < plain.mid.y)
        #expect(abs(down.mid.x - plain.mid.x) < 0.001)
        // Both control points move the full bend, so the middle moves 3/4 of it.
        #expect(abs(down.mid.y - plain.mid.y - 30) < 0.001)
    }

    @Test func negativeBendIsUpWhicheverWayTheArrowRuns() {
        let leftward = ArrowRouter.route(from: right, to: left, offset: 0)
        let bent = ArrowRouter.route(from: right, to: left, offset: 0, bend: -40)
        #expect(bent.mid.y < leftward.mid.y)
    }

    @Test func curvesApplyTheArrowsBend() throws {
        var bent = arrow("f", "a", "b")
        bent.bend = -40
        let boxes = [box("a", left), box("b", right)]
        let plain = try #require(ArrowRouter.curves(for: MapLayout(boxes: boxes, arrows: [arrow("f", "a", "b")]))["f"])
        let curve = try #require(ArrowRouter.curves(for: MapLayout(boxes: boxes, arrows: [bent]))["f"])
        #expect(curve.p0 == plain.p0 && curve.p3 == plain.p3)
        #expect(curve.mid.y < plain.mid.y)
    }
}
#endif
