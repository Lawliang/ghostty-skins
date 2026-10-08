#if os(macOS)
import CoreGraphics
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
}
#endif
