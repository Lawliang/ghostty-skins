#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias FocusLayout = MindControl.FocusLayout

struct FocusLayoutTests {
    @Test func systemFocusPutsSendersLeftAndReceiversRight() throws {
        let layout = try #require(FocusLayout.system("audio", map: FlowFixtures.arca, broken: []))
        #expect(layout.fixedLevel)
        let audio = try #require(layout.box("audio")).rect
        #expect(try #require(layout.box("tap")).rect.maxX < audio.minX)
        #expect(try #require(layout.box("agent")).rect.minX > audio.maxX)
        #expect(layout.box("audio.capture") != nil && layout.box("audio.gate") != nil)
        #expect(layout.box("openai") == nil)
        #expect(layout.box("ble") == nil)
        #expect(Set(layout.arrows.map(\.id)) == ["flow:begin", "flow:pcm", "flow:check", "flow:commit", "flow:discard"])
    }

    @Test func systemFocusOnUnknownSystemIsNil() {
        #expect(FocusLayout.system("nope", map: FlowFixtures.arca, broken: []) == nil)
    }

    @Test func featureFocusFollowsStepOrderLeftToRight() throws {
        let layout = try #require(FocusLayout.feature("speech", map: FlowFixtures.arca, broken: []))
        #expect(layout.fixedLevel)
        let order = ["ring", "ble", "tap", "audio", "agent", "openai"]
        let xs = try order.map { try #require(layout.box($0)).rect.minX }
        #expect(xs == xs.sorted())
        #expect(Set(layout.boxes.map(\.id)) == Set(order))
    }

    @Test func conditionalStepsSplitIntoLanes() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "yes", "name": "Yes" }, { "id": "no", "name": "No" } ],
          "flows": [ { "id": "y", "from": "a", "to": "yes", "kind": "control", "carries": "x", "when": "words heard" },
                     { "id": "n", "from": "a", "to": "no", "kind": "control", "carries": "x", "when": "nothing heard" } ],
          "features": [ { "id": "f", "name": "F", "route": ["y", "n"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        let a = try #require(layout.box("a")).rect, yes = try #require(layout.box("yes")).rect, no = try #require(layout.box("no")).rect
        #expect(yes.maxY < a.midY)
        #expect(no.minY > a.midY)
        #expect(yes.minX == no.minX)
    }

    // MARK: - Edge cases

    @Test func twoWayNeighboursSitWithSenders() throws {
        // The agent both sends to and receives from OpenAI.
        let layout = try #require(FocusLayout.system("openai", map: FlowFixtures.arca, broken: []))
        let openai = try #require(layout.box("openai")).rect
        #expect(try #require(layout.box("agent")).rect.maxX < openai.minX)
        #expect(layout.boxes.filter { $0.id == "agent" }.count == 1)
        #expect(Set(layout.arrows.map(\.id)) == ["flow:send", "flow:reply"])
    }

    @Test func systemWithNoNeighboursShowsOnlyItselfAndItsParts() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "solo", "name": "Solo", "parts": [ { "id": "p", "name": "P" }, { "id": "q", "name": "Q" } ] },
                       { "id": "other", "name": "Other" } ],
          "flows": [ { "id": "pq", "from": "solo.p", "to": "solo.q", "kind": "data", "carries": "x" } ] }
        """#)
        let layout = try #require(FocusLayout.system("solo", map: map, broken: []))
        #expect(layout.fixedLevel)
        #expect(Set(layout.boxes.map(\.id)) == ["solo", "solo.p", "solo.q"])
        #expect(layout.arrows.map(\.id) == ["flow:pq"])
    }

    @Test func brokenFlowsLeaveSystemFocus() throws {
        let layout = try #require(FocusLayout.system("audio", map: FlowFixtures.arca, broken: ["begin"]))
        #expect(layout.box("tap") == nil)
        #expect(!layout.arrows.contains { $0.id == "flow:begin" })
    }

    @Test func systemFocusCentresOnlyKnownNeighbours() throws {
        // `ghost` isn't a system. Even when no health report marks its flow broken, it must not take a slot.
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "b", "name": "B" } ],
          "flows": [ { "id": "g", "from": "ghost", "to": "a", "kind": "data", "carries": "x" },
                     { "id": "x", "from": "b", "to": "a", "kind": "data", "carries": "x" } ] }
        """#)
        let layout = try #require(FocusLayout.system("a", map: map, broken: []))
        #expect(Set(layout.boxes.map(\.id)) == ["a", "b"])
        #expect(try #require(layout.box("b")).rect.midY == (try #require(layout.box("a")).rect.midY))
        #expect(layout.arrows.map(\.id) == ["flow:x"])
    }

    @Test func featureFocusSkipsUnknownAndBrokenSteps() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "b", "name": "B" }, { "id": "c", "name": "C" } ],
          "flows": [ { "id": "ab", "from": "a", "to": "b", "kind": "data", "carries": "x" },
                     { "id": "bc", "from": "b", "to": "c", "kind": "data", "carries": "x" } ],
          "features": [ { "id": "f", "name": "F", "route": ["ab", "nope", "bc"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: ["bc"]))
        #expect(Set(layout.boxes.map(\.id)) == ["a", "b"])
        #expect(layout.arrows.map(\.id) == ["flow:ab"])
        #expect(FocusLayout.feature("nope", map: map, broken: []) == nil)
    }

    @Test func featureFocusLeavesNoGapForUnknownSystems() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "b", "name": "B" } ],
          "flows": [ { "id": "g", "from": "a", "to": "ghost", "kind": "data", "carries": "x" },
                     { "id": "ab", "from": "a", "to": "b", "kind": "data", "carries": "x" } ],
          "features": [ { "id": "f", "name": "F", "route": ["g", "ab"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        #expect(Set(layout.boxes.map(\.id)) == ["a", "b"])
        #expect(layout.arrows.map(\.id) == ["flow:ab"])
        let a = try #require(layout.box("a")).rect, b = try #require(layout.box("b")).rect
        #expect(b.minX - a.maxX == FocusLayout.featureGap)
    }

    @Test func conditionalSelfFlowKeepsItsSystemOnTheMainLine() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A", "parts": [ { "id": "p", "name": "P" }, { "id": "q", "name": "Q" } ] },
                       { "id": "b", "name": "B" } ],
          "flows": [ { "id": "s", "from": "a.p", "to": "a.q", "kind": "data", "carries": "x", "when": "ready" },
                     { "id": "t", "from": "a.q", "to": "b", "kind": "data", "carries": "x" } ],
          "features": [ { "id": "f", "name": "F", "route": ["s", "t"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        let a = try #require(layout.box("a")).rect, b = try #require(layout.box("b")).rect
        #expect(a.midY == b.midY)
        #expect(a.maxX < b.minX)
        #expect(layout.arrows.map(\.id) == ["flow:t"])
    }

    @Test func stepsSharingAConditionContinueInTheirLane() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "yes", "name": "Yes" }, { "id": "no", "name": "No" },
                       { "id": "more", "name": "More" } ],
          "flows": [ { "id": "y", "from": "a", "to": "yes", "kind": "control", "carries": "x", "when": "words heard" },
                     { "id": "n", "from": "a", "to": "no", "kind": "control", "carries": "x", "when": "nothing heard" },
                     { "id": "m", "from": "yes", "to": "more", "kind": "data", "carries": "x", "when": "words heard" } ],
          "features": [ { "id": "f", "name": "F", "route": ["y", "n", "m"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        let yes = try #require(layout.box("yes")).rect, more = try #require(layout.box("more")).rect
        #expect(more.midY == yes.midY)
        #expect(more.minX > yes.maxX)
        #expect(!overlaps(layout))
    }

    @Test func aConditionalStepInsideItsOwnLaneStaysUnbent() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "yes", "name": "Yes" }, { "id": "no", "name": "No" },
                       { "id": "more", "name": "More" } ],
          "flows": [ { "id": "y", "from": "a", "to": "yes", "kind": "control", "carries": "x", "when": "words heard" },
                     { "id": "n", "from": "a", "to": "no", "kind": "control", "carries": "x", "when": "nothing heard" },
                     { "id": "m", "from": "yes", "to": "more", "kind": "data", "carries": "x", "when": "words heard" } ],
          "features": [ { "id": "f", "name": "F", "route": ["y", "n", "m"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        let m = try #require(layout.arrows.first { $0.id == "flow:m" })
        #expect(m.bend == 0)
        // `yes` and `more` both sit in the "words heard" lane; the arrow stays in that row's band.
        let row = try #require(layout.box("yes")).rect
        let curve = try #require(MindControl.ArrowRouter.curves(for: layout)["flow:m"])
        #expect((0...100).allSatisfy { (row.minY...row.maxY).contains(curve.point(at: CGFloat($0) / 100).y) })
    }

    @Test func anUnconditionalStepInsideALaneStaysUnbent() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "yes", "name": "Yes" }, { "id": "also", "name": "Also" } ],
          "flows": [ { "id": "y", "from": "a", "to": "yes", "kind": "control", "carries": "x", "when": "words heard" },
                     { "id": "z", "from": "a", "to": "also", "kind": "control", "carries": "x", "when": "words heard" },
                     { "id": "u", "from": "yes", "to": "also", "kind": "data", "carries": "x" } ],
          "features": [ { "id": "f", "name": "F", "route": ["y", "z", "u"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        #expect(try #require(layout.box("yes")).rect.minY == (try #require(layout.box("also")).rect.minY))
        #expect(layout.arrows.first { $0.id == "flow:u" }?.bend == 0)
    }

    @Test func aStepFromOneLaneToAnotherMovesRight() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "yes", "name": "Yes" }, { "id": "no", "name": "No" } ],
          "flows": [ { "id": "y", "from": "a", "to": "yes", "kind": "control", "carries": "x", "when": "words heard" },
                     { "id": "n", "from": "yes", "to": "no", "kind": "control", "carries": "x", "when": "nothing heard" } ],
          "features": [ { "id": "f", "name": "F", "route": ["y", "n"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        let a = try #require(layout.box("a")).rect, yes = try #require(layout.box("yes")).rect, no = try #require(layout.box("no")).rect
        #expect(no.minX > yes.maxX)
        #expect(yes.maxY < a.midY)
        #expect(no.minY > a.midY)
    }

    @Test func conditionalStepsToAPlacedSystemBendIntoTheirLanes() throws {
        // In `speech`, `commit` and `discard` both run audio → agent, which `pcm` already placed.
        let layout = try #require(FocusLayout.feature("speech", map: FlowFixtures.arca, broken: []))
        let curves = MindControl.ArrowRouter.curves(for: layout)
        let pcm = try #require(curves["flow:pcm"]), commit = try #require(curves["flow:commit"])
        let discard = try #require(curves["flow:discard"])
        #expect(commit.mid.y < pcm.mid.y)
        #expect(discard.mid.y > pcm.mid.y)
        let lane = FocusLayout.featureBoxSize.height + FocusLayout.laneGap
        let bends = Dictionary(uniqueKeysWithValues: layout.arrows.map { ($0.id, $0.bend) })
        #expect(bends["flow:commit"] == -lane)
        #expect(bends["flow:discard"] == lane)
        #expect(bends["flow:pcm"] == 0)
    }

    @Test func conditionalArrowsIntoALaneStayUnbent() throws {
        // The targets already sit in their lanes, so a bend would only curl the arrows back over `a`.
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "yes", "name": "Yes" }, { "id": "no", "name": "No" } ],
          "flows": [ { "id": "y", "from": "a", "to": "yes", "kind": "control", "carries": "x", "when": "words heard" },
                     { "id": "n", "from": "a", "to": "no", "kind": "control", "carries": "x", "when": "nothing heard" } ],
          "features": [ { "id": "f", "name": "F", "route": ["y", "n"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        #expect(layout.arrows.map(\.id) == ["flow:y", "flow:n"])
        #expect(layout.arrows.map(\.bend) == [0, 0])
        let a = try #require(layout.box("a")).rect.insetBy(dx: 0.5, dy: 0.5)
        let curves = MindControl.ArrowRouter.curves(for: layout)
        for id in ["flow:y", "flow:n"] {
            let curve = try #require(curves[id])
            #expect(!(1...100).contains { a.contains(curve.point(at: CGFloat($0) / 100)) }, "\(id) passes over a")
        }
    }

    @Test func aRepeatedStepDrawsOneArrow() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "b", "name": "B" }, { "id": "c", "name": "C" } ],
          "flows": [ { "id": "ab", "from": "a", "to": "b", "kind": "data", "carries": "x" },
                     { "id": "bc", "from": "b", "to": "c", "kind": "data", "carries": "x" } ],
          "features": [ { "id": "f", "name": "F", "route": ["ab", "bc", "ab"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        #expect(layout.arrows.map(\.id) == ["flow:ab", "flow:bc"])
        #expect(Set(layout.boxes.map(\.id)) == ["a", "b", "c"])
    }

    @Test func aFeatureWithNothingToDrawHasNoFocus() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "b", "name": "B" } ],
          "flows": [ { "id": "ab", "from": "a", "to": "b", "kind": "data", "carries": "x" },
                     { "id": "g", "from": "a", "to": "ghost", "kind": "data", "carries": "x" } ],
          "features": [ { "id": "broken", "name": "Broken", "route": ["nope", "ab"] },
                        { "id": "ghostly", "name": "Ghostly", "route": ["g"] },
                        { "id": "empty", "name": "Empty", "route": [] } ] }
        """#)
        #expect(FocusLayout.feature("broken", map: map, broken: ["ab"]) == nil)
        #expect(FocusLayout.feature("ghostly", map: map, broken: []) == nil)
        #expect(FocusLayout.feature("empty", map: map, broken: []) == nil)
    }

    @MainActor
    @Test func featureFocusNamesFitAtTheFittedZoom() throws {
        // Six systems in a row, fitted to a 1200 pt view: each name (13 pt semibold, 14 pt in from the left with the
        // same room kept on the right, as FlowLabels places it) fits without "…", as does a typical 16-character one.
        let layout = try #require(FocusLayout.feature("speech", map: FlowFixtures.arca, broken: []))
        #expect(layout.boxes.count == 6)
        let zoom = MindControl.PanZoomCamera.fitting(layout.bounds, in: CGSize(width: 1200, height: 800)).zoom
        let measure = { (text: String) in MindControl.LabelOverlayView.measure(text, 13, true).width }
        for box in layout.boxes {
            let room = box.rect.width * zoom - 28
            #expect(room >= measure(box.title), "\(box.title) needs \(measure(box.title)) pt, has \(room)")
            #expect(room >= measure("Upload scheduler"))
        }
        // The gaps still show the arrows between the boxes.
        let row = layout.boxes.filter { $0.rect.minY == 0 }.map(\.rect).sorted { $0.minX < $1.minX }
        for (a, b) in zip(row, row.dropFirst()) { #expect((b.minX - a.maxX) * zoom >= 35) }
        #expect(!overlaps(layout))
    }

    private func overlaps(_ layout: MindControl.MapLayout) -> Bool {
        let rects = layout.boxes.map(\.rect)
        for i in rects.indices {
            for j in rects.indices where j > i && rects[i].intersects(rects[j]) { return true }
        }
        return false
    }
}
#endif
