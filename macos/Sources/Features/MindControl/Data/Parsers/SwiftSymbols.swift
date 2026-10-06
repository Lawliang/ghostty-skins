import Foundation

extension MindControl {
    /// Swift files don't import each other, so relationships come from type names:
    /// which types a file declares, and which declared types it mentions.
    enum SwiftSymbols {
        /// Standard library, Foundation and SwiftUI names that projects also declare as nested types.
        /// Linking every mention of these to the project's declaration would draw false dependencies.
        static let frameworkTypeNames: Set<String> = [
            "Action", "Any", "AnyObject", "Array", "Binding", "Bool", "Button", "Character", "Codable", "Color",
            "Configuration", "Context", "Coordinator", "Data", "Date", "Dictionary", "Double", "Element",
            "Environment", "Error", "Event", "Float", "Font", "Group", "ID", "Image", "Index", "Int", "Item",
            "Key", "Kind", "Label", "List", "Mode", "Never", "Notification", "Optional", "Options", "Published",
            "Result", "Section", "Self", "Set", "Shape", "State", "Status", "String", "Style", "Text", "Type",
            "URL", "UUID", "Value", "View", "Void",
        ]

        private static let declaration = ParserSupport.regex(
            #"^[ \t]*(?:@\w+(?:\([^)\n]*\))?[ \t]+)*"# +
            #"((?:(?:public|internal|open|private|fileprivate|final|indirect|nonisolated)(?:\([^)\n]*\))?[ \t]+)*)"# +
            #"(?:class|struct|enum|protocol|actor|typealias)[ \t]+([A-Z]\w*)"#)

        /// Capitalised type names declared in the file, excluding `private`/`fileprivate` ones.
        static func declaredTypes(in source: String) -> [String] {
            let text = source as NSString
            return declaration.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
                let modifiersRange = match.range(at: 1)
                let modifiers = modifiersRange.location == NSNotFound ? "" : text.substring(with: modifiersRange)
                if modifiers.contains("private") { return nil }
                return text.substring(with: match.range(at: 2))
            }
        }

        /// Capitalised identifiers outside comments and string literals.
        static func typeLikeIdentifiers(in source: String) -> Set<String> {
            let bytes = Array(source.utf8)
            let count = bytes.count
            let slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), quote = UInt8(ascii: "\"")
            let backslash = UInt8(ascii: "\\"), newline = UInt8(ascii: "\n")
            var result = Set<String>()
            var i = 0

            func isIdentifierStart(_ b: UInt8) -> Bool { (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 }
            func isIdentifier(_ b: UInt8) -> Bool { isIdentifierStart(b) || (b >= 48 && b <= 57) }

            while i < count {
                let b = bytes[i]
                if b == slash, i + 1 < count, bytes[i + 1] == slash {
                    while i < count, bytes[i] != newline { i += 1 }
                    continue
                }
                if b == slash, i + 1 < count, bytes[i + 1] == star {
                    var depth = 1
                    i += 2
                    while i < count, depth > 0 {
                        if bytes[i] == slash, i + 1 < count, bytes[i + 1] == star {
                            depth += 1; i += 2
                        } else if bytes[i] == star, i + 1 < count, bytes[i + 1] == slash {
                            depth -= 1; i += 2
                        } else {
                            i += 1
                        }
                    }
                    continue
                }
                if b == quote {
                    if i + 2 < count, bytes[i + 1] == quote, bytes[i + 2] == quote {
                        i += 3
                        while i + 2 < count, !(bytes[i] == quote && bytes[i + 1] == quote && bytes[i + 2] == quote) { i += 1 }
                        i += 3
                        continue
                    }
                    i += 1
                    while i < count, bytes[i] != quote, bytes[i] != newline {
                        if bytes[i] == backslash { i += 1 }
                        i += 1
                    }
                    i += 1
                    continue
                }
                if isIdentifierStart(b) {
                    let start = i
                    while i < count, isIdentifier(bytes[i]) { i += 1 }
                    // `@State`, `@MainActor`: attributes aren't references to project types.
                    let isAttribute = start > 0 && bytes[start - 1] == UInt8(ascii: "@")
                    if b >= 65, b <= 90, !isAttribute { result.insert(String(decoding: bytes[start..<i], as: UTF8.self)) }
                    continue
                }
                i += 1
            }
            return result
        }
    }
}
