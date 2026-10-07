#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias ProjectScanner = MindControl.ProjectScanner
private typealias ScanError = MindControl.ScanError

private extension MindControl.ProjectScanner {
    /// A scanner that keeps every file, for tests about scanning mechanics rather than filtering.
    static var everything: Self {
        var scanner = Self()
        scanner.includes = { _ in true }
        return scanner
    }
}

struct ProjectScannerTests {
    /// A fresh temporary directory, removed when the test ends.
    private final class TempDir {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("mc-scan-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }

        func file(_ path: String) throws {
            let target = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: target)
        }

        @discardableResult
        func git(_ args: String...) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", url.path] + args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
    }

    @Test func gitRepoRespectsIgnoreAndIncludesUntracked() throws {
        let dir = try TempDir()
        try dir.git("init", "-q")
        try dir.file(".gitignore")
        try Data("ignored/\n*.log\n".utf8).write(to: dir.url.appendingPathComponent(".gitignore"))
        try dir.file("src/main.swift")
        try dir.file("README.md")
        try dir.file("ignored/secret.txt")
        try dir.file("debug.log")
        try dir.git("add", "src/main.swift", ".gitignore")
        let tree = try ProjectScanner.everything.scan(pwd: dir.url)
        #expect(tree.files == [".gitignore", "README.md", "src/main.swift"])
        #expect(tree.totalFileCount == 3)
        #expect(!tree.truncated)
    }

    @Test func subfolderPwdResolvesToGitRoot() throws {
        let dir = try TempDir()
        try dir.git("init", "-q")
        try dir.file("top.txt")
        try dir.file("deep/inner/file.swift")
        let tree = try ProjectScanner.everything.scan(pwd: dir.url.appendingPathComponent("deep/inner"))
        #expect(tree.rootName == dir.url.lastPathComponent)
        #expect(tree.files.contains("top.txt"))
    }

    @Test func plainDirectoryHonoursSkipList() throws {
        let dir = try TempDir()
        try dir.file("app/main.zig")
        try dir.file("node_modules/pkg/index.js")
        try dir.file("zig-out/bin/app")
        try dir.file(".hidden/config")
        try dir.file(".env")
        let tree = try ProjectScanner.everything.scan(pwd: dir.url)
        #expect(tree.files == ["app/main.zig"])
    }

    @Test func plainDirectoryStopsAtMaxDepth() throws {
        let dir = try TempDir()
        let deep = (1...14).map { "d\($0)" }.joined(separator: "/")
        try dir.file(deep + "/too-deep.txt")
        try dir.file("d1/shallow.txt")
        let tree = try ProjectScanner.everything.scan(pwd: dir.url)
        #expect(tree.files == ["d1/shallow.txt"])
    }

    @Test func capKeepsShallowFilesFirst() throws {
        let dir = try TempDir()
        try dir.file("z-top.txt")
        for i in 0..<5 { try dir.file("a/b/deep\(i).txt") }
        var scanner = ProjectScanner.everything
        scanner.fileCap = 3
        let tree = try scanner.scan(pwd: dir.url)
        #expect(tree.files.count == 3)
        #expect(tree.files.contains("z-top.txt"))
        #expect(tree.truncated)
        #expect(tree.totalIsLowerBound)       // the walk stops at the cap instead of counting everything
    }

    @Test func brokenGitFallsBackToWalk() throws {
        let dir = try TempDir()
        try dir.file(".git")          // a `.git` file that isn't a valid gitdir pointer
        try dir.file("main.c")
        let tree = try ProjectScanner.everything.scan(pwd: dir.url)
        #expect(tree.files == ["main.c"])
    }

    @Test func missingDirectoryThrows() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(throws: ScanError.noDirectory(missing.path)) {
            try ProjectScanner.everything.scan(pwd: missing)
        }
    }

    @Test func gitCapReportsExactTotal() throws {
        let dir = try TempDir()
        try dir.git("init", "-q")
        for i in 0..<6 { try dir.file("f\(i).txt") }
        var scanner = ProjectScanner.everything
        scanner.fileCap = 3
        let tree = try scanner.scan(pwd: dir.url)
        #expect(tree.files.count == 3)
        #expect(tree.totalFileCount == 6)
        #expect(!tree.totalIsLowerBound)
    }

    @Test func walkStopsEarlyOnHugeTrees() throws {
        let dir = try TempDir()
        for i in 0..<50 { try dir.file("top\(i).txt") }
        for i in 0..<200 { try dir.file("a/b/c/deep\(i).txt") }
        var scanner = ProjectScanner.everything
        scanner.fileCap = 10
        let tree = try scanner.scan(pwd: dir.url)
        #expect(tree.files.count == 10)
        #expect(tree.files.allSatisfy { $0.hasPrefix("top") })   // breadth-first: shallow files win
        #expect(tree.totalFileCount <= 11)                       // stopped right after the cap, never walked a/b/c
    }

    @Test func unreadableDirectoryThrows() throws {
        let dir = try TempDir()
        let locked = dir.url.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(throws: ScanError.unreadable(locked.path)) {
            try ProjectScanner.everything.scan(pwd: locked)
        }
    }

    @Test func stopRequestCancelsScan() throws {
        let dir = try TempDir()
        try dir.file("a.txt")
        #expect(throws: CancellationError.self) {
            try ProjectScanner.everything.scan(pwd: dir.url, shouldStop: { true })
        }
    }

    @Test func homeLibraryIsSkipped() throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/huge.bin")
        try dir.file("Documents/notes.md")
        var scanner = ProjectScanner.everything
        scanner.homeDirectory = dir.url.path
        #expect(try scanner.scan(pwd: dir.url).files == ["Documents/notes.md"])
    }

    @Test func defaultScannerKeepsOnlyFeatureSourceInGitRepos() throws {
        let dir = try TempDir()
        try dir.git("init", "-q")
        for path in ["app/Sources/App.swift", "app/Tests/AppTests.swift", "docs/plan.md", "README.md",
                     "harness/run.py", "assets/logo.png", "config.json", "relay/server.ts"] {
            try dir.file(path)
        }
        let tree = try ProjectScanner().scan(pwd: dir.url)
        #expect(tree.files == ["app/Sources/App.swift", "relay/server.ts"])
        #expect(tree.totalFileCount == 2)
    }

    @Test func defaultScannerKeepsOnlyFeatureSourceInPlainFolders() throws {
        let dir = try TempDir()
        for path in ["src/main.zig", "src/main_test.go", "scripts/build.sh", "docs/guide.md", "tests/test_core.py"] {
            try dir.file(path)
        }
        #expect(try ProjectScanner().scan(pwd: dir.url).files == ["src/main.zig"])
    }

    @Test func capCountsOnlyKeptFiles() throws {
        let dir = try TempDir()
        for i in 0..<20 { try dir.file("notes/n\(i).md") }
        for i in 0..<5 { try dir.file("src/s\(i).swift") }
        var scanner = ProjectScanner()
        scanner.fileCap = 5
        let tree = try scanner.scan(pwd: dir.url)
        #expect(tree.files.count == 5)
        #expect(!tree.truncated)                 // 20 notes were never candidates
    }
}
#endif
