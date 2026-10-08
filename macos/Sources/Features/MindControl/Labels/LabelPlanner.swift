import CoreGraphics
import Foundation

extension MindControl {
    struct LabelCandidate: Equatable {
        let id: String
        let text: String
        /// View points, top-left origin. The label's left-middle when `leading`, else its centre.
        let anchor: CGPoint
        let leading: Bool
        let fontSize: CGFloat
        let bold: Bool
        let opacity: CGFloat
        /// Lower wins when two labels would overlap.
        let priority: Int
        let background: Bool
        let maxWidth: CGFloat?
    }

    /// Chooses which labels show: by priority, never overlapping, on screen, within the budget.
    enum LabelPlanner {
        static let budget = 150
        /// Larger than any view. Every RectGrid rect lies inside the viewport, so this bounds its Int64 cells (which
        /// trap on overflow) and how many cells one label can cover.
        static let maxViewportSide: CGFloat = 100_000

        /// A viewport that is not finite, has no area, or is larger than `maxViewportSide` gets no labels. A
        /// candidate whose anchor or measured size is not finite (or is negative) is skipped.
        static func plan(_ candidates: [LabelCandidate], viewport: CGSize, measure: (String, CGFloat, Bool) -> CGSize) -> [PlacedLabel] {
            guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0,
                  viewport.width <= maxViewportSide, viewport.height <= maxViewportSide else { return [] }
            let screen = CGRect(origin: .zero, size: viewport)
            let ordered = candidates.enumerated().sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }.map(\.element)
            var occupied = RectGrid(cell: 64)
            var placed: [PlacedLabel] = []
            for candidate in ordered {
                if placed.count >= budget { break }
                guard candidate.opacity > 0.02, !candidate.text.isEmpty,
                      candidate.anchor.x.isFinite, candidate.anchor.y.isFinite,
                      let fit = fitted(candidate, measure: measure) else { continue }
                let origin = candidate.leading
                    ? CGPoint(x: candidate.anchor.x, y: candidate.anchor.y - fit.size.height / 2)
                    : CGPoint(x: candidate.anchor.x - fit.size.width / 2, y: candidate.anchor.y - fit.size.height / 2)
                let frame = CGRect(origin: origin, size: fit.size)
                let footprint = candidate.background
                    ? frame.insetBy(dx: -LabelOverlayView.pillPadding.width, dy: -LabelOverlayView.pillPadding.height)
                    : frame
                guard isFinite(footprint), footprint.maxX > 0, footprint.minX < viewport.width,
                      footprint.maxY > 0, footprint.minY < viewport.height else { continue }
                // Only the on-screen part can collide, and clipping keeps every RectGrid rect within the viewport.
                let visible = footprint.intersection(screen)
                guard !occupied.intersects(visible) else { continue }
                occupied.insert(visible)
                placed.append(PlacedLabel(id: candidate.id, text: fit.text, frame: frame, fontSize: candidate.fontSize,
                                          isBold: candidate.bold, opacity: candidate.opacity, hasBackground: candidate.background))
            }
            return placed
        }

        /// The text and its size, cut to the longest prefix that fits `maxWidth` with "…". Nil when the size is not
        /// finite and non-negative, `maxWidth` leaves no room, or nothing but the "…" would fit.
        private static func fitted(_ candidate: LabelCandidate, measure: (String, CGFloat, Bool) -> CGSize) -> (text: String, size: CGSize)? {
            func size(_ text: String) -> CGSize? {
                let size = measure(text, candidate.fontSize, candidate.bold)
                return size.width.isFinite && size.height.isFinite && size.width >= 0 && size.height >= 0 ? size : nil
            }
            guard let whole = size(candidate.text) else { return nil }
            guard let maxWidth = candidate.maxWidth else { return (candidate.text, whole) }
            guard maxWidth > 12 else { return nil }
            if whole.width <= maxWidth { return (candidate.text, whole) }
            // Binary search on the prefix length: labels are re-planned every frame, and measuring is the costly part.
            let characters = Array(candidate.text)
            var best: (text: String, size: CGSize)?
            var low = 1, high = characters.count - 1
            while low <= high {
                let count = (low + high) / 2
                let text = String(characters[..<count]) + "…"
                if let measured = size(text), measured.width <= maxWidth {
                    best = (text, measured)
                    low = count + 1
                } else {
                    high = count - 1
                }
            }
            return best
        }

        /// Finite edges: an anchor and a size can each be finite and still add up to infinity.
        private static func isFinite(_ rect: CGRect) -> Bool {
            rect.minX.isFinite && rect.maxX.isFinite && rect.minY.isFinite && rect.maxY.isFinite
        }
    }
}
