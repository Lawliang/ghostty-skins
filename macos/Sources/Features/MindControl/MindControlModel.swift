import CoreGraphics
import Foundation

extension MindControl {
    /// Loads the focused terminal's flow map off the main thread, and reloads when the flow file changes.
    /// One per window. Nothing is cached: every open reads the project again.
    @MainActor
    final class Model: ObservableObject {
        struct Project: Equatable {
            let root: URL
            let name: String
            /// Why Draft/Refresh with Claude are off here, or nil.
            let claudeBlockReason: String?
        }

        struct Loaded: Equatable {
            let map: FlowMap
            let report: HealthReport
            let saved: [String: CGPoint]
            /// Changes on every load, so views can tell a reload from a repeat.
            let generation: Int
        }

        enum State: Equatable {
            case idle
            case noProject
            /// While loading, `claudeBlockReason` is the last one known for this root (nil for a new root).
            case loading(Project)
            case noFlowFile(Project)
            case invalid(Project, [FlowError])
            case ready(Project, Loaded)
            case failed(String)
        }

        enum Outcome: Sendable {
            case none
            case invalid([FlowError])
            case ready(FlowMap, HealthReport, [String: CGPoint])
        }

        @Published private(set) var state: State = .idle
        private(set) var loadingTask: Task<Void, Never>?

        private let snapshot: @Sendable (URL) throws -> FlowSnapshot
        private let age: @Sendable (URL, FlowMap) -> HealthReport.Age
        private let guardReason: @Sendable (URL) -> String?
        private let watch: Bool
        private var terminalPwd: URL?
        private var override: URL?
        private var watcher: FlowWatcher?
        private var watchedRoot: URL?
        private var generation = 0

        init(snapshot: @escaping @Sendable (URL) throws -> FlowSnapshot = { try FlowSource.workingTree.snapshot(root: $0) },
             age: @escaping @Sendable (URL, FlowMap) -> HealthReport.Age = { FlowAge.age(root: $0, map: $1) },
             guardReason: @escaping @Sendable (URL) -> String? = { ProjectGuard.claudeBlockReason(root: $0) },
             watch: Bool = true) {
            self.snapshot = snapshot
            self.age = age
            self.guardReason = guardReason
            self.watch = watch
        }

        var project: Project? {
            switch state {
            case .loading(let project), .noFlowFile(let project), .invalid(let project, _), .ready(let project, _): project
            case .idle, .noProject, .failed: nil
            }
        }

        /// The terminal's folder; ignored while a folder chosen with Change… is in effect.
        func load(pwd: URL?) {
            terminalPwd = pwd
            reload()
        }

        /// Change…: map this folder until MindControl closes.
        func choose(root: URL) {
            override = root
            reload()
        }

        /// MindControl closed: forget the chosen folder, drop any load in flight, and stop watching.
        func close() {
            override = nil
            cancelLoad()
            stopWatching()
        }

        func reload() {
            cancelLoad()
            guard let root = resolvedRoot() else {
                stopWatching()
                state = .noProject
                return
            }
            // Watch before reading, so a change made while the load runs still triggers a reload.
            if watch { startWatching(root) }
            if case .ready(let shown, _) = state, shown.root == root {
                // Keep showing the map while it reloads.
            } else {
                let known = project?.root == root ? project?.claudeBlockReason : nil
                state = .loading(Project(root: root, name: root.lastPathComponent, claudeBlockReason: known))
            }
            let current = generation
            let snapshot = self.snapshot, age = self.age, guardReason = self.guardReason
            // Everything that runs git or reads the project happens here, off the main thread.
            let work = Task.detached(priority: .userInitiated) { () -> (String?, Result<Outcome, Error>) in
                (guardReason(root), Result { try Self.compute(root: root, snapshot: snapshot, age: age) })
            }
            loadingTask = Task { [weak self] in
                let (reason, result) = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
                guard let self, !Task.isCancelled, current == self.generation else { return }
                let project = Project(root: root, name: root.lastPathComponent, claudeBlockReason: reason)
                switch result {
                case .success(.none): self.state = .noFlowFile(project)
                case .success(.invalid(let errors)): self.state = .invalid(project, errors)
                case .success(.ready(let map, let report, let saved)):
                    self.state = .ready(project, Loaded(map: map, report: report, saved: saved, generation: current))
                case .failure(let error): self.state = .failed(Self.message(for: error))
                }
            }
        }

        /// Stops between steps once cancelled, so a superseded load doesn't go on to run git.
        nonisolated static func compute(root: URL, snapshot: (URL) throws -> FlowSnapshot,
                                        age: (URL, FlowMap) -> HealthReport.Age) throws -> Outcome {
            let snap = try snapshot(root)
            guard let data = snap.flowData else { return .none }
            switch FlowFile.parse(data) {
            case .failure(let failure):
                return .invalid(failure.errors)
            case .success(let map):
                try Task.checkCancellation()
                var report = FlowCheck.run(map: map, snapshot: snap)
                try Task.checkCancellation()
                report.age = age(root, map)
                return .ready(map, report, LayoutStore.decode(snap.layoutData))
            }
        }

        /// A folder chosen with Change… is used as-is, not resolved to its git root: the user picked it deliberately.
        /// The terminal's folder maps its git root, or itself outside git. Symlinks are resolved before the git root
        /// is looked for, so a folder reached through a link maps the repository it really sits in, and the root
        /// agrees with the paths git reports. Only file-system lookups here, no git.
        private func resolvedRoot() -> URL? {
            if let override { return Self.canonical(override) }
            guard let pwd = terminalPwd else { return nil }
            return Self.canonical(ProjectScanner.projectRoot(for: Self.canonical(pwd)))
        }

        /// Symlinks, `.` and `..` resolved; always a directory URL, so equal folders compare equal.
        private static func canonical(_ url: URL) -> URL {
            URL(fileURLWithPath: url.standardizedFileURL.resolvingSymlinksInPath().path, isDirectory: true)
        }

        /// Ends the load in flight, if any; its result, should it still arrive, is ignored.
        private func cancelLoad() {
            loadingTask?.cancel()
            generation += 1
        }

        private func startWatching(_ root: URL) {
            guard watchedRoot != root else { return }
            watcher?.stop()
            watchedRoot = root
            watcher = FlowWatcher(root: root) { [weak self] in self?.reload() }
        }

        private func stopWatching() {
            watcher?.stop()
            watcher = nil
            watchedRoot = nil
        }

        private static func message(for error: Error) -> String {
            switch error {
            case ScanError.noDirectory(let path), ScanError.unreadable(let path): "Can't read \(path)."
            default: error.localizedDescription
            }
        }
    }
}
