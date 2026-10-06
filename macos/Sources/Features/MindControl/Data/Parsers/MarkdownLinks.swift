import Foundation

extension MindControl {
    /// Local targets of Markdown links and images (no URLs, anchors-only or mail links).
    enum MarkdownLinks {
        private static let pattern = ParserSupport.regex(#"!?\[[^\]\n]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)"#)

        static func targets(in source: String) -> [String] {
            ParserSupport.captures(pattern, in: source).compactMap { raw in
                guard !raw.contains("://"), !raw.hasPrefix("#"), !raw.hasPrefix("mailto:") else { return nil }
                var target = raw
                if let cut = target.firstIndex(where: { $0 == "#" || $0 == "?" }) {
                    target = String(target[..<cut])
                }
                target = target.removingPercentEncoding ?? target
                return target.isEmpty ? nil : target
            }
        }
    }
}
