import CoreGraphics
import Foundation

extension MindControl {
    struct PlacedLabel: Equatable {
        let index: Int
        let text: String
        /// View points, AppKit bottom-left origin.
        let frame: CGRect
        let fontSize: CGFloat
        let isBold: Bool
        let opacity: CGFloat
    }

    /// Chooses which labels show and where: focus first, then its neighbours, folders by size, then
    /// files that are close enough to read. Never overlaps two labels and never exceeds the budget.
    enum LabelPlanner {
        static let budget = 150
        static let fileShowRadius: CGFloat = 2.5
        static let fileFullRadius: CGFloat = 5
        static let gap: CGFloat = 4
        /// Candidates are in priority order; beyond this many tries the rest wouldn't fit anyway.
        static let maxAttempts = budget * 6

        struct Input {
            let screen: [ScreenNode]
            /// Indexed by `ScreenNode.index`.
            let nodes: [GraphNode]
            let focus: Int?
            let neighbours: Set<Int>
            let viewport: CGSize
            /// Measures text (string, font size, bold); injected so tests don't depend on fonts.
            let measure: (String, CGFloat, Bool) -> CGSize
        }

        private struct Candidate {
            let screen: ScreenNode
            let tier: Int        // 0 focus, 1 neighbour, 2 folder, 3 file
        }

        static func plan(_ input: Input) -> [PlacedLabel] {
            // One packed sort key per candidate — tier, then size (bigger first), then index — so the
            // sort compares plain integers (a closure comparator was the frame's biggest cost).
            func rank(_ value: CGFloat) -> UInt64 {
                let maxRank: CGFloat = 0x0FFF_FFFF
                return UInt64(max(0, min(maxRank, maxRank - value)))
            }
            var keys: [UInt64] = []
            keys.reserveCapacity(input.screen.count)
            for (position, s) in input.screen.enumerated() {
                let node = input.nodes[s.index]
                let tier: UInt64
                let order: UInt64
                if s.index == input.focus {
                    (tier, order) = (0, 0)
                } else if input.neighbours.contains(s.index) {
                    (tier, order) = (1, rank(s.radius * 1_000))
                } else if node.kind == .folder || node.kind == .root {
                    (tier, order) = (2, rank(CGFloat(node.descendantFiles)))
                } else if s.radius >= fileShowRadius {
                    (tier, order) = (3, rank(s.radius * 1_000))
                } else {
                    continue
                }
                keys.append(tier << 60 | order << 32 | UInt64(position))
            }
            // C's qsort is always optimised; Swift's generic sort is slow in Debug builds, where this
            // runs every frame while developing.
            keys.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                qsort(base, buffer.count, MemoryLayout<UInt64>.stride) { a, b in
                    let x = a!.load(as: UInt64.self), y = b!.load(as: UInt64.self)
                    return x < y ? -1 : (x > y ? 1 : 0)
                }
            }
            let candidates = keys.map { key in
                Candidate(screen: input.screen[Int(key & 0xFFFF_FFFF)], tier: Int(key >> 60))
            }

            let highlighting = input.focus != nil
            var placed: [PlacedLabel] = []
            var occupied = RectGrid(cell: 64)
            for (attempt, candidate) in candidates.enumerated() {
                if placed.count >= budget || attempt >= maxAttempts { break }
                let s = candidate.screen
                let node = input.nodes[s.index]
                let isFolder = node.kind == .folder || node.kind == .root
                let text = candidate.tier == 0 && node.id != ConeTreeLayout.rootID ? node.id : node.label
                let fontSize: CGFloat = isFolder ? 12 + min(2, CGFloat(log10(Double(max(1, node.descendantFiles))))) : 10.5
                let size = input.measure(text, fontSize, isFolder)
                let frame = CGRect(x: s.point.x + s.radius + gap, y: s.point.y - size.height / 2,
                                   width: size.width, height: size.height)
                guard frame.maxX > 0, frame.minX < input.viewport.width,
                      frame.maxY > 0, frame.minY < input.viewport.height,
                      !occupied.intersects(frame) else { continue }

                var opacity: CGFloat = isFolder
                    ? 0.9
                    : min(1, max(0, (s.radius - fileShowRadius) / (fileFullRadius - fileShowRadius))) * 0.85
                if candidate.tier <= 1 {
                    opacity = max(opacity, 0.9)
                } else if highlighting {
                    opacity *= 0.35
                }
                guard opacity > 0.02 else { continue }

                occupied.insert(frame)
                placed.append(PlacedLabel(index: s.index, text: text, frame: frame, fontSize: fontSize,
                                          isBold: isFolder, opacity: opacity))
            }
            return placed
        }
    }

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
