import Foundation

extension MindControl {
    /// `@import("…zig")` paths. Package imports like `@import("std")` don't end in `.zig` and are ignored.
    enum ZigImports {
        private static let pattern = ParserSupport.regex(#"@import\(\s*"([^"]+\.zig)"\s*\)"#)

        static func specifiers(in source: String) -> [String] {
            ParserSupport.captures(pattern, in: source)
        }
    }
}
