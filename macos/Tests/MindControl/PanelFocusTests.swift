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
        // Tab stops here too: the window's key-view loop would hand focus to the terminal.
        view.keyDown(with: try key("\t", code: 48))
        view.keyDown(with: try key("\t", code: 48, modifiers: .shift))
        #expect(recorder.keys.isEmpty)
        // Return can reach a default button, and keys with ⌘ or ⌃ go on up.
        view.keyDown(with: try key("\r", code: 36))
        view.keyDown(with: try key("k", code: 40, modifiers: .command))
        view.keyDown(with: try key("c", code: 8, modifiers: .control))
        #expect(recorder.keys == [36, 40, 8])
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
    /// The feature bar runs along the top of the map. Only its chips take the mouse; clicks and scrolls beside them
    /// reach the map.
    @Test func theMapGetsTheMouseBesideTheFeatureChips() async throws {
        let files = FlowFixtures.arcaSources
        let model = MindControl.Model(snapshot: { root in
            MindControl.FlowSnapshot(root: root, flowData: Data(FlowFixtures.arcaJSON.utf8), layoutData: nil,
                                     sourceFiles: files.keys.sorted(), read: { files[$0] })
        }, age: { _, _ in .hidden }, guardReason: { _ in nil }, watch: false)
        model.load(pwd: URL(fileURLWithPath: "/tmp/mc-hit"))
        await model.loadingTask?.value
        guard case .ready = model.state else { Issue.record("\(model.state)"); return }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MindControl.Panel(model: model, onClose: {}))
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        var mapView: MindControl.FlowMTKView?
        for _ in 0..<50 {
            host.layoutSubtreeIfNeeded()
            mapView = Self.find(MindControl.FlowMTKView.self, in: host)
            if mapView != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let map = try #require(mapView)
        // The feature bar's row: just below the map view's top edge, in the map view's (top-left) points.
        func hit(_ x: CGFloat, _ yFromMapTop: CGFloat) -> NSView? {
            let inMap = CGPoint(x: x, y: map.isFlipped ? yFromMapTop : map.bounds.height - yFromMapTop)
            return host.hitTest(map.convert(inMap, to: host.superview))
        }
        let beside = hit(700, 22)
        #expect(beside === map || beside?.isDescendant(of: map) == true, "hit \(String(describing: beside))")
        // The middle of the map, for comparison.
        #expect(hit(600, 400) === map || hit(600, 400)?.isDescendant(of: map) == true)
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let found = find(type, in: sub) { return found } }
        return nil
    }
    /// The holder takes focus back whenever the panel moves to another state without a map view, and only then.
    @Test func theHolderRetakesFocusWhenTheStateChanges() async throws {
        let project = MindControl.Model.Project(root: URL(fileURLWithPath: "/tmp/arca"), name: "arca", claudeBlockReason: nil)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content
        let other = NSTextView(frame: CGRect(x: 0, y: 0, width: 50, height: 20))
        content.addSubview(other)
        let host = NSHostingView(rootView: MindControl.PanelFocusHolder(onEscape: {}, state: .loading(project)))
        host.frame = content.bounds
        content.addSubview(host)
        func settle(until done: () -> Bool) async throws {
            for _ in 0..<50 where !done() {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        try await settle { window.firstResponder is MindControl.PanelKeyView }
        #expect(window.firstResponder is MindControl.PanelKeyView)
        // Something else took focus (the terminal, say); the same state again leaves it there.
        window.makeFirstResponder(other)
        host.rootView = MindControl.PanelFocusHolder(onEscape: {}, state: .loading(project))
        try await settle { false }
        #expect(window.firstResponder === other)
        // A new state takes it back.
        host.rootView = MindControl.PanelFocusHolder(onEscape: {}, state: .noFlowFile(project))
        try await settle { window.firstResponder is MindControl.PanelKeyView }
        #expect(window.firstResponder is MindControl.PanelKeyView)
        window.makeFirstResponder(other)
        host.rootView = MindControl.PanelFocusHolder(onEscape: {}, state: .invalid(project, []))
        try await settle { window.firstResponder is MindControl.PanelKeyView }
        #expect(window.firstResponder is MindControl.PanelKeyView)
    }
}
#endif
