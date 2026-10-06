import Foundation

extension MindControl {
    /// Scans the focused terminal's project off the main thread and publishes its graph.
    /// One per window; caches graphs by project root.
    @MainActor
    final class Model: ObservableObject {
        enum State: Equatable {
            case idle
            case scanning
            case ready(FileTree)
            case noProject
            case empty(String)
            case failed(String)
        }

        @Published private(set) var state: State = .idle
        /// Bumped whenever `graph` is (re)published, so views can react without Graph being Equatable.
        @Published private(set) var graphVersion = 0
        private(set) var graph: Graph?
        private(set) var loadingTask: Task<Void, Never>?

        private let scan: @Sendable (URL) throws -> FileTree
        private var cache: [String: (tree: FileTree, graph: Graph)] = [:]

        init(scan: @escaping @Sendable (URL) throws -> FileTree = { try ProjectScanner().scan(pwd: $0) }) {
            self.scan = scan
        }

        func load(pwd: URL?) {
            loadingTask?.cancel()
            loadingTask = nil

            guard let pwd else {
                state = .noProject
                publish(nil)
                return
            }

            let key = ProjectScanner.projectRoot(for: pwd).path
            if let hit = cache[key] {
                apply(hit.tree, hit.graph)
                return
            }

            state = .scanning
            let scan = self.scan
            loadingTask = Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) { () -> Result<(FileTree, Graph), Error> in
                    Result {
                        let tree = try scan(pwd)
                        return (tree, TreeLayout.graph(for: tree))
                    }
                }.value
                guard !Task.isCancelled, let self else { return }
                switch result {
                case .success(let (tree, graph)):
                    self.cache[key] = (tree, graph)
                    self.apply(tree, graph)
                case .failure(let error):
                    self.state = .failed(Self.message(for: error))
                    self.publish(nil)
                }
            }
        }

        private func apply(_ tree: FileTree, _ graph: Graph) {
            if tree.files.isEmpty {
                state = .empty(tree.rootName)
                publish(nil)
            } else {
                state = .ready(tree)
                publish(graph)
            }
        }

        private func publish(_ graph: Graph?) {
            self.graph = graph
            graphVersion += 1
        }

        private static func message(for error: Error) -> String {
            if case ScanError.noDirectory(let path) = error { return "Can't read \(path)." }
            return error.localizedDescription
        }
    }
}
