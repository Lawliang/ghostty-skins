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
                let files = try ProjectScanner().scan(pwd: root, shouldStop: { false }).files
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
                let show: @Sendable (String) -> Data? = { path in Git.run(root, ["show", "\(revision):\(path)"]) }
                return FlowSnapshot(root: root,
                                    flowData: show(FlowFile.relativePath),
                                    layoutData: show(FlowFile.layoutRelativePath),
                                    sourceFiles: files,
                                    read: { path in show(path).map { String(decoding: $0, as: UTF8.self) } })
            }
        }
    }
}
