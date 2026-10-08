import Foundation

extension MindControl {
    struct SourceLocation: Equatable, Sendable {
        let file: String
        /// 1-based.
        let line: Int
    }

    /// Whether a flow map still matches the code, plus the lookups search and the side panel need.
    struct HealthReport: Equatable, Sendable {
        enum IssueKind: String, Equatable, Sendable {
            case staleAnchor, staleVia, unverified, unknownReference, pathTie, density
        }

        struct Issue: Equatable, Sendable {
            let kind: IssueKind
            /// A part key ("audio.gate"), flow id, feature id, file path, or "map" for density.
            let subject: String
            let message: String
        }

        enum Age: Equatable, Sendable {
            case hidden
            case notCommitted
            case commits(Int)
        }

        var issues: [Issue] = []
        var unmapped: [String] = []
        var age: Age = .hidden
        var staleParts: Set<String> = []
        var staleFlows: Set<String> = []
        var unverifiedFlows: Set<String> = []
        /// Flows naming an unknown system or part; they are not drawn.
        var brokenFlows: Set<String> = []
        var viaLocations: [String: SourceLocation] = [:]
        /// Source file → owning system id; files with no single owner are absent.
        var owners: [String: String] = [:]
        /// Swift type name → declaring file (the first by path order).
        var typeFiles: [String: String] = [:]
        /// Part key ("audio.capture") → the file its anchor resolves to.
        var anchorFiles: [String: String] = [:]

        var densityWarnings: [Issue] { issues.filter { $0.kind == .density } }
        /// Every issue, plus one for the unmapped list as a whole.
        var issueCount: Int { issues.count + (unmapped.isEmpty ? 0 : 1) }
        var isHealthy: Bool { issueCount == 0 }
    }

    enum FlowCheck {
        static let maxSystems = 20
        static let maxPartsPerSystem = 8
        static let maxFlows = 60

        /// An anchor with a `/` or a file extension is a path; anything else is a Swift type name.
        static func isFileAnchor(_ anchor: String) -> Bool {
            anchor.contains("/") || !(anchor as NSString).pathExtension.isEmpty
        }

        static func run(map: FlowMap, snapshot: FlowSnapshot) -> HealthReport {
            var report = HealthReport()
            var contents: [String: String] = [:]
            func source(_ file: String) -> String? {
                if let cached = contents[file] { return cached }
                let text = snapshot.read(file)
                if let text { contents[file] = text }
                return text
            }

            // Ownership and unmapped files.
            let ownership = PathOwnership(map: map)
            var filesBySystem: [String: [String]] = [:]
            for file in snapshot.sourceFiles {
                switch ownership.owner(of: file) {
                case .system(let id):
                    report.owners[file] = id
                    filesBySystem[id, default: []].append(file)
                case .none:
                    report.unmapped.append(file)
                case .tie(let ids):
                    report.unmapped.append(file)
                    report.issues.append(.init(kind: .pathTie, subject: file,
                                               message: "\(file) matches \(ids.joined(separator: " and ")) equally. Make one pattern more specific."))
                }
            }

            // Swift types, globally and per owning system.
            var typesBySystem: [String: [String: String]] = [:]
            for file in snapshot.sourceFiles where file.hasSuffix(".swift") {
                guard let text = source(file) else { continue }
                for type in SwiftSymbols.declaredTypes(in: text) {
                    if report.typeFiles[type] == nil { report.typeFiles[type] = file }
                    if let owner = report.owners[file], typesBySystem[owner]?[type] == nil {
                        typesBySystem[owner, default: [:]][type] = file
                    }
                }
            }

            // Part anchors.
            let sourceSet = Set(snapshot.sourceFiles)
            for system in map.systems {
                for part in system.parts {
                    guard let anchor = part.anchor else { continue }
                    let key = "\(system.id).\(part.id)"
                    if isFileAnchor(anchor) {
                        if sourceSet.contains(anchor) || snapshot.read(anchor) != nil {
                            report.anchorFiles[key] = anchor
                        } else {
                            report.staleParts.insert(key)
                            report.issues.append(.init(kind: .staleAnchor, subject: key, message: "\(part.name): file \(anchor) not found."))
                        }
                    } else if let file = typesBySystem[system.id]?[anchor] {
                        report.anchorFiles[key] = file
                    } else {
                        report.staleParts.insert(key)
                        report.issues.append(.init(kind: .staleAnchor, subject: key,
                                                   message: "\(part.name): type \(anchor) isn't declared in \(system.name)'s files."))
                    }
                }
            }

            // References.
            func resolves(_ endpoint: FlowMap.Endpoint) -> Bool {
                guard let system = map.system(endpoint.system) else { return false }
                return endpoint.part.map { system.part($0) != nil } ?? true
            }
            for flow in map.flows {
                let unknown = [flow.from, flow.to].filter { !resolves($0) }.map(\.description)
                guard !unknown.isEmpty else { continue }
                report.brokenFlows.insert(flow.id)
                report.issues.append(.init(kind: .unknownReference, subject: flow.id,
                                           message: "Flow \(flow.id) names unknown \(unknown.joined(separator: " and ")); it isn't drawn."))
            }
            for feature in map.features {
                let unknown = feature.route.filter { map.flow($0) == nil }
                guard !unknown.isEmpty else { continue }
                report.issues.append(.init(kind: .unknownReference, subject: feature.id,
                                           message: "\(feature.name) names unknown flows: \(unknown.joined(separator: ", "))."))
            }

            // Hand-offs.
            for flow in map.flows where !report.brokenFlows.contains(flow.id) {
                guard let from = map.system(flow.from.system), let to = map.system(flow.to.system) else { continue }
                if from.external, to.external { continue }
                let searched = from.external ? to : from
                guard let via = flow.via else {
                    report.unverifiedFlows.insert(flow.id)
                    report.issues.append(.init(kind: .unverified, subject: flow.id,
                                               message: "Flow \(flow.id) has no via. Add the call where \(flow.carries) is handed over."))
                    continue
                }
                if let location = find(word: via, in: filesBySystem[searched.id] ?? [], source: source) {
                    report.viaLocations[flow.id] = location
                } else {
                    report.staleFlows.insert(flow.id)
                    report.issues.append(.init(kind: .staleVia, subject: flow.id,
                                               message: "Flow \(flow.id): \(via) isn't found in \(searched.name)'s files."))
                }
            }

            // Density.
            if map.systems.count > maxSystems {
                report.issues.append(.init(kind: .density, subject: "map",
                                           message: "Map is getting dense: \(map.systems.count) systems (limit \(maxSystems)). Consider merging."))
            }
            for system in map.systems where system.parts.count > maxPartsPerSystem {
                report.issues.append(.init(kind: .density, subject: system.id,
                                           message: "\(system.name) has \(system.parts.count) parts (limit \(maxPartsPerSystem)). Consider merging."))
            }
            if map.flows.count > maxFlows {
                report.issues.append(.init(kind: .density, subject: "map",
                                           message: "Map is getting dense: \(map.flows.count) flows (limit \(maxFlows)). Consider merging."))
            }
            return report
        }

        /// First whole-word match of `word`, searching `files` in order.
        static func find(word: String, in files: [String], source: (String) -> String?) -> SourceLocation? {
            guard let regex = try? NSRegularExpression(pattern: #"\b\#(NSRegularExpression.escapedPattern(for: word))\b"#) else { return nil }
            for file in files {
                guard let text = source(file) else { continue }
                let ns = text as NSString
                guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
                let line = 1 + ns.substring(to: match.range.location).filter { $0 == "\n" }.count
                return SourceLocation(file: file, line: line)
            }
            return nil
        }
    }
}
