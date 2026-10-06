import Foundation
import simd

extension MindControl {
    /// Places the folder tree so sibling clusters don't overlap: every folder owns a cone of space
    /// sized by how many files it holds, subfolders sit along their cone's axis, and a folder's own
    /// files form a small ball around it.
    enum ConeTreeLayout {
        static let rootID = "."
        static let documentExtensions: Set<String> = ["md", "markdown", "txt", "rst", "adoc", "org", "pdf"]
        /// Files in folders with more siblings than this start to dim.
        static let crowdThreshold: Float = 30
        static let minimumFileWeight: Float = 0.12

        /// Brightness for a file with `siblings` files beside it (itself included).
        static func fileWeight(siblings: Int) -> Float {
            min(1, max(minimumFileWeight, pow(crowdThreshold / Float(max(siblings, 1)), 0.75)))
        }

        /// Radius of the ball a folder's own files sit in.
        static func fileBallRadius(fileCount: Int) -> Float {
            0.8 + 0.35 * Float(fileCount).squareRoot()
        }

        /// How far a subfolder sits from its parent: clear of the parent's file ball, further for bigger subtrees.
        static func subfolderDistance(parentFiles: Int, childTotalFiles: Int) -> Float {
            fileBallRadius(fileCount: parentFiles) + 2 + 1.2 * Float(1 + childTotalFiles).squareRoot()
        }

        private final class Folder {
            let id: String
            var folders: [String: Folder] = [:]
            var files: [String] = []
            /// Files anywhere beneath this folder.
            var totalFiles = 0

            init(id: String) { self.id = id }
        }

        static func graph(for tree: FileTree, dependencies: [Dependency] = []) -> Graph {
            let root = Folder(id: rootID)
            for path in tree.files {
                var folder = root
                let parts = path.split(separator: "/").map(String.init)
                for depth in 0..<max(0, parts.count - 1) {
                    if let existing = folder.folders[parts[depth]] {
                        folder = existing
                    } else {
                        let created = Folder(id: parts[0...depth].joined(separator: "/"))
                        folder.folders[parts[depth]] = created
                        folder = created
                    }
                }
                folder.files.append(path)
            }
            countFiles(root)

            var nodes = [GraphNode(id: rootID, label: tree.rootName, kind: .root, position: .zero,
                                   descendantFiles: root.totalFiles)]
            var edges: [GraphEdge] = []
            nodes.reserveCapacity(tree.files.count * 2)
            place(root, at: .zero, axis: SIMD3(0, 1, 0), halfAngle: .pi, nodes: &nodes, edges: &edges)

            let ids = Set(nodes.map(\.id))
            for dependency in dependencies where dependency.from != dependency.to
                && ids.contains(dependency.from) && ids.contains(dependency.to) {
                edges.append(GraphEdge(from: dependency.from, to: dependency.to, kind: .uses))
            }
            return Graph(nodes: nodes, edges: edges)
        }

        @discardableResult
        private static func countFiles(_ folder: Folder) -> Int {
            folder.totalFiles = folder.files.count + folder.folders.values.reduce(0) { $0 + countFiles($1) }
            return folder.totalFiles
        }

        private static func place(_ folder: Folder, at position: SIMD3<Float>, axis: SIMD3<Float>, halfAngle: Float,
                                  nodes: inout [GraphNode], edges: inout [GraphEdge]) {
            let files = folder.files.sorted()
            let ball = fileBallRadius(fileCount: files.count)
            let weight = fileWeight(siblings: files.count)
            for (i, path) in files.enumerated() {
                let direction = fibonacciSphere(index: i, count: files.count)
                // Spread through a thick shell so big folders read as volumes, not a crust.
                let distance = ball * (0.55 + 0.45 * fract(Float(i) * 0.618034))
                nodes.append(GraphNode(id: path, label: (path as NSString).lastPathComponent, kind: kind(for: path),
                                       position: position + direction * distance, weight: weight))
                edges.append(GraphEdge(from: folder.id, to: path))
            }

            // Heaviest subfolders take the centre of the cap; ties keep name order.
            let byName = folder.folders.keys.sorted().compactMap { folder.folders[$0] }
            let subfolders = byName.enumerated().sorted { a, b in
                a.element.totalFiles != b.element.totalFiles ? a.element.totalFiles > b.element.totalFiles : a.offset < b.offset
            }.map(\.element)
            let totalWeight = Float(subfolders.reduce(0) { $0 + $1.totalFiles + 1 })

            for (i, child) in subfolders.enumerated() {
                let childAxis = capDirection(index: i, count: subfolders.count, axis: axis, halfAngle: halfAngle)
                let share = Float(child.totalFiles + 1) / totalWeight
                let childHalfAngle = max(0.05, halfAngle * share.squareRoot() * 0.85)
                let childPosition = position
                    + childAxis * subfolderDistance(parentFiles: files.count, childTotalFiles: child.totalFiles)
                nodes.append(GraphNode(id: child.id, label: (child.id as NSString).lastPathComponent, kind: .folder,
                                       position: childPosition, descendantFiles: child.totalFiles))
                edges.append(GraphEdge(from: folder.id, to: child.id))
                place(child, at: childPosition, axis: childAxis, halfAngle: childHalfAngle, nodes: &nodes, edges: &edges)
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

        /// Directions spread evenly (equal area) over the spherical cap around `axis`; index 0 is the axis.
        static func capDirection(index: Int, count: Int, axis: SIMD3<Float>, halfAngle: Float) -> SIMD3<Float> {
            let up = simd_normalize(axis)
            guard count > 1 else { return up }
            let rimZ = cos(min(halfAngle, .pi))
            let z = 1 - (1 - rimZ) * Float(index) / Float(count - 1)
            let r = max(0, 1 - z * z).squareRoot()
            let phi = goldenAngle * Float(index)
            let reference: SIMD3<Float> = abs(up.y) < 0.99 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let tangent = simd_normalize(simd_cross(up, reference))
            let bitangent = simd_cross(up, tangent)
            return simd_normalize(tangent * (r * cos(phi)) + bitangent * (r * sin(phi)) + up * z)
        }
    }
}
