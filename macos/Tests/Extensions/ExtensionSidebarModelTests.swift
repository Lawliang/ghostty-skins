#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct ExtensionSidebarModelTests {
    @Test func startsWithNothingOpen() {
        let model = ExtensionSidebarModel()
        #expect(model.active == nil)
        #expect(model.focusedSurfaceID == nil)
    }

    @Test func clickingAnIconOpensItAndClickingAgainCloses() {
        let model = ExtensionSidebarModel()
        model.select(.codebaseVisualizer)
        #expect(model.active == .codebaseVisualizer)
        model.select(.codebaseVisualizer)
        #expect(model.active == nil)
    }

    @Test func clickingAnotherIconSwitchesToIt() {
        let model = ExtensionSidebarModel()
        model.select(.codebaseVisualizer)
        model.select(.skins)
        #expect(model.active == .skins)
    }

    @Test func sidebarOrderIsVisualizerThenSkins() {
        #expect(LosttyExtension.allCases == [.codebaseVisualizer, .skins])
        #expect(LosttyExtension.codebaseVisualizer.title == "Codebase visualizer")
        #expect(LosttyExtension.skins.title == "Skins")
    }

    @Test func tracksTheFocusedPane() {
        let model = ExtensionSidebarModel()
        let pane = UUID()
        model.focusedSurfaceID = pane
        #expect(model.focusedSurfaceID == pane)
    }

    // These use real folders: the sidebar's MindControl model reads the disk, and a missing folder
    // fails to load (no project).
    @Test func openingTheVisualizerLoadsTheTerminalsProject() async throws {
        let model = ExtensionSidebarModel()
        let dir = try TempProject()
        model.workingDirectory = { dir.url }
        model.select(.codebaseVisualizer)
        await model.mindControl.loadingTask?.value
        #expect(model.mindControl.project?.root.path == dir.url.standardizedFileURL.resolvingSymlinksInPath().path)
        model.mindControl.close()
    }

    @Test func closingTheVisualizerForgetsTheChosenFolder() async throws {
        let model = ExtensionSidebarModel()
        let x = try TempProject(), y = try TempProject()
        model.workingDirectory = { x.url }
        model.select(.codebaseVisualizer)
        model.mindControl.choose(root: x.url)
        model.select(.codebaseVisualizer)          // closed
        model.workingDirectory = { y.url }
        model.select(.codebaseVisualizer)          // reopened in another folder
        await model.mindControl.loadingTask?.value
        #expect(model.mindControl.project?.root.path == y.url.standardizedFileURL.resolvingSymlinksInPath().path)
        model.mindControl.close()
    }

    @Test func closingTheVisualizerReturnsFocusToTheTerminal() {
        let model = ExtensionSidebarModel()
        model.workingDirectory = { nil }
        var focused = 0
        model.focusTerminal = { focused += 1 }

        model.select(.codebaseVisualizer)
        #expect(focused == 0)
        model.select(.codebaseVisualizer)          // icon clicked again, or Esc
        #expect(focused == 1)

        model.select(.codebaseVisualizer)
        model.select(.skins)                       // switching panels: the terminal stays covered
        #expect(focused == 1)
        model.select(.skins)                       // closing the last panel hands focus back
        #expect(focused == 2)
    }
}
#endif
