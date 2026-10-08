#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias Panel = MindControl.Panel

struct PanelTextTests {
    @Test func ageCopy() {
        #expect(Panel.ageText(.hidden) == nil)
        #expect(Panel.ageText(.notCommitted) == "Map not committed yet")
        #expect(Panel.ageText(.commits(0)) == "Map up to date")
        #expect(Panel.ageText(.commits(1)) == "Map updated 1 commit ago")
        #expect(Panel.ageText(.commits(23)) == "Map updated 23 commits ago")
    }

    @Test func healthCopy() {
        var report = MindControl.HealthReport()
        #expect(Panel.healthText(report) == "Map healthy")
        report.unmapped = ["a.swift"]
        #expect(Panel.healthText(report) == "1 issue")
        report.issues = [.init(kind: .staleVia, subject: "f", message: "m")]
        #expect(Panel.healthText(report) == "2 issues")
    }

    @MainActor
    @Test func stateCopy() {
        let project = MindControl.Model.Project(root: URL(fileURLWithPath: "/tmp/arca"), name: "arca", claudeBlockReason: nil)
        #expect(Panel.centerMessage(for: .noProject) == "This terminal hasn't reported a working directory.")
        #expect(Panel.centerMessage(for: .loading(project)) == "Reading the flow map…")
        #expect(Panel.centerMessage(for: .failed("Can't read /x.")) == "Can't read /x.")
        #expect(Panel.centerMessage(for: .noFlowFile(project)) == nil)
        #expect(Panel.emptyTitle(project) == "No flow map for arca yet")
    }

    @Test func unmappedCopy() {
        #expect(Panel.unmappedText(0) == nil)
        #expect(Panel.unmappedText(1) == "1 unmapped file")
        #expect(Panel.unmappedText(12) == "12 unmapped files")
    }

    /// Draft and Refresh run only once the folder has been checked (not while loading, when the reason is
    /// still unknown) and only when nothing blocks them.
    @MainActor
    @Test func claudeRunsOnlyInACheckedUnblockedFolder() {
        let open = MindControl.Model.Project(root: URL(fileURLWithPath: "/tmp/arca"), name: "arca", claudeBlockReason: nil)
        let home = MindControl.Model.Project(root: URL(fileURLWithPath: "/Users/me"), name: "me", claudeBlockReason: "This is your home folder.")
        let loaded = MindControl.Model.Loaded(map: FlowFixtures.arca, report: .init(), saved: [:], generation: 1)
        #expect(Panel.canRunClaude(in: .noFlowFile(open)))
        #expect(Panel.canRunClaude(in: .ready(open, loaded)))
        #expect(!Panel.canRunClaude(in: .loading(open)))
        #expect(!Panel.canRunClaude(in: .invalid(open, [])))
        #expect(!Panel.canRunClaude(in: .noFlowFile(home)))
        #expect(!Panel.canRunClaude(in: .ready(home, loaded)))
        #expect(!Panel.canRunClaude(in: .noProject))
        #expect(!Panel.canRunClaude(in: .idle))
        #expect(!Panel.canRunClaude(in: .failed("x")))
    }
    /// With a map, a blocked Refresh says why beside the button, not only in its tooltip.
    @MainActor
    @Test func aBlockedRefreshShowsItsReason() {
        let open = MindControl.Model.Project(root: URL(fileURLWithPath: "/tmp/arca"), name: "arca", claudeBlockReason: nil)
        let home = MindControl.Model.Project(root: URL(fileURLWithPath: "/Users/me"), name: "me", claudeBlockReason: "This is your home folder.")
        let loaded = MindControl.Model.Loaded(map: FlowFixtures.arca, report: .init(), saved: [:], generation: 1)
        #expect(Panel.refreshBlockedCaption(in: .ready(home, loaded)) == "This is your home folder.")
        #expect(Panel.refreshBlockedCaption(in: .ready(open, loaded)) == nil)
        // The empty state shows its own reason under Draft.
        #expect(Panel.refreshBlockedCaption(in: .noFlowFile(home)) == nil)
        #expect(Panel.refreshBlockedCaption(in: .loading(home)) == nil)
    }

    /// The copy sheet shows plain text, so its copy must not lean on Markdown.
    @Test func missingClaudeCopyIsPlainText() {
        let detail = Panel.missingClaudeDetail(projectName: "arca")
        #expect(detail == "Claude Code isn't on your shell's PATH. Install it, or paste this prompt into a Claude session in arca.")
        #expect(!detail.contains("`"))
        #expect(!Panel.unsavedPromptDetail(error: "Disk full.", projectName: "arca").contains("`"))
    }
}
#endif
