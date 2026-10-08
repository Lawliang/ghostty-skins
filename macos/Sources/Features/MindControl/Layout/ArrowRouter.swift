import CoreGraphics

extension MindControl {
    /// A cubic Bézier in world points.
    struct Curve: Equatable {
        var p0: CGPoint
        var p1: CGPoint
        var p2: CGPoint
        var p3: CGPoint

        func point(at t: CGFloat) -> CGPoint {
            let s = 1 - t
            let a = s * s * s, b = 3 * s * s * t, c = 3 * s * t * t, d = t * t * t
            return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }

        func tangent(at t: CGFloat) -> CGVector {
            let s = 1 - t
            let a = 3 * s * s, b = 6 * s * t, c = 3 * t * t
            return CGVector(dx: a * (p1.x - p0.x) + b * (p2.x - p1.x) + c * (p3.x - p2.x),
                            dy: a * (p1.y - p0.y) + b * (p2.y - p1.y) + c * (p3.y - p2.y))
        }

        var mid: CGPoint { point(at: 0.5) }

        /// Approximate distance from `p` to the curve, sampled at 32 segments.
        func distance(to p: CGPoint) -> CGFloat {
            var best = CGFloat.greatestFiniteMagnitude
            var previous = p0
            for i in 1...32 {
                let next = point(at: CGFloat(i) / 32)
                best = min(best, Self.segmentDistance(p, previous, next))
                previous = next
            }
            return best
        }

        private static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }
    }

    /// Curves for arrow specs: out of the facing edges of the two boxes, with parallel arrows between
    /// the same two boxes spread apart so a flow and its return never overlap.
    enum ArrowRouter {
        static func curves(for layout: MapLayout) -> [String: Curve] {
            var rects: [String: CGRect] = [:]
            for box in layout.boxes { rects[box.id] = box.rect }
            var groups: [String: [MapLayout.ArrowSpec]] = [:]
            var keys: [String] = []
            for arrow in layout.arrows {
                let pair = [arrow.from, arrow.to].sorted()
                let key = "\(arrow.level.rawValue)|\(pair[0])|\(pair[1])"
                if groups[key] == nil { keys.append(key) }
                groups[key, default: []].append(arrow)
            }
            var curves: [String: Curve] = [:]
            for key in keys {
                let group = groups[key] ?? []
                for (index, arrow) in group.enumerated() {
                    guard let a = rects[arrow.from], let b = rects[arrow.to] else { continue }
                    let offset = (CGFloat(index) - CGFloat(group.count - 1) / 2) * LayoutMetrics.parallelSpacing
                    curves[arrow.id] = route(from: a, to: b, offset: offset)
                }
            }
            return curves
        }

        static func route(from a: CGRect, to b: CGRect, offset: CGFloat) -> Curve {
            let separatedHorizontally = b.minX > a.maxX || b.maxX < a.minX
            if separatedHorizontally {
                let sign: CGFloat = b.midX >= a.midX ? 1 : -1
                let dy = clamp(offset, a, b, \.height)
                let start = CGPoint(x: sign > 0 ? a.maxX : a.minX, y: a.midY + dy)
                let end = CGPoint(x: sign > 0 ? b.minX : b.maxX, y: b.midY + dy)
                let k = max(40, abs(end.x - start.x) * 0.45)
                return Curve(p0: start, p1: CGPoint(x: start.x + sign * k, y: start.y),
                             p2: CGPoint(x: end.x - sign * k, y: end.y), p3: end)
            }
            let sign: CGFloat = b.midY >= a.midY ? 1 : -1
            let dx = clamp(offset, a, b, \.width)
            let start = CGPoint(x: a.midX + dx, y: sign > 0 ? a.maxY : a.minY)
            let end = CGPoint(x: b.midX + dx, y: sign > 0 ? b.minY : b.maxY)
            let k = max(30, abs(end.y - start.y) * 0.45)
            return Curve(p0: start, p1: CGPoint(x: start.x, y: start.y + sign * k),
                         p2: CGPoint(x: end.x, y: end.y - sign * k), p3: end)
        }

        private static func clamp(_ offset: CGFloat, _ a: CGRect, _ b: CGRect, _ side: KeyPath<CGRect, CGFloat>) -> CGFloat {
            let limit = max(0, min(a[keyPath: side], b[keyPath: side]) / 2 - 4)
            return max(-limit, min(limit, offset))
        }
    }
}
