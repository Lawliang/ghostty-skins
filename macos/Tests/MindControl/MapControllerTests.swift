#if os(macOS)
import CoreGraphics
import Foundation
import QuartzCore
import AppKit
import Testing
@testable import Ghostty

private typealias MapController = MindControl.MapController

@MainActor
struct MapControllerTests {
    private func loaded(generation: Int = 1) -> MindControl.Model.Loaded {
        let files = FlowFixtures.arcaSources
        let snapshot = MindControl.FlowSnapshot(root: URL(fileURLWithPath: "/tmp/mc-ctl"), flowData: nil, layoutData: nil,
                                                sourceFiles: files.keys.sorted(), read: { files[$0] })
        return .init(map: FlowFixtures.arca, report: MindControl.FlowCheck.run(map: FlowFixtures.arca, snapshot: snapshot),
                     saved: [:], generation: generation)
    }

    private func controller(root: URL = URL(fileURLWithPath: "/tmp/mc-ctl")) -> MapController {
        let controller = MapController()
        controller.viewSize = CGSize(width: 1200, height: 800)
        controller.show(loaded(), root: root)
        return controller
    }

    @Test func showLaysOutAndFitsTheMap() {
        let c = controller()
        #expect(c.layout == c.baseLayout)
        #expect(c.baseLayout.box("audio") != nil)
        let topLeft = c.camera.toScreen(c.layout.bounds.origin, viewSize: c.viewSize)
        let bottomRight = c.camera.toScreen(CGPoint(x: c.layout.bounds.maxX, y: c.layout.bounds.maxY), viewSize: c.viewSize)
        #expect(topLeft.x >= 0 && topLeft.y >= 0 && bottomRight.x <= 1200 && bottomRight.y <= 800)
    }

    @Test func selectingAFeatureLightsItAndListsItsSteps() {
        let c = controller()
        c.selectFeature("speech")
        #expect(c.style.litFlows.count == 9)
        guard case .feature(let name, let groups, let unknown) = c.sidePanel else { Issue.record("\(c.sidePanel)"); return }
        #expect(name == "A press becomes speech")
        #expect(groups.count == 4)
        #expect(unknown.isEmpty)
        c.selectFeature("speech")
        #expect(c.selectedFeature == nil)
    }

    @Test func escapeUnwindsSearchThenFocusThenSelection() {
        let c = controller()
        c.selectFeature("speech")
        c.enterFocus(.system("audio"))
        c.query = "aud"
        #expect(c.escape())
        #expect(c.query.isEmpty)
        #expect(c.escape())
        #expect(c.focus == nil)
        #expect(c.escape())
        #expect(c.selectedFeature == nil)
        #expect(!c.escape())
    }

    @Test func focusSwapsTheLayoutAndBack() {
        let c = controller()
        c.enterFocus(.system("audio"))
        #expect(c.layout.fixedLevel)
        #expect(c.layout.box("ble") == nil)
        #expect(c.breadcrumb == ["mc-ctl", "Audio"])
        c.exitFocus()
        #expect(c.layout == c.baseLayout)
    }

    @Test func blendSlidesSharedBoxesAndFadesTheRest() throws {
        let c = controller()
        let focus = try #require(MindControl.FocusLayout.system("audio", map: FlowFixtures.arca, broken: []))
        let (mid, fade) = MapController.blend(from: c.baseLayout, to: focus, t: 0.5)
        let a = try #require(c.baseLayout.box("audio")).rect, b = try #require(focus.box("audio")).rect
        #expect(abs(try #require(mid.box("audio")).rect.minX - (a.minX + b.minX) / 2) < 1e-9)
        #expect(fade["ble"] == 0.5)
        #expect(fade["audio"] == nil)
    }

    @Test func draggingASystemSavesItsPosition() throws {
        let project = try TempProject()
        let c = controller(root: project.url)
        let before = try #require(c.baseLayout.box("audio")).rect
        c.drag(system: "audio", byScreen: CGSize(width: 100, height: 0))
        let after = try #require(c.baseLayout.box("audio")).rect
        #expect(abs(after.minX - (before.minX + 100 / c.camera.zoom)) < 1e-6)
        c.endDrag("audio")
        let data = try Data(contentsOf: project.url.appendingPathComponent(".mindcontrol/layout.json"))
        #expect(MindControl.LayoutStore.decode(data)["audio"] == after.origin)
    }

    @Test func onlySystemsOnTheMainMapCanBeDragged() {
        let c = controller()
        #expect(c.canDrag("audio"))
        #expect(!c.canDrag("audio.gate"))
        #expect(!c.canDrag("zone:phone"))
        c.enterFocus(.system("audio"))
        #expect(!c.canDrag("audio"))
    }

    @Test func searchingAFileWithNoSystemOpensHealth() {
        let c = controller()
        c.navigate(to: MindControl.SearchResult(kind: .file, title: "Stray.swift", detail: "", target: .file(path: "x/Stray.swift", system: nil)))
        #expect(c.mode == .health)
        if case .health = c.sidePanel {} else { Issue.record("\(c.sidePanel)") }
    }

    @Test func searchingASystemSelectsIt() {
        let c = controller()
        c.navigate(to: MindControl.SearchResult(kind: .system, title: "Audio", detail: "", target: .system("audio")))
        #expect(c.selection == .box("audio"))
        #expect(c.style.pulsed == "audio")
        guard case .system(let name, _, let incoming, let outgoing, let files) = c.sidePanel else { Issue.record("\(c.sidePanel)"); return }
        #expect(name == "Audio")
        #expect(incoming.map(\.id) == ["begin"])
        #expect(Set(outgoing.map(\.id)) == ["pcm", "commit", "discard"])
        #expect(files == ["app/Sources/Audio/AudioCapture.swift", "app/Sources/Audio/SpeechGate.swift"])
    }

    @Test func doubleClickingAnArrowOpensItsHandOff() throws {
        let c = controller()
        var opened: (URL, Int?)?
        c.openFile = { opened = ($0, $1) }
        let mid = try #require(c.curves["flow:pcm"]).mid
        c.camera = MindControl.PanZoomCamera(center: mid, zoom: 1.5)
        c.doubleClick(at: c.camera.toScreen(mid, viewSize: c.viewSize))
        #expect(opened?.0.path.hasSuffix("app/Sources/Audio/AudioCapture.swift") == true)
        #expect(opened?.1 == 4)
    }

    @Test func nothingOutsideTheProjectIsOpened() throws {
        let c = controller()
        var opened: [URL] = []
        c.openFile = { url, _ in opened.append(url) }
        c.openSource("../../bin/x")
        c.openSource("/etc/hosts")
        c.open(MindControl.SourceLocation(file: "app/../../x.swift", line: 3))
        #expect(opened.isEmpty)
        c.openSource("app/./Sources/../Sources/Audio/AudioCapture.swift")
        #expect(opened.map(\.path) == ["/tmp/mc-ctl/app/Sources/Audio/AudioCapture.swift"])
    }

    @Test func aSymlinkOutOfTheProjectIsNotOpened() throws {
        let project = try TempProject()
        try project.write("app/Real.swift", "let x = 1\n")
        try FileManager.default.createSymbolicLink(atPath: project.url.appendingPathComponent("app/Link.swift").path,
                                                   withDestinationPath: "/etc/hosts")
        let c = controller(root: project.url)
        var opened: [URL] = []
        c.openFile = { url, _ in opened.append(url) }
        c.openSource("app/Link.swift")
        #expect(opened.isEmpty)
        c.openSource("app/Real.swift")
        #expect(opened.map(\.lastPathComponent) == ["Real.swift"])
    }

    @Test func clickingAHealthIssueGoesToItsSubject() {
        let c = controller()
        c.mode = .health
        c.goToIssue(.init(kind: .staleAnchor, subject: "audio.gate", message: "SpeechGate: type missing"))
        #expect(c.selection == .box("audio.gate"))
        c.goToIssue(.init(kind: .staleVia, subject: "pcm", message: "pcm: sendAudio missing"))
        #expect(c.selection == .arrow("flow:pcm"))
    }

    @Test func reloadKeepsFocusAndDropsVanishedSelection() {
        let c = controller()
        c.enterFocus(.system("audio"))
        c.click(at: .zero)
        c.show(loaded(generation: 2), root: URL(fileURLWithPath: "/tmp/mc-ctl"))
        #expect(c.focus == .system("audio"))
        #expect(c.layout.fixedLevel)
    }

    // MARK: Beyond the brief

    /// Ids are unique only within their own list: here a flow, a system and a feature share names.
    private static let clashJSON = """
    {
      "version": 1,
      "systems": [
        { "id": "src", "name": "Source", "paths": ["src/**"] },
        { "id": "relay", "name": "Relay", "paths": ["relay/**"] },
        { "id": "dst", "name": "Sink", "paths": ["dst/**"] }
      ],
      "flows": [
        { "id": "relay", "from": "src", "to": "dst", "kind": "data", "carries": "bytes" },
        { "id": "dup", "from": "src", "to": "relay", "kind": "data", "carries": "more", "via": "push" },
        { "id": "lost", "from": "src", "to": "missing", "kind": "data", "carries": "nothing", "via": "push" }
      ],
      "features": [
        { "id": "dup", "name": "Dup", "route": ["dup", "nope"] },
        { "id": "ghost", "name": "Ghost", "route": ["nope"] }
      ]
    }
    """

    private func loaded(_ map: MindControl.FlowMap, files: [String: String] = [:], generation: Int = 1) -> MindControl.Model.Loaded {
        let snapshot = MindControl.FlowSnapshot(root: URL(fileURLWithPath: "/tmp/mc-ctl"), flowData: nil, layoutData: nil,
                                                sourceFiles: files.keys.sorted(), read: { files[$0] })
        return .init(map: map, report: MindControl.FlowCheck.run(map: map, snapshot: snapshot), saved: [:], generation: generation)
    }

    private func controller(showing map: MindControl.FlowMap) -> MapController {
        let controller = MapController()
        controller.viewSize = CGSize(width: 1200, height: 800)
        controller.show(loaded(map), root: URL(fileURLWithPath: "/tmp/mc-ctl"))
        return controller
    }

    @Test func anIssueAboutAFlowGoesToTheFlowEvenWhenASystemSharesItsID() {
        let c = controller(showing: FlowFixtures.map(Self.clashJSON))
        #expect(c.report.issues.contains { $0.kind == .unverified && $0.subject == "relay" })
        c.goToIssue(.init(kind: .unverified, subject: "relay", message: ""))
        #expect(c.selection == .arrow("flow:relay"))
        c.goToIssue(.init(kind: .density, subject: "relay", message: ""))
        #expect(c.selection == .box("relay"))
    }

    @Test func anUnknownReferenceGoesToTheFeatureUnlessItsFlowIsTheBrokenOne() {
        let c = controller(showing: FlowFixtures.map(Self.clashJSON))
        // Flow `dup` is fine; feature `dup` names an unknown flow.
        c.goToIssue(.init(kind: .unknownReference, subject: "dup", message: ""))
        #expect(c.selectedFeature == "dup")
        #expect(c.selection == nil)
        // Flow `lost` is broken and not drawn: go to the end that exists.
        c.goToIssue(.init(kind: .unknownReference, subject: "lost", message: ""))
        #expect(c.selection == .box("src"))
    }

    @Test func aPathTieOpensTheFileAndMapDensityFitsTheMap() {
        let c = controller()
        var opened: URL?
        c.openFile = { url, _ in opened = url }
        c.goToIssue(.init(kind: .pathTie, subject: "app/Sources/Tie.swift", message: ""))
        #expect(opened?.path.hasSuffix("/tmp/mc-ctl/app/Sources/Tie.swift") == true)
        c.pan(by: CGSize(width: 300, height: 120))
        c.goToIssue(.init(kind: .density, subject: "map", message: ""))
        #expect(c.camera == MindControl.PanZoomCamera.fitting(c.baseLayout.bounds, in: c.viewSize))
    }

    @Test func goingToAnIssueLeavesFocus() {
        let c = controller()
        c.enterFocus(.system("agent"))
        c.goToIssue(.init(kind: .staleAnchor, subject: "audio.gate", message: ""))
        #expect(c.focus == nil)
        #expect(c.layout == c.baseLayout)
        #expect(c.selection == .box("audio.gate"))
    }

    @Test func aStepOutsideTheFocusLeavesFocusForTheMap() {
        let c = controller()
        c.enterFocus(.system("ble"))
        c.goToStep("send")
        #expect(c.focus == nil)
        #expect(c.selection == .arrow("flow:send"))
        c.enterFocus(.feature("speech"))
        c.goToStep("pcm")
        #expect(c.focus == .feature("speech"))
        #expect(c.selection == .arrow("flow:pcm"))
    }

    // MARK: Fix round 1

    @Test func walkingAFeaturesStepsKeepsTheStepList() {
        let c = controller()
        c.selectFeature("speech")
        c.goToStep("pcm")
        if case .feature = c.sidePanel {} else { Issue.record("\(c.sidePanel)") }
        #expect(c.selection == nil)
        #expect(c.style.selected == "flow:pcm")
        c.goToStep("send")
        if case .feature = c.sidePanel {} else { Issue.record("\(c.sidePanel)") }
        #expect(c.style.selected == "flow:send")
        // A click elsewhere is a real selection again.
        c.click(at: .zero)
        #expect(c.style.selected == nil)
    }

    @Test func aStepOffTheFeaturesRouteIsSelected() {
        let c = controller(showing: FlowFixtures.map(Self.clashJSON))
        c.selectFeature("dup")
        c.goToStep("relay")
        #expect(c.selection == .arrow("flow:relay"))
    }

    @Test func goingToAStepZoomsPastThePartCrossFade() {
        let c = controller()
        c.camera = MindControl.PanZoomCamera(center: .zero, zoom: 0.5)
        c.goToStep("pcm")
        #expect(c.camera.zoom >= MindControl.ZoomLevels.systemsToParts.upperBound)
    }

    @Test func anotherProjectNeverAnswersFromTheOldIndex() async {
        let c = controller()
        await c.searchSettled()
        c.show(loaded(FlowFixtures.map(Self.clashJSON)), root: URL(fileURLWithPath: "/tmp/mc-other"))
        #expect(c.results.isEmpty)
        c.query = "speech"
        c.flushSearch()
        #expect(c.results.isEmpty)
        c.query = "relay"
        await c.searchSettled()
        #expect(c.results.first?.target == .system("relay"))
    }

    @Test func aResultMissingFromTheMapIsIgnored() {
        let c = controller(showing: FlowFixtures.map(Self.clashJSON))
        c.navigate(to: MindControl.SearchResult(kind: .feature, title: "Speech", detail: "", target: .feature("speech")))
        #expect(c.selectedFeature == nil)
        c.navigate(to: MindControl.SearchResult(kind: .system, title: "Audio", detail: "", target: .system("audio")))
        c.navigate(to: MindControl.SearchResult(kind: .part, title: "Gate", detail: "", target: .part("audio.gate")))
        c.navigate(to: MindControl.SearchResult(kind: .file, title: "A.swift", detail: "", target: .file(path: "a/A.swift", system: "audio")))
        #expect(c.selection == nil)
        #expect(c.mode == .map)
    }

    @Test func grabbingAPartOrAnInnerArrowDragsItsSystem() throws {
        let c = controller()
        let gate = try #require(c.baseLayout.box("audio.gate")).rect
        c.camera = MindControl.PanZoomCamera(center: CGPoint(x: gate.midX, y: gate.midY), zoom: 1.5)
        #expect(c.dragTarget(at: c.camera.toScreen(CGPoint(x: gate.midX, y: gate.midY), viewSize: c.viewSize)) == "audio")
        let check = try #require(c.curves["flow:check"]).mid
        #expect(c.hit(at: c.camera.toScreen(check, viewSize: c.viewSize)) == .arrow("flow:check"))
        #expect(c.dragTarget(at: c.camera.toScreen(check, viewSize: c.viewSize)) == "audio")
        let pcm = try #require(c.curves["flow:pcm"]).mid
        #expect(c.dragTarget(at: c.camera.toScreen(pcm, viewSize: c.viewSize)) == nil)
        // Clicks keep their own targets.
        c.click(at: c.camera.toScreen(CGPoint(x: gate.midX, y: gate.midY), viewSize: c.viewSize))
        #expect(c.selection == .box("audio.gate"))
    }

    @Test func draggingAPartInTheViewMovesItsSystemAndSavesIt() throws {
        let project = try TempProject()
        let c = controller(root: project.url)
        let view = MindControl.FlowMTKView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), device: nil)
        view.controller = c
        let gate = try #require(c.baseLayout.box("audio.gate")).rect
        let before = try #require(c.baseLayout.box("audio")).rect
        c.camera = MindControl.PanZoomCamera(center: CGPoint(x: gate.midX, y: gate.midY), zoom: 1.5)
        // The view's centre is the gate's centre; window coordinates have a bottom-left origin.
        func event(_ type: NSEvent.EventType, x: CGFloat) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 400), modifierFlags: [], timestamp: 0,
                                            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, x: 600))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 660))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 690))
        view.mouseUp(with: try event(.leftMouseUp, x: 690))
        let after = try #require(c.baseLayout.box("audio")).rect
        #expect(abs(after.minX - (before.minX + 90 / 1.5)) < 1e-6)
        let data = try Data(contentsOf: project.url.appendingPathComponent(".mindcontrol/layout.json"))
        #expect(MindControl.LayoutStore.decode(data)["audio"] == after.origin)
    }

    @Test func goingToAHiddenControlStepShowsControlArrows() {
        let c = controller()
        c.showControl = false
        c.goToStep("press")
        #expect(c.showControl)
        #expect(c.selection == .arrow("flow:press"))
    }

    @Test func searchWaitsForTypingToPauseAndRunsOnce() async {
        let c = controller()
        c.searchDelay = 30_000_000
        c.query = "a"
        c.query = "au"
        c.query = "aud"
        // Not searched on the keystroke.
        #expect(c.results.isEmpty)
        await c.searchSettled()
        #expect(c.results == MindControl.FlowSearch(map: c.map!, report: c.report).search("aud"))
        #expect(c.results.first?.target == .system("audio"))
        c.query = ""
        #expect(c.results.isEmpty)
    }

    @Test func flushingSearchesNowOnceTheIndexIsBuilt() async {
        let c = controller()
        await c.searchSettled()
        c.query = "ble"
        c.flushSearch()
        #expect(c.results.first?.target == .system("ble"))
    }

    @Test func aReloadReRunsTheQueryAgainstTheNewMap() async {
        let c = controller()
        c.query = "keeper"
        await c.searchSettled()
        #expect(c.results.isEmpty)
        let renamed = FlowFixtures.map(FlowFixtures.arcaJSON.replacingOccurrences(of: "\"name\": \"SpeechGate\"", with: "\"name\": \"Keeper\""))
        c.show(loaded(renamed, files: FlowFixtures.arcaSources, generation: 2), root: URL(fileURLWithPath: "/tmp/mc-ctl"))
        await c.searchSettled()
        #expect(c.results.first?.target == .part("audio.gate"))
    }

    @Test func userInputStopsACameraAnimation() throws {
        let renderer = try MindControl.Renderer()
        let c = controller()
        c.attach(renderer)
        let start = c.camera
        let viewCentre = CGPoint(x: 600, y: 400)
        for input in [{ c.pan(by: CGSize(width: 40, height: 0)) }, { c.zoom(by: 1.2, about: viewCentre) },
                      { c.drag(system: "audio", byScreen: CGSize(width: 10, height: 0)) }] {
            c.camera = start
            c.navigate(to: MindControl.SearchResult(kind: .system, title: "Agent", detail: "", target: .system("agent")))
            #expect(renderer.isAnimatingCamera)
            input()
            #expect(!renderer.isAnimatingCamera)
            let after = c.camera
            renderer.advanceCamera(to: CACurrentMediaTime() + 10)
            #expect(c.camera == after)
        }
    }

    @Test func idleFramesLeaveTheSceneAlone() throws {
        let renderer = try MindControl.Renderer()
        let c = controller()
        c.attach(renderer)
        let now = CACurrentMediaTime()
        let built = c.sceneVersion
        c.tick(now)
        c.tick(now + 0.016)
        #expect(c.sceneVersion == built)

        c.enterFocus(.system("audio"))
        c.tick(now + 0.1)
        #expect(c.sceneVersion > built)
        #expect(c.layout != c.baseLayout && !c.layout.boxes.isEmpty)
        c.tick(now + 5)
        #expect(c.layout == MindControl.FocusLayout.system("audio", map: FlowFixtures.arca, broken: c.report.brokenFlows))
        let settled = c.sceneVersion
        c.tick(now + 5.016)
        c.tick(now + 5.032)
        #expect(c.sceneVersion == settled)
    }

    /// The edge nearest `p`: which side of `rect` an arrow end sits on.
    private func side(of p: CGPoint, on rect: CGRect) -> String {
        let distances = [("left", abs(p.x - rect.minX)), ("right", abs(p.x - rect.maxX)),
                         ("top", abs(p.y - rect.minY)), ("bottom", abs(p.y - rect.maxY))]
        return distances.min { $0.1 < $1.1 }?.0 ?? ""
    }

    /// Ticks a transition through in 20 steps and returns each arrow's side pairs, frame by frame.
    private func sidesThroughTransition(_ c: MapController, start: CFTimeInterval) -> [String: [String]] {
        var sides: [String: [String]] = [:]
        for step in 1...20 {
            c.tick(start + MapController.transitionDuration * Double(step) / 20)
            for arrow in c.layout.arrows {
                guard let curve = c.curves[arrow.id], let from = c.layout.box(arrow.from)?.rect,
                      let to = c.layout.box(arrow.to)?.rect else { continue }
                sides[arrow.id, default: []].append(side(of: curve.p0, on: from) + ">" + side(of: curve.p3, on: to))
            }
        }
        return sides
    }

    @Test func arrowsKeepTheirSidesThroughFocusTransitions() throws {
        // Sides are chosen once, for where the boxes end up; only the ends follow the sliding boxes.
        let renderer = try MindControl.Renderer()
        let c = controller()
        c.attach(renderer)
        for (name, enter) in [("feature", MapController.Focus.feature("speech")), ("system", .system("audio"))] {
            c.enterFocus(enter)
            let into = sidesThroughTransition(c, start: CACurrentMediaTime())
            #expect(c.curves == MindControl.ArrowRouter.curves(for: c.layout), "main → \(name) ends on the usual routing")
            c.exitFocus()
            let back = sidesThroughTransition(c, start: CACurrentMediaTime())
            #expect(c.layout == c.baseLayout)
            #expect(c.curves == MindControl.ArrowRouter.curves(for: c.baseLayout), "\(name) → main ends on the usual routing")
            for (id, pairs) in into { #expect(Set(pairs).count == 1, "main → \(name): \(id) goes \(pairs)") }
            for (id, pairs) in back { #expect(Set(pairs).count == 1, "\(name) → main: \(id) goes \(pairs)") }
        }
    }

    @Test func labelsArePlannedOnlyWhenSomethingMoved() {
        let c = controller()
        let first = c.labels()
        let planned = c.labelPlans
        #expect(c.labels() == first)
        #expect(c.labelPlans == planned)
        c.pan(by: CGSize(width: 10, height: 0))
        _ = c.labels()
        #expect(c.labelPlans == planned + 1)
    }

    @Test func anEmptyMapNeverMovesTheCameraToNaN() {
        let c = controller(showing: MindControl.FlowMap(zones: [], systems: [], flows: [], features: []))
        c.fit(animated: false)
        c.fit(animated: true)
        #expect(c.camera.center.x.isFinite && c.camera.center.y.isFinite && c.camera.zoom.isFinite)
        let before = c.camera
        c.enterFocus(.system("nothing"))
        c.enterFocus(.feature("nothing"))
        #expect(c.focus == nil)
        #expect(c.camera == before)
    }

    @Test func focusingAFeatureWithNothingToDrawDoesNothing() {
        let c = controller(showing: FlowFixtures.map(Self.clashJSON))
        c.selectFeature("ghost")
        let before = c.camera
        c.enterFocus()
        #expect(c.focus == nil)
        #expect(c.focusTarget == nil)
        #expect(c.layout == c.baseLayout)
        #expect(c.camera == before)
    }

    @Test func aRootWithATrailingSlashIsTheSameProject() {
        let c = controller()
        c.pan(by: CGSize(width: 200, height: 0))
        let panned = c.camera
        c.show(loaded(), root: URL(fileURLWithPath: "/tmp/mc-ctl/", isDirectory: true))
        #expect(c.camera == panned)
    }

    @Test func anotherProjectStartsClean() {
        let c = controller()
        c.navigate(to: MindControl.SearchResult(kind: .part, title: "SpeechGate", detail: "", target: .part("audio.gate")))
        c.selectFeature("speech")
        c.enterFocus(.system("audio"))
        #expect(c.focus != nil)
        c.show(loaded(), root: URL(fileURLWithPath: "/tmp/mc-other"))
        #expect(c.focus == nil)
        #expect(c.selection == nil)
        #expect(c.selectedFeature == nil)
        #expect(c.layout == c.baseLayout)
    }

    @Test func aReloadDropsASelectionThatVanished() {
        let c = controller()
        c.navigate(to: MindControl.SearchResult(kind: .part, title: "SpeechGate", detail: "", target: .part("audio.gate")))
        #expect(c.selection == .box("audio.gate"))
        let renamed = FlowFixtures.map(FlowFixtures.arcaJSON.replacingOccurrences(of: "\"id\": \"gate\"", with: "\"id\": \"keeper\""))
        c.show(loaded(renamed, files: FlowFixtures.arcaSources, generation: 2), root: URL(fileURLWithPath: "/tmp/mc-ctl"))
        #expect(c.selection == nil)
    }

    @Test func choosingAFeatureShowsItsStepsOverASelectedBox() {
        let c = controller()
        c.navigate(to: MindControl.SearchResult(kind: .system, title: "Audio", detail: "", target: .system("audio")))
        c.selectFeature("speech")
        if case .feature = c.sidePanel {} else { Issue.record("\(c.sidePanel)") }
    }

    @Test func fTargetsTheSelectedSystemThenTheFeature() {
        let c = controller()
        #expect(c.focusTarget == nil)
        c.selectFeature("speech")
        #expect(c.focusTarget == .feature("speech"))
        c.click(at: c.camera.toScreen(CGPoint(x: c.baseLayout.box("tap")!.rect.midX, y: c.baseLayout.box("tap")!.rect.midY), viewSize: c.viewSize))
        #expect(c.selection == .box("tap"))
        #expect(c.focusTarget == .system("tap"))
    }
    @Test func enterInTheSearchFieldSearchesNowBeforeGoingToTheFirstResult() async {
        let c = controller()
        await c.searchSettled()
        // A pause long enough that only a flush could have searched by the time Enter is handled.
        c.searchDelay = 60_000_000_000
        c.query = "ble"
        #expect(c.results.isEmpty)
        c.submitSearch()
        #expect(c.selection == .box("ble"))
        #expect(c.query.isEmpty)
    }

    @Test func theFocusTargetIsWorkedOutOnChangeNotOnEveryRead() {
        let c = controller()
        c.selectFeature("speech")
        let checks = c.focusTargetChecks
        for _ in 0..<5 { #expect(c.focusTarget == .feature("speech")) }
        #expect(c.focusTargetChecks == checks)
        c.selectFeature("speech")
        #expect(c.focusTarget == nil)
        #expect(c.focusTargetChecks > checks)
    }

    @Test func aReloadThatDropsTheFeatureClearsTheFocusTarget() {
        let c = controller()
        c.selectFeature("speech")
        let trimmed = FlowFixtures.map(FlowFixtures.arcaJSON.replacingOccurrences(of: "\"id\": \"speech\"", with: "\"id\": \"talk\""))
        c.show(loaded(trimmed, files: FlowFixtures.arcaSources, generation: 2), root: URL(fileURLWithPath: "/tmp/mc-ctl"))
        #expect(c.selectedFeature == nil)
        #expect(c.focusTarget == nil)
    }

    /// Keys the map doesn't use (Tab, arrows, anything with ⌘) go up the responder chain, so Tab can move to the
    /// search field and menu shortcuts still work.
    @Test func theMapPassesOnKeysItDoesNotUse() throws {
        final class Recorder: NSResponder {
            var keys: [UInt16] = []
            override func keyDown(with event: NSEvent) { keys.append(event.keyCode) }
        }
        let c = controller()
        let view = MindControl.FlowMTKView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800), device: nil)
        view.controller = c
        let recorder = Recorder()
        view.nextResponder = recorder
        func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                          context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                          isARepeat: false, keyCode: code))
        }
        view.keyDown(with: try key("\t", code: 48))
        view.keyDown(with: try key(String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!), code: 124))
        view.keyDown(with: try key("k", code: 40, modifiers: .command))
        #expect(recorder.keys == [48, 124, 40])
        // Letters still start a search and stay with the map.
        view.keyDown(with: try key("a", code: 0))
        #expect(c.query == "a")
        #expect(recorder.keys == [48, 124, 40])
    }
    /// The health indicator and the unmapped badge open the issue list even when a box or step is selected.
    @Test func showingHealthOpensTheIssueListOverASelection() {
        let c = controller()
        c.navigate(to: MindControl.SearchResult(kind: .system, title: "Audio", detail: "", target: .system("audio")))
        #expect(c.selection == .box("audio"))
        c.showHealth()
        #expect(c.mode == .health)
        #expect(c.selection == nil)
        #expect(c.sidePanel == .health(c.report))
        // A step highlighted from the feature's list is cleared too.
        c.mode = .map
        c.selectFeature("speech")
        c.goToStep("pcm")
        c.showHealth()
        #expect(c.style.selected == nil)
        #expect(c.sidePanel == .health(c.report))
    }
}
#endif
