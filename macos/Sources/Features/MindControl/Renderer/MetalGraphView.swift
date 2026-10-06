import SwiftUI
import MetalKit

extension MindControl {
    /// MTKView that turns mouse and trackpad input into camera moves, hover and pins,
    /// and draws node labels in an overlay.
    final class GraphMTKView: MTKView {
        var renderer: Renderer?
        var inspector: Inspector?
        var onEscape: (() -> Void)?

        private let labels = LabelOverlayView()
        private var screenNodes: [ScreenNode] = []
        private var mouseDownPoint: CGPoint?
        private var trackingArea: NSTrackingArea?

        override init(frame: CGRect, device: MTLDevice?) {
            super.init(frame: frame, device: device)
            labels.frame = bounds
            labels.autoresizingMask = [.width, .height]
            addSubview(labels)
        }

        required init(coder: NSCoder) {
            super.init(coder: coder)
            labels.frame = bounds
            labels.autoresizingMask = [.width, .height]
            addSubview(labels)
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Take keyboard focus so Esc reaches us while the panel is open.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func keyDown(with event: NSEvent) {
            // Esc unpins first, then closes. Other keys are swallowed so the panel doesn't beep;
            // menu shortcuts still arrive via performKeyEquivalent.
            guard event.keyCode == 53 else { return }
            if inspector?.escape() == true { return }
            onEscape?()
        }

        override func mouseMoved(with event: NSEvent) {
            inspector?.hover(pick(event))
        }

        override func mouseExited(with event: NSEvent) {
            inspector?.hover(nil)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            renderer?.camera.beginDrag()
        }

        override func mouseDragged(with event: NSEvent) {
            renderer?.camera.drag(dx: Float(event.deltaX), dy: Float(event.deltaY))
        }

        override func mouseUp(with event: NSEvent) {
            renderer?.camera.endDrag()
            let point = convert(event.locationInWindow, from: nil)
            if let start = mouseDownPoint, hypot(point.x - start.x, point.y - start.y) < 3 {
                inspector?.click(pick(event))
            }
            mouseDownPoint = nil
        }

        override func scrollWheel(with event: NSEvent) {
            let step: Float = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            renderer?.camera.zoom(by: exp(-Float(event.scrollingDeltaY) * step))
        }

        override func magnify(with event: NSEvent) {
            renderer?.camera.zoom(by: 1 / max(0.1, 1 + Float(event.magnification)))
        }

        private func pick(_ event: NSEvent) -> Int? {
            Picking.nearest(to: convert(event.locationInWindow, from: nil), in: screenNodes)
        }

        /// After each frame: re-project nodes (for picking) and re-plan labels.
        func frameDidRender() {
            guard let renderer, let camera = renderer.lastCamera else { return }
            screenNodes = Picking.project(positions: renderer.nodePositions, radii: renderer.nodeRadii, camera: camera)
            let focus = inspector?.focus
            let neighbours = focus.map { Set(renderer.neighbours(of: $0)) } ?? []
            labels.show(LabelPlanner.plan(.init(screen: screenNodes, nodes: renderer.nodes, focus: focus,
                                                neighbours: neighbours, viewport: bounds.size,
                                                measure: LabelOverlayView.measure)))
        }
    }

    struct MetalGraphView: NSViewRepresentable {
        let renderer: Renderer
        let inspector: Inspector
        var onEscape: (() -> Void)?

        func makeNSView(context: Context) -> GraphMTKView {
            let view = GraphMTKView(frame: .zero, device: renderer.device)
            view.renderer = renderer
            view.inspector = inspector
            view.onEscape = onEscape
            view.delegate = renderer
            view.colorPixelFormat = Renderer.outputFormat
            view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            view.framebufferOnly = true
            view.preferredFramesPerSecond = 120
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderer.onFrame = { [weak view] in view?.frameDidRender() }
            inspector.onFocusChange = { [weak renderer] focus in renderer?.setFocus(focus) }
            return view
        }

        func updateNSView(_ view: GraphMTKView, context: Context) {
            view.onEscape = onEscape
        }
    }
}
