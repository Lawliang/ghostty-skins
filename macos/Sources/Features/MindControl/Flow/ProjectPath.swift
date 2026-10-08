import Foundation

extension MindControl {
    /// Paths a flow map names, relative to the project root. None may lead outside it.
    enum ProjectPath {
        /// `path` with `.`, `..` and empty components resolved; nil when it's absolute, names the root itself,
        /// or climbs out of it.
        static func normalized(_ path: String) -> String? {
            guard !path.hasPrefix("/") else { return nil }
            var parts: [Substring] = []
            for component in path.split(separator: "/") {
                switch component {
                case ".": continue
                case "..":
                    guard !parts.isEmpty else { return nil }
                    parts.removeLast()
                default: parts.append(component)
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: "/")
        }

        /// The file `path` names under `root`; nil when it leads outside, by its text or, for a file that
        /// exists, through a symbolic link.
        static func url(for path: String, in root: URL) -> URL? {
            guard let relative = normalized(path) else { return nil }
            let url = root.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { return url }
            let base = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            let target = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard target.count > base.count, Array(target.prefix(base.count)) == base else { return nil }
            return url
        }
    }
}
