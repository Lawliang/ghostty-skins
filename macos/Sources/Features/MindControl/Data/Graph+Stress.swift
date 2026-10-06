import simd

extension MindControl {
    /// Small, fast, seedable generator so stress graphs are identical across runs.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

extension MindControl.Graph {
    /// A synthetic project-shaped graph for performance and visual testing:
    /// one root, about √n/2 folders on a sphere, leaves clustered around folders, and n/8 cross-links.
    static func stress(nodeCount: Int, seed: UInt64 = 42) -> MindControl.Graph {
        guard nodeCount > 0 else { return MindControl.Graph(nodes: [], edges: []) }
        var rng = MindControl.SplitMix64(seed: seed)
        var nodes = [MindControl.GraphNode(id: "root", label: "root", kind: .root, position: .zero)]
        var edges: [MindControl.GraphEdge] = []

        let remaining = nodeCount - 1
        guard remaining > 0 else { return MindControl.Graph(nodes: nodes, edges: edges) }

        let folderCount = min(remaining, max(1, Int(Double(remaining).squareRoot() / 2)))
        let shellRadius = 4 + Float(remaining).squareRoot() * 0.35
        var folderPositions: [SIMD3<Float>] = []
        for i in 0..<folderCount {
            let position = randomUnitVector(using: &rng) * shellRadius * Float.random(in: 0.75...1, using: &rng)
            folderPositions.append(position)
            nodes.append(MindControl.GraphNode(id: "f\(i)", label: "Folder \(i)", kind: .folder, position: position))
            edges.append(MindControl.GraphEdge(from: "root", to: "f\(i)"))
        }

        let leafCount = remaining - folderCount
        let perFolder = Float(leafCount) / Float(folderCount)
        let clusterRadius = 1.2 + perFolder.squareRoot() * 0.45
        for i in 0..<leafCount {
            let folder = i % folderCount
            let offset = randomUnitVector(using: &rng) * clusterRadius * cbrt(Float.random(in: 0.05...1, using: &rng))
            let kind: MindControl.NodeKind = Float.random(in: 0..<1, using: &rng) < 0.2 ? .document : .source
            nodes.append(MindControl.GraphNode(id: "l\(i)", label: "File \(i)", kind: kind, position: folderPositions[folder] + offset))
            edges.append(MindControl.GraphEdge(from: "f\(folder)", to: "l\(i)"))
        }

        if leafCount > 1 {
            for _ in 0..<(leafCount / 8) {
                let a = Int.random(in: 0..<leafCount, using: &rng)
                var b = Int.random(in: 0..<leafCount, using: &rng)
                if a == b { b = (b + 1) % leafCount }
                edges.append(MindControl.GraphEdge(from: "l\(a)", to: "l\(b)", kind: .uses))
            }
        }

        return MindControl.Graph(nodes: nodes, edges: edges)
    }

    private static func randomUnitVector(using rng: inout MindControl.SplitMix64) -> SIMD3<Float> {
        let z = Float.random(in: -1...1, using: &rng)
        let theta = Float.random(in: 0..<(2 * .pi), using: &rng)
        let r = (1 - z * z).squareRoot()
        return SIMD3(r * cos(theta), r * sin(theta), z)
    }
}
