#if os(macOS)
import AppKit
import Combine

/// An extension reachable from the window's sidebar. Order is sidebar order.
enum LosttyExtension: String, CaseIterable, Identifiable {
    case codebaseVisualizer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codebaseVisualizer: "Codebase visualizer"
        }
    }
}

/// Per-window sidebar state: whether the sidebar is shown, which extension
/// (if any) is open in the terminal area, and the window's title bar color,
/// which the sidebar matches.
@MainActor
final class ExtensionSidebarModel: ObservableObject {
    @Published private(set) var isShown = true
    @Published private(set) var active: LosttyExtension?
    /// The title bar's color (the top pane's background), set by the window.
    @Published var chromeColor: NSColor?

    /// MindControl's project map for this window; its scan cache outlives the open visualizer.
    let mindControl = MindControl.Model()
    /// The focused terminal's working directory. Set by the window's controller.
    var workingDirectory: () -> URL? = { nil }
    /// Gives keyboard focus back to the terminal. Set by the window's controller.
    var focusTerminal: () -> Void = {}

    /// Clicking an icon opens its extension; clicking the open one closes it.
    func select(_ ext: LosttyExtension) {
        setActive(active == ext ? nil : ext)
    }

    /// Hiding the sidebar also closes whatever extension was open.
    func toggleShown() {
        isShown.toggle()
        if !isShown { setActive(nil) }
    }

    private func setActive(_ ext: LosttyExtension?) {
        let previous = active
        active = ext
        if ext == .codebaseVisualizer, previous != .codebaseVisualizer {
            mindControl.load(pwd: workingDirectory())
        }
        // An open extension may hold keyboard focus (the visualizer does, for Esc); hand it back.
        if previous != nil, ext == nil {
            focusTerminal()
        }
    }
}
#endif
