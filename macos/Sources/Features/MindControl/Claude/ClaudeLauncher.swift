import Foundation

extension MindControl {
    /// Starts `claude` with a bundled prompt in a new terminal tab.
    enum ClaudeLauncher {
        /// Whether `command` resolves in the user's login shell, which is where the new tab will look for it.
        ///
        /// Blocking by design: it starts `$SHELL -lic` (login and interactive, so the user's PATH set up in
        /// .zprofile or .zshrc is seen) and waits for it. Call it off the main thread. It never hangs: stdin is
        /// /dev/null and output is discarded, so the shell can't wait on a terminal or a full pipe, and after
        /// `timeout` seconds the shell is killed with SIGKILL (interactive shells ignore SIGTERM) and the answer is no.
        static func isInstalled(command: String = "claude",
                                shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
                                timeout: TimeInterval = 5) -> Bool {
            assert(!Thread.isMainThread, "isInstalled runs a login shell and blocks; call it off the main thread")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-lic", "command -v \(shellQuote(command)) >/dev/null 2>&1"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let exited = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in exited.signal() }
            do { try process.run() } catch { return false }
            if exited.wait(timeout: .now() + timeout) == .timedOut {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                exited.wait()
                return false
            }
            return process.terminationStatus == 0
        }

        /// Saves `text` to a new file in the temporary folder, for the new tab's shell to read.
        static func writePrompt(_ text: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindcontrol-prompt-\(UUID().uuidString).md")
            try Data(text.utf8).write(to: url)
            return url
        }

        /// What to type into the new tab's shell: `claude` with the prompt file's contents as its first message.
        static func command(promptFile: URL) -> String {
            "claude \"$(cat \(shellQuote(promptFile.path)))\"\n"
        }

        /// `text` as one single-quoted shell word; any `'` inside becomes `'\''`.
        static func shellQuote(_ text: String) -> String {
            "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
    }
}
