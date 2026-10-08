#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Ghostty

/// A surface's local mouse-down monitor focuses the surface only when the click really lands on it: views layered
/// over it (the MindControl panel, the Skins picker) keep their clicks. A real SurfaceView needs a running Ghostty
/// app, so these tests check the decision, `Ghostty.SurfaceView.clickLands(on:atWindowPoint:)`, with stand-in views.
@MainActor
struct SurfaceClickTests {
    private func window(_ size: CGSize = CGSize(width: 400, height: 300)) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func aClickOnAnOverlayIsNotTheSurfaces() {
        let window = window()
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = content
        let left = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        let right = NSView(frame: CGRect(x: 200, y: 0, width: 200, height: 300))
        let inner = NSView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        left.addSubview(inner)
        content.addSubview(left)
        content.addSubview(right)
        // An overlay sibling over the right half of the left pane and all of the right pane.
        let overlay = NSView(frame: CGRect(x: 100, y: 0, width: 300, height: 300))
        content.addSubview(overlay)
        func lands(_ view: NSView, _ x: CGFloat, _ y: CGFloat) -> Bool {
            Ghostty.SurfaceView.clickLands(on: view, atWindowPoint: content.convert(CGPoint(x: x, y: y), to: nil))
        }
        #expect(lands(left, 50, 150))
        #expect(lands(left, 20, 20), "a subview of the surface counts as the surface")
        #expect(!lands(left, 150, 150))
        #expect(!lands(right, 300, 150))
        // Split panes without an overlay: each click is its own pane's.
        overlay.removeFromSuperview()
        #expect(lands(right, 300, 150))
        #expect(!lands(left, 300, 150))
    }

    private struct Pane: NSViewRepresentable {
        let view: NSView
        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    /// The real arrangement: the terminal pane is an NSView inside SwiftUI, and the panel is SwiftUI content over it.
    @Test func swiftUIContentOverTheSurfaceKeepsItsClicks() async throws {
        let window = window()
        let surface = NSView()
        let host = NSHostingView(rootView: ZStack(alignment: .trailing) {
            Pane(view: surface)
            Color.black.frame(width: 200)
        }.frame(width: 400, height: 300))
        window.contentView = host
        for _ in 0..<20 where surface.window == nil || surface.frame.width == 0 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        func lands(_ x: CGFloat) -> Bool {
            let inHost = CGPoint(x: x, y: host.isFlipped ? 150 : host.bounds.height - 150)
            return Ghostty.SurfaceView.clickLands(on: surface, atWindowPoint: host.convert(inHost, to: nil))
        }
        #expect(lands(100))
        #expect(!lands(300))
    }

    @Test func aClickOutsideTheContentIsNobodys() {
        let window = window()
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = content
        let surface = NSView(frame: content.bounds)
        content.addSubview(surface)
        #expect(!Ghostty.SurfaceView.clickLands(on: surface, atWindowPoint: CGPoint(x: -50, y: -50)))
        let detached = NSView(frame: content.bounds)
        #expect(!Ghostty.SurfaceView.clickLands(on: detached, atWindowPoint: CGPoint(x: 50, y: 50)))
    }
}
#endif
