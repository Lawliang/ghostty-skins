import AppKit
import UniformTypeIdentifiers

extension MindControl {
    /// Opens a project file for reading. A flow file names the files, and a cloned repository isn't quarantined,
    /// so nothing that Launch Services would run (a script, a `.command`, an app) goes to its default app.
    enum FileOpener {
        enum Route: Equatable {
            /// The file's own default app.
            case defaultApp
            /// Xcode, at the line.
            case xed(line: Int)
            /// The editor for source code, explicitly, so the file is opened as a document and never run.
            case app(URL)
            /// Shown in Finder.
            case reveal
        }

        /// The app lookups a route depends on.
        struct Apps {
            var defaultApp: (URL) -> URL?
            /// The default app for source code, else for plain text.
            var editor: () -> URL?
            var bundleID: (URL) -> String?

            static let live = Apps(
                defaultApp: { NSWorkspace.shared.urlForApplication(toOpen: $0) },
                editor: {
                    NSWorkspace.shared.urlForApplication(toOpen: .sourceCode) ?? NSWorkspace.shared.urlForApplication(toOpen: .plainText)
                },
                bundleID: { Bundle(url: $0)?.bundleIdentifier })
        }

        /// What carrying out a route does.
        struct Actions {
            var open: (URL) -> Void
            var openWith: (URL, URL) -> Void
            var reveal: (URL) -> Void
            /// False when xed couldn't be run.
            var xed: (URL, Int) -> Bool

            static let live = Actions(
                open: { NSWorkspace.shared.open($0) },
                openWith: { url, app in
                    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                },
                reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
                xed: { url, line in
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/xed")
                    process.arguments = ["--line", String(line), url.path]
                    return (try? process.run()) != nil
                })
        }

        static let xcode = "com.apple.dt.Xcode"
        /// Apps that run what they open.
        static let runners: Set<String> = [
            "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.apple.ScriptEditor2",
            "com.apple.Automator", "com.apple.shortcuts", "com.apple.installer", "com.apple.archiveutility",
        ]
        /// Files that run, install or point elsewhere when opened, whatever their type says.
        static let runnableExtensions: Set<String> = [
            "command", "tool", "terminal", "app", "workflow", "action", "shortcut", "scpt", "scptd", "applescript",
            "pkg", "mpkg", "fileloc", "webloc", "inetloc", "dmg",
        ]

        /// Lostty itself is a terminal too.
        static func runs(_ bundleID: String) -> Bool {
            runners.contains(bundleID) || bundleID.hasPrefix("com.lawliang.ghostty")
        }

        static func open(_ url: URL, line: Int?, apps: Apps = .live, actions: Actions = .live) {
            switch route(for: url, line: line, apps: apps) {
            case .defaultApp: actions.open(url)
            case .xed(let line):
                if !actions.xed(url, line) { actions.open(url) }
            case .app(let app): actions.openWith(url, app)
            case .reveal: actions.reveal(url)
            }
        }

        /// The default app only for a plain, non-executable text or source file whose default app doesn't run
        /// things; Xcode at the line when that app is Xcode. Anything else goes to the source editor (no line),
        /// or Finder.
        static func route(for url: URL, line: Int?, apps: Apps) -> Route {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
            guard values?.isRegularFile ?? true else { return .reveal }
            let executable = FileManager.default.isExecutableFile(atPath: url.path)
            let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
            let readable = type.map { $0.conforms(to: .text) || $0.conforms(to: .sourceCode) } ?? false
            let runnable = runnableExtensions.contains(url.pathExtension.lowercased())
            if !executable, readable, !runnable, let app = apps.defaultApp(url), let id = apps.bundleID(app), !runs(id) {
                if let line, id == xcode { return .xed(line: line) }
                return .defaultApp
            }
            // No xed here: if it failed to start, its fallback would be the default app.
            guard let editor = apps.editor(), let id = apps.bundleID(editor), !runs(id) else { return .reveal }
            return .app(editor)
        }
    }
}
