#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias ProjectGuard = MindControl.ProjectGuard

struct ProjectGuardTests {
    @Test func homeFolderIsBlocked() {
        let reason = ProjectGuard.claudeBlockReason(root: URL(fileURLWithPath: "/Users/someone"), home: "/Users/someone", isGit: { _ in true })
        #expect(reason?.contains("home folder") == true)
    }

    @Test func homeFolderIsBlockedWhateverTheCase() {
        // APFS is usually case-insensitive, so `cd /users/someone` reaches the home folder too.
        let reason = ProjectGuard.claudeBlockReason(root: URL(fileURLWithPath: "/users/Someone/"), home: "/Users/someone", isGit: { _ in true })
        #expect(reason?.contains("home folder") == true)
    }

    @Test func diskRootIsBlocked() {
        #expect(ProjectGuard.claudeBlockReason(root: URL(fileURLWithPath: "/"), home: "/Users/someone", isGit: { _ in true }) != nil)
    }

    @Test func nonGitFolderIsBlocked() {
        let reason = ProjectGuard.claudeBlockReason(root: URL(fileURLWithPath: "/tmp/x"), home: "/Users/someone", isGit: { _ in false })
        #expect(reason?.contains("git") == true)
    }

    @Test func gitProjectIsAllowed() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        #expect(ProjectGuard.claudeBlockReason(root: project.url, home: "/Users/someone") == nil)
    }
}
#endif
