import Foundation

extension MindControl {
    /// A project's files as sorted, "/"-separated paths relative to the root.
    struct FileTree: Equatable, Sendable {
        let rootName: String
        let rootPath: String
        let files: [String]
        /// Files found before the cap was applied.
        let totalFileCount: Int
        /// True when the scan stopped at the cap, so `totalFileCount` is only a lower bound.
        var totalIsLowerBound = false

        var truncated: Bool { files.count < totalFileCount }
    }

    enum ScanError: Error, Equatable {
        case noDirectory(String)
        case unreadable(String)
    }

    /// Lists the files of the project containing a working directory.
    struct ProjectScanner {
        static let defaultFileCap = 10_000
        static let maxWalkDepth = 12
        static let skippedDirectories: Set<String> = [
            "node_modules", ".build", "zig-out", "zig-cache", ".zig-cache",
            "DerivedData", "build", "dist", "vendor", "Pods", "target",
        ]

        var fileCap = ProjectScanner.defaultFileCap
        /// `~/Library` is skipped when the root is the home directory.
        var homeDirectory = NSHomeDirectory()

        /// The git root containing `pwd`, or `pwd` itself outside git.
        static func projectRoot(for pwd: URL) -> URL {
            if let root = ProjectResolver.gitRoot(of: pwd.path) {
                return URL(fileURLWithPath: root)
            }
            return pwd
        }

        /// `shouldStop` is polled during the scan; returning true throws `CancellationError`.
        func scan(pwd: URL, shouldStop: () -> Bool = { Task.isCancelled }) throws -> FileTree {
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: pwd.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ScanError.noDirectory(pwd.path)
            }
            guard fileManager.isReadableFile(atPath: pwd.path) else {
                throw ScanError.unreadable(pwd.path)
            }

            let gitRoot = ProjectResolver.gitRoot(of: pwd.path)
            let root = gitRoot.map { URL(fileURLWithPath: $0) } ?? pwd
            let rootPath = root.standardizedFileURL.path
            let isHome = rootPath == URL(fileURLWithPath: homeDirectory).standardizedFileURL.path
            // A dotfiles repo at ~ or / would list every untracked file on disk; stick to tracked files there.
            let isBroadRoot = isHome || rootPath == "/"

            var all: [String]
            var complete = true
            if gitRoot != nil, let listed = try? Self.gitFiles(root: root, includeUntracked: !isBroadRoot) {
                all = listed
            } else {
                (all, complete) = try Self.walk(root: root, limit: fileCap, skipLibrary: isHome, shouldStop: shouldStop)
            }
            if shouldStop() { throw CancellationError() }

            let kept = all.count <= fileCap ? all : Self.shallowest(all, count: fileCap)
            return FileTree(rootName: root.lastPathComponent, rootPath: root.path, files: kept.sorted(),
                            totalFileCount: all.count, totalIsLowerBound: !complete)
        }

        /// The `count` files with the fewest path components, ties broken by path.
        private static func shallowest(_ files: [String], count: Int) -> [String] {
            let slash = UInt8(ascii: "/")
            let ranked: [(path: String, depth: Int)] = files.map { path in
                (path, path.utf8.filter { $0 == slash }.count)
            }
            let sorted = ranked.sorted { a, b in
                a.depth != b.depth ? a.depth < b.depth : a.path < b.path
            }
            return sorted.prefix(count).map { $0.path }
        }

        /// Tracked plus (optionally) untracked-but-not-ignored files.
        private static func gitFiles(root: URL, includeUntracked: Bool) throws -> [String] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path, "ls-files", "-z", "--cached"]
                + (includeUntracked ? ["--others", "--exclude-standard"] : [])
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            // Read before waiting so a large listing can't fill the pipe and deadlock.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ScanError.noDirectory(root.path) }
            return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
        }

        /// Breadth-first, so the shallowest files survive; stops once more than `limit` files are found.
        /// Returns whether the walk finished.
        private static func walk(root: URL, limit: Int, skipLibrary: Bool,
                                 shouldStop: () -> Bool) throws -> (files: [String], complete: Bool) {
            let fileManager = FileManager.default
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
            var files: [String] = []
            var queue: [(path: String, depth: Int)] = [("", 0)]
            var next = 0

            while next < queue.count {
                if shouldStop() { throw CancellationError() }
                let (relative, depth) = queue[next]
                next += 1

                let directory = relative.isEmpty ? root : root.appendingPathComponent(relative)
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }

                for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let name = entry.lastPathComponent
                    let path = relative.isEmpty ? name : relative + "/" + name
                    let values = try? entry.resourceValues(forKeys: Set(keys))
                    let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true

                    if isDirectory {
                        let skipped = skippedDirectories.contains(name)
                            || (skipLibrary && depth == 0 && name == "Library")
                            || depth + 1 >= maxWalkDepth
                        if !skipped { queue.append((path, depth + 1)) }
                    } else {
                        files.append(path)
                        if files.count > limit { return (files, false) }
                    }
                }
            }
            return (files, true)
        }
    }
}
