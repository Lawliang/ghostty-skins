import SwiftUI
import MetalKit

extension MindControl {
    /// MTKView that turns mouse and trackpad input into camera moves.
    final class GraphMTKView: MTKView {
        var renderer: Renderer?
        var onEscape: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            // Esc closes; other keys are swallowed so the open panel doesn't beep.
            // Menu shortcuts still work: they arrive via performKeyEquivalent first.
            if event.keyCode == 53 {
                onEscape?()
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Take keyboard focus so Esc reaches us while the panel is open.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            renderer?.camera.beginDrag()
        }

        override func mouseDragged(with event: NSEvent) {
            renderer?.camera.drag(dx: Float(event.deltaX), dy: Float(event.deltaY))
        }

        override func mouseUp(with event: NSEvent) {
            renderer?.camera.endDrag()
        }

        override func scrollWheel(with event: NSEvent) {
            let step: Float = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            renderer?.camera.zoom(by: exp(-Float(event.scrollingDeltaY) * step))
        }

        override func magnify(with event: NSEvent) {
            renderer?.camera.zoom(by: 1 / max(0.1, 1 + Float(event.magnification)))
        }
    }

    struct MetalGraphView: NSViewRepresentable {
        let renderer: Renderer
        var onEscape: (() -> Void)?

        func makeNSView(context: Context) -> GraphMTKView {
            let view = GraphMTKView(frame: .zero, device: renderer.device)
            view.renderer = renderer
            view.onEscape = onEscape
            view.delegate = renderer
            view.colorPixelFormat = Renderer.outputFormat
            view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            view.framebufferOnly = true
            view.preferredFramesPerSecond = 120
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            return view
        }

        func updateNSView(_ view: GraphMTKView, context: Context) {
            view.onEscape = onEscape
        }
    }
}
