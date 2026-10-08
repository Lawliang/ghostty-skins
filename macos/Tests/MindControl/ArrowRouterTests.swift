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

    // MARK: - Around boxes

    private func box(_ id: String, _ kind: MapLayout.BoxKind, _ rect: CGRect) -> MapLayout.Box {
        MapLayout.Box(id: id, kind: kind, rect: rect, title: id, subtitle: nil, external: false, tint: -1, partCount: 0)
    }

    private func arrow(_ id: String, _ from: String, _ to: String, level: MapLayout.ArrowLevel) -> MapLayout.ArrowSpec {
        MapLayout.ArrowSpec(id: id, level: level, from: from, to: to, kind: .data, flowIDs: [id], label: id, conditional: false, weight: 1)
    }

    /// Boxes the curve passes inside, sampled finely; edges don't count.
    private func crossed(_ curve: MindControl.Curve, _ boxes: [MapLayout.Box]) -> [String] {
        boxes.filter { box in
            let inner = box.rect.insetBy(dx: 1, dy: 1)
            return (0...400).contains { inner.contains(curve.point(at: CGFloat($0) / 400)) }
        }.map(\.id)
    }

    @Test func stackedBoxesRouteAroundABoxBetweenThem() throws {
        let a = box("a", CGRect(x: 0, y: 0, width: 220, height: 84))
        let middle = box("middle", CGRect(x: 0, y: 134, width: 220, height: 84))
        let b = box("b", CGRect(x: 0, y: 268, width: 220, height: 84))
        let layout = MapLayout(boxes: [a, middle, b], arrows: [arrow("down", "a", "b"), arrow("up", "b", "a")])
        let curves = ArrowRouter.curves(for: layout)
        for id in ["down", "up"] {
            let curve = try #require(curves[id])
            #expect(crossed(curve, [a, middle, b]).isEmpty, "\(id) crosses \(crossed(curve, [a, middle, b]))")
        }
        let down = try #require(curves["down"]), up = try #require(curves["up"])
        // Each end sits on its box's edge.
        #expect(a.rect.insetBy(dx: -0.01, dy: -0.01).contains(down.p0) && !a.rect.insetBy(dx: 0.01, dy: 0.01).contains(down.p0))
        #expect(b.rect.insetBy(dx: -0.01, dy: -0.01).contains(down.p3) && !b.rect.insetBy(dx: 0.01, dy: 0.01).contains(down.p3))
        // The flow and its return still keep apart.
        #expect(hypot(down.mid.x - up.mid.x, down.mid.y - up.mid.y) >= 8)
    }

    @Test func aPartsArrowToAnotherSystemGoesAroundItsSiblingPart() throws {
        let zone = box("zone:z", .zone, CGRect(x: -48, y: -104, width: 1000, height: 400))
        let system = box("s", .system, CGRect(x: 0, y: 0, width: 420, height: 124))
        let first = box("s.first", .part, CGRect(x: 20, y: 64, width: 160, height: 40))
        let sibling = box("s.sibling", .part, CGRect(x: 220, y: 64, width: 160, height: 40))
        let other = box("t", .system, CGRect(x: 600, y: 20, width: 220, height: 84))
        let boxes = [zone, system, first, sibling, other]
        let layout = MapLayout(boxes: boxes, arrows: [arrow("f", "s.first", "t", level: .part), arrow("g", "s.first", "t", level: .part)])
        let curves = ArrowRouter.curves(for: layout)
        for id in ["f", "g"] {
            let curve = try #require(curves[id])
            #expect(!crossed(curve, [sibling, other, first]).contains("s.sibling"), "\(id) crosses the sibling part")
            #expect(crossed(curve, [sibling, other, first]).isEmpty)
        }
    }

    @Test func partsArrowsIgnoreHiddenBoxesAtTheSystemLevel() throws {
        // At the system level parts are hidden, so a system arrow passing over another system's part area is
        // fine as long as it misses the systems.
        let a = box("a", .system, CGRect(x: 0, y: 0, width: 220, height: 84))
        let b = box("b", .system, CGRect(x: 400, y: 0, width: 220, height: 84))
        let hiddenPart = box("c.p", .part, CGRect(x: 250, y: 20, width: 100, height: 40))
        let layout = MapLayout(boxes: [a, b, hiddenPart], arrows: [arrow("f", "a", "b", level: .system)])
        let curve = try #require(ArrowRouter.curves(for: layout)["f"])
        #expect(curve == ArrowRouter.route(from: a.rect, to: b.rect, offset: 0))
    }

    @Test func unobstructedArrowsKeepTheirFacingCurves() throws {
        // The same numbers the router gave before it learned to avoid boxes.
        let boxes = [box("a", left), box("b", right), box("c", CGRect(x: 20, y: 200, width: 100, height: 60))]
        var bent = arrow("bent", "a", "c")
        bent.bend = 30
        let layout = MapLayout(boxes: boxes, arrows: [arrow("go", "a", "b"), arrow("back", "b", "a"), bent])
        let curves = ArrowRouter.curves(for: layout)
        #expect(curves["go"] == MindControl.Curve(p0: CGPoint(x: 100, y: 23), p1: CGPoint(x: 190, y: 23),
                                                  p2: CGPoint(x: 210, y: 23), p3: CGPoint(x: 300, y: 23)))
        #expect(curves["back"] == MindControl.Curve(p0: CGPoint(x: 300, y: 37), p1: CGPoint(x: 210, y: 37),
                                                    p2: CGPoint(x: 190, y: 37), p3: CGPoint(x: 100, y: 37)))
        let plain = MindControl.Curve(p0: CGPoint(x: 50, y: 60), p1: CGPoint(x: 50, y: 123),
                                      p2: CGPoint(x: 70, y: 137), p3: CGPoint(x: 70, y: 200))
        #expect(curves["bent"] == ArrowRouter.route(from: left, to: CGRect(x: 20, y: 200, width: 100, height: 60), offset: 0, bend: 30))
        #expect(ArrowRouter.route(from: left, to: CGRect(x: 20, y: 200, width: 100, height: 60), offset: 0) == plain)
    }

    @Test func theArcaMapsArrowsMissEveryBoxTheyDoNotStartOrEndIn() throws {
        let map = FlowFixtures.arca
        let main = MindControl.FlowLayout.layout(map: map, broken: [])
        let layouts = [("main", main),
                       ("system", try #require(MindControl.FocusLayout.system("audio", map: map, broken: []))),
                       ("feature", try #require(MindControl.FocusLayout.feature("speech", map: map, broken: [])))]
        for (name, layout) in layouts {
            let curves = ArrowRouter.curves(for: layout)
            for arrow in layout.arrows {
                let curve = try #require(curves[arrow.id])
                guard let from = layout.box(arrow.from)?.rect, let to = layout.box(arrow.to)?.rect else { continue }
                let byLevel: [MapLayout.ArrowLevel: Set<MapLayout.BoxKind>] = [.zone: [.zone], .system: [.zone, .system],
                                                                                 .part: [.zone, .system, .part]]
                let shown: Set<MapLayout.BoxKind> = layout.fixedLevel ? [.zone, .system, .part] : byLevel[arrow.level] ?? []
                let obstacles = layout.boxes.filter { box in
                    shown.contains(box.kind) && box.id != arrow.from && box.id != arrow.to
                        && !box.rect.contains(from) && !box.rect.contains(to)
                }
                #expect(crossed(curve, obstacles).isEmpty, "\(name) \(arrow.id) crosses \(crossed(curve, obstacles))")
            }
        }
    }

    @Test func keepingALayoutsOwnRoutesGivesItsCurves() throws {
        let map = FlowFixtures.arca
        // (layout, whether any arrow there has to detour)
        let cases = [(MindControl.FlowLayout.layout(map: map, broken: []), true),
                     (try #require(MindControl.FocusLayout.system("audio", map: map, broken: [])), true),
                     (try #require(MindControl.FocusLayout.feature("speech", map: map, broken: [])), false)]
        for (layout, detours) in cases {
            let plan = ArrowRouter.plan(for: layout)
            #expect(plan.curves == ArrowRouter.curves(for: layout))
            #expect(ArrowRouter.curves(for: layout, keeping: plan.routes) == plan.curves)
            #expect(plan.routes.values.contains { $0.detour } == detours)
        }
    }

    @Test func keptRoutesFollowMovedBoxesOnTheSameSides() throws {
        // `begin` detours left of BLE link; moved boxes keep that bracket, only its ends move.
        let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        let routes = ArrowRouter.plan(for: layout).routes
        let begin = try #require(routes["sys:tap>audio"])
        #expect(begin.detour && begin.exit == .left && begin.entry == .left)
        var moved = layout
        moved.boxes = moved.boxes.map { box in
            var box = box
            if box.id == "tap" { box.rect = box.rect.offsetBy(dx: 400, dy: 0) }
            return box
        }
        let curve = try #require(ArrowRouter.curves(for: moved, keeping: routes)["sys:tap>audio"])
        let tap = try #require(moved.box("tap")).rect
        #expect(abs(curve.p0.x - tap.minX) < 0.001)
        #expect(curve.p1.x < curve.p0.x)
    }

    @Test func routingIsDeterministic() {
        let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        #expect(ArrowRouter.curves(for: layout) == ArrowRouter.curves(for: layout))
    }
}
#endif
