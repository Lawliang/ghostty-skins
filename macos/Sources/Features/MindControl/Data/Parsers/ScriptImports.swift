import Foundation

extension MindControl {
    /// Relative module specifiers from TypeScript/JavaScript import, export-from, require and dynamic import.
    enum ScriptImports {
        static let extensions = ["ts", "tsx", "js", "jsx", "mjs", "cjs"]

        private static let pattern = ParserSupport.regex(
            // The span before `from` is bounded so quote-free generated files can't make matching quadratic.
            #"(?:import|export)\s[^'"`;]{0,300}?\sfrom\s*['"]([^'"]+)['"]"# + "|" +
            #"\bimport\s*['"]([^'"]+)['"]"# + "|" +
            #"\brequire\(\s*['"]([^'"]+)['"]\s*\)"# + "|" +
            #"\bimport\(\s*['"]([^'"]+)['"]\s*\)"#)

        static func specifiers(in source: String) -> [String] {
            ParserSupport.captures(pattern, in: source).filter { $0.hasPrefix("./") || $0.hasPrefix("../") }
        }
    }
}
