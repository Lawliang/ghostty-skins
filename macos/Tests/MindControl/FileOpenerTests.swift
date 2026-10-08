#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FileOpener = MindControl.FileOpener

struct FileOpenerTests {
    private static let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    private static let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    private static let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")

    /// Real file checks, made-up apps: scripts and Terminal files open in Terminal, everything else in TextEdit,
    /// and the source editor is TextEdit unless `editor` says otherwise.
    private func apps(defaultApp: URL? = nil, editor: URL? = FileOpenerTests.textEdit) -> FileOpener.Apps {
        FileOpener.Apps(
            defaultApp: { url in
                if let defaultApp { return defaultApp }
                return ["", "command", "terminal", "tool"].contains(url.pathExtension) ? Self.terminal : Self.textEdit
            },
            editor: { editor },
            bundleID: { app in
                switch app {
                case Self.terminal: return "com.apple.Terminal"
                case Self.xcode: return "com.apple.dt.Xcode"
                default: return "com.apple.TextEdit"
                }
            })
    }

    private func project() throws -> TempProject {
        let project = try TempProject()
        try project.write("src/Main.swift", "let x = 1\n")
        try project.write("bin/cli", "#!/bin/sh\necho hi\n")
        try project.write("bin/tool.sh", "#!/bin/sh\necho hi\n")
        try project.write("run.command", "echo hi\n")
        try project.write("x.terminal", "<plist/>\n")
        try project.write("Thing.app/Contents/Info.plist", "<plist/>\n")
        for file in ["bin/cli", "bin/tool.sh"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: project.url.appendingPathComponent(file).path)
        }
        return project
    }

    @Test func plainSourceOpensInItsDefaultAppOrXcodeAtTheLine() throws {
        let p = try project()
        let main = p.url.appendingPathComponent("src/Main.swift")
        #expect(FileOpener.route(for: main, line: nil, apps: apps()) == .defaultApp)
        #expect(FileOpener.route(for: main, line: 3, apps: apps()) == .defaultApp)
        #expect(FileOpener.route(for: main, line: 3, apps: apps(defaultApp: Self.xcode)) == .xed(line: 3))
    }

    @Test(arguments: ["bin/cli", "bin/tool.sh", "run.command", "x.terminal"])
    func anythingThatWouldRunOpensInTheEditor(file: String) throws {
        let p = try project()
        let url = p.url.appendingPathComponent(file)
        #expect(FileOpener.route(for: url, line: nil, apps: apps()) == .app(Self.textEdit))
        // Even when its default app is a text editor.
        #expect(FileOpener.route(for: url, line: nil, apps: apps(defaultApp: Self.textEdit)) == .app(Self.textEdit))
    }

    @Test func withNoSafeEditorItIsRevealed() throws {
        let p = try project()
        #expect(FileOpener.route(for: p.url.appendingPathComponent("bin/cli"), line: nil, apps: apps(editor: nil)) == .reveal)
        #expect(FileOpener.route(for: p.url.appendingPathComponent("bin/cli"), line: nil, apps: apps(editor: Self.terminal)) == .reveal)
    }

    @Test func aFolderOrBundleIsRevealed() throws {
        let p = try project()
        #expect(FileOpener.route(for: p.url.appendingPathComponent("Thing.app"), line: nil, apps: apps()) == .reveal)
        #expect(FileOpener.route(for: p.url.appendingPathComponent("src"), line: nil, apps: apps()) == .reveal)
    }

    @Test func anExecutableIsNeverHandedToItsDefaultApp() throws {
        let p = try project()
        var calls: [String] = []
        let actions = FileOpener.Actions(
            open: { calls.append("open \($0.lastPathComponent)") },
            openWith: { url, app in calls.append("openWith \(url.lastPathComponent) \(app.lastPathComponent)") },
            reveal: { calls.append("reveal \($0.lastPathComponent)") },
            xed: { url, line in calls.append("xed \(url.lastPathComponent) \(line)"); return true })
        FileOpener.open(p.url.appendingPathComponent("bin/cli"), line: nil, apps: apps(), actions: actions)
        FileOpener.open(p.url.appendingPathComponent("run.command"), line: 2, apps: apps(), actions: actions)
        FileOpener.open(p.url.appendingPathComponent("src/Main.swift"), line: nil, apps: apps(), actions: actions)
        FileOpener.open(p.url.appendingPathComponent("src/Main.swift"), line: 4, apps: apps(defaultApp: Self.xcode), actions: actions)
        #expect(calls == ["openWith cli TextEdit.app", "openWith run.command TextEdit.app", "open Main.swift", "xed Main.swift 4"])
    }
}
#endif
