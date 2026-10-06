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
        private var scanTask: Task<Result<(FileTree, Graph), Error>, Never>?
        /// Root whose scan is currently running, so reopening the drawer mid-scan doesn't start another.
        private var inFlightKey: String?

        private let dependencies: @Sendable (FileTree) throws -> [Dependency]

        init(scan: @escaping @Sendable (URL) throws -> FileTree = { try ProjectScanner().scan(pwd: $0) },
             dependencies: @escaping @Sendable (FileTree) throws -> [Dependency] = { try DependencyScanner.scan(tree: $0) }) {
            self.scan = scan
            self.dependencies = dependencies
        }

        func load(pwd: URL?) {
            guard let pwd else {
                cancelScan()
                state = .noProject
                publish(nil)
                return
            }

            let key = ProjectScanner.projectRoot(for: pwd).path
            if let hit = cache[key] {
                cancelScan()
                apply(hit.tree, hit.graph)
                return
            }
            if key == inFlightKey { return }

            cancelScan()
            state = .scanning
            inFlightKey = key
            let scan = self.scan
            let dependencies = self.dependencies
            let scanTask = Task.detached(priority: .userInitiated) { () -> Result<(FileTree, Graph), Error> in
                Result {
                    let tree = try scan(pwd)
                    try Task.checkCancellation()
                    let found = try dependencies(tree)
                    try Task.checkCancellation()
                    return (tree, TreeLayout.graph(for: tree, dependencies: found))
                }
            }
            self.scanTask = scanTask
            loadingTask = Task { [weak self] in
                let result = await scanTask.value
                guard !Task.isCancelled, let self else { return }
                self.inFlightKey = nil
                switch result {
                case .success(let (tree, graph)):
                    self.cache[key] = (tree, graph)
                    self.apply(tree, graph)
                case .failure(let error) where error is CancellationError:
                    return
                case .failure(let error):
                    self.state = .failed(Self.message(for: error))
                    self.publish(nil)
                }
            }
        }

        private func cancelScan() {
            scanTask?.cancel()
            loadingTask?.cancel()
            scanTask = nil
            inFlightKey = nil
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
            switch error {
            case ScanError.noDirectory(let path), ScanError.unreadable(let path):
                return "Can't read \(path)."
            default:
                return error.localizedDescription
            }
        }
    }
}
