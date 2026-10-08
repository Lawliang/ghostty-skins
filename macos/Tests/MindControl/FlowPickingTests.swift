#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias FlowPicking = MindControl.FlowPicking

struct FlowPickingTests {
    private let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
    private var curves: [String: MindControl.Curve] { MindControl.ArrowRouter.curves(for: layout) }

    private func centre(_ id: String) -> CGPoint {
        let rect = layout.box(id)!.rect
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test func partsAreHitOnlyWhenZoomedIn() {
        let point = centre("audio.gate")
        #expect(FlowPicking.hit(point, layout: layout, curves: curves, zoom: 1.3, showControl: true) == .box("audio.gate"))
        #expect(FlowPicking.hit(point, layout: layout, curves: curves, zoom: 0.5, showControl: true) == .box("audio"))
    }

    @Test func arrowsAreHitAtTheirOwnLevel() throws {
        let mid = try #require(curves["flow:pcm"]).mid
        #expect(FlowPicking.hit(mid, layout: layout, curves: curves, zoom: 1.5, showControl: true) == .arrow("flow:pcm"))
        let merged = try #require(curves["sys:audio>agent"]).mid
        #expect(FlowPicking.hit(merged, layout: layout, curves: curves, zoom: 0.6, showControl: true) == .arrow("sys:audio>agent"))
    }

    @Test func farOutWithoutZonesSystemArrowsAreHit() throws {
        let flat = MindControl.FlowLayout.layout(map: FlowFixtures.arcaNoZones, broken: [])
        let curves = MindControl.ArrowRouter.curves(for: flat)
        let merged = try #require(curves["sys:audio>agent"]).mid
        #expect(FlowPicking.hit(merged, layout: flat, curves: curves, zoom: 0.15, showControl: true) == .arrow("sys:audio>agent"))
        #expect(MindControl.ZoomLevels.arrowLevel(at: 0.15, systemFloor: true) == .system)
        #expect(MindControl.ZoomLevels.arrowLevel(at: 0.15, systemFloor: false) == .zone)
        #expect(MindControl.ZoomLevels.arrowLevel(at: 1.2, systemFloor: true) == .part)
    }

    @Test func hiddenControlArrowsAreNotHit() throws {
        let mid = try #require(curves["flow:event"]).mid
        #expect(FlowPicking.hit(mid, layout: layout, curves: curves, zoom: 1.5, showControl: true) == .arrow("flow:event"))
        #expect(FlowPicking.hit(mid, layout: layout, curves: curves, zoom: 1.5, showControl: false) != .arrow("flow:event"))
    }

    @Test func emptySpaceAndZonesHitNothing() {
        let zone = layout.box("zone:phone")!.rect
        let insideZoneOnly = CGPoint(x: zone.minX + 4, y: zone.minY + 4)
        #expect(FlowPicking.hit(insideZoneOnly, layout: layout, curves: curves, zoom: 0.6, showControl: true) == nil)
        #expect(FlowPicking.hit(CGPoint(x: -99_999, y: -99_999), layout: layout, curves: curves, zoom: 1, showControl: true) == nil)
    }

    // MARK: Beyond the brief

    /// Focus layouts show every box and arrow at any zoom, so they are all pickable far out, bent arrows included.
    @Test func focusLayoutsHitPartsAndBentArrowsAtAnyZoom() throws {
        let system = try #require(MindControl.FocusLayout.system("audio", map: FlowFixtures.arca, broken: []))
        let systemCurves = MindControl.ArrowRouter.curves(for: system)
        let gate = try #require(system.box("audio.gate")).rect
        #expect(FlowPicking.hit(CGPoint(x: gate.midX, y: gate.midY), layout: system, curves: systemCurves, zoom: 0.2, showControl: true)
            == .box("audio.gate"))

        let feature = try #require(MindControl.FocusLayout.feature("speech", map: FlowFixtures.arca, broken: []))
        let featureCurves = MindControl.ArrowRouter.curves(for: feature)
        for id in ["flow:commit", "flow:discard"] {
            let arrow = try #require(feature.arrows.first { $0.id == id })
            #expect(arrow.bend != 0)
            let mid = try #require(featureCurves[id]).mid
            #expect(FlowPicking.hit(mid, layout: feature, curves: featureCurves, zoom: 0.2, showControl: true) == .arrow(id))
        }
    }

    @Test func nothingIsHitInAnEmptyLayoutOrAtANonFinitePoint() {
        let empty = MindControl.MapLayout(boxes: [], arrows: [])
        #expect(FlowPicking.hit(.zero, layout: empty, curves: [:], zoom: 1, showControl: true) == nil)
        for point in [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity), CGPoint(x: -CGFloat.infinity, y: 0)] {
            #expect(FlowPicking.hit(point, layout: layout, curves: curves, zoom: 1.3, showControl: true) == nil)
        }
    }
}
#endif
