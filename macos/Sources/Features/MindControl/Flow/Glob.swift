import Foundation

extension MindControl {
    /// Path patterns relative to the project root: `*` matches within one folder name, `**` across
    /// folders (including none), `?` one character. A pattern with no wildcard also matches everything
    /// inside it when it names a folder.
    enum Glob {
        static func regex(for pattern: String) -> NSRegularExpression {
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
            if !pattern.contains("*"), !pattern.contains("?") {
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
            guard let index = pattern.firstIndex(where: { $0 == "*" || $0 == "?" }) else { return pattern.count }
            return pattern.distance(from: pattern.startIndex, to: index)
        }
    }
}
