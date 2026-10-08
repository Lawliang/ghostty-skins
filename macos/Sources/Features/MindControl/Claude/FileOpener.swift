import AppKit

extension MindControl {
    /// Opens a project file for reading. A flow file names the files, and a cloned repository isn't quarantined,
    /// so the file's default handler is never used: it could be a script runner (Python Launcher, a terminal).
    /// Every open names a known editor, the file's default app only when it is one, else a fallback editor.
    enum FileOpener {
        enum Route: Equatable {
            /// This editor, explicitly.
            case app(URL)
            /// Xcode (`app`), at the line.
            case xed(line: Int, app: URL)
            /// Shown in Finder.
            case reveal
        }

        /// The app lookups a route depends on.
        struct Apps {
            var defaultApp: (URL) -> URL?
            /// Xcode if installed, else TextEdit.
            var fallbackEditor: () -> URL?
            var bundleID: (URL) -> String?

            static let live = Apps(
                defaultApp: { NSWorkspace.shared.urlForApplication(toOpen: $0) },
                fallbackEditor: {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: FileOpener.xcode)
                        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
                },
                bundleID: { Bundle(url: $0)?.bundleIdentifier })
        }

        /// What carrying out a route does. There's deliberately no plain `NSWorkspace.open(url)`.
        struct Actions {
            var openWith: (URL, URL) -> Void
            var reveal: (URL) -> Void
            /// False when xed couldn't be run.
            var xed: (URL, Int) -> Bool

            static let live = Actions(
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
        /// Apps that only edit what they open.
        static let editors: Set<String> = [
            xcode, "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92" /* Cursor */,
            "com.exafunction.windsurf", "dev.zed.Zed", "dev.zed.Zed-Preview", "com.sublimetext.4", "com.sublimetext.3",
            "com.barebones.bbedit", "com.panic.Nova", "com.coteditor.CotEditor", "com.apple.TextEdit",
            "org.vim.MacVim", "org.gnu.Emacs", "org.gnu.Aquamacs",
        ]
        /// Files that run, install or point elsewhere when opened: never handed to a default app, editor or not.
        static let refusedExtensions: Set<String> = [
            "command", "tool", "terminal", "app", "workflow", "action", "shortcut", "scpt", "scptd", "applescript",
            "pkg", "mpkg", "fileloc", "webloc", "inetloc", "dmg", "mobileconfig",
        ]

        /// JetBrains IDEs share a prefix.
        static func isEditor(_ bundleID: String) -> Bool {
            editors.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.")
        }

        static func open(_ url: URL, line: Int?, apps: Apps = .live, actions: Actions = .live) {
            switch route(for: url, line: line, apps: apps) {
            case .app(let app): actions.openWith(url, app)
            case .xed(let line, let app):
                if !actions.xed(url, line) { actions.openWith(url, app) }
            case .reveal: actions.reveal(url)
            }
        }

        /// A folder or bundle is revealed. A plain file goes to its default app when that is a known editor,
        /// else (an executable, a refused extension, no default app, or one that isn't an editor) to the
        /// fallback editor; with neither, it's revealed. Xcode opens at the line when there is one.
        static func route(for url: URL, line: Int?, apps: Apps) -> Route {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile ?? true else { return .reveal }
            let executable = FileManager.default.isExecutableFile(atPath: url.path)
            let refused = refusedExtensions.contains(url.pathExtension.lowercased())
            let candidates = (executable || refused ? [] : [apps.defaultApp(url)]) + [apps.fallbackEditor()]
            for case let app? in candidates {
                guard let id = apps.bundleID(app), isEditor(id) else { continue }
                if let line, id == xcode { return .xed(line: line, app: app) }
                return .app(app)
            }
            return .reveal
        }
    }
}
