#if os(macOS)
import Testing
@testable import Ghostty

@MainActor
struct ExtensionSidebarModelTests {
    @Test func startsShownWithNothingOpen() {
        let model = ExtensionSidebarModel()
        #expect(model.isShown)
        #expect(model.active == nil)
    }

    @Test func clickingAnIconOpensItAndClickingAgainCloses() {
        let model = ExtensionSidebarModel()
        model.select(.codebaseVisualizer)
        #expect(model.active == .codebaseVisualizer)
        model.select(.codebaseVisualizer)
        #expect(model.active == nil)
    }

    @Test func hidingTheSidebarClosesTheOpenExtension() {
        let model = ExtensionSidebarModel()
        model.select(.codebaseVisualizer)
        model.toggleShown()
        #expect(!model.isShown)
        #expect(model.active == nil)
        model.toggleShown()
        #expect(model.isShown)
        #expect(model.active == nil)
    }

    @Test func theVisualizerIsTheFirstExtension() {
        #expect(LosttyExtension.allCases.first == .codebaseVisualizer)
        #expect(LosttyExtension.codebaseVisualizer.title == "Codebase visualizer")
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
        model.toggleShown()                        // hiding the sidebar closes it too
        #expect(focused == 2)

        model.toggleShown()
        model.toggleShown()                        // nothing open: focus is left alone
        #expect(focused == 2)
    }
}
#endif
