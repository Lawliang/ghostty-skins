#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowFile = MindControl.FlowFile
private typealias FlowMap = MindControl.FlowMap

struct FlowFileTests {
    private func errors(_ json: String) -> [MindControl.FlowError] {
        if case .failure(let failure) = FlowFile.parse(Data(json.utf8)) { return failure.errors }
        Issue.record("Expected errors for:\n\(json)")
        return []
    }

    @Test func parsesArcaExample() throws {
        let map = FlowFixtures.arca
        #expect(map.zones.map(\.id) == ["ring", "phone", "cloud"])
        #expect(map.systems.map(\.id) == ["ring", "ble", "tap", "audio", "agent", "openai"])
        #expect(map.system("audio")?.parts.map(\.id) == ["capture", "gate"])
        #expect(map.system("ring")?.external == true)
        let commit = try #require(map.flow("commit"))
        #expect(commit.from == FlowMap.Endpoint(system: "audio", part: "capture"))
        #expect(commit.to.description == "agent.session")
        #expect(commit.kind == .control)
        #expect(commit.when == "words heard")
        #expect(map.features.first?.route.count == 9)
        #expect(map.zoneOf(system: "openai") == "cloud")
    }

    @Test func optionalListsDefaultToEmpty() throws {
        let json = #"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ] }"#
        let map = try FlowFile.parse(Data(json.utf8)).get()
        #expect(map.zones.isEmpty && map.flows.isEmpty && map.features.isEmpty)
        #expect(map.systems.first?.paths == [] && map.systems.first?.external == false)
    }

    @Test func trailingCommaReportsLine() {
        let json = "{\n  \"version\": 1,\n  \"systems\": [\n    { \"id\": \"a\", \"name\": \"A\" },\n  ]\n}\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.message.hasPrefix("Not valid JSON") == true)
        #expect((3...6).contains(found.first?.line ?? 0))
    }

    @Test func ruleErrorPointsAtTheItemsLine() {
        let json = "{\n  \"version\": 1,\n  \"systems\": [\n    { \"id\": \"ok\", \"name\": \"OK\" },\n    { \"id\": \"audio\" }\n  ]\n}\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.line == 5)
        #expect(found.first?.message.contains("\"name\"") == true)
    }

    @Test(arguments: [
        (#"{ "systems": [] }"#, "version"),
        (#"{ "version": 2, "systems": [] }"#, "version 1"),
        (#"{ "version": 1 }"#, "\"systems\""),
        (#"{ "version": 1, "systems": [ { "id": "Audio", "name": "A" } ] }"#, "a-z"),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" }, { "id": "a", "name": "B" } ] }"#, "Duplicate"),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A", "zone": "nope" } ] }"#, "unknown zone"),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A", "external": true, "paths": ["x/**"] } ] }"#, "external"),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A", "parts": [ { "id": "p" } ] } ] }"#, "\"name\""),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ], "flows": [ { "id": "f", "from": "a", "to": "a", "kind": "event", "carries": "x" } ] }"#, "\"kind\""),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ], "flows": [ { "id": "f", "from": "a.b.c", "to": "a", "kind": "data", "carries": "x" } ] }"#, "\"from\""),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ], "flows": [ { "id": "f", "from": "a", "to": "a", "kind": "data" } ] }"#, "\"carries\""),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ], "features": [ { "id": "x", "name": "X", "route": "f" } ] }"#, "\"route\""),
        (#"[1, 2]"#, "JSON object"),
    ])
    func ruleViolations(json: String, expected: String) {
        let found = errors(json)
        #expect(!found.isEmpty)
        #expect(found.contains { $0.message.contains(expected) }, "\(found) should mention \(expected)")
    }

    @Test func endpointParsing() {
        #expect(FlowMap.Endpoint("audio") == FlowMap.Endpoint(system: "audio", part: nil))
        #expect(FlowMap.Endpoint("audio.capture") == FlowMap.Endpoint(system: "audio", part: "capture"))
        #expect(FlowMap.Endpoint("audio.") == nil)
        #expect(FlowMap.Endpoint("a.b.c") == nil)
        #expect(FlowMap.Endpoint("Audio") == nil)
    }
}
#endif
