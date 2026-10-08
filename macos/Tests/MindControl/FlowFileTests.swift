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
        #expect(found.first?.line == 4)
    }

    @Test func missingCommaBetweenMembersReportsSyntaxError() {
        let json = "{\n  \"version\": 1\n  \"systems\": []\n}\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.message.hasPrefix("Not valid JSON") == true)
        #expect(found.first?.line == 3, "\(found)")
    }

    @Test func missingValueReportsSyntaxError() {
        let json = "{\n  \"version\": ,\n  \"systems\": []\n}\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.message.hasPrefix("Not valid JSON") == true)
        #expect(found.first?.line == 2, "\(found)")
    }

    @Test func commasInsideStringsAreNotTrailingCommas() throws {
        let json = "{\n  \"version\": 1,\n  \"systems\": [\n    { \"id\": \"a\", \"name\": \"x,] y,} \\\"q,]\\\" z\\\\\", \"summary\": \"ends with a slash \\\\\" }\n  ]\n}\n"
        let map = try FlowFile.parse(Data(json.utf8)).get()
        #expect(map.system("a")?.name == "x,] y,} \"q,]\" z\\")
        #expect(map.system("a")?.summary == "ends with a slash \\")
    }

    @Test func duplicateIDPointsAtTheDuplicate() {
        let json = "{\n  \"version\": 1,\n  \"systems\": [\n    { \"id\": \"a\", \"name\": \"A\" },\n    { \"id\": \"b\", \"name\": \"B\" },\n    { \"id\": \"a\", \"name\": \"A again\" }\n  ]\n}\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("Duplicate") == true)
        #expect(found.first?.line == 6)
    }

    @Test func idSharedWithAnotherListDoesNotMisleadTheLine() {
        let json = "{\n  \"version\": 1,\n  \"zones\": [\n    { \"id\": \"ring\", \"name\": \"Ring\" }\n  ],\n  \"systems\": [\n    { \"id\": \"ring\", \"name\": \"Ring\", \"zone\": \"nope\" }\n  ]\n}\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("unknown zone") == true)
        #expect(found.first?.line == 7)
    }

    @Test func partErrorPointsAtThePartInTheSecondSystem() {
        let json = "{\n  \"version\": 1,\n  \"systems\": [\n    { \"id\": \"one\", \"name\": \"One\",\n      \"parts\": [ { \"id\": \"p\", \"name\": \"P\" } ] },\n    { \"id\": \"two\", \"name\": \"Two\",\n      \"parts\": [\n        { \"id\": \"p\", \"name\": \"P\" },\n        { \"id\": \"q\" }\n      ] }\n  ]\n}\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("\"name\"") == true)
        #expect(found.first?.line == 9)
    }

    @Test func errorLinesCountCRLFFiles() {
        let json = "{\r\n  \"version\": 1,\r\n  \"systems\": [\r\n    { \"id\": \"ok\", \"name\": \"OK\" },\r\n    { \"id\": \"audio\" }\r\n  ]\r\n}\r\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.line == 5)
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
    // MARK: Unknown keys

    /// A misspelt key is ignored, not an error: the map still loads, and the key is reported with its line.
    @Test func aTopLevelTypoIsReportedWithItsLine() throws {
        let json = "{\n  \"version\": 1,\n  \"systems\": [ { \"id\": \"a\", \"name\": \"A\" } ],\n  \"flow\": []\n}\n"
        let map = try FlowFile.parse(Data(json.utf8)).get()
        #expect(map.unknownKeys == [MindControl.FlowError(line: 4, message: #"Unknown key "flow" is ignored. Did you mean "flows"?"#)])
    }

    @Test func fieldTyposAreReportedWithTheirLines() throws {
        let json = """
        {
          "version": 1,
          "zones": [ { "id": "z", "name": "Z", "colour": "red" } ],
          "systems": [
            { "id": "a", "name": "A", "zone": "z",
              "pathz": ["a/**"],
              "parts": [ { "id": "p", "name": "P",
                           "ancor": "P" } ] },
            { "id": "b", "name": "B" }
          ],
          "flows": [
            { "id": "f", "from": "a", "to": "b", "kind": "data", "carries": "x",
              "whne": "now" }
          ],
          "features": [ { "id": "g", "name": "G", "route": ["f"], "notes": "x" } ]
        }
        """
        let map = try FlowFile.parse(Data(json.utf8)).get()
        #expect(map.unknownKeys.map(\.description) == [
            #"Line 3: Unknown key "colour" in zone "z" is ignored."#,
            #"Line 6: Unknown key "pathz" in system "a" is ignored. Did you mean "paths"?"#,
            #"Line 8: Unknown key "ancor" in part "a.p" is ignored. Did you mean "anchor"?"#,
            #"Line 13: Unknown key "whne" in flow "f" is ignored. Did you mean "when"?"#,
            #"Line 15: Unknown key "notes" in feature "g" is ignored."#,
        ])
        #expect(map.flow("f")?.when == nil)
    }

    @Test func aKnownFileHasNoUnknownKeys() {
        #expect(FlowFixtures.arca.unknownKeys.isEmpty)
    }

    /// When the file is invalid anyway, a misspelling is listed too: it's often the cause.
    @Test func anInvalidFileListsItsUnknownKeysToo() {
        let found = errors(#"{ "version": 1, "systems": [ { "id": "a", "nmae": "A" } ] }"#)
        #expect(found.map(\.message) == [#"System "a" is missing "name"."#, #"Unknown key "nmae" in system "a" is ignored. Did you mean "name"?"#])
    }
}
#endif
