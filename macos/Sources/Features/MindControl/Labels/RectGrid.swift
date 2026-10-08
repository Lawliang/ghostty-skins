import CoreGraphics

extension MindControl {
    /// Rectangles bucketed into a coarse grid for quick overlap tests.
    struct RectGrid {
        let cell: CGFloat
        private var buckets: [Int64: [CGRect]] = [:]

        init(cell: CGFloat) { self.cell = cell }

        func intersects(_ rect: CGRect) -> Bool {
            let (xs, ys) = span(of: rect)
            for x in xs {
                for y in ys {
                    if let bucket = buckets[key(x, y)], bucket.contains(where: { $0.intersects(rect) }) { return true }
                }
            }
            return false
        }

        mutating func insert(_ rect: CGRect) {
            let (xs, ys) = span(of: rect)
            for x in xs { for y in ys { buckets[key(x, y), default: []].append(rect) } }
        }

        private func span(of rect: CGRect) -> (ClosedRange<Int64>, ClosedRange<Int64>) {
            (Int64((rect.minX / cell).rounded(.down))...Int64((rect.maxX / cell).rounded(.down)),
             Int64((rect.minY / cell).rounded(.down))...Int64((rect.maxY / cell).rounded(.down)))
        }

        private func key(_ x: Int64, _ y: Int64) -> Int64 { x << 32 ^ (y & 0xFFFF_FFFF) }
    }
}
