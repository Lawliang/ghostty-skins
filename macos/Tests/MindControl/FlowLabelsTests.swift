#if os(macOS)
import CoreGraphics
import Foundation
import Testing
@testable import Ghostty

private typealias LabelPlanner = MindControl.LabelPlanner
private typealias LabelCandidate = MindControl.LabelCandidate
private typealias FlowLabels = MindControl.FlowLabels

struct FlowLabelsTests {
    private let view = CGSize(width: 1200, height: 800)
    private let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
    private static func measure(_ text: String, _ size: CGFloat, _ bold: Bool) -> CGSize { CGSize(width: CGFloat(text.count) * 6, height: 14) }

    private func texts(zoom: CGFloat, lit: Set<String> = []) -> Set<String> {
        let curves = MindControl.ArrowRouter.curves(for: layout)
        var camera = MindControl.PanZoomCamera.fitting(layout.bounds, in: view)
        camera.zoom = zoom
        let candidates = FlowLabels.candidates(layout: layout, curves: curves, camera: camera, viewSize: view, litFlows: lit, showControl: true)
        return Set(candidates.map(\.text))
    }

    @Test func farZoomShowsOnlyZones() {
        let shown = texts(zoom: 0.15)
        #expect(shown.contains("Phone"))
        #expect(!shown.contains("Audio"))
        #expect(!shown.contains("PCM16 24 kHz"))
    }

    /// With no zones there are no zone arrows to stand in for the systems far out, so the systems stay named.
    @Test func farZoomWithoutZonesShowsSystemNames() throws {
        let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arcaNoZones, broken: [])
        #expect(!layout.boxes.contains { $0.kind == .zone })
        #expect(layout.systemFloor)
        #expect(!self.layout.systemFloor)
        var camera = MindControl.PanZoomCamera.fitting(layout.bounds, in: view)
        camera.zoom = 0.15
        let candidates = FlowLabels.candidates(layout: layout, curves: MindControl.ArrowRouter.curves(for: layout), camera: camera,
                                               viewSize: view, litFlows: [], showControl: true)
        let audio = try #require(candidates.first { $0.id == "audio" })
        #expect(audio.opacity == 1)
        #expect(!candidates.contains { $0.id == "audio.gate" })
    }

    @MainActor
    @Test func farZoneNamesSitJustAboveTheirZones() throws {
        // At 0.15 a zone's name strip is 8 pt tall, so the 22 pt name goes above the zone, not over it or its neighbours.
        let curves = MindControl.ArrowRouter.curves(for: layout)
        let camera = MindControl.PanZoomCamera(center: CGPoint(x: layout.bounds.midX, y: layout.bounds.midY), zoom: 0.15)
        let candidates = FlowLabels.candidates(layout: layout, curves: curves, camera: camera, viewSize: view, litFlows: [], showControl: true)
        let placed = LabelPlanner.plan(candidates, viewport: view, measure: MindControl.LabelOverlayView.measure)
        let zones = layout.boxes.filter { $0.kind == .zone }
        #expect(zones.count == 3)
        let screenRects = zones.map { zone -> CGRect in
            let a = camera.toScreen(CGPoint(x: zone.rect.minX, y: zone.rect.minY), viewSize: view)
            let b = camera.toScreen(CGPoint(x: zone.rect.maxX, y: zone.rect.maxY), viewSize: view)
            return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        }
        var frames: [CGRect] = []
        for (zone, rect) in zip(zones, screenRects) {
            let label = try #require(placed.first { $0.id == zone.id }, "\(zone.title) is not shown")
            #expect(label.fontSize == 22)
            #expect(label.frame.maxY <= rect.minY, "\(zone.title) covers its zone")
            #expect(rect.minY - label.frame.maxY <= 8, "\(zone.title) floats away from its zone")
            #expect(abs(label.frame.minX - rect.minX) <= 1, "\(zone.title) is not over its zone's left edge")
            for other in screenRects { #expect(!label.frame.intersects(other), "\(zone.title) covers a zone") }
            frames.append(label.frame)
        }
        for i in frames.indices { for j in frames.indices where j > i { #expect(!frames[i].intersects(frames[j])) } }
    }

    @Test func nearZoneNamesStayInTheirNameStrip() throws {
        let curves = MindControl.ArrowRouter.curves(for: layout)
        let camera = MindControl.PanZoomCamera(center: CGPoint(x: layout.bounds.midX, y: layout.bounds.midY), zoom: 0.6)
        let candidates = FlowLabels.candidates(layout: layout, curves: curves, camera: camera, viewSize: view, litFlows: [], showControl: true)
        for zone in layout.boxes where zone.kind == .zone {
            let label = try #require(candidates.first { $0.id == zone.id })
            let expected = camera.toScreen(CGPoint(x: zone.rect.minX + MindControl.LayoutMetrics.zonePad * 0.6,
                                                   y: zone.rect.minY + MindControl.LayoutMetrics.zoneLabel / 2), viewSize: view)
            #expect(label.anchor == expected)
            #expect(label.leading && label.fontSize == 14)
        }
    }

    @Test func middleZoomShowsSystemsAndPartHints() {
        let shown = texts(zoom: 0.6)
        #expect(shown.contains("Audio"))
        #expect(shown.contains("2 parts"))
        #expect(!shown.contains("SpeechGate"))
        #expect(!shown.contains("PCM16 24 kHz"))
    }

    @Test func nearZoomShowsPartsAndArrowLabels() {
        let shown = texts(zoom: 1.3)
        #expect(shown.contains("SpeechGate"))
        #expect(shown.contains("PCM16 24 kHz"))
        #expect(!shown.contains("2 parts"))
    }

    @Test func selectedFeatureLabelsItsArrowsAtAnyArrowLevel() {
        #expect(texts(zoom: 0.6, lit: ["pcm"]).contains("PCM16 24 kHz +2"))
    }

    @Test func plannerNeverOverlapsAndPrefersPriority() {
        let a = LabelCandidate(id: "a", text: "low", anchor: CGPoint(x: 100, y: 100), leading: false, fontSize: 11, bold: false,
                               opacity: 1, priority: 5, background: false, maxWidth: nil)
        let b = LabelCandidate(id: "b", text: "high", anchor: CGPoint(x: 102, y: 101), leading: false, fontSize: 11, bold: false,
                               opacity: 1, priority: 1, background: false, maxWidth: nil)
        let placed = LabelPlanner.plan([a, b], viewport: view, measure: Self.measure)
        #expect(placed.map(\.id) == ["b"])
    }

    @Test func plannerTruncatesToMaxWidthAndSkipsOffscreen() {
        let long = LabelCandidate(id: "l", text: "Mic capture, the words-heard check, playback.", anchor: CGPoint(x: 10, y: 10), leading: true,
                                  fontSize: 11, bold: false, opacity: 1, priority: 1, background: false, maxWidth: 60)
        let off = LabelCandidate(id: "o", text: "gone", anchor: CGPoint(x: -500, y: 10), leading: true, fontSize: 11, bold: false,
                                 opacity: 1, priority: 1, background: false, maxWidth: nil)
        let placed = LabelPlanner.plan([long, off], viewport: view, measure: Self.measure)
        #expect(placed.count == 1)
        #expect(placed[0].text.hasSuffix("…"))
        #expect(placed[0].frame.width <= 60)
    }

    @Test func plannerRespectsBudget() {
        let many = (0..<400).map { i in
            LabelCandidate(id: "\(i)", text: "x", anchor: CGPoint(x: CGFloat(i % 40) * 30 + 5, y: CGFloat(i / 40) * 30 + 5), leading: true,
                           fontSize: 11, bold: false, opacity: 1, priority: 1, background: false, maxWidth: nil)
        }
        #expect(LabelPlanner.plan(many, viewport: view, measure: Self.measure).count == LabelPlanner.budget)
    }

    // MARK: Beyond the brief

    private static func label(_ id: String, _ text: String? = nil, at anchor: CGPoint, leading: Bool = true, priority: Int = 1,
                              maxWidth: CGFloat? = nil) -> LabelCandidate {
        LabelCandidate(id: id, text: text ?? id, anchor: anchor, leading: leading, fontSize: 11, bold: false, opacity: 1,
                       priority: priority, background: false, maxWidth: maxWidth)
    }

    /// Spec: zoomed out, a box shows its name, its summary and a faint "N parts" hint. All three must fit, not only be
    /// candidates: a summary that always collides with its own name never shows.
    /// Main actor: the real measure caches sizes in a static dictionary that only the main thread may touch.
    @MainActor
    @Test func middleZoomPlacesSystemNameSummaryAndPartHint() throws {
        let audio = try #require(layout.box("audio")).rect
        let curves = MindControl.ArrowRouter.curves(for: layout)
        for zoom: CGFloat in [0.45, 0.6, 0.8] {
            let camera = MindControl.PanZoomCamera(center: CGPoint(x: audio.midX, y: audio.midY), zoom: zoom)
            let candidates = FlowLabels.candidates(layout: layout, curves: curves, camera: camera, viewSize: view, litFlows: [], showControl: true)
            let placed = LabelPlanner.plan(candidates, viewport: view, measure: MindControl.LabelOverlayView.measure)
            let ids = Set(placed.map(\.id))
            #expect(ids.isSuperset(of: ["audio", "audio#summary"]), "zoom \(zoom): \(ids.sorted())")
            if zoom >= 0.6 { #expect(ids.contains("audio#parts"), "zoom \(zoom): \(ids.sorted())") }
            // The summary stays inside its box.
            let box = CGRect(origin: camera.toScreen(audio.origin, viewSize: view),
                             size: CGSize(width: audio.width * zoom, height: audio.height * zoom))
            if let summary = placed.first(where: { $0.id == "audio#summary" }) {
                #expect(box.contains(summary.frame), "zoom \(zoom): \(summary.frame) outside \(box)")
            }
        }
    }

    /// Focus layouts label everything at any zoom; a bent arrow's label sits on its bent middle.
    @Test func focusLayoutsLabelEveryBoxAndArrowAtAnyZoom() throws {
        let camera = MindControl.PanZoomCamera(center: .zero, zoom: 0.15)
        let feature = try #require(MindControl.FocusLayout.feature("speech", map: FlowFixtures.arca, broken: []))
        let featureCurves = MindControl.ArrowRouter.curves(for: feature)
        let featureLabels = FlowLabels.candidates(layout: feature, curves: featureCurves, camera: camera, viewSize: view, litFlows: [],
                                                  showControl: true)
        #expect(Set(featureLabels.map(\.text)).isSuperset(of: ["Audio", "Ring", "press DOWN / UP", "PCM16 24 kHz", "commit turn", "discard turn"]))
        let commit = try #require(featureLabels.first { $0.id == "flow:commit" })
        #expect(commit.anchor == camera.toScreen(try #require(featureCurves["flow:commit"]).mid, viewSize: view))

        let system = try #require(MindControl.FocusLayout.system("audio", map: FlowFixtures.arca, broken: []))
        let systemLabels = FlowLabels.candidates(layout: system, curves: MindControl.ArrowRouter.curves(for: system), camera: camera,
                                                 viewSize: view, litFlows: [], showControl: true)
        let shown = Set(systemLabels.map(\.text))
        #expect(shown.isSuperset(of: ["Audio", "AudioCapture", "SpeechGate", "PCM buffers", "begin / end"]))
        #expect(!shown.contains("2 parts"))
        // The summary sits below the name in view points; zoomed this far out it would hang off the box, so it waits.
        #expect(!systemLabels.contains { $0.id == "audio#summary" })
        let near = MindControl.PanZoomCamera(center: .zero, zoom: 0.5)
        #expect(FlowLabels.candidates(layout: system, curves: MindControl.ArrowRouter.curves(for: system), camera: near, viewSize: view,
                                      litFlows: [], showControl: true).contains { $0.id == "audio#summary" })
    }

    @Test func emptyLayoutHasNoLabels() {
        let empty = MindControl.MapLayout(boxes: [], arrows: [])
        let camera = MindControl.PanZoomCamera.fitting(empty.bounds, in: view)
        #expect(FlowLabels.candidates(layout: empty, curves: [:], camera: camera, viewSize: view, litFlows: ["pcm"], showControl: true).isEmpty)
        #expect(LabelPlanner.plan([], viewport: view, measure: Self.measure).isEmpty)
    }

    /// RectGrid converts to Int64 and traps on non-finite or huge values; such labels are skipped, never crash.
    @Test func plannerSkipsNonFiniteAnchorsAndSizes() {
        let anchors = [CGPoint(x: CGFloat.nan, y: 10), CGPoint(x: CGFloat.infinity, y: 10), CGPoint(x: -CGFloat.infinity, y: 10),
                       CGPoint(x: 10, y: CGFloat.nan), CGPoint(x: 10, y: CGFloat.infinity), CGPoint(x: 10, y: -CGFloat.infinity)]
        var candidates: [LabelCandidate] = []
        for (i, anchor) in anchors.enumerated() {
            candidates.append(Self.label("anchor\(i)", "bad", at: anchor, leading: true))
            candidates.append(Self.label("centred\(i)", "bad", at: anchor, leading: false))
        }
        let sizes: [String: CGSize] = ["wide": CGSize(width: CGFloat.infinity, height: 14), "tall": CGSize(width: 20, height: CGFloat.infinity),
                                       "nan": CGSize(width: CGFloat.nan, height: 14), "negative": CGSize(width: -40, height: 14),
                                       "flat": CGSize(width: 30, height: -14)]
        for (i, text) in sizes.keys.sorted().enumerated() {
            candidates.append(Self.label(text, at: CGPoint(x: 10, y: 100 + CGFloat(i) * 40)))
            candidates.append(Self.label(text + "-centred", text, at: CGPoint(x: 300, y: 100 + CGFloat(i) * 40), leading: false))
        }
        candidates.append(Self.label("ok", at: CGPoint(x: 600, y: 400)))
        let placed = LabelPlanner.plan(candidates, viewport: view) { text, size, bold in sizes[text] ?? Self.measure(text, size, bold) }
        #expect(placed.map(\.id) == ["ok"])
    }

    @Test func plannerClipsHugeFootprintsToTheViewport() {
        // A finite footprint far wider than RectGrid's Int64 cells can index, crossing the whole view.
        let huge = Self.label("huge", at: CGPoint(x: -1e30, y: 100))
        let blocked = Self.label("blocked", "b", at: CGPoint(x: 600, y: 100), priority: 2)
        let clear = Self.label("clear", "c", at: CGPoint(x: 600, y: 300), priority: 2)
        let placed = LabelPlanner.plan([huge, blocked, clear], viewport: view) { text, size, bold in
            text == "huge" ? CGSize(width: 2e30, height: 14) : Self.measure(text, size, bold)
        }
        #expect(placed.map(\.id) == ["huge", "clear"])
    }

    @Test func plannerNeedsAUsableViewport() {
        let near = Self.label("near", at: CGPoint(x: 10, y: 10))
        let far = Self.label("far", at: CGPoint(x: 1e25, y: 10))
        for viewport in [CGSize.zero, CGSize(width: -1200, height: 800), CGSize(width: CGFloat.nan, height: 800),
                         CGSize(width: 1200, height: CGFloat.infinity), CGSize(width: 1e30, height: 1e30)] {
            #expect(LabelPlanner.plan([near, far], viewport: viewport, measure: Self.measure).isEmpty, "\(viewport)")
        }
    }

    @Test func plannerSkipsUnusableMaxWidths() {
        let candidates = [Self.label("zero", at: CGPoint(x: 10, y: 10), maxWidth: 0),
                          Self.label("negative", at: CGPoint(x: 10, y: 60), maxWidth: -40),
                          Self.label("tiny", at: CGPoint(x: 10, y: 110), maxWidth: 12),
                          Self.label("nan", at: CGPoint(x: 10, y: 160), maxWidth: .nan),
                          Self.label("unbounded", "a long label that is never cut", at: CGPoint(x: 10, y: 210), maxWidth: .infinity)]
        let placed = LabelPlanner.plan(candidates, viewport: view, measure: Self.measure)
        #expect(placed.map(\.id) == ["unbounded"])
        #expect(placed.first?.text == "a long label that is never cut")
    }

    @Test func plannerDropsLabelsWithNothingToShow() {
        let wide: (String, CGFloat, Bool) -> CGSize = { text, _, _ in CGSize(width: CGFloat(text.count) * 10, height: 14) }
        let empty = Self.label("empty", "", at: CGPoint(x: 100, y: 100))
        // Only "…" (10 wide) fits in 15; "W…" is 20.
        let ellipsis = Self.label("ellipsis", "Wide", at: CGPoint(x: 100, y: 200), maxWidth: 15)
        let kept = Self.label("kept", "Wide", at: CGPoint(x: 100, y: 300), maxWidth: 25)
        let placed = LabelPlanner.plan([empty, ellipsis, kept], viewport: view, measure: wide)
        #expect(placed.map(\.id) == ["kept"])
        #expect(placed.first?.text == "W…")
    }

    /// Labels are re-planned every frame and measuring text is the costly part, so cutting a long label to fit
    /// takes a handful of measurements, not one per character.
    @Test func plannerTruncatesLongTextWithFewMeasurements() {
        let long = Self.label("long", String(repeating: "word ", count: 800), at: CGPoint(x: 10, y: 10), maxWidth: 60)
        var calls = 0
        let placed = LabelPlanner.plan([long], viewport: view) { text, size, bold in
            calls += 1
            return Self.measure(text, size, bold)
        }
        #expect(placed.map(\.text) == ["word word…"])
        #expect(calls <= 20, "\(calls) measurements")
    }
    // MARK: Alternate anchors

    @Test func plannerTriesAlternateAnchorsBeforeDroppingALabel() {
        let first = Self.label("first", "aaaaaaaaaa", at: CGPoint(x: 100, y: 100), leading: false, priority: 1)
        var second = Self.label("second", "bbbbbbbbbb", at: CGPoint(x: 100, y: 100), leading: false, priority: 2)
        second.alternates = [CGPoint(x: 110, y: 104), CGPoint(x: 100, y: 140), CGPoint(x: 100, y: 180)]
        let placed = LabelPlanner.plan([first, second], viewport: view, measure: Self.measure)
        #expect(placed.map(\.id) == ["first", "second"])
        // The first alternate still overlaps; the second is free.
        #expect(placed.last?.frame.midY == 140)
        var blocked = second
        blocked.alternates = [CGPoint(x: 104, y: 102)]
        #expect(LabelPlanner.plan([first, blocked], viewport: view, measure: Self.measure).map(\.id) == ["first"])
    }

    /// Arrow labels carry alternates along their curve, so parallel arrows that share a midpoint area all get one.
    @Test func arrowLabelsOfferPointsAlongTheirCurve() throws {
        let curves = MindControl.ArrowRouter.curves(for: layout)
        var camera = MindControl.PanZoomCamera.fitting(layout.bounds, in: view)
        camera.zoom = 1.3
        let candidates = FlowLabels.candidates(layout: layout, curves: curves, camera: camera, viewSize: view, litFlows: [], showControl: true)
        let pcm = try #require(candidates.first { $0.text == "PCM16 24 kHz" })
        let curve = try #require(curves[pcm.id])
        #expect(pcm.alternates == [0.35, 0.65, 0.25, 0.75].map { camera.toScreen(curve.point(at: $0), viewSize: view) })
        // Box names stay where they are.
        #expect(candidates.filter { !$0.background }.allSatisfy { $0.alternates.isEmpty })
    }

    @MainActor
    private func plannedTexts(zoom: CGFloat? = nil, feature: String? = nil) -> [MindControl.PlacedLabel] {
        let c = MindControl.MapController()
        c.viewSize = view
        let files = FlowFixtures.arcaSources
        let snapshot = MindControl.FlowSnapshot(root: URL(fileURLWithPath: "/tmp/mc-labels"), flowData: nil, layoutData: nil,
                                                sourceFiles: files.keys.sorted(), read: { files[$0] })
        c.show(.init(map: FlowFixtures.arca, report: MindControl.FlowCheck.run(map: FlowFixtures.arca, snapshot: snapshot),
                     saved: [:], generation: 1), root: URL(fileURLWithPath: "/tmp/mc-labels"))
        if let zoom { c.camera = MindControl.PanZoomCamera(center: c.camera.center, zoom: zoom) }
        if let feature { c.selectFeature(feature) }
        return c.labels()
    }

    private static func footprint(_ label: MindControl.PlacedLabel) -> CGRect {
        label.hasBackground
            ? label.frame.insetBy(dx: -MindControl.LabelOverlayView.pillPadding.width, dy: -MindControl.LabelOverlayView.pillPadding.height)
            : label.frame
    }

    private static func expectNoOverlaps(_ labels: [MindControl.PlacedLabel]) {
        for (i, a) in labels.enumerated() {
            for b in labels[(i + 1)...] {
                #expect(!footprint(a).intersects(footprint(b)), "\(a.text) overlaps \(b.text)")
            }
        }
    }

    @MainActor
    @Test func parallelArrowsUpCloseAllGetTheirLabels() {
        let placed = plannedTexts(zoom: 1.3)
        let texts = Set(placed.map(\.text))
        #expect(texts.isSuperset(of: ["PCM16 24 kHz", "commit turn", "discard turn"]), "\(texts.sorted())")
        Self.expectNoOverlaps(placed)
    }

    @MainActor
    @Test func aLitFeatureLabelsEveryStepAtFitZoom() {
        let placed = plannedTexts(feature: "speech")
        let texts = Set(placed.map(\.text))
        #expect(texts.isSuperset(of: ["begin / end", "press DOWN / UP"]), "\(texts.sorted())")
        Self.expectNoOverlaps(placed)
    }
}
#endif
