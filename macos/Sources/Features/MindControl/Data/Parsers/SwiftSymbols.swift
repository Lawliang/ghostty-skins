import Foundation

extension MindControl {
    /// Type names a Swift file declares; used to check part anchors and to search by type.
    enum SwiftSymbols {
        private static let declaration = ParserSupport.regex(
            #"^[ \t]*(?:@\w+(?:\([^)\n]*\))?[ \t]+)*"# +
            #"((?:(?:public|package|internal|open|private|fileprivate|final|indirect|nonisolated|distributed)(?:\([^)\n]*\))?[ \t]+)*)"# +
            #"(?:class|struct|enum|protocol|actor|typealias)[ \t]+([A-Z]\w*)"#)

        /// Capitalised type names declared in the file. `private`/`fileprivate` ones are left out
        /// unless `includePrivate` is true.
        static func declaredTypes(in source: String, includePrivate: Bool = false) -> [String] {
            let text = source as NSString
            return declaration.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
                let modifiersRange = match.range(at: 1)
                let modifiers = modifiersRange.location == NSNotFound ? "" : text.substring(with: modifiersRange)
                if !includePrivate, modifiers.contains("private") { return nil }
                return text.substring(with: match.range(at: 2))
            }
        }
    }
}
