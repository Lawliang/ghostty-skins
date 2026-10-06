import Foundation
import simd

extension MindControl {
    /// Places a project's folder tree in 3D: top-level entries on a sphere around the root,
    /// deeper entries on hemispheres that face away from their grandparent so branches grow outward.
    enum TreeLayout {
        static let rootID = "."
        static let documentExtensions: Set<String> = ["md", "markdown", "txt", "rst", "adoc", "org", "pdf"]
        /// Files in folders with more siblings than this start to dim.
        static let crowdThreshold: Float = 30
        static let minimumFileWeight: Float = 0.12

        /// Brightness for a file with `siblings` files beside it (itself included).
        static func fileWeight(siblings: Int) -> Float {
            min(1, max(minimumFileWeight, pow(crowdThreshold / Float(max(siblings, 1)), 0.75)))
        }

        private final class Folder {
            let id: String
            var folders: [String: Folder] = [:]
            var files: [String] = []
            /// Files and folders beneath this folder, used for spacing.
            var size = 0

            init(id: String) { self.id = id }
        }

        private enum Entry {
            case folder(Folder)
            case file(String)

            var weight: Int {
                switch self {
                case .folder(let f): f.size + 1
                case .file: 1
                }
            }
        }

        static func graph(for tree: FileTree) -> Graph {
            let root = Folder(id: rootID)
            for path in tree.files {
                var folder = root
                let parts = path.split(separator: "/").map(String.init)
                for (depth, part) in parts.dropLast().enumerated() {
                    let id = parts[0...depth].joined(separator: "/")
                    if let existing = folder.folders[part] {
                        folder = existing
                    } else {
                        let created = Folder(id: id)
                        folder.folders[part] = created
                        folder = created
                    }
                }
                folder.files.append(path)
            }
            computeSize(root)

            var nodes = [GraphNode(id: rootID, label: tree.rootName, kind: .root, position: .zero)]
            var edges: [GraphEdge] = []
            nodes.reserveCapacity(root.size + 1)
            edges.reserveCapacity(root.size)

            let total = Float(root.size + 1)
            let rootRadius = 4 + 0.35 * total.squareRoot()
            // Largest subtrees first, so the Fibonacci spiral spreads the big folders apart.
            let topLevel = entries(of: root).sorted { $0.weight > $1.weight }
            for (i, entry) in topLevel.enumerated() {
                let direction = fibonacciSphere(index: i, count: topLevel.count)
                place(entry, at: direction * rootRadius, outward: direction, parent: rootID,
                      fileWeight: fileWeight(siblings: root.files.count), nodes: &nodes, edges: &edges)
            }
            return Graph(nodes: nodes, edges: edges)
        }

        private static func computeSize(_ folder: Folder) {
            folder.size = folder.files.count
            for child in folder.folders.values {
                computeSize(child)
                folder.size += child.size + 1
            }
        }

        /// Subfolders then files, each sorted by name.
        private static func entries(of folder: Folder) -> [Entry] {
            folder.folders.keys.sorted().map { .folder(folder.folders[$0]!) } + folder.files.sorted().map { .file($0) }
        }

        private static func place(_ entry: Entry, at position: SIMD3<Float>, outward: SIMD3<Float>, parent: String,
                                  fileWeight: Float, nodes: inout [GraphNode], edges: inout [GraphEdge]) {
            switch entry {
            case .file(let path):
                nodes.append(GraphNode(id: path, label: (path as NSString).lastPathComponent, kind: kind(for: path),
                                       position: position, weight: fileWeight))
                edges.append(GraphEdge(from: parent, to: path))

            case .folder(let folder):
                nodes.append(GraphNode(id: folder.id, label: (folder.id as NSString).lastPathComponent, kind: .folder, position: position))
                edges.append(GraphEdge(from: parent, to: folder.id))

                let children = entries(of: folder)
                let childFileWeight = Self.fileWeight(siblings: folder.files.count)
                let radius = 1.0 + 0.6 * Float(folder.size).squareRoot()
                for (i, child) in children.enumerated() {
                    let direction = hemisphere(index: i, count: children.count, facing: outward)
                    let distance: Float
                    if case .folder = child {
                        distance = radius * 2.0
                    } else {
                        // Spread files through a thick shell so big folders read as volumes, not a crust.
                        distance = radius * (0.6 + 0.4 * fract(Float(i) * 0.618034))
                    }
                    place(child, at: position + direction * distance, outward: direction, parent: folder.id,
                          fileWeight: childFileWeight, nodes: &nodes, edges: &edges)
                }
            }
        }

        private static func kind(for path: String) -> NodeKind {
            documentExtensions.contains((path as NSString).pathExtension.lowercased()) ? .document : .source
        }

        private static func fract(_ x: Float) -> Float { x - x.rounded(.down) }

        private static let goldenAngle = Float.pi * (3 - Float(5).squareRoot())

        private static func fibonacciSphere(index: Int, count: Int) -> SIMD3<Float> {
            let y = count == 1 ? 0 : 1 - (Float(index) / Float(count - 1)) * 2
            let r = max(0, 1 - y * y).squareRoot()
            let theta = goldenAngle * Float(index)
            return SIMD3(cos(theta) * r, y, sin(theta) * r)
        }

        /// Unit vectors spread over the hemisphere around `facing`; the first points straight along it.
        private static func hemisphere(index: Int, count: Int, facing: SIMD3<Float>) -> SIMD3<Float> {
            let t = count == 1 ? 0 : Float(index) / Float(count - 1) * 0.95
            let cosTheta = 1 - t
            let sinTheta = max(0, 1 - cosTheta * cosTheta).squareRoot()
            let phi = goldenAngle * Float(index)

            let up = simd_normalize(facing)
            let reference: SIMD3<Float> = abs(up.y) < 0.99 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let tangent = simd_normalize(simd_cross(up, reference))
            let bitangent = simd_cross(up, tangent)
            return simd_normalize(tangent * (sinTheta * cos(phi)) + up * cosTheta + bitangent * (sinTheta * sin(phi)))
        }
    }
}
