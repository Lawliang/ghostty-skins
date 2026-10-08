#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// The panel's focus holder: with no map view, it keeps keys away from the terminal behind the panel.
@MainActor
struct PanelFocusTests {
    private final class Recorder: NSResponder {
        var keys: [UInt16] = []
        override func keyDown(with event: NSEvent) { keys.append(event.keyCode) }
    }

    private func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                      isARepeat: false, keyCode: code))
    }

    @Test func escClosesOnceAndPlainTypingStopsHere() throws {
        let view = MindControl.PanelKeyView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        var closes = 0
        view.onEscape = { closes += 1 }
        let recorder = Recorder()
        view.nextResponder = recorder
        view.keyDown(with: try key("\u{1b}", code: 53))
        #expect(closes == 1)
        view.keyDown(with: try key("a", code: 0))
        view.keyDown(with: try key(" ", code: 49))
        view.keyDown(with: try key("1", code: 18))
        #expect(recorder.keys.isEmpty)
        // Tab moves between buttons, Return can reach a default button, and keys with ⌘ or ⌃ go on up.
        view.keyDown(with: try key("\t", code: 48))
        view.keyDown(with: try key("\r", code: 36))
        view.keyDown(with: try key("k", code: 40, modifiers: .command))
        view.keyDown(with: try key("c", code: 8, modifiers: .control))
        #expect(recorder.keys == [48, 36, 40, 8])
        #expect(closes == 1)
    }

    @Test func takesKeyboardFocusInAWindowAndKeepsCommandFFromTheTerminal() async throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content
        let other = NSTextView(frame: CGRect(x: 0, y: 0, width: 50, height: 20))
        content.addSubview(other)
        window.makeFirstResponder(other)
        let view = MindControl.PanelKeyView(frame: content.bounds)
        content.addSubview(view)
        // It asks for focus on the next turn of the main queue.
        await Task.yield()
        for _ in 0..<5 where window.firstResponder !== view {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(window.firstResponder === view)
        #expect(view.performKeyEquivalent(with: try key("f", code: 3, modifiers: .command)))
        // Other shortcuts are left for the menus.
        #expect(!view.performKeyEquivalent(with: try key("t", code: 17, modifiers: .command)))
        // Not focused: ⌘F isn't its business.
        window.makeFirstResponder(other)
        #expect(!view.performKeyEquivalent(with: try key("f", code: 3, modifiers: .command)))
    }
    /// With the focus holder in charge, Return still presses Draft with Claude (its default action), and Esc still
    /// closes the panel exactly once.
    @Test func returnStillDraftsAndEscClosesOnceInThePanel() async throws {
        let model = MindControl.Model(snapshot: { root in
            MindControl.FlowSnapshot(root: root, flowData: nil, layoutData: nil, sourceFiles: [], read: { _ in nil })
        }, age: { _, _ in .hidden }, guardReason: { _ in nil }, watch: false)
        model.load(pwd: URL(fileURLWithPath: "/tmp/mc-focus"))
        await model.loadingTask?.value
        guard case .noFlowFile = model.state else { Issue.record("\(model.state)"); return }
        var closes = 0, tabs = 0
        let panel = MindControl.Panel(model: model, onClose: { closes += 1 }, openTab: { _, _ in tabs += 1 })
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: panel)
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<50 where !(window.firstResponder is MindControl.PanelKeyView) {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(window.firstResponder is MindControl.PanelKeyView)
        func send(_ characters: String, code: UInt16) throws {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                window.sendEvent(try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                               windowNumber: window.windowNumber, context: nil, characters: characters,
                                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)))
            }
        }
        try send("\u{1b}", code: 53)
        #expect(closes == 1)
        try send("\r", code: 36)
        // Draft checks for claude in a login shell first; then it opens a tab or shows the prompt to copy.
        for _ in 0..<400 where tabs == 0 && window.attachedSheet == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(tabs == 1 || window.attachedSheet != nil)
        if let sheet = window.attachedSheet { window.endSheet(sheet) }
    }
}
#endif
