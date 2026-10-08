#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowSearch = MindControl.FlowSearch

struct FlowSearchTests {
    private var search: FlowSearch {
        var report = MindControl.HealthReport()
        report.owners = ["app/Sources/Audio/AudioCapture.swift": "audio", "app/Sources/Coordination/CostMeter.swift": "tap"]
        report.typeFiles = ["AudioCapture": "app/Sources/Audio/AudioCapture.swift", "CostMeter": "app/Sources/Coordination/CostMeter.swift"]
        report.unmapped = ["app/Sources/Other/Stray.swift"]
        return FlowSearch(map: FlowFixtures.arca, report: report)
    }

    @Test func groupsComeInKindOrder() {
        let kinds = search.search("audio").map(\.kind)
        #expect(kinds == kinds.sorted())
        #expect(kinds.contains(.system) && kinds.contains(.part) && kinds.contains(.file))
    }

    @Test func prefixBeatsWordStartBeatsSubstring() {
        let titles = search.search("a").filter { $0.kind == .system }.map(\.title)
        // "Audio" (prefix), "Realtime agent" (word start), "Tap coordinator" (substring)
        #expect(titles.firstIndex(of: "Audio")! < titles.firstIndex(of: "Realtime agent")!)
        #expect(titles.firstIndex(of: "Realtime agent")! < titles.firstIndex(of: "Tap coordinator")!)
    }

    @Test func typeNameResolvesToItsSystem() throws {
        let result = try #require(search.search("CostMeter").first { $0.kind == .file && $0.title == "CostMeter" })
        #expect(result.target == .file(path: "app/Sources/Coordination/CostMeter.swift", system: "tap"))
        #expect(result.detail.contains("Tap coordinator"))
    }

    @Test func strayFileSaysNoSystem() throws {
        let result = try #require(search.search("stray").first)
        #expect(result.target == .file(path: "app/Sources/Other/Stray.swift", system: nil))
        #expect(result.detail.contains("no system"))
    }

    @Test func featuresAndPartsAreFound() {
        #expect(search.search("press becomes").first?.target == .feature("speech"))
        #expect(search.search("speechgate").first?.target == .part("audio.gate"))
    }

    @Test func emptyQueryFindsNothing() {
        #expect(search.search("  ").isEmpty)
    }

    @Test func caseInsensitive() {
        #expect(search.search("AUDIO").first?.title == "Audio")
    }

    // MARK: Ranking edge cases

    /// Titles whose order differs from their ids' order and from plain alphabetical order.
    private static let rankingJSON = """
    {
      "version": 1,
      "systems": [
        { "id": "crew", "name": "Agents" },
        { "id": "agent", "name": "Voice agent" },
        { "id": "lab", "name": "Reagents" },
        { "id": "agentic", "name": "Mic" }
      ],
      "features": [
        { "id": "squash", "name": "Compress becomes small", "route": [] },
        { "id": "talk", "name": "The press becomes loud", "route": [] }
      ]
    }
    """

    private var ranking: FlowSearch {
        var report = MindControl.HealthReport()
        report.unmapped = ["Sources/Kit.swift"]
        report.typeFiles = ["Aggregate": "Sources/Kit.swift", "Observer": "Sources/Kit.swift",
                            "SpeechGate": "Sources/Kit.swift", "URLServer": "Sources/Kit.swift"]
        return FlowSearch(map: FlowFixtures.map(Self.rankingJSON), report: report)
    }

    @Test func aWordStartCanSpanWords() {
        // Alphabetical order alone would put "Compress" first.
        #expect(ranking.search("press becomes").map(\.title) == ["The press becomes loud", "Compress becomes small"])
    }

    @Test func camelCaseHumpsStartWords() {
        #expect(ranking.search("gate").map(\.title) == ["SpeechGate", "Aggregate"])
        #expect(ranking.search("server").map(\.title) == ["URLServer", "Observer"])
    }

    @Test func wordsStartAfterSpacesAndPunctuationAndAtHumps() {
        #expect(FlowSearch.wordTails("A press") == ["a press", "press"])
        #expect(FlowSearch.wordTails("URLServer.swift") == ["urlserver.swift", "server.swift", "swift"])
        #expect(FlowSearch.wordTails("Base64Encoder") == ["base64encoder", "encoder"])
    }

    @Test func idsFindButDoNotRank() {
        // "Voice agent" ranks as a word start although its id starts with "agent"; "Mic" is found only by
        // its id, so it ranks as a substring.
        #expect(ranking.search("agent").map(\.title) == ["Agents", "Voice agent", "Mic", "Reagents"])
    }

    @Test func limitCapsResults() {
        #expect(search.search("a").count > 2)
        #expect(search.search("a", limit: 2).count == 2)
    }
}
#endif
