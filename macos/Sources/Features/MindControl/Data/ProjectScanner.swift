import Foundation

extension MindControl {
    /// A project's files as sorted, "/"-separated paths relative to the root.
    struct FileTree: Equatable, Sendable {
        let rootName: String
        let rootPath: String
        let files: [String]
        /// Files found before the cap was applied.
        let totalFileCount: Int

        var truncated: Bool { files.count < totalFileCount }
    }

    enum ScanError: Error, Equatable {
        case noDirectory(String)
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

        /// The git root containing `pwd`, or `pwd` itself outside git.
        static func projectRoot(for pwd: URL) -> URL {
            if let root = ProjectResolver.gitRoot(of: pwd.path) {
                return URL(fileURLWithPath: root)
            }
            return pwd
        }

        func scan(pwd: URL) throws -> FileTree {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: pwd.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ScanError.noDirectory(pwd.path)
            }

            let root = Self.projectRoot(for: pwd)
            let isGit = ProjectResolver.gitRoot(of: pwd.path) != nil
            let all = (isGit ? try? Self.gitFiles(root: root) : nil) ?? Self.walk(root: root)

            // Over the cap, keep the shallowest files so the top-level structure survives.
            let kept = all.count <= fileCap ? all : Array(all.sorted { a, b in
                let da = a.split(separator: "/").count, db = b.split(separator: "/").count
                return da != db ? da < db : a < b
            }.prefix(fileCap))

            return FileTree(rootName: root.lastPathComponent, rootPath: root.path, files: kept.sorted(), totalFileCount: all.count)
        }

        /// Tracked plus untracked-but-not-ignored files.
        private static func gitFiles(root: URL) throws -> [String] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
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

        private static func walk(root: URL) -> [String] {
            guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }
            var files: [String] = []
            while let relative = enumerator.nextObject() as? String {
                let name = (relative as NSString).lastPathComponent
                let isDirectory = (enumerator.fileAttributes?[.type] as? FileAttributeType) == .typeDirectory
                if name.hasPrefix(".") {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
                if isDirectory {
                    if skippedDirectories.contains(name) || enumerator.level >= maxWalkDepth {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                files.append(relative)
            }
            return files
        }
    }
}
