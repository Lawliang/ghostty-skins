import Foundation

extension MindControl {
    struct SearchResult: Equatable, Sendable {
        enum Kind: Int, Comparable, Sendable {
            case feature, system, part, file
            static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
        }

        enum Target: Equatable, Sendable {
            case feature(String)
            case system(String)
            /// "system.part"
            case part(String)
            case file(path: String, system: String?)
        }

        let kind: Kind
        let title: String
        let detail: String
        let target: Target
    }

    /// Features, systems, parts, source files and Swift types. Grouped by kind; within a group ranked by
    /// the title: prefix, then word start, then substring, then alphabetical. Ids, part anchors and file
    /// paths also find a result, but rank it as a substring match, since the user never sees them.
    struct FlowSearch: Sendable {
        private struct Entry: Sendable {
            let result: SearchResult
            /// The lowercased title from its start, then from each later word start.
            let titleTails: [String]
            /// Other lowercased text that finds the entry.
            let otherKeys: [String]

            var lowercasedTitle: String { titleTails[0] }
        }

        private let entries: [Entry]

        init(map: FlowMap, report: HealthReport) {
            var entries: [Entry] = []
            func add(_ kind: SearchResult.Kind, _ title: String, _ detail: String, _ target: SearchResult.Target, keys: [String?]) {
                entries.append(Entry(result: SearchResult(kind: kind, title: title, detail: detail, target: target),
                                     titleTails: FlowSearch.wordTails(title), otherKeys: keys.compactMap { $0?.lowercased() }))
            }
            for feature in map.features {
                add(.feature, feature.name, "Feature", .feature(feature.id), keys: [feature.id])
            }
            for system in map.systems {
                add(.system, system.name, system.summary ?? "System", .system(system.id), keys: [system.id])
                for part in system.parts {
                    add(.part, part.name, system.name, .part("\(system.id).\(part.id)"), keys: [part.id, part.anchor])
                }
            }
            func systemName(_ id: String?) -> String { id.flatMap { map.system($0)?.name } ?? "no system" }
            for file in (Array(report.owners.keys) + report.unmapped).sorted() {
                let owner = report.owners[file]
                add(.file, (file as NSString).lastPathComponent, "\(file) · \(systemName(owner))",
                    .file(path: file, system: owner), keys: [file])
            }
            for (type, file) in report.typeFiles.sorted(by: { $0.key < $1.key }) {
                let owner = report.owners[file]
                add(.file, type, "\(file) · \(systemName(owner))", .file(path: file, system: owner), keys: [])
            }
            self.entries = entries
        }

        func search(_ query: String, limit: Int = 40) -> [SearchResult] {
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty, limit > 0 else { return [] }
            let scored = entries.compactMap { entry in Self.score(needle, entry).map { (score: $0, entry: entry) } }
            return scored.sorted {
                ($0.entry.result.kind.rawValue, $0.score, $0.entry.lowercasedTitle, $0.entry.result.detail)
                    < ($1.entry.result.kind.rawValue, $1.score, $1.entry.lowercasedTitle, $1.entry.result.detail)
            }
            .prefix(limit).map { $0.entry.result }
        }

        /// 0 the title starts with it, 1 a later word in the title does, 2 the title or another key
        /// contains it; nil no match.
        private static func score(_ needle: String, _ entry: Entry) -> Int? {
            if entry.lowercasedTitle.hasPrefix(needle) { return 0 }
            if entry.titleTails.dropFirst().contains(where: { $0.hasPrefix(needle) }) { return 1 }
            if entry.lowercasedTitle.contains(needle) || entry.otherKeys.contains(where: { $0.contains(needle) }) { return 2 }
            return nil
        }

        /// `text` lowercased from its start, then from each later word start: a letter or digit after
        /// anything else ("A |press"), an uppercase letter after a lowercase one or a digit
        /// ("Speech|Gate", "Base64|Encoder"), and the last capital of an acronym before a lowercase
        /// letter ("URL|Server"). Matching a tail's prefix lets a query span words ("press becomes").
        static func wordTails(_ text: String) -> [String] {
            let characters = Array(text)
            var tails = [text.lowercased()]
            for i in characters.indices.dropFirst() {
                let previous = characters[i - 1], current = characters[i]
                guard current.isLetter || current.isNumber else { continue }
                let startsWord: Bool
                if !(previous.isLetter || previous.isNumber) {
                    startsWord = true
                } else if current.isUppercase {
                    let nextIsLowercase = i + 1 < characters.count && characters[i + 1].isLowercase
                    startsWord = previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLowercase)
                } else {
                    startsWord = false
                }
                if startsWord { tails.append(String(characters[i...]).lowercased()) }
            }
            return tails
        }
    }
}
