import Foundation

extension MindControl {
    /// Which system owns a source file: the system whose matching pattern is most specific.
    struct PathOwnership {
        enum Owner: Equatable, Sendable {
            case system(String)
            case none
            /// Two or more systems match equally specifically. Ids sorted.
            case tie([String])
        }

        private struct Entry {
            let system: String
            let regex: NSRegularExpression
            let specificity: Int
        }

        private let entries: [Entry]

        init(map: FlowMap) {
            entries = map.systems.flatMap { system in
                system.paths.map { Entry(system: system.id, regex: Glob.regex(for: $0), specificity: Glob.literalPrefixLength($0)) }
            }
        }

        func owner(of path: String) -> Owner {
            var best = -1
            var winners: [String] = []
            for entry in entries where Glob.matches(entry.regex, path) {
                if entry.specificity > best {
                    best = entry.specificity
                    winners = [entry.system]
                } else if entry.specificity == best, !winners.contains(entry.system) {
                    winners.append(entry.system)
                }
            }
            switch winners.count {
            case 0: return .none
            case 1: return .system(winners[0])
            default: return .tie(winners.sorted())
            }
        }
    }
}
