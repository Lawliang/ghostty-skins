import Foundation

extension MindControl {
    enum Git {
        /// Runs `/usr/bin/git -C root args…`; returns stdout when git exits 0, else nil.
        static func run(_ root: URL, _ args: [String]) -> Data? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + args
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            // Read before waiting so a large output can't fill the pipe and deadlock.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        }

        static func isRepository(_ root: URL) -> Bool {
            run(root, ["rev-parse", "--is-inside-work-tree"]) != nil
        }
    }
}
