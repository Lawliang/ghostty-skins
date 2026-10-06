extension MindControl {
    /// What the info card shows for a node.
    struct NodeDetails: Equatable {
        let name: String
        let path: String
        let kind: NodeKind
        /// Files this file uses.
        let uses: Int
        /// Files that use this file.
        let usedBy: Int
        /// For folders: files beneath.
        let files: Int

        static func make(graph: Graph, nodeID: String) -> NodeDetails? {
            guard let node = graph.nodes.first(where: { $0.id == nodeID }) else { return nil }
            var uses = 0, usedBy = 0
            for edge in graph.edges where edge.kind == .uses {
                if edge.from == nodeID { uses += 1 }
                if edge.to == nodeID { usedBy += 1 }
            }
            return NodeDetails(name: node.label, path: node.id == ConeTreeLayout.rootID ? "/" : node.id,
                               kind: node.kind, uses: uses, usedBy: usedBy, files: node.descendantFiles)
        }
    }
}
