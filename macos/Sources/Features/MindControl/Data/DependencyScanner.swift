import Foundation

extension MindControl {
    /// `from` uses something defined in `to`; both are paths relative to the project root.
    struct Dependency: Hashable, Sendable {
        let from: String
        let to: String
    }

    /// Finds file-to-file relationships: imports, Swift type references and Markdown links.
    enum DependencyScanner {
        static let maxFileBytes = 512 * 1024
        static let maxPerFile = 40
        static let maxTotal = 30_000
        /// A Swift type name declared in more files than this is too ambiguous to link.
        static let maxDeclarers = 3

        static func scan(tree: FileTree, shouldStop: () -> Bool = { Task.isCancelled }) throws -> [Dependency] {
            let root = URL(fileURLWithPath: tree.rootPath)
            let files = Set(tree.files)

            // Swift needs a project-wide index of which file declares which type.
            var swiftSources: [String: String] = [:]
            var declarers: [String: Set<String>] = [:]
            for path in tree.files where path.hasSuffix(".swift") {
                if shouldStop() { throw CancellationError() }
                guard let source = read(path, root: root) else { continue }
                swiftSources[path] = source
                for name in SwiftSymbols.declaredTypes(in: source) {
                    declarers[name, default: []].insert(path)
                }
            }
            declarers = declarers.filter { $0.value.count <= maxDeclarers }

            var result: [Dependency] = []
            for path in tree.files {
                if shouldStop() { throw CancellationError() }
                guard let targets = targets(of: path, root: root, files: files,
                                            swiftSources: swiftSources, declarers: declarers) else { continue }
                for target in targets.subtracting([path]).sorted().prefix(maxPerFile) {
                    result.append(Dependency(from: path, to: target))
                    if result.count >= maxTotal { return result }
                }
            }
            return result
        }

        private static func targets(of path: String, root: URL, files: Set<String>,
                                    swiftSources: [String: String], declarers: [String: Set<String>]) -> Set<String>? {
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "swift" {
                guard let source = swiftSources[path] else { return nil }
                return Set(SwiftSymbols.typeLikeIdentifiers(in: source).flatMap { declarers[$0] ?? [] })
            }
            let isScript = ScriptImports.extensions.contains(ext)
            guard ["zig", "py", "md", "markdown"].contains(ext) || isScript,
                  let source = read(path, root: root) else { return nil }
            switch ext {
            case "zig":
                return Set(ZigImports.specifiers(in: source).compactMap { resolveRelative($0, from: path, in: files) })
            case "py":
                return Set(PythonImports.imports(in: source).flatMap { resolvePython($0, from: path, in: files) })
            case "md", "markdown":
                return Set(MarkdownLinks.targets(in: source).compactMap { resolveMarkdown($0, from: path, in: files) })
            default:
                return Set(ScriptImports.specifiers(in: source).compactMap { resolveScript($0, from: path, in: files) })
            }
        }

        /// UTF-8 contents, or nil for missing, oversized or non-UTF-8 files.
        private static func read(_ path: String, root: URL) -> String? {
            let url = root.appendingPathComponent(path)
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxFileBytes,
                  let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private static func child(_ directory: String, _ name: String) -> String {
            directory.isEmpty ? name : (name.isEmpty ? directory : directory + "/" + name)
        }

        static func resolveRelative(_ spec: String, from path: String, in files: Set<String>) -> String? {
            guard let joined = ParserSupport.join(ParserSupport.directory(of: path), spec), files.contains(joined) else { return nil }
            return joined
        }

        static func resolveScript(_ spec: String, from path: String, in files: Set<String>) -> String? {
            guard let base = ParserSupport.join(ParserSupport.directory(of: path), spec) else { return nil }
            let candidates = [base]
                + ScriptImports.extensions.map { "\(base).\($0)" }
                + ScriptImports.extensions.map { "\(base)/index.\($0)" }
            return candidates.first { files.contains($0) }
        }

        static func resolveMarkdown(_ target: String, from path: String, in files: Set<String>) -> String? {
            let directory = target.hasPrefix("/") ? "" : ParserSupport.directory(of: path)
            guard let joined = ParserSupport.join(directory, target), files.contains(joined) else { return nil }
            return joined
        }

        static func resolvePython(_ statement: PythonImports.Import, from path: String, in files: Set<String>) -> [String] {
            let dots = statement.module.prefix { $0 == "." }.count
            let modulePath = statement.module.dropFirst(dots).split(separator: ".").joined(separator: "/")

            var bases: [String] = []
            if dots > 0 {
                // One dot is the importing file's package; each extra dot climbs a level.
                var directory = ParserSupport.directory(of: path)
                for _ in 0..<(dots - 1) {
                    guard !directory.isEmpty else { return [] }
                    directory = ParserSupport.directory(of: directory)
                }
                bases.append(child(directory, modulePath))
            } else {
                bases.append(modulePath)
                let directory = ParserSupport.directory(of: path)
                if !directory.isEmpty { bases.append(child(directory, modulePath)) }
            }

            func moduleFile(_ base: String) -> String? {
                guard !base.isEmpty else { return nil }
                return [base + ".py", base + "/__init__.py"].first { files.contains($0) }
            }

            for base in bases {
                var found: [String] = []
                if let file = moduleFile(base) { found.append(file) }
                for name in statement.names where name != "*" {
                    if let file = moduleFile(child(base, name)) { found.append(file) }
                }
                if !found.isEmpty { return found }
            }
            return []
        }
    }
}
