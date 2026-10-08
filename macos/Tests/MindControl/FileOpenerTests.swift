#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FileOpener = MindControl.FileOpener

struct FileOpenerTests {
    private static let pythonLauncher = URL(fileURLWithPath: "/Applications/Python 3.12/Python Launcher.app")
    private static let kitty = URL(fileURLWithPath: "/Applications/kitty.app")
    private static let ghosttyDebug = URL(fileURLWithPath: "/tmp/build/Debug/Ghostty.app")
    private static let cursor = URL(fileURLWithPath: "/Applications/Cursor.app")
    private static let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    private static let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")

    private static let ids: [URL: String] = [
        pythonLauncher: "org.python.PythonLauncher", kitty: "net.kovidgoyal.kitty", ghosttyDebug: "com.mitchellh.ghostty.debug",
        cursor: "com.todesktop.230313mzl4w4u92", textEdit: "com.apple.TextEdit", xcode: "com.apple.dt.Xcode",
    ]

    /// Real file checks, made-up apps.
    private func apps(default defaultApp: URL?, fallback: URL? = FileOpenerTests.textEdit) -> FileOpener.Apps {
        FileOpener.Apps(defaultApp: { _ in defaultApp }, fallbackEditor: { fallback }, bundleID: { Self.ids[$0] })
    }

    private func project() throws -> TempProject {
        let project = try TempProject()
        try project.write("src/Main.swift", "let x = 1\n")
        try project.write("src/pipe.ts", "export const x = 1\n")
        try project.write("tools/gen.py", "print('hi')\n")
        try project.write("tools/run.sh", "echo hi\n")
        try project.write("bin/cli", "#!/bin/sh\necho hi\n")
        try project.write("run.command", "echo hi\n")
        try project.write("x.terminal", "<plist/>\n")
        try project.write("wifi.mobileconfig", "<plist/>\n")
        try project.write("Thing.app/Contents/Info.plist", "<plist/>\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: project.url.appendingPathComponent("bin/cli").path)
        return project
    }

    private func route(_ p: TempProject, _ file: String, line: Int? = nil, _ apps: FileOpener.Apps) -> FileOpener.Route {
        FileOpener.route(for: p.url.appendingPathComponent(file), line: line, apps: apps)
    }

    @Test func aScriptWhoseDefaultAppRunsItGoesToTheFallbackEditor() throws {
        let p = try project()
        #expect(route(p, "tools/gen.py", apps(default: Self.pythonLauncher)) == .app(Self.textEdit))
        #expect(route(p, "tools/run.sh", apps(default: Self.kitty)) == .app(Self.textEdit))
        #expect(route(p, "tools/run.sh", apps(default: Self.ghosttyDebug)) == .app(Self.textEdit))
        // The fallback is Xcode when installed, at the line.
        #expect(route(p, "tools/gen.py", line: 5, apps(default: Self.pythonLauncher, fallback: Self.xcode)) == .xed(line: 5, app: Self.xcode))
        #expect(route(p, "tools/gen.py", apps(default: Self.pythonLauncher, fallback: Self.xcode)) == .app(Self.xcode))
    }

    @Test func aFileOpensInItsDefaultAppOnlyWhenThatIsAnEditor() throws {
        let p = try project()
        #expect(route(p, "src/Main.swift", line: 3, apps(default: Self.xcode)) == .xed(line: 3, app: Self.xcode))
        #expect(route(p, "src/Main.swift", apps(default: Self.xcode)) == .app(Self.xcode))
        #expect(route(p, "src/pipe.ts", apps(default: Self.cursor)) == .app(Self.cursor))
        #expect(route(p, "src/pipe.ts", line: 7, apps(default: Self.xcode)) == .xed(line: 7, app: Self.xcode))
        #expect(route(p, "src/Main.swift", apps(default: nil)) == .app(Self.textEdit))
    }

    @Test(arguments: ["bin/cli", "run.command", "x.terminal", "wifi.mobileconfig"])
    func anythingThatWouldRunGoesToTheFallbackEvenWithAnEditorDefault(file: String) throws {
        let p = try project()
        #expect(route(p, file, apps(default: Self.cursor)) == .app(Self.textEdit))
    }

    @Test func withNoFallbackEditorItIsRevealed() throws {
        let p = try project()
        #expect(route(p, "tools/gen.py", apps(default: Self.pythonLauncher, fallback: nil)) == .reveal)
        #expect(route(p, "tools/gen.py", apps(default: Self.pythonLauncher, fallback: Self.kitty)) == .reveal)
    }

    @Test func aFolderOrBundleIsRevealed() throws {
        let p = try project()
        #expect(route(p, "Thing.app", apps(default: Self.textEdit)) == .reveal)
        #expect(route(p, "src", apps(default: Self.textEdit)) == .reveal)
    }

    @Test(arguments: ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
                      "com.exafunction.windsurf", "dev.zed.Zed", "com.sublimetext.4", "com.barebones.bbedit", "com.panic.Nova",
                      "com.coteditor.CotEditor", "com.apple.TextEdit", "com.jetbrains.intellij", "com.jetbrains.pycharm",
                      "org.vim.MacVim", "org.gnu.Emacs"])
    func knownEditors(id: String) {
        #expect(FileOpener.isEditor(id))
    }

    @Test(arguments: ["org.python.PythonLauncher", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "dev.warp.Warp-Stable",
                      "org.alacritty", "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
                      "com.mitchellh.ghostty.debug", "com.lawliang.ghostty-skins", "com.apple.ScriptEditor2", "com.apple.Automator"])
    func notEditors(id: String) {
        #expect(!FileOpener.isEditor(id))
    }

    /// The default handler is never used: every open names its app.
    @Test func everyOpenNamesItsApp() throws {
        let p = try project()
        var calls: [String] = []
        var xedWorks = true
        let actions = FileOpener.Actions(
            openWith: { url, app in calls.append("openWith \(url.lastPathComponent) \(app.lastPathComponent)") },
            reveal: { calls.append("reveal \($0.lastPathComponent)") },
            xed: { url, line in calls.append("xed \(url.lastPathComponent) \(line)"); return xedWorks })
        FileOpener.open(p.url.appendingPathComponent("tools/gen.py"), line: nil, apps: apps(default: Self.pythonLauncher), actions: actions)
        FileOpener.open(p.url.appendingPathComponent("src/pipe.ts"), line: nil, apps: apps(default: Self.cursor), actions: actions)
        FileOpener.open(p.url.appendingPathComponent("src/Main.swift"), line: 4, apps: apps(default: Self.xcode), actions: actions)
        xedWorks = false
        FileOpener.open(p.url.appendingPathComponent("src/Main.swift"), line: 4, apps: apps(default: Self.xcode), actions: actions)
        FileOpener.open(p.url.appendingPathComponent("src"), line: nil, apps: apps(default: Self.textEdit), actions: actions)
        #expect(calls == ["openWith gen.py TextEdit.app", "openWith pipe.ts Cursor.app", "xed Main.swift 4",
                          "xed Main.swift 4", "openWith Main.swift Xcode.app", "reveal src"])
    }
}
#endif
