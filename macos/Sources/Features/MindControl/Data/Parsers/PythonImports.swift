import Foundation

extension MindControl {
    /// `import a.b` and `from x import y` statements (single-line forms).
    enum PythonImports {
        struct Import: Equatable {
            /// Dotted module, with leading dots for relative imports ("." alone for `from . import x`).
            let module: String
            /// Names after `import` in a `from` statement; empty for plain `import`.
            let names: [String]
        }

        private static let plain = ParserSupport.regex(#"^[ \t]*import[ \t]+([^\n#]+)"#)
        private static let from = ParserSupport.regex(#"^[ \t]*from[ \t]+(\.*[\w.]*)[ \t]+import[ \t]+\(?([^\n#)]+)"#)

        static func imports(in source: String) -> [Import] {
            let text = source as NSString
            let range = NSRange(location: 0, length: text.length)
            var result: [Import] = []
            for match in plain.matches(in: source, range: range) {
                for part in text.substring(with: match.range(at: 1)).split(separator: ",") {
                    if let module = firstWord(part) { result.append(Import(module: module, names: [])) }
                }
            }
            for match in from.matches(in: source, range: range) {
                let module = text.substring(with: match.range(at: 1))
                let names = text.substring(with: match.range(at: 2)).split(separator: ",").compactMap(firstWord)
                result.append(Import(module: module, names: names))
            }
            return result
        }

        /// "pkg.mod as m" → "pkg.mod".
        private static func firstWord(_ part: Substring) -> String? {
            part.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
        }
    }
}
