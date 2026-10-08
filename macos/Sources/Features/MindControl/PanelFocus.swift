import AppKit
import SwiftUI

extension MindControl {
    /// Holds keyboard focus while the panel has no map view (empty, error and loading states, or no Metal), so keys
    /// don't reach the terminal hidden behind the panel. Esc closes the panel, plain typing stops here, ⌘F is kept
    /// from opening the terminal's search, and every other shortcut goes on to the menus. Buttons' own shortcuts
    /// (Draft's Return) still work: Return is passed on.
    final class PanelKeyView: NSView {
        var onEscape: () -> Void = {}
        /// Return and keypad Enter. Tab stays here: the window's key-view loop would hand focus to the terminal,
        /// and the panel's controls are used with the mouse.
        static let passedOn: Set<UInt16> = [36, 76]

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            takeFocus()
        }

        /// On the next turn, once SwiftUI has finished updating.
        func takeFocus() {
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
            // Return / Enter go up the responder chain (which never reaches the terminal), so the window can still
            // give them to a default button. Tab and Shift-Tab stop here with the typing; ⌃Tab and the like go on.
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

    /// Takes keyboard focus when it appears and again whenever `state` changes (loading, then no flow file, …),
    /// since a click elsewhere may have moved focus meanwhile.
    struct PanelFocusHolder: NSViewRepresentable {
        let onEscape: () -> Void
        let state: Model.State

        final class Coordinator {
            var state: Model.State
            init(state: Model.State) { self.state = state }
        }

        func makeCoordinator() -> Coordinator { Coordinator(state: state) }

        func makeNSView(context: Context) -> PanelKeyView {
            let view = PanelKeyView()
            view.onEscape = onEscape
            return view
        }

        func updateNSView(_ view: PanelKeyView, context: Context) {
            view.onEscape = onEscape
            guard context.coordinator.state != state else { return }
            context.coordinator.state = state
            view.takeFocus()
        }
    }
}
