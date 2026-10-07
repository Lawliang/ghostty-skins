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

    @Test func openingTheVisualizerLoadsTheTerminalsProject() {
        let model = ExtensionSidebarModel()
        model.workingDirectory = { nil }           // e.g. shell integration hasn't reported a pwd
        model.select(.codebaseVisualizer)
        #expect(model.mindControl.state == .noProject)
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
