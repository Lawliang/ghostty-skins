import Foundation
import simd

extension MindControl {
    /// A short, bounded force pass over a laid-out graph: pushes apart nodes closer than `minSpacing`
    /// and gently pulls files that use each other together. Folders are anchors; the root never moves.
    enum Relaxation {
        static let iterations = 60
        static let minSpacing: Float = 0.45
        static let springRestLength: Float = 2.5
        static let springStrength: Float = 0.02
        static let folderMobility: Float = 0.2
        static let maxMovePerStep: Float = 1.0
        static let settledMove: Float = 0.001

        /// The 13 neighbour-cell offsets "after" (0,0,0), so each pair of adjacent cells is visited once.
        private static let forwardOffsets: [(Int32, Int32, Int32)] = {
            var offsets: [(Int32, Int32, Int32)] = []
            for dx: Int32 in -1...1 { for dy: Int32 in -1...1 { for dz: Int32 in -1...1 {
                if (dx, dy, dz) > (0, 0, 0) { offsets.append((dx, dy, dz)) }
            } } }
            return offsets
        }()

        static func relax(_ graph: Graph, shouldStop: () -> Bool = { Task.isCancelled }) throws -> Graph {
            let count = graph.nodes.count
            guard count > 1 else { return graph }

            var positions = graph.nodes.map(\.position)
            let mobility: [Float] = graph.nodes.map { node in
                switch node.kind {
                case .root: 0
                case .folder: folderMobility
                case .source, .document: 1
                }
            }
            var index: [String: Int] = [:]
            for (i, node) in graph.nodes.enumerated() { index[node.id] = i }
            let springs: [(Int, Int)] = graph.edges.compactMap { edge in
                guard edge.kind == .uses, let a = index[edge.from], let b = index[edge.to] else { return nil }
                return (a, b)
            }

            var delta = [SIMD3<Float>](repeating: .zero, count: count)
            // Cell list: (cell key, node) pairs sorted by key, plus each key's range in that array.
            var entries = [(key: Int64, node: Int32)](repeating: (0, 0), count: count)
            var ranges: [Int64: Range<Int>] = [:]

            func push(_ i: Int, _ j: Int) {
                var offset = positions[i] - positions[j]
                var distance = simd_length(offset)
                guard distance < minSpacing else { return }
                if distance < 1e-5 {
                    // Coincident nodes: separate along a direction that depends only on the pair.
                    offset = SIMD3(sin(Float(i * 7 + j)), cos(Float(i * 13 + j)), sin(Float(i + j * 3)))
                    distance = 1e-5
                }
                let shove = offset / max(simd_length(offset), 1e-5) * ((minSpacing - distance) * 0.5)
                delta[i] += shove
                delta[j] -= shove
            }

            for iteration in 0..<iterations {
                if shouldStop() { throw CancellationError() }
                let step = 0.5 + (0.05 - 0.5) * Float(iteration) / Float(iterations - 1)
                for i in 0..<count { delta[i] = .zero }

                for i in 0..<count { entries[i] = (key(cell(positions[i])), Int32(i)) }
                // Sorting by (key, node) keeps the summation order, and so the result, deterministic.
                entries.sort { $0.key != $1.key ? $0.key < $1.key : $0.node < $1.node }
                ranges.removeAll(keepingCapacity: true)
                var start = 0
                while start < count {
                    var end = start + 1
                    while end < count, entries[end].key == entries[start].key { end += 1 }
                    ranges[entries[start].key] = start..<end
                    start = end
                }

                start = 0
                while start < count {
                    let cellKey = entries[start].key
                    let members = ranges[cellKey]!
                    for a in members {
                        for b in (a + 1)..<members.upperBound { push(Int(entries[a].node), Int(entries[b].node)) }
                    }
                    let (cx, cy, cz) = unpack(cellKey)
                    for (dx, dy, dz) in forwardOffsets {
                        guard let others = ranges[key((cx + dx, cy + dy, cz + dz))] else { continue }
                        for a in members { for b in others { push(Int(entries[a].node), Int(entries[b].node)) } }
                    }
                    start = members.upperBound
                }

                for (a, b) in springs {
                    let offset = positions[b] - positions[a]
                    let distance = simd_length(offset)
                    guard distance > 1e-5 else { continue }
                    let pull = offset / distance * ((distance - springRestLength) * springStrength)
                    delta[a] += pull
                    delta[b] -= pull
                }

                var largestMove: Float = 0
                for i in 0..<count where mobility[i] > 0 {
                    let move = delta[i] * (2 * step * mobility[i])
                    let length = simd_length(move)
                    positions[i] += length > maxMovePerStep ? move / length * maxMovePerStep : move
                    largestMove = max(largestMove, min(length, maxMovePerStep))
                }
                // Settled: nothing overlaps and the springs are at rest (within a thousandth).
                if largestMove < settledMove { break }
            }

            var relaxed = graph
            for i in 0..<count { relaxed.nodes[i].position = positions[i] }
            return relaxed
        }

        private static func cell(_ p: SIMD3<Float>) -> (Int32, Int32, Int32) {
            (Int32((p.x / minSpacing).rounded(.down)), Int32((p.y / minSpacing).rounded(.down)), Int32((p.z / minSpacing).rounded(.down)))
        }

        private static let bias: Int64 = 1 << 20
        private static let mask: Int64 = (1 << 21) - 1

        private static func key(_ c: (Int32, Int32, Int32)) -> Int64 {
            ((Int64(c.0) + bias) & mask) << 42 | ((Int64(c.1) + bias) & mask) << 21 | ((Int64(c.2) + bias) & mask)
        }

        private static func unpack(_ k: Int64) -> (Int32, Int32, Int32) {
            (Int32((k >> 42) & mask - bias), Int32((k >> 21) & mask - bias), Int32(k & mask - bias))
        }
    }
}
