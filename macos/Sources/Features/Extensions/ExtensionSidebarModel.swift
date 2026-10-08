#if os(macOS)
import AppKit
import Combine

/// An extension reachable from the window's sidebar. Order is sidebar order.
enum LosttyExtension: String, CaseIterable, Identifiable {
    case codebaseVisualizer
    case skins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codebaseVisualizer: "Codebase visualizer"
        case .skins: "Skins"
        }
    }
}

/// Per-window sidebar state: which extension (if any) is open in the
/// terminal area, the pane extensions act on, and the window's title bar
/// color, which the sidebar matches.
@MainActor
final class ExtensionSidebarModel: ObservableObject {
    @Published private(set) var active: LosttyExtension?
    /// The window's focused (or last focused) pane, set by the controller.
    @Published var focusedSurfaceID: UUID?
    /// The title bar's color (the top pane's background), set by the window.
    @Published var chromeColor: NSColor?

    /// MindControl's flow map for this window. It reloads every time the visualizer opens.
    let mindControl = MindControl.Model()
    /// The focused terminal's working directory. Set by the window's controller.
    var workingDirectory: () -> URL? = { nil }
    /// Gives keyboard focus back to the terminal. Set by the window's controller.
    var focusTerminal: () -> Void = {}
    /// Opens a new tab in `directory` and types `input` into its shell. Set by the window's controller.
    var openTab: (_ directory: URL, _ input: String) -> Void = { _, _ in }

    /// Clicking an icon opens its extension; clicking the open one closes it.
    func select(_ ext: LosttyExtension) {
        setActive(active == ext ? nil : ext)
    }

    private func setActive(_ ext: LosttyExtension?) {
        let previous = active
        active = ext
        if ext == .codebaseVisualizer, previous != .codebaseVisualizer {
            mindControl.load(pwd: workingDirectory())
        }
        if previous == .codebaseVisualizer, ext != .codebaseVisualizer {
            mindControl.close()
        }
        // An open extension may hold keyboard focus (the visualizer does, for Esc); hand it back.
        if previous != nil, ext == nil {
            focusTerminal()
        }
    }
}
#endif
