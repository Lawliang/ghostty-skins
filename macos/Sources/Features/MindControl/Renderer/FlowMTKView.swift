import MetalKit
import SwiftUI

extension MindControl {
    /// The Metal view: turns mouse, trackpad and keys into MapController calls and hosts the label overlay.
    final class FlowMTKView: MTKView {
        /// Scroll-wheel zoom direction: +1 zooms in when `scrollingDeltaY` is positive (scrolling up). Checked by
        /// hand in Task 19; flip to -1 if it feels inverted.
        static let scrollZoomSign: CGFloat = 1

        weak var controller: MapController?
        private let labels = LabelOverlayView()
        private var shownLabels: [PlacedLabel] = []
        private var lastPoint: CGPoint?
        private var downPoint: CGPoint?
        private var dragSystem: String?
        private var moved = false

        override init(frame: CGRect, device: MTLDevice?) {
            super.init(frame: frame, device: device)
            setUpLabels()
        }

        required init(coder: NSCoder) {
            super.init(coder: coder)
            setUpLabels()
        }

        private func setUpLabels() {
            labels.frame = bounds
            labels.autoresizingMask = [.width, .height]
            addSubview(labels)
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Take keyboard focus so Esc, F and typing reach the map while the panel is open.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            guard let controller else { return }
            let first = controller.viewSize == .zero
            controller.viewSize = newSize
            if first { controller.fit(animated: false) }
        }

        /// View points with a top-left origin, the camera's convention.
        private func point(_ event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            return CGPoint(x: p.x, y: bounds.height - p.y)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // ⌘F searches while the map has keyboard focus.
            if window?.firstResponder === self, let controller,
               event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
               event.charactersIgnoringModifiers?.lowercased() == "f" {
                controller.beginSearch(with: "")
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        /// Esc, F and typing (letters, digits, space, ".") are the map's; every other key goes up the responder
        /// chain, so Tab moves keyboard focus and menu shortcuts still work.
        override func keyDown(with event: NSEvent) {
            guard let controller else { return super.keyDown(with: event) }
            if event.keyCode == 53 {
                if !controller.escape() { controller.onClose() }
                return
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty, let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
                return super.keyDown(with: event)
            }
            if characters.lowercased() == "f", controller.query.isEmpty, controller.focusTarget != nil {
                controller.enterFocus()
            } else if characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "." }) {
                controller.beginSearch(with: characters)
            } else {
                super.keyDown(with: event)
            }
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            guard let controller else { return }
            let p = point(event)
            downPoint = p
            lastPoint = p
            moved = false
            dragSystem = controller.dragTarget(at: p)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let controller, let last = lastPoint, let down = downPoint else { return }
            let p = point(event)
            if hypot(p.x - down.x, p.y - down.y) > 3 { moved = true }
            guard moved else { return }
            let delta = CGSize(width: p.x - last.x, height: p.y - last.y)
            if let id = dragSystem { controller.drag(system: id, byScreen: delta) } else { controller.pan(by: delta) }
            lastPoint = p
        }

        override func mouseUp(with event: NSEvent) {
            guard let controller else { return }
            let p = point(event)
            if moved, let id = dragSystem {
                controller.endDrag(id)
            } else if !moved {
                if event.clickCount >= 2 { controller.doubleClick(at: p) } else { controller.click(at: p) }
            }
            downPoint = nil
            lastPoint = nil
            dragSystem = nil
            moved = false
        }

        override func scrollWheel(with event: NSEvent) {
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            controller?.zoom(by: exp(Self.scrollZoomSign * event.scrollingDeltaY * step), about: point(event))
        }

        override func magnify(with event: NSEvent) {
            controller?.zoom(by: max(0.1, 1 + event.magnification), about: point(event))
        }

        /// After each frame: show the labels for the current camera, touching the layers only when they changed.
        func frameDidRender() {
            guard let controller else { return }
            let next = controller.labels()
            guard next != shownLabels else { return }
            shownLabels = next
            labels.show(next)
        }
    }

    struct FlowMetalView: NSViewRepresentable {
        let renderer: Renderer
        let controller: MapController

        func makeNSView(context: Context) -> FlowMTKView {
            let view = FlowMTKView(frame: .zero, device: renderer.device)
            view.controller = controller
            view.delegate = renderer
            view.colorPixelFormat = Renderer.outputFormat
            view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            view.framebufferOnly = true
            view.preferredFramesPerSecond = 120
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderer.onFrame = { [weak view] in view?.frameDidRender() }
            controller.focusMap = { [weak view] in
                guard let view, let window = view.window else { return }
                window.makeFirstResponder(view)
            }
            controller.attach(renderer)
            return view
        }

        func updateNSView(_ view: FlowMTKView, context: Context) {
            view.controller = controller
        }
    }
}
