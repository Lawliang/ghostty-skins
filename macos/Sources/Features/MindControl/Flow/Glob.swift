import Foundation

extension MindControl {
    /// Path patterns relative to the project root: `*` matches within one folder name, `**` across
    /// folders (including none), `?` one character. A pattern with no wildcard also matches everything
    /// inside it when it names a folder, with or without a trailing `/`. As with git's `:(glob)`, a pattern
    /// with a wildcard and a trailing `/` matches no files.
    enum Glob {
        /// A plain folder pattern without its trailing `/`s ("relay/src/" → "relay/src").
        static func normalized(_ pattern: String) -> String {
            guard !hasWildcard(pattern) else { return pattern }
            var pattern = pattern
            while pattern.count > 1, pattern.hasSuffix("/") { pattern.removeLast() }
            return pattern
        }

        static func hasWildcard(_ pattern: String) -> Bool {
            pattern.contains("*") || pattern.contains("?")
        }

        static func regex(for pattern: String) -> NSRegularExpression {
            let pattern = normalized(pattern)
            var out = "^"
            let chars = Array(pattern)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                    if i + 2 < chars.count, chars[i + 2] == "/" {
                        out += "(?:.*/)?"
                        i += 3
                    } else {
                        out += ".*"
                        i += 2
                    }
                } else if c == "*" {
                    out += "[^/]*"
                    i += 1
                } else if c == "?" {
                    out += "[^/]"
                    i += 1
                } else {
                    out += NSRegularExpression.escapedPattern(for: String(c))
                    i += 1
                }
            }
            if !hasWildcard(pattern) {
                out += "(?:/.*)?"
            }
            out += "$"
            // swiftlint:disable:next force_try
            return try! NSRegularExpression(pattern: out)
        }

        static func matches(_ pattern: String, _ path: String) -> Bool {
            matches(regex(for: pattern), path)
        }

        static func matches(_ regex: NSRegularExpression, _ path: String) -> Bool {
            regex.firstMatch(in: path, range: NSRange(location: 0, length: (path as NSString).length)) != nil
        }

        /// How much of the pattern is fixed text before its first wildcard; longer is more specific.
        static func literalPrefixLength(_ pattern: String) -> Int {
            let pattern = normalized(pattern)
            guard let index = pattern.firstIndex(where: { $0 == "*" || $0 == "?" }) else { return pattern.count }
            return pattern.distance(from: pattern.startIndex, to: index)
        }
    }
}
