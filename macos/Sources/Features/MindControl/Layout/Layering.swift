import Foundation

extension MindControl {
    /// A deterministic layered (Sugiyama-style) layout: break cycles, rank by longest path, then order
    /// each rank by barycenter sweeps to reduce crossings. Ties always fall back to ids.
    enum Layering {
        struct Edge: Hashable, Sendable {
            let from: String
            let to: String
        }

        struct Result: Equatable, Sendable {
            /// Column index, 0 on the left.
            let rank: [String: Int]
            /// Position within its rank, 0 at the top.
            let order: [String: Int]
            /// Edges that point against the columns to break cycles; drawn as return arrows.
            let reversed: Set<Edge>
            let layers: [[String]]
        }

        static let sweeps = 4

        static func layout(nodes: [String], edges: [Edge], pinFirst: Set<String> = [], pinLast: Set<String> = []) -> Result {
            let nodes = Array(Set(nodes)).sorted()
            guard !nodes.isEmpty else { return Result(rank: [:], order: [:], reversed: [], layers: []) }
            let nodeSet = Set(nodes)

            var unique: [Edge] = []
            var seen = Set<Edge>()
            for edge in edges.sorted(by: { ($0.from, $0.to) < ($1.from, $1.to) })
            where edge.from != edge.to && nodeSet.contains(edge.from) && nodeSet.contains(edge.to) && seen.insert(edge).inserted {
                unique.append(edge)
            }

            // 1. Break cycles: depth-first from sources, reversing edges back onto the stack.
            var successors: [String: [String]] = [:]
            for edge in unique { successors[edge.from, default: []].append(edge.to) }
            var state: [String: Int] = [:]   // 1 on the stack, 2 finished
            var reversed = Set<Edge>()
            func visit(_ node: String) {
                state[node] = 1
                for next in successors[node] ?? [] {
                    switch state[next] {
                    case nil: visit(next)
                    case 1: reversed.insert(Edge(from: node, to: next))
                    default: break
                    }
                }
                state[node] = 2
            }
            let hasIncoming = Set(unique.map(\.to))
            for node in nodes where !hasIncoming.contains(node) && state[node] == nil { visit(node) }
            for node in nodes where state[node] == nil { visit(node) }
            let dag = unique.map { reversed.contains($0) ? Edge(from: $0.to, to: $0.from) : $0 }

            // 2. Rank by longest path.
            var indegree = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
            var out: [String: [String]] = [:]
            for edge in dag {
                indegree[edge.to, default: 0] += 1
                out[edge.from, default: []].append(edge.to)
            }
            var rank = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
            var queue = nodes.filter { indegree[$0] == 0 }
            var head = 0
            while head < queue.count {
                let node = queue[head]
                head += 1
                for next in (out[node] ?? []).sorted() {
                    rank[next] = max(rank[next] ?? 0, (rank[node] ?? 0) + 1)
                    indegree[next, default: 0] -= 1
                    if indegree[next] == 0 { queue.append(next) }
                }
            }

            // 3. Pins: senders in the first column, receivers after everything else.
            for node in pinFirst where nodeSet.contains(node) { rank[node] = 0 }
            let unpinned = nodes.filter { !pinLast.contains($0) }
            if let lastUnpinned = unpinned.compactMap({ rank[$0] }).max() {
                for node in nodes where pinLast.contains(node) { rank[node] = max(rank[node] ?? 0, lastUnpinned + 1) }
            }

            // Close gaps so columns are 0, 1, 2… with none empty.
            let distinct = Array(Set(rank.values)).sorted()
            let compact = Dictionary(uniqueKeysWithValues: distinct.enumerated().map { ($1, $0) })
            for node in nodes { rank[node] = compact[rank[node] ?? 0] ?? 0 }

            // 4. Order within ranks by barycenter sweeps.
            var layers = Array(repeating: [String](), count: distinct.count)
            for node in nodes { layers[rank[node] ?? 0].append(node) }
            var predecessors: [String: [String]] = [:]
            var followers: [String: [String]] = [:]
            for edge in dag {
                predecessors[edge.to, default: []].append(edge.from)
                followers[edge.from, default: []].append(edge.to)
            }
            var position: [String: Double] = [:]
            func reindex() {
                for layer in layers { for (index, node) in layer.enumerated() { position[node] = Double(index) } }
            }
            func reorder(_ layer: [String], by neighbours: [String: [String]]) -> [String] {
                layer.map { node -> (node: String, bary: Double, current: Double) in
                    let current = position[node] ?? 0
                    let linked = neighbours[node] ?? []
                    let bary = linked.isEmpty ? current : linked.map { position[$0] ?? 0 }.reduce(0, +) / Double(linked.count)
                    return (node, bary, current)
                }
                .sorted { ($0.bary, $0.current, $0.node) < ($1.bary, $1.current, $1.node) }
                .map(\.node)
            }
            reindex()
            for _ in 0..<sweeps {
                for r in layers.indices.dropFirst() {
                    layers[r] = reorder(layers[r], by: predecessors)
                    reindex()
                }
                for r in layers.indices.dropLast().reversed() {
                    layers[r] = reorder(layers[r], by: followers)
                    reindex()
                }
            }

            var order: [String: Int] = [:]
            for layer in layers { for (index, node) in layer.enumerated() { order[node] = index } }
            return Result(rank: rank, order: order, reversed: reversed, layers: layers)
        }
    }
}
