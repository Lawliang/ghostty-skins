#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias ClaudeLauncher = MindControl.ClaudeLauncher
private typealias ClaudePrompts = MindControl.ClaudePrompts

struct ClaudeLauncherTests {
    @Test func findsCommandsInTheLoginShell() {
        #expect(ClaudeLauncher.isInstalled(command: "ls", shell: "/bin/zsh"))
        #expect(!ClaudeLauncher.isInstalled(command: "mc-definitely-missing-command", shell: "/bin/zsh"))
    }

    @Test func theCommandNameIsQuotedForTheShell() {
        // Unquoted, `ls; true` would run `true` and report success.
        #expect(!ClaudeLauncher.isInstalled(command: "ls; true", shell: "/bin/zsh"))
    }

    @Test func aMissingShellIsNotInstalled() {
        #expect(!ClaudeLauncher.isInstalled(command: "ls", shell: "/definitely/missing/shell"))
    }

    /// A login shell whose startup files hang (and ignore SIGTERM, as interactive shells do) must not hang the caller.
    @Test func givesUpOnAShellThatHangs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mc-hang-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shell = dir.appendingPathComponent("hanging-shell")
        try "#!/bin/sh\ntrap '' TERM\nsleep 5\n".write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)

        let start = Date()
        #expect(!ClaudeLauncher.isInstalled(command: "ls", shell: shell.path, timeout: 0.5))
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func commandQuotesThePromptPath() {
        let command = ClaudeLauncher.command(promptFile: URL(fileURLWithPath: "/tmp/it's here.md"))
        #expect(command == "claude \"$(cat '/tmp/it'\\''s here.md')\"\n")
    }

    @Test func shellQuoteWrapsInSingleQuotes() {
        #expect(ClaudeLauncher.shellQuote("plain") == "'plain'")
        #expect(ClaudeLauncher.shellQuote("a b \"c\" $d `e`") == "'a b \"c\" $d `e`'")
        #expect(ClaudeLauncher.shellQuote("it's") == "'it'\\''s'")
    }

    @Test func promptIsWrittenToATemporaryFile() throws {
        let url = try ClaudeLauncher.writePrompt("hello")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "hello")
    }

    @Test func draftPromptCarriesTheRules() {
        let prompt = ClaudePrompts.draft(projectName: "arca")
        for needle in ["arca", ".mindcontrol/flow.json", "\"via\"", "\"when\"", "\"control\"", "\"data\"", "20 systems", "8 parts",
                       "60 flows", "CLAUDE.md", ClaudePrompts.upkeepRule, "\"version\": 1"] {
            #expect(prompt.contains(needle), "draft prompt should mention \(needle)")
        }
    }

    @Test func refreshPromptReadsChangesAndLeavesPositionsAlone() {
        let prompt = ClaudePrompts.refresh(projectName: "arca")
        for needle in ["arca", "git log", ".mindcontrol/flow.json", "layout.json", "\"via\""] {
            #expect(prompt.contains(needle), "refresh prompt should mention \(needle)")
        }
    }

    @Test func upkeepRuleIsTheAgreedWording() {
        #expect(ClaudePrompts.upkeepRule == "When you change how data or control moves between systems, update `.mindcontrol/flow.json`.")
    }

    @Test func promptLimitsMatchTheChecks() {
        let prompt = ClaudePrompts.draft(projectName: "arca")
        #expect(prompt.contains("\(MindControl.FlowCheck.maxSystems) systems"))
        #expect(prompt.contains("\(MindControl.FlowCheck.maxPartsPerSystem) parts"))
        #expect(prompt.contains("\(MindControl.FlowCheck.maxFlows) flows"))
    }

    /// Every "via" and Swift anchor has to be in a file MindControl reads, so the prompts name exactly those files.
    @Test func promptsNameTheFilesMindControlReads() {
        for prompt in [ClaudePrompts.draft(projectName: "arca"), ClaudePrompts.refresh(projectName: "arca")] {
            for ext in MindControl.SourceFilter.sourceExtensions {
                #expect(prompt.contains("`.\(ext)`"), "prompt should list .\(ext)")
            }
            for folder in MindControl.SourceFilter.excludedDirectories {
                #expect(prompt.contains("`\(folder)`"), "prompt should list the \(folder) folder")
            }
            for needle in ["\"Tests\"", "\"-tests\"", "\"_tests\"", "ModelTests.swift", "server_test.go", "test_core.py", "app.test.ts",
                           "app.spec.js"] {
                #expect(prompt.contains(needle), "prompt should mention \(needle)")
            }
        }
    }

    /// FeatureSteps groups only consecutive steps that share a "when".
    @Test func promptsKeepAConditionsFlowsTogetherInARoute() {
        for prompt in [ClaudePrompts.draft(projectName: "arca"), ClaudePrompts.refresh(projectName: "arca")] {
            #expect(prompt.contains("Flows with the same \"when\" sit next to each other in a route"))
        }
    }

    /// FlowCheck finds a via with a whole-word (\\b…\\b) search, which needs a word character at each end.
    @Test func promptsAskForViasTheWholeWordSearchCanFind() {
        for prompt in [ClaudePrompts.draft(projectName: "arca"), ClaudePrompts.refresh(projectName: "arca")] {
            #expect(prompt.contains("A \"via\" starts and ends with a letter, digit or \"_\""))
        }
    }

    /// The example Claude copies must itself be a valid, healthy flow file.
    @Test func promptExampleParsesAndPassesTheChecks() throws {
        let rules = ClaudePrompts.formatAndRules
        let start = try #require(rules.range(of: "```json\n"))
        let end = try #require(rules.range(of: "\n```", range: start.upperBound..<rules.endIndex))
        let json = String(rules[start.upperBound..<end.lowerBound])
        let map = try MindControl.FlowFile.parse(Data(json.utf8)).get()

        let sources = [
            "app/Sources/Audio/AudioCapture.swift":
                "final class AudioCapture {\n    func run() {\n        session.sendAudio(pcm)\n        if heard { session.commitTurn() }\n    }\n}\n",
        ]
        let snapshot = MindControl.FlowSnapshot(root: URL(fileURLWithPath: "/nonexistent"), flowData: Data(json.utf8), layoutData: nil,
                                                sourceFiles: sources.keys.sorted(), read: { sources[$0] })
        let report = MindControl.FlowCheck.run(map: map, snapshot: snapshot)
        #expect(report.issues.isEmpty, "\(report.issues)")
        #expect(report.unmapped.isEmpty)
    }
}
#endif
