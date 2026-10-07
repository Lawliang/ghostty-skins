import Foundation

extension MindControl {
    /// Decides which files implement features: source code that isn't docs, scripts and tooling,
    /// tests, samples, assets or config. Only these files appear on the map.
    enum SourceFilter {
        static let sourceExtensions: Set<String> = [
            "swift", "m", "mm", "h", "hh", "hpp", "c", "cc", "cpp", "cxx", "zig", "rs", "go", "py",
            "ts", "tsx", "js", "jsx", "mjs", "cjs", "kt", "kts", "java", "rb", "cs", "metal", "dart",
            "lua", "vue", "svelte", "ino",
        ]

        /// Folder names (compared lowercased) whose contents never implement features.
        static let excludedDirectories: Set<String> = [
            "docs", "doc", "documentation",
            "scripts", "script", "tools", "tooling", "harness", "plugins", "plugin", "bin",
            "examples", "example", "samples", "sample", "benchmarks", "benchmark", "bench",
            "tests", "test", "__tests__", "spec", "specs", "fixtures", "fixture", "testdata", "mocks", "__mocks__",
            ".github", ".claude", ".codex", ".vscode", ".idea",
        ]

        static func isFeatureSource(_ path: String) -> Bool {
            let parts = path.split(separator: "/").map(String.init)
            guard let name = parts.last,
                  sourceExtensions.contains((name as NSString).pathExtension.lowercased()) else { return false }
            if parts.dropLast().contains(where: isExcludedDirectory) { return false }
            return !isTestFile(name)
        }

        static func isExcludedDirectory(_ name: String) -> Bool {
            excludedDirectories.contains(name.lowercased())
                || name.hasSuffix("Tests") || name.hasSuffix("-tests") || name.hasSuffix("_tests")
        }

        /// `ModelTests.swift`, `server_test.go`, `test_core.py`, `app.test.ts`, `app.spec.js`, …
        static func isTestFile(_ name: String) -> Bool {
            let base = (name as NSString).deletingPathExtension
            let lower = base.lowercased()
            return base.hasSuffix("Tests") || base.hasSuffix("Test") || base.hasSuffix("Spec")
                || lower.hasPrefix("test_") || lower.hasSuffix("_test")
                || lower.hasSuffix(".test") || lower.hasSuffix(".spec")
        }
    }
}
