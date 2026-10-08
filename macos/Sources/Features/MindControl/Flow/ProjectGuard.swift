import Foundation

extension MindControl {
    /// Keeps Draft and Refresh with Claude away from folders where they'd do harm or make no sense.
    enum ProjectGuard {
        /// Why Claude can't draft or refresh a map here, or nil when it can. Runs git, so call it off the main thread.
        static func claudeBlockReason(root: URL, home: String = NSHomeDirectory(),
                                      isGit: (URL) -> Bool = Git.isRepository) -> String? {
            let path = canonical(root.path)
            // APFS is usually case-insensitive, so `cd /users/me` is still the home folder.
            if path.lowercased() == canonical(home).lowercased() { return "This is your home folder. Choose a project folder." }
            if path == "/" { return "This is the top of the disk. Choose a project folder." }
            if !isGit(root) { return "This folder isn't a git repository, so Claude can't draft or refresh its map." }
            return nil
        }

        private static func canonical(_ path: String) -> String {
            URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        }
    }
}
