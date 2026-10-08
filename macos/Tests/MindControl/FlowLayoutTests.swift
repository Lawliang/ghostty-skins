#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias FlowLayout = MindControl.FlowLayout
private typealias MapLayout = MindControl.MapLayout
private typealias FlowMap = MindControl.FlowMap

struct FlowLayoutTests {
    private func rect(_ layout: MapLayout, _ id: String) -> CGRect {
        layout.box(id)?.rect ?? .null
    }

    @Test func sameInputSameOutput() {
        #expect(FlowLayout.layout(map: FlowFixtures.arca, broken: []) == FlowLayout.layout(map: FlowFixtures.arca, broken: []))
    }

    @Test func zonesOrderedByDataFlowEvenWithACrossZoneCycle() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        let ring = rect(layout, "zone:ring"), phone = rect(layout, "zone:phone"), cloud = rect(layout, "zone:cloud")
        #expect(ring.maxX < phone.minX)
        #expect(phone.maxX < cloud.minX)
    }

    @Test func zonesContainTheirSystemsAndDoNotOverlap() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        let map = FlowFixtures.arca
        for system in map.systems {
            #expect(rect(layout, "zone:\(system.zone!)").contains(rect(layout, system.id)), "\(system.id)")
        }
        let zones = layout.boxes.filter { $0.kind == .zone }
        for (i, a) in zones.enumerated() { for b in zones[(i + 1)...] { #expect(!a.rect.intersects(b.rect)) } }
    }

    @Test func passThroughOutsideZoneStaysBetweenItsNeighbours() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "zones": [ { "id": "r", "name": "R" }, { "id": "x", "name": "X" }, { "id": "p", "name": "P" } ],
          "systems": [ { "id": "src", "name": "Src", "zone": "r" },
                       { "id": "relay", "name": "Relay", "zone": "x", "external": true },
                       { "id": "dst", "name": "Dst", "zone": "p" } ],
          "flows": [ { "id": "1", "from": "src", "to": "relay", "kind": "data", "carries": "x" },
                     { "id": "2", "from": "relay", "to": "dst", "kind": "data", "carries": "x" } ] }
        """#)
        let layout = FlowLayout.layout(map: map, broken: [])
        #expect(rect(layout, "zone:r").maxX < rect(layout, "zone:x").minX)
        #expect(rect(layout, "zone:x").maxX < rect(layout, "zone:p").minX)
    }

    @Test func mixedZoneInACycleFollowsDeclarationOrder() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "zones": [ { "id": "phone", "name": "Phone" }, { "id": "cloud", "name": "Cloud" } ],
          "systems": [ { "id": "app", "name": "App", "zone": "phone" },
                       { "id": "openai", "name": "OpenAI", "zone": "cloud", "external": true },
                       { "id": "worker", "name": "Worker", "zone": "cloud" } ],
          "flows": [ { "id": "send", "from": "app", "to": "openai", "kind": "data", "carries": "x" },
                     { "id": "reply", "from": "openai", "to": "app", "kind": "data", "carries": "x" } ] }
        """#)
        let layout = FlowLayout.layout(map: map, broken: [])
        #expect(rect(layout, "zone:phone").maxX < rect(layout, "zone:cloud").minX)
    }

    @Test func outsideZoneWithNoFlowsSitsLeftmost() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "zones": [ { "id": "a", "name": "A" }, { "id": "b", "name": "B" }, { "id": "e", "name": "E" } ],
          "systems": [ { "id": "one", "name": "One", "zone": "a" }, { "id": "two", "name": "Two", "zone": "b" },
                       { "id": "ext", "name": "Ext", "zone": "e", "external": true } ],
          "flows": [ { "id": "1", "from": "one", "to": "two", "kind": "data", "carries": "x" } ] }
        """#)
        let layout = FlowLayout.layout(map: map, broken: [])
        #expect(rect(layout, "zone:e").maxX < rect(layout, "zone:a").minX)
        #expect(rect(layout, "zone:a").maxX < rect(layout, "zone:b").minX)
    }

    @Test func dataSourceSitsLeftOfWhatItFeeds() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        #expect(rect(layout, "audio").maxX < rect(layout, "agent").minX)
    }

    @Test func controlFlowsDoNotMoveSystems() {
        let arca = FlowFixtures.arca
        let dataOnly = FlowMap(zones: arca.zones, systems: arca.systems, flows: arca.flows.filter { $0.kind == .data }, features: [])
        let a = FlowLayout.layout(map: arca, broken: []), b = FlowLayout.layout(map: dataOnly, broken: [])
        for system in arca.systems { #expect(rect(a, system.id) == rect(b, system.id), "\(system.id)") }
    }

    @Test func externalSenderFirstAndReceiverLast() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "s", "name": "S", "external": true }, { "id": "a", "name": "A" }, { "id": "b", "name": "B" },
                       { "id": "c", "name": "C" }, { "id": "d", "name": "D" }, { "id": "r", "name": "R", "external": true } ],
          "flows": [ { "id": "1", "from": "s", "to": "a", "kind": "data", "carries": "x" },
                     { "id": "2", "from": "a", "to": "b", "kind": "data", "carries": "x" },
                     { "id": "3", "from": "b", "to": "c", "kind": "data", "carries": "x" },
                     { "id": "4", "from": "c", "to": "d", "kind": "data", "carries": "x" },
                     { "id": "5", "from": "a", "to": "r", "kind": "data", "carries": "x" } ] }
        """#)
        let layout = FlowLayout.layout(map: map, broken: [])
        let systems = layout.boxes.filter { $0.kind == .system }
        #expect(systems.allSatisfy { $0.id == "s" || rect(layout, "s").maxX < $0.rect.minX })
        #expect(systems.allSatisfy { $0.id == "r" || $0.rect.maxX < rect(layout, "r").minX })
    }

    @Test func partsSitInsideTheirSystemInFlowOrder() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        let audio = rect(layout, "audio")
        #expect(audio.contains(rect(layout, "audio.capture")))
        #expect(audio.contains(rect(layout, "audio.gate")))
        #expect(rect(layout, "audio.capture").maxX < rect(layout, "audio.gate").minX)
        #expect(layout.box("audio")?.partCount == 2)
    }

    @Test func systemsAreSizedForTheirParts() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        #expect(rect(layout, "tap").size == MindControl.LayoutMetrics.systemMinSize)
        #expect(rect(layout, "audio").height > rect(layout, "tap").height)
    }

    @Test func savedPositionsWinAndCarryTheirParts() {
        let base = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        let moved = FlowLayout.layout(map: FlowFixtures.arca, broken: [], saved: ["audio": CGPoint(x: 5000, y: 5000)])
        #expect(rect(moved, "audio").origin == CGPoint(x: 5000, y: 5000))
        let delta = CGPoint(x: 5000 - rect(base, "audio").minX, y: 5000 - rect(base, "audio").minY)
        #expect(rect(moved, "audio.gate").origin == CGPoint(x: rect(base, "audio.gate").minX + delta.x, y: rect(base, "audio.gate").minY + delta.y))
        #expect(rect(moved, "zone:phone").contains(rect(moved, "audio")))
    }

    @Test func selfFlowAndIsolatedSystemLayOut() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "b", "name": "B" },
                       { "id": "c", "name": "C", "parts": [ { "id": "p", "name": "P" }, { "id": "q", "name": "Q" } ] } ],
          "flows": [ { "id": "1", "from": "a", "to": "a", "kind": "data", "carries": "x" },
                     { "id": "2", "from": "c.p", "to": "c.q", "kind": "data", "carries": "x" } ] }
        """#)
        let layout = FlowLayout.layout(map: map, broken: [])
        let systems = layout.boxes.filter { $0.kind == .system }
        #expect(systems.count == 3)
        for (i, a) in systems.enumerated() { for b in systems[(i + 1)...] { #expect(!a.rect.intersects(b.rect)) } }
        #expect(layout.boxes.filter { $0.kind == .zone }.isEmpty)
    }

    @Test func arrowsAtThreeLevels() throws {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        #expect(layout.arrows.filter { $0.level == .part }.count == 9)
        let merged = try #require(layout.arrows.first { $0.id == "sys:audio>agent" })
        #expect(merged.weight == 3)
        #expect(merged.kind == .data)
        #expect(merged.label == "PCM16 24 kHz +2")
        #expect(merged.conditional)
        #expect(merged.flowIDs == ["pcm", "commit", "discard"])
        #expect(Set(layout.arrows.filter { $0.level == .zone }.map(\.id)) == ["zone:ring>phone", "zone:phone>cloud", "zone:cloud>phone"])
        #expect(layout.arrows.first { $0.id == "flow:check" }?.from == "audio.capture")
    }

    @Test func brokenFlowsAreNotDrawn() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: ["pcm"])
        #expect(layout.arrows.first { $0.id == "flow:pcm" } == nil)
        #expect(layout.arrows.first { $0.id == "sys:audio>agent" }?.weight == 2)
    }
}
#endif
