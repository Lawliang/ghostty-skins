import Foundation

extension MindControl {
    /// Shared helpers for the line/regex based import parsers.
    enum ParserSupport {
        /// Compiles a constant pattern. A bad pattern is a programming error caught by the parser tests.
        static func regex(_ pattern: String) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }

        /// The first participating capture group of every match, in order.
        static func captures(_ regex: NSRegularExpression, in source: String) -> [String] {
            let text = source as NSString
            return regex.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
                for group in 1..<match.numberOfRanges {
                    let range = match.range(at: group)
                    if range.location != NSNotFound { return text.substring(with: range) }
                }
                return nil
            }
        }

        /// Joins a relative path onto a directory, resolving `.` and `..`. Nil if it climbs above the root.
        static func join(_ directory: String, _ relative: String) -> String? {
            var parts = directory.split(separator: "/").map(String.init)
            for part in relative.split(separator: "/") {
                switch part {
                case ".":
                    continue
                case "..":
                    guard !parts.isEmpty else { return nil }
                    parts.removeLast()
                default:
                    parts.append(String(part))
                }
            }
            return parts.joined(separator: "/")
        }

        /// The directory part of a relative path ("" at the root).
        static func directory(of path: String) -> String {
            guard let slash = path.lastIndex(of: "/") else { return "" }
            return String(path[..<slash])
        }
    }
}
