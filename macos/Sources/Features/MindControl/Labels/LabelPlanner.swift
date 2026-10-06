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
            let key: CGFloat     // lower first within a tier
        }

        static func plan(_ input: Input) -> [PlacedLabel] {
            var candidates: [Candidate] = []
            for s in input.screen {
                let node = input.nodes[s.index]
                if s.index == input.focus {
                    candidates.append(Candidate(screen: s, tier: 0, key: 0))
                } else if input.neighbours.contains(s.index) {
                    candidates.append(Candidate(screen: s, tier: 1, key: -s.radius))
                } else if node.kind == .folder || node.kind == .root {
                    candidates.append(Candidate(screen: s, tier: 2, key: -CGFloat(node.descendantFiles)))
                } else if s.radius >= fileShowRadius {
                    candidates.append(Candidate(screen: s, tier: 3, key: -s.radius))
                }
            }
            candidates.sort { a, b in
                if a.tier != b.tier { return a.tier < b.tier }
                if a.key != b.key { return a.key < b.key }
                return a.screen.index < b.screen.index
            }

            let highlighting = input.focus != nil
            var placed: [PlacedLabel] = []
            var occupied = RectGrid(cell: 64)
            for candidate in candidates {
                if placed.count >= budget { break }
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
            keys(for: rect).contains { key in buckets[key]?.contains { $0.intersects(rect) } ?? false }
        }

        mutating func insert(_ rect: CGRect) {
            for key in keys(for: rect) { buckets[key, default: []].append(rect) }
        }

        private func keys(for rect: CGRect) -> [Int64] {
            let x0 = Int64((rect.minX / cell).rounded(.down)), x1 = Int64((rect.maxX / cell).rounded(.down))
            let y0 = Int64((rect.minY / cell).rounded(.down)), y1 = Int64((rect.maxY / cell).rounded(.down))
            var keys: [Int64] = []
            for x in x0...x1 { for y in y0...y1 { keys.append(x << 32 ^ (y & 0xFFFF_FFFF)) } }
            return keys
        }
    }
}
