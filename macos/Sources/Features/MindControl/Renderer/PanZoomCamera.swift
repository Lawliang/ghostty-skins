import CoreGraphics
import Foundation

extension MindControl {
    /// World (points, y down) ↔ view (points, top-left origin). `center` is the world point at the view's centre.
    ///
    /// `center` is always finite and `zoom` always within `minZoom…maxZoom`. Construction and assignment refuse a
    /// non-finite value (a NaN zoom or non-finite centre keeps the previous one) and clamp an out-of-range zoom,
    /// so nothing downstream divides by zero or draws NaN.
    struct PanZoomCamera: Equatable {
        static let minZoom: CGFloat = 0.08
        static let maxZoom: CGFloat = 4

        var center: CGPoint {
            didSet { if !Self.isFinite(center) { center = oldValue } }
        }

        var zoom: CGFloat {
            didSet { zoom = Self.clamped(zoom) ?? oldValue }
        }

        init(center: CGPoint = .zero, zoom: CGFloat = 1) {
            self.center = Self.isFinite(center) ? center : .zero
            self.zoom = Self.clamped(zoom) ?? 1
        }

        func toScreen(_ p: CGPoint, viewSize: CGSize) -> CGPoint {
            CGPoint(x: (p.x - center.x) * zoom + viewSize.width / 2, y: (p.y - center.y) * zoom + viewSize.height / 2)
        }

        func toWorld(_ p: CGPoint, viewSize: CGSize) -> CGPoint {
            CGPoint(x: (p.x - viewSize.width / 2) / zoom + center.x, y: (p.y - viewSize.height / 2) / zoom + center.y)
        }

        /// Zoom by `factor`, keeping the world point under `screen` where it is. A factor that is not a positive
        /// finite number, or a move that would leave the finite range, changes nothing.
        mutating func zoom(by factor: CGFloat, about screen: CGPoint, viewSize: CGSize) {
            guard factor.isFinite, factor > 0 else { return }
            let anchor = toWorld(screen, viewSize: viewSize)
            let next = PanZoomCamera(center: center, zoom: zoom * factor)
            let moved = next.toWorld(screen, viewSize: viewSize)
            let nextCenter = CGPoint(x: center.x + (anchor.x - moved.x), y: center.y + (anchor.y - moved.y))
            guard Self.isFinite(nextCenter) else { return }
            self = PanZoomCamera(center: nextCenter, zoom: next.zoom)
        }

        /// Drag by a screen delta (top-left origin): the world follows the pointer.
        mutating func pan(byScreen delta: CGSize) {
            // One assignment, so a non-finite result is refused whole rather than one axis at a time.
            center = CGPoint(x: center.x - delta.width / zoom, y: center.y - delta.height / zoom)
        }

        /// Centres `rect` and zooms so all of it shows with `margin` points to spare on each side. A margin that
        /// would leave no room on an axis is dropped on that axis. An empty (null) or non-finite rect gives the
        /// default camera. A view with no area yet, or a rect with none, gives zoom 1 on the rect's centre.
        static func fitting(_ rect: CGRect, in viewSize: CGSize, margin: CGFloat = 56) -> PanZoomCamera {
            guard !rect.isNull, !rect.isInfinite, rect.origin.x.isFinite, rect.origin.y.isFinite,
                  rect.size.width.isFinite, rect.size.height.isFinite else { return PanZoomCamera() }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            guard viewSize.width.isFinite, viewSize.height.isFinite, viewSize.width > 0, viewSize.height > 0 else {
                return PanZoomCamera(center: center, zoom: 1)
            }
            func room(_ length: CGFloat) -> CGFloat {
                let inside = length - 2 * margin
                return inside > 0 ? inside : length
            }
            var fits: [CGFloat] = []
            if rect.width > 0 { fits.append(room(viewSize.width) / rect.width) }
            if rect.height > 0 { fits.append(room(viewSize.height) / rect.height) }
            return PanZoomCamera(center: center, zoom: fits.min() ?? 1)
        }

        /// Centre linearly, zoom in log space so the motion feels even. `t` outside 0…1 is clamped; a NaN `t`
        /// (a zero-length animation's 0 / 0) gives `b`.
        static func interpolate(_ a: PanZoomCamera, _ b: PanZoomCamera, t: CGFloat) -> PanZoomCamera {
            if t.isNaN || t >= 1 { return b }
            if t <= 0 { return a }
            // a·(1−t) + b·t rather than a + (b−a)·t: b−a can overflow for far-apart centres.
            return PanZoomCamera(center: CGPoint(x: a.center.x * (1 - t) + b.center.x * t, y: a.center.y * (1 - t) + b.center.y * t),
                                 zoom: exp(log(a.zoom) * (1 - t) + log(b.zoom) * t))
        }

        private static func isFinite(_ p: CGPoint) -> Bool { p.x.isFinite && p.y.isFinite }

        /// `nil` for NaN; otherwise the zoom clamped to `minZoom…maxZoom` (±∞ included).
        private static func clamped(_ zoom: CGFloat) -> CGFloat? {
            zoom.isNaN ? nil : min(maxZoom, max(minZoom, zoom))
        }
    }
}
