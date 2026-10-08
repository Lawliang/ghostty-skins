#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowCheck = MindControl.FlowCheck
private typealias HealthReport = MindControl.HealthReport

struct FlowCheckTests {
    private func snapshot(_ files: [String: String]) -> MindControl.FlowSnapshot {
        MindControl.FlowSnapshot(root: URL(fileURLWithPath: "/tmp/mc-check"), flowData: nil, layoutData: nil,
                                 sourceFiles: files.keys.sorted(), read: { files[$0] })
    }

    private func check(_ map: MindControl.FlowMap = FlowFixtures.arca, _ files: [String: String] = FlowFixtures.arcaSources) -> HealthReport {
        FlowCheck.run(map: map, snapshot: snapshot(files))
    }

    @Test func healthyArcaHasNoIssues() {
        let report = check()
        #expect(report.issues == [])
        #expect(report.unmapped == [])
        #expect(report.isHealthy)
        #expect(report.viaLocations["pcm"] == MindControl.SourceLocation(file: "app/Sources/Audio/AudioCapture.swift", line: 4))
        #expect(report.viaLocations["reply"]?.file == "app/Sources/Agent/RealtimeAgentSession.swift")
        #expect(report.owners["app/Sources/Coordination/TapCoordinator.swift"] == "tap")
        #expect(report.anchorFiles["audio.gate"] == "app/Sources/Audio/SpeechGate.swift")
        #expect(report.typeFiles["ArcaLink"] == "app/Sources/BLE/ArcaLink.swift")
    }

    @Test func renamedTypeMakesAnchorStale() {
        var files = FlowFixtures.arcaSources
        files["app/Sources/Audio/SpeechGate.swift"] = "struct Gate {}\n"
        let report = check(FlowFixtures.arca, files)
        #expect(report.staleParts == ["audio.gate"])
        #expect(report.issues.contains { $0.kind == .staleAnchor && $0.subject == "audio.gate" })
    }

    @Test func typeAnchorMustBeDeclaredInItsOwnSystem() {
        var files = FlowFixtures.arcaSources
        files["app/Sources/Audio/SpeechGate.swift"] = nil
        files["app/Sources/Agent/SpeechGate.swift"] = "struct SpeechGate {}\n"
        #expect(check(FlowFixtures.arca, files).staleParts.contains("audio.gate"))
    }

    @Test func anchorsResolveToPrivatePackageAndDistributedTypes() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "core", "name": "Core", "paths": ["core/**"],
                         "parts": [ { "id": "foo", "name": "Foo", "anchor": "Foo" },
                                    { "id": "bar", "name": "Bar", "anchor": "Bar" },
                                    { "id": "baz", "name": "Baz", "anchor": "Baz" },
                                    { "id": "qux", "name": "Qux", "anchor": "Qux" } ] } ] }
        """#)
        let report = check(map, [
            "core/Foo.swift": "private struct Foo {}\n",
            "core/Bar.swift": "fileprivate final class Bar {}\n",
            "core/Baz.swift": "package enum Baz {}\n",
            "core/Qux.swift": "import Distributed\n\ndistributed actor Qux {}\n",
        ])
        #expect(report.staleParts.isEmpty)
        #expect(!report.issues.contains { $0.kind == .staleAnchor })
        #expect(report.anchorFiles == ["core.foo": "core/Foo.swift", "core.bar": "core/Bar.swift",
                                       "core.baz": "core/Baz.swift", "core.qux": "core/Qux.swift"])
        #expect(report.typeFiles == ["Foo": "core/Foo.swift", "Bar": "core/Bar.swift",
                                     "Baz": "core/Baz.swift", "Qux": "core/Qux.swift"])
    }

    @Test func fileAnchorsWorkWithoutSwift() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [
            { "id": "relay", "name": "Relay", "paths": ["relay/src/**"],
              "parts": [ { "id": "pipe", "name": "pipe", "anchor": "relay/src/pipe.ts" },
                         { "id": "gone", "name": "gone", "anchor": "relay/src/gone.ts" } ] },
            { "id": "apns", "name": "APNs", "external": true } ],
          "flows": [ { "id": "push", "from": "relay.pipe", "to": "apns", "kind": "data", "carries": "alert", "via": "push" } ] }
        """#)
        let report = check(map, ["relay/src/pipe.ts": "export function push() {}\n"])
        #expect(report.anchorFiles["relay.pipe"] == "relay/src/pipe.ts")
        #expect(report.staleParts == ["relay.gone"])
        #expect(report.viaLocations["push"] == MindControl.SourceLocation(file: "relay/src/pipe.ts", line: 1))
    }

    @Test func viaLineCountsCRLFLineEndings() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "relay", "name": "Relay", "paths": ["relay/**"] }, { "id": "apns", "name": "APNs", "external": true } ],
          "flows": [ { "id": "push", "from": "relay", "to": "apns", "kind": "data", "carries": "alert", "via": "push" } ] }
        """#)
        let crlf = "// relay\r\n\r\nfunc push() {}\r\n"
        let report = check(map, ["relay/pipe.swift": crlf])
        #expect(report.viaLocations["push"] == MindControl.SourceLocation(file: "relay/pipe.swift", line: 3))
    }

    @Test func missingViaIsStaleAndNoViaIsUnverified() {
        var files = FlowFixtures.arcaSources
        files["app/Sources/Audio/AudioCapture.swift"] = "final class AudioCapture {\n    func beginTransmission() {}\n}\n"
        let report = check(FlowFixtures.arca, files)
        // `check` stays fresh: its via (`append`) is still declared in SpeechGate.swift, which is also in Audio.
        #expect(report.staleFlows.isSuperset(of: ["pcm", "commit", "discard"]))
        #expect(!report.staleFlows.contains("check"))

        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A", "paths": ["a/**"] }, { "id": "x", "name": "X", "external": true },
                       { "id": "y", "name": "Y", "external": true } ],
          "flows": [ { "id": "f", "from": "a", "to": "x", "kind": "data", "carries": "c" },
                     { "id": "g", "from": "x", "to": "y", "kind": "data", "carries": "c" } ] }
        """#)
        let second = check(map, ["a/main.swift": "let x = 1\n"])
        #expect(second.unverifiedFlows == ["f"])
        #expect(second.staleFlows.isEmpty)
        #expect(second.issues.filter { $0.kind == .unverified }.map(\.subject) == ["f"])
    }

    @Test func unknownReferencesBreakOnlyThatFlow() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A", "paths": ["a/**"], "parts": [ { "id": "p", "name": "P" } ] } ],
          "flows": [ { "id": "ok", "from": "a.p", "to": "a", "kind": "data", "carries": "c", "via": "x" },
                     { "id": "bad", "from": "a.q", "to": "nope", "kind": "data", "carries": "c" } ],
          "features": [ { "id": "f", "name": "F", "route": ["ok", "ghost"] } ] }
        """#)
        let report = check(map, ["a/main.swift": "let x = 1\n"])
        #expect(report.brokenFlows == ["bad"])
        #expect(report.issues.contains { $0.kind == .unknownReference && $0.subject == "bad" && $0.message.contains("nope") && $0.message.contains("a.q") })
        #expect(report.issues.contains { $0.kind == .unknownReference && $0.subject == "f" && $0.message.contains("ghost") })
        #expect(report.viaLocations["ok"] != nil)
    }

    @Test func pathTieIsReportedAndUnmapped() {
        let map = FlowFixtures.map(#"""
        { "version": 1, "systems": [ { "id": "a", "name": "A", "paths": ["app/*.swift"] },
                                     { "id": "b", "name": "B", "paths": ["app/*.swift"] } ] }
        """#)
        let report = check(map, ["app/x.swift": "let x = 1\n"])
        #expect(report.unmapped == ["app/x.swift"])
        #expect(report.issues.contains { $0.kind == .pathTie && $0.message.contains("a") && $0.message.contains("b") })
    }

    @Test func unmappedFilesCountAsOneIssue() {
        var files = FlowFixtures.arcaSources
        files["app/Sources/Other/X.swift"] = "let x = 1\n"
        files["app/Sources/Other/Y.swift"] = "let y = 1\n"
        let report = check(FlowFixtures.arca, files)
        #expect(report.unmapped == ["app/Sources/Other/X.swift", "app/Sources/Other/Y.swift"])
        #expect(report.issueCount == 1)
    }

    @Test func patternMatchingNothingIsHarmless() {
        let map = FlowFixtures.map(#"{ "version": 1, "systems": [ { "id": "a", "name": "A", "paths": ["nothing/**"] } ] }"#)
        let report = check(map, [:])
        #expect(report.isHealthy)
    }

    @Test func densityWarningsAtTheirLimits() {
        let systems = (0...20).map { #"{ "id": "s\#($0)", "name": "S\#($0)" }"# }
        let parts = (0...8).map { #"{ "id": "p\#($0)", "name": "P\#($0)" }"# }.joined(separator: ",")
        let flows = (0...60).map { #"{ "id": "f\#($0)", "from": "s0", "to": "s1", "kind": "data", "carries": "c" }"# }
        let json = #"{ "version": 1, "systems": [\#(systems.joined(separator: ",")), { "id": "big", "name": "Big", "parts": [\#(parts)] }], "flows": [\#(flows.joined(separator: ","))] }"#
        let warnings = check(FlowFixtures.map(json), [:]).densityWarnings.map(\.message)
        #expect(warnings.count == 3)
        #expect(warnings.contains { $0.contains("22 systems") })
        #expect(warnings.contains { $0.contains("Big has 9 parts") })
        #expect(warnings.contains { $0.contains("61 flows") })
    }

    @Test func anAnchorOutsideTheProjectIsStale() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "core", "name": "Core", "paths": ["core/**"],
                         "parts": [ { "id": "up", "name": "Up", "anchor": "../../bin/x" },
                                    { "id": "abs", "name": "Abs", "anchor": "/etc/hosts" },
                                    { "id": "ok", "name": "Ok", "anchor": "core/./a/../Main.swift" } ] } ] }
        """#)
        // A snapshot that would read anything it's asked for.
        let snapshot = MindControl.FlowSnapshot(root: URL(fileURLWithPath: "/tmp/mc-check"), flowData: nil, layoutData: nil,
                                                sourceFiles: ["core/Main.swift"], read: { _ in "text" })
        let report = FlowCheck.run(map: map, snapshot: snapshot)
        #expect(report.staleParts == ["core.up", "core.abs"])
        #expect(report.anchorFiles["core.up"] == nil)
        #expect(report.anchorFiles["core.abs"] == nil)
        #expect(report.anchorFiles["core.ok"] == "core/Main.swift")
        #expect(report.issues.first { $0.subject == "core.up" }?.message == "Up: file ../../bin/x is outside the project.")
    }

    @Test(arguments: [
        ("a/b.swift", "a/b.swift"), ("a/./b/../c.swift", "a/c.swift"), ("a//b", "a/b"),
        ("../x", nil), ("a/../../x", nil), ("/etc/hosts", nil), ("..", nil), ("a/..", nil), ("", nil),
    ] as [(String, String?)])
    func projectPathsStayInsideTheRoot(path: String, expected: String?) {
        #expect(MindControl.ProjectPath.normalized(path) == expected)
    }

    @Test(arguments: [("relay/src/pipe.ts", true), ("AudioCapture", false), ("Package.swift", true), ("README", false)])
    func fileAnchorDetection(anchor: String, isFile: Bool) {
        #expect(FlowCheck.isFileAnchor(anchor) == isFile)
    }
}
#endif
