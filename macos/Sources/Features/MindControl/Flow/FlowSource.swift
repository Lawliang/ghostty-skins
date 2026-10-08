import Foundation

extension MindControl {
    /// Everything the flow map reads from a project, at one point in time.
    struct FlowSnapshot: Sendable {
        let root: URL
        let flowData: Data?
        let layoutData: Data?
        /// Feature source files (SourceFilter), relative to the root, sorted.
        let sourceFiles: [String]
        /// Contents of a file relative to the root, or nil.
        let read: @Sendable (String) -> String?
    }

    enum FlowSourceError: Error, Equatable {
        case unknownRevision(String)
    }

    /// Where a snapshot comes from: the files on disk, or a git revision (for comparing branches later).
    enum FlowSource: Equatable, Sendable {
        case workingTree
        case revision(String)

        func snapshot(root: URL) throws -> FlowSnapshot {
            switch self {
            case .workingTree:
                // The scanner lists files relative to the git root. When `root` is a subfolder of the
                // repository, keep only files inside it, filter them by their path relative to `root`
                // (so a folder like `tools/cli` isn't excluded by its own location), then strip the prefix.
                var scanner = ProjectScanner()
                let prefix = Self.repositoryPrefix(of: root) ?? ""
                if !prefix.isEmpty {
                    scanner.includes = { $0.hasPrefix(prefix) && SourceFilter.isFeatureSource(String($0.dropFirst(prefix.count))) }
                }
                let files = try scanner.scan(pwd: root, shouldStop: { false }).files.map { String($0.dropFirst(prefix.count)) }
                let read: @Sendable (String) -> String? = { path in
                    try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                }
                return FlowSnapshot(root: root,
                                    flowData: try? Data(contentsOf: root.appendingPathComponent(FlowFile.relativePath)),
                                    layoutData: try? Data(contentsOf: root.appendingPathComponent(FlowFile.layoutRelativePath)),
                                    sourceFiles: files, read: read)

            case .revision(let revision):
                guard Git.run(root, ["rev-parse", "--verify", "--quiet", "\(revision)^{commit}"]) != nil else {
                    throw FlowSourceError.unknownRevision(revision)
                }
                let listing = Git.run(root, ["ls-tree", "-r", "-z", "--name-only", revision]) ?? Data()
                let files = String(decoding: listing, as: UTF8.self).split(separator: "\0").map(String.init)
                    .filter(SourceFilter.isFeatureSource).sorted()
                // `./` makes the path relative to `root`, the same base `ls-tree` listed from.
                let show: @Sendable (String) -> Data? = { path in Git.run(root, ["show", "\(revision):./\(path)"]) }
                return FlowSnapshot(root: root,
                                    flowData: show(FlowFile.relativePath),
                                    layoutData: show(FlowFile.layoutRelativePath),
                                    sourceFiles: files,
                                    read: { path in show(path).map { String(decoding: $0, as: UTF8.self) } })
            }
        }

        /// `root`'s path inside its git repository ("sub/dir/"), empty at the repository root, nil outside git.
        private static func repositoryPrefix(of root: URL) -> String? {
            Git.run(root, ["rev-parse", "--show-prefix"]).map {
                String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
