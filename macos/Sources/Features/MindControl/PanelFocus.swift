import AppKit
import SwiftUI

extension MindControl {
    /// Holds keyboard focus while the panel has no map view (empty, error and loading states, or no Metal), so keys
    /// don't reach the terminal hidden behind the panel. Esc closes the panel, plain typing stops here, ⌘F is kept
    /// from opening the terminal's search, and every other shortcut goes on to the menus. Buttons' own shortcuts
    /// (Draft's Return) still work: Return is passed on.
    final class PanelKeyView: NSView {
        var onEscape: () -> Void = {}
        /// Tab, Return, keypad Enter.
        static let passedOn: Set<UInt16> = [48, 36, 76]

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Next turn, once SwiftUI has finished inserting it.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onEscape()
                return
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            // Up the responder chain (which never reaches the terminal): Tab, to move between the panel's buttons,
            // and Return / Enter, so the window can still give them to a default button.
            if modifiers.isEmpty, !Self.passedOn.contains(event.keyCode) { return }
            super.keyDown(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if window?.firstResponder === self,
               event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }

    struct PanelFocusHolder: NSViewRepresentable {
        let onEscape: () -> Void

        func makeNSView(context: Context) -> PanelKeyView {
            let view = PanelKeyView()
            view.onEscape = onEscape
            return view
        }

        func updateNSView(_ view: PanelKeyView, context: Context) {
            view.onEscape = onEscape
        }
    }
}
