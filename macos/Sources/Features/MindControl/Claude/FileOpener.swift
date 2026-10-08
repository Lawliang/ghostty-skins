import AppKit

extension MindControl {
    enum FileOpener {
        /// Opens `url` in its default app. When that app is Xcode and a line is given, opens at the line.
        static func open(_ url: URL, line: Int?) {
            if let line, let app = NSWorkspace.shared.urlForApplication(toOpen: url),
               Bundle(url: app)?.bundleIdentifier == "com.apple.dt.Xcode" {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xed")
                process.arguments = ["--line", String(line), url.path]
                if (try? process.run()) != nil { return }
            }
            NSWorkspace.shared.open(url)
        }
    }
}
