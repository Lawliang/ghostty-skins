#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

enum FlowFixtures {
    /// A small map shaped like Arca's speech path.
    static let arcaJSON = """
    {
      "version": 1,
      "zones": [
        { "id": "ring", "name": "Ring" },
        { "id": "phone", "name": "Phone" },
        { "id": "cloud", "name": "Cloud services" }
      ],
      "systems": [
        { "id": "ring", "name": "Ring", "zone": "ring", "external": true },
        { "id": "ble", "name": "BLE link", "zone": "phone", "paths": ["app/Sources/BLE/**"],
          "parts": [ { "id": "link", "name": "ArcaLink", "anchor": "ArcaLink" } ] },
        { "id": "tap", "name": "Tap coordinator", "zone": "phone", "paths": ["app/Sources/Coordination/Tap*.swift"] },
        { "id": "audio", "name": "Audio", "zone": "phone", "summary": "Mic capture, the words-heard check, playback.",
          "paths": ["app/Sources/Audio/**"],
          "parts": [
            { "id": "capture", "name": "AudioCapture", "anchor": "AudioCapture" },
            { "id": "gate", "name": "SpeechGate", "anchor": "SpeechGate" }
          ] },
        { "id": "agent", "name": "Realtime agent", "zone": "phone", "paths": ["app/Sources/Agent/**"],
          "parts": [ { "id": "session", "name": "RealtimeAgentSession", "anchor": "RealtimeAgentSession" } ] },
        { "id": "openai", "name": "OpenAI Realtime", "zone": "cloud", "external": true }
      ],
      "flows": [
        { "id": "press", "from": "ring", "to": "ble.link", "kind": "control", "carries": "press DOWN / UP", "via": "didUpdateValue" },
        { "id": "event", "from": "ble.link", "to": "tap", "kind": "control", "carries": "onEvent", "via": "onEvent" },
        { "id": "begin", "from": "tap", "to": "audio.capture", "kind": "control", "carries": "begin / end", "via": "beginTransmission" },
        { "id": "pcm", "from": "audio.capture", "to": "agent.session", "kind": "data", "carries": "PCM16 24 kHz", "via": "sendAudio" },
        { "id": "check", "from": "audio.capture", "to": "audio.gate", "kind": "data", "carries": "PCM buffers", "via": "append" },
        { "id": "commit", "from": "audio.capture", "to": "agent.session", "kind": "control", "carries": "commit turn", "via": "commitTurn", "when": "words heard" },
        { "id": "discard", "from": "audio.capture", "to": "agent.session", "kind": "control", "carries": "discard turn", "via": "discardTurn", "when": "nothing heard" },
        { "id": "send", "from": "agent.session", "to": "openai", "kind": "data", "carries": "audio + commit", "via": "send" },
        { "id": "reply", "from": "openai", "to": "agent.session", "kind": "data", "carries": "response audio", "via": "receive" }
      ],
      "features": [
        { "id": "speech", "name": "A press becomes speech",
          "route": ["press", "event", "begin", "pcm", "check", "commit", "discard", "send", "reply"] }
      ]
    }
    """

    static func map(_ json: String) -> MindControl.FlowMap {
        switch MindControl.FlowFile.parse(Data(json.utf8)) {
        case .success(let map): return map
        case .failure(let errors): fatalError("Fixture is invalid: \(errors.errors)")
        }
    }

    static var arca: MindControl.FlowMap { map(arcaJSON) }

    /// `arca` with no zones, which the format allows.
    static var arcaNoZonesJSON: String {
        arcaJSON.replacingOccurrences(of: #""zone": "[a-z]+", "#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #""zones": \[[^\]]*\],"#, with: "", options: .regularExpression)
    }

    static var arcaNoZones: MindControl.FlowMap { map(arcaNoZonesJSON) }

    /// Source files matching `arca`'s anchors and vias.
    static let arcaSources: [String: String] = [
        "app/Sources/BLE/ArcaLink.swift": "final class ArcaLink {\n    var onEvent: ((Int) -> Void)?\n    func didUpdateValue() { onEvent?(1) }\n}\n",
        "app/Sources/Coordination/TapCoordinator.swift": "final class TapCoordinator {\n    func handle() { capture.beginTransmission() }\n}\n",
        "app/Sources/Audio/AudioCapture.swift": "final class AudioCapture {\n    func beginTransmission() {}\n    func run() {\n        agent.sendAudio()\n        gate.append()\n        agent.commitTurn()\n        agent.discardTurn()\n    }\n}\n",
        "app/Sources/Audio/SpeechGate.swift": "struct SpeechGate {\n    func append() {}\n}\n",
        "app/Sources/Agent/RealtimeAgentSession.swift": "actor RealtimeAgentSession {\n    func sendAudio() {}\n    func commitTurn() {}\n    func discardTurn() {}\n    func send() {}\n    func receive() {}\n}\n",
    ]
}

/// A fresh temporary project directory, removed when the test ends.
final class TempProject {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("mc-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ path: String, _ contents: String) throws {
        let target = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
    }

    func write(_ files: [String: String]) throws {
        for (path, contents) in files { try write(path, contents) }
    }

    struct GitFailure: Error, CustomStringConvertible {
        let arguments: [String]
        let status: Int32
        let message: String
        var description: String { "git \(arguments.joined(separator: " ")) exited \(status): \(message)" }
    }

    /// The exit status of git run in the project.
    @discardableResult
    func git(_ args: String...) throws -> Int32 {
        try run(args).status
    }

    /// `git add -A && git commit`, for test repos only. Throws when either step fails.
    func commitAll(_ message: String) throws {
        for args in [["add", "-A"], ["commit", "-q", "-m", message]] {
            let result = try run(args)
            guard result.status == 0 else {
                throw GitFailure(arguments: args, status: result.status, message: result.errors)
            }
        }
    }

    /// Runs git with a fixed identity and signing off, so commits work (and never prompt) on a
    /// machine that signs by default.
    private func run(_ args: [String]) throws -> (status: Int32, errors: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "-c", "user.name=Test", "-c", "user.email=test@example.com",
                             "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false"] + args
        let errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        // Read before waiting so a long error can't fill the pipe and deadlock.
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

struct TempProjectTests {
    @Test func commitAllThrowsWhenGitFails() throws {
        let project = try TempProject()
        try project.write("main.swift", "let x = 1\n")
        // No `git init`, so `git add` fails.
        #expect(throws: (any Error).self) { try project.commitAll("first") }
    }

    @Test func commitsAndTagsAreNeverSigned() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        // A machine that signs by default, with a signer that always fails.
        try project.git("config", "commit.gpgsign", "true")
        try project.git("config", "tag.gpgsign", "true")
        try project.git("config", "gpg.program", "/usr/bin/false")
        try project.write("main.swift", "let x = 1\n")
        try project.commitAll("first")
        #expect(try project.git("rev-parse", "--verify", "--quiet", "HEAD") == 0)
        #expect(try project.git("tag", "-a", "v1", "-m", "v1") == 0)
    }
}
#endif
