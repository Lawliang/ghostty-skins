import Foundation

extension MindControl {
    /// How far the code has moved since the flow map was last committed.
    enum FlowAge {
        static func age(root: URL, map: FlowMap) -> HealthReport.Age {
            guard Git.isRepository(root) else { return .hidden }
            guard let log = Git.run(root, ["log", "-1", "--format=%H", "--", FlowFile.relativePath]) else { return .notCommitted }
            let sha = String(decoding: log, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sha.isEmpty else { return .notCommitted }
            let pathspecs = map.systems.flatMap(\.paths).map { ":(glob)\($0)" }
            // Nothing to count, or git couldn't: hidden, not "Map up to date".
            guard !pathspecs.isEmpty,
                  let output = Git.run(root, ["rev-list", "--count", "\(sha)..HEAD", "--"] + pathspecs),
                  let count = Int(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else { return .hidden }
            return .commits(count)
        }
    }
}
