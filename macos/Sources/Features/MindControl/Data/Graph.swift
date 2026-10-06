import Foundation
import simd

extension MindControl {
    enum NodeKind: Sendable {
        case root
        case folder
        case source
        case document
    }

    struct GraphNode: Identifiable, Sendable {
        let id: String
        let label: String
        let kind: NodeKind
        var position: SIMD3<Float>
        /// Brightness multiplier (0...1); crowded files are dimmed so dense folders stay readable.
        var weight: Float = 1
    }

    /// What a line between two nodes means.
    enum EdgeKind: Sendable {
        /// A folder contains a file or subfolder.
        case contains
        /// A file uses something defined in another file (import, type reference, link).
        case uses
    }

    struct GraphEdge: Sendable {
        let from: String
        let to: String
        var kind: EdgeKind = .contains
    }

    struct Graph: Sendable {
        var nodes: [GraphNode]
        var edges: [GraphEdge]
    }
}

extension MindControl.Graph {
    /// Placeholder graph shown until directory loading is implemented.
    static let sample: MindControl.Graph = {
        var nodes: [MindControl.GraphNode] = [
            MindControl.GraphNode(id: "root", label: "MindControl", kind: .root, position: .zero)
        ]
        var edges: [MindControl.GraphEdge] = []

        let folders = ["Graph", "Views", "Parsing", "Resources", "Docs"]
        for (i, folder) in folders.enumerated() {
            let folderPos = fibonacciPoint(index: i, count: folders.count, radius: 6)
            nodes.append(MindControl.GraphNode(id: folder, label: folder, kind: .folder, position: folderPos))
            edges.append(MindControl.GraphEdge(from: "root", to: folder))

            let leafCount = 4 + i % 3
            for j in 0..<leafCount {
                let id = "\(folder)/\(j)"
                let kind: MindControl.NodeKind = folder == "Docs" ? .document : .source
                let offset = fibonacciPoint(index: j, count: leafCount, radius: 2.5)
                nodes.append(MindControl.GraphNode(id: id, label: "\(folder) \(j + 1)", kind: kind, position: folderPos + offset))
                edges.append(MindControl.GraphEdge(from: folder, to: id))
            }
        }

        // A few cross-links to suggest relationships between files.
        edges.append(MindControl.GraphEdge(from: "Views/0", to: "Graph/1", kind: .uses))
        edges.append(MindControl.GraphEdge(from: "Parsing/2", to: "Graph/0", kind: .uses))
        edges.append(MindControl.GraphEdge(from: "Docs/1", to: "Views/2", kind: .uses))

        return MindControl.Graph(nodes: nodes, edges: edges)
    }()

    /// Evenly distributes points on a sphere.
    private static func fibonacciPoint(index: Int, count: Int, radius: Float) -> SIMD3<Float> {
        let golden = Float.pi * (3 - sqrt(5))
        let y = count == 1 ? 0 : 1 - (Float(index) / Float(count - 1)) * 2
        let r = sqrt(max(0, 1 - y * y))
        let theta = golden * Float(index)
        return SIMD3(cos(theta) * r, y, sin(theta) * r) * radius
    }
}
