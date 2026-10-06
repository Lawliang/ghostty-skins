import simd

extension MindControl {
    /// Visual size and colour for each node kind. Colours are linear HDR.
    enum NodeStyle {
        static func radius(for kind: NodeKind) -> Float {
            switch kind {
            case .root: 0.55
            case .folder: 0.32
            case .source, .document: 0.16
            }
        }

        static func color(for kind: NodeKind) -> SIMD3<Float> {
            switch kind {
            case .root:     SIMD3(0.95, 0.80, 1.00)  // warm white-violet
            case .folder:   SIMD3(0.25, 0.50, 1.00)  // electric blue
            case .source:   SIMD3(0.20, 0.85, 1.00)  // cyan
            case .document: SIMD3(0.65, 0.35, 1.00)  // violet
            }
        }
    }

    /// Deterministic string hash, so a node keeps its pulse phase across launches.
    enum StableHash {
        static func unit(_ string: String) -> Float {
            var hash: UInt32 = 2_166_136_261
            for byte in string.utf8 {
                hash ^= UInt32(byte)
                hash = hash &* 16_777_619
            }
            // Use the top 24 bits so the result is exactly representable and < 1.
            return Float(hash >> 8) / Float(1 << 24)
        }
    }

    /// GPU-ready instance arrays built from a `Graph`.
    struct GraphBuffers {
        let nodes: [MCNodeInstance]
        let edges: [MCEdgeInstance]
        let center: SIMD3<Float>
        let boundingRadius: Float

        init(graph: Graph) {
            var index: [String: UInt32] = [:]
            var nodes: [MCNodeInstance] = []
            nodes.reserveCapacity(graph.nodes.count)

            for node in graph.nodes where index[node.id] == nil {
                index[node.id] = UInt32(nodes.count)
                nodes.append(MCNodeInstance(
                    position: node.position,
                    radius: NodeStyle.radius(for: node.kind),
                    color: NodeStyle.color(for: node.kind),
                    phase: StableHash.unit(node.id) * 2 * .pi,
                    intensity: node.weight
                ))
            }

            self.edges = graph.edges.compactMap { edge in
                guard let a = index[edge.from], let b = index[edge.to], a != b else { return nil }
                return MCEdgeInstance(a: a, b: b, signalSeed: StableHash.unit(edge.from + "\u{1F}" + edge.to))
            }
            self.nodes = nodes

            guard let first = nodes.first else {
                center = .zero
                boundingRadius = 0
                return
            }
            var lo = first.position, hi = first.position
            for n in nodes {
                lo = simd_min(lo, n.position)
                hi = simd_max(hi, n.position)
            }
            let center = (lo + hi) / 2
            self.center = center
            boundingRadius = nodes.map { simd_distance($0.position, center) + $0.radius }.max() ?? 0
        }
    }
}
