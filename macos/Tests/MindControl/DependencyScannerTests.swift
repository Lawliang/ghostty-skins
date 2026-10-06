#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias DependencyScanner = MindControl.DependencyScanner
private typealias Dependency = MindControl.Dependency
private typealias FileTree = MindControl.FileTree

struct DependencyScannerTests {
    /// A temporary project; `tree` lists every file written.
    private final class Project {
        let url: URL
        private(set) var files: [String] = []

        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("mc-deps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }

        func write(_ path: String, _ contents: String) throws {
            try write(path, Data(contents.utf8))
        }

        func write(_ path: String, _ data: Data) throws {
            let target = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
            files.append(path)
        }

        var tree: FileTree {
            FileTree(rootName: url.lastPathComponent, rootPath: url.path, files: files.sorted(), totalFileCount: files.count)
        }
    }

    private func scan(_ project: Project) throws -> Set<Dependency> {
        Set(try DependencyScanner.scan(tree: project.tree))
    }

    @Test func zigRelativeImports() throws {
        let p = try Project()
        try p.write("src/main.zig", #"const t = @import("terminal/Terminal.zig"); const std = @import("std");"#)
        try p.write("src/terminal/Terminal.zig", #"const page = @import("../page.zig");"#)
        try p.write("src/page.zig", "")
        #expect(try scan(p) == [Dependency(from: "src/main.zig", to: "src/terminal/Terminal.zig"),
                                Dependency(from: "src/terminal/Terminal.zig", to: "src/page.zig")])
    }

    @Test func scriptImportsResolveExtensionsAndIndex() throws {
        let p = try Project()
        try p.write("web/app.ts", "import { a } from './lib/a';\nimport b from './lib';\nimport x from 'react';")
        try p.write("web/lib/a.tsx", "")
        try p.write("web/lib/index.js", "")
        #expect(try scan(p) == [Dependency(from: "web/app.ts", to: "web/lib/a.tsx"),
                                Dependency(from: "web/app.ts", to: "web/lib/index.js")])
    }

    @Test func pythonImportsResolveModulesAndPackages() throws {
        let p = try Project()
        try p.write("pkg/__init__.py", "")
        try p.write("pkg/util.py", "")
        try p.write("pkg/sub/__init__.py", "")
        try p.write("pkg/sub/mod.py", "from .. import util\nfrom . import helper\nimport os")
        try p.write("pkg/sub/helper.py", "")
        try p.write("main.py", "import pkg.util\nfrom pkg.sub import mod")
        // A `from X import name` statement depends on package X (its __init__.py) as well as `name`.
        #expect(try scan(p) == [
            Dependency(from: "pkg/sub/mod.py", to: "pkg/__init__.py"),
            Dependency(from: "pkg/sub/mod.py", to: "pkg/util.py"),
            Dependency(from: "pkg/sub/mod.py", to: "pkg/sub/__init__.py"),
            Dependency(from: "pkg/sub/mod.py", to: "pkg/sub/helper.py"),
            Dependency(from: "main.py", to: "pkg/util.py"),
            Dependency(from: "main.py", to: "pkg/sub/__init__.py"),
            Dependency(from: "main.py", to: "pkg/sub/mod.py"),
        ])
    }

    @Test func pythonResolvesSiblingsOfTheImportingFile() throws {
        let p = try Project()
        try p.write("scripts/run.py", "import helpers")
        try p.write("scripts/helpers.py", "")
        #expect(try scan(p) == [Dependency(from: "scripts/run.py", to: "scripts/helpers.py")])
    }

    @Test func markdownLinksToProjectFiles() throws {
        let p = try Project()
        try p.write("README.md", "[guide](docs/guide.md#start) [web](https://x.y) [missing](nope.md)")
        try p.write("docs/guide.md", "[back](../README.md) [code](/src/main.zig)")
        try p.write("src/main.zig", "")
        #expect(try scan(p) == [Dependency(from: "README.md", to: "docs/guide.md"),
                                Dependency(from: "docs/guide.md", to: "README.md"),
                                Dependency(from: "docs/guide.md", to: "src/main.zig")])
    }

    @Test func swiftTypeReferences() throws {
        let p = try Project()
        try p.write("A.swift", "struct Alpha {}\nlet b = Beta()")
        try p.write("B.swift", "final class Beta { let a: Alpha? = nil }\n// Gamma in a comment")
        try p.write("C.swift", "enum Gamma {}\nprivate struct Secret {}")
        try p.write("D.swift", "let s: Secret? = nil")
        #expect(try scan(p) == [Dependency(from: "A.swift", to: "B.swift"),
                                Dependency(from: "B.swift", to: "A.swift")])
    }

    @Test func ambiguousSwiftNamesAreSkipped() throws {
        let p = try Project()
        for i in 0..<4 { try p.write("M\(i).swift", "struct Model {}") }
        try p.write("Use.swift", "let m = Model()")
        #expect(try scan(p).isEmpty)
    }

    @Test func capsPerFileAndTotal() throws {
        let p = try Project()
        let imports = (0..<60).map { "@import(\"t\($0).zig\");" }.joined(separator: "\n")
        try p.write("hub.zig", imports)
        for i in 0..<60 { try p.write("t\(i).zig", "") }
        let deps = try DependencyScanner.scan(tree: p.tree)
        #expect(deps.count == DependencyScanner.maxPerFile)
        #expect(Set(deps).count == deps.count)
    }

    @Test func unreadableAndHugeFilesAreSkipped() throws {
        let p = try Project()
        try p.write("binary.ts", Data([0xFF, 0xFE, 0x00, 0x80, 0x27]))
        try p.write("huge.zig", String(repeating: "// x\n", count: 120_000) + #"@import("t.zig");"#)
        try p.write("t.zig", "")
        try p.write("ok.zig", #"@import("t.zig");"#)
        #expect(try scan(p) == [Dependency(from: "ok.zig", to: "t.zig")])
    }

    @Test func selfReferencesAreDropped() throws {
        let p = try Project()
        try p.write("Loop.swift", "struct Loop { var next: Loop? }")
        #expect(try scan(p).isEmpty)
    }

    @Test func stopRequestCancels() throws {
        let p = try Project()
        try p.write("a.zig", "")
        #expect(throws: CancellationError.self) {
            try DependencyScanner.scan(tree: p.tree, shouldStop: { true })
        }
    }

    @Test func frameworkNamesAndAttributesDontLink() throws {
        let p = try Project()
        try p.write("Model.swift", "enum Store {\n    struct State {}\n}\nenum Failure {\n    struct Error {}\n}\nstruct Widget {}")
        try p.write("View.swift", "struct Screen { @State var on = false\n func f() throws -> Error? { nil } }")
        try p.write("Uses.swift", "let w = Widget()")
        #expect(try scan(p) == [Dependency(from: "Uses.swift", to: "Model.swift")])
    }

    @Test func onlyRegularFilesAreRead() throws {
        let p = try Project()
        try p.write("ok.zig", "")
        let pipe = p.url.appendingPathComponent("pipe.zig")
        #expect(mkfifo(pipe.path, 0o644) == 0)
        #expect(DependencyScanner.isRegularFile(p.url.appendingPathComponent("ok.zig")))
        #expect(!DependencyScanner.isRegularFile(pipe))
        #expect(!DependencyScanner.isRegularFile(p.url.appendingPathComponent("missing.zig")))
    }
}
#endif
