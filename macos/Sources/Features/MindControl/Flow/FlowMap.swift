import Foundation

extension MindControl {
    /// A project's flow map, decoded from `.mindcontrol/flow.json`.
    struct FlowMap: Equatable, Sendable {
        struct Zone: Equatable, Sendable {
            let id: String
            let name: String
        }

        struct Part: Equatable, Sendable {
            let id: String
            let name: String
            /// A Swift type name, or a file path relative to the project root.
            let anchor: String?
        }

        struct System: Equatable, Sendable {
            let id: String
            let name: String
            let summary: String?
            let zone: String?
            let paths: [String]
            let parts: [Part]
            let external: Bool

            func part(_ id: String) -> Part? { parts.first { $0.id == id } }
        }

        enum Kind: String, Equatable, Sendable {
            case data, control
        }

        /// `audio` (a whole system) or `audio.capture` (one of its parts).
        struct Endpoint: Hashable, Sendable, CustomStringConvertible {
            let system: String
            let part: String?

            init(system: String, part: String?) {
                self.system = system
                self.part = part
            }

            init?(_ text: String) {
                let pieces = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                guard (1...2).contains(pieces.count), pieces.allSatisfy(FlowFile.isValidID) else { return nil }
                system = pieces[0]
                part = pieces.count == 2 ? pieces[1] : nil
            }

            var description: String { part.map { "\(system).\($0)" } ?? system }
        }

        struct Flow: Equatable, Sendable {
            let id: String
            let from: Endpoint
            let to: Endpoint
            let kind: Kind
            /// What travels, or what is triggered.
            let carries: String
            /// The call or symbol where the hand-off happens.
            let via: String?
            /// The condition this step depends on, e.g. "words heard".
            let when: String?
        }

        struct Feature: Equatable, Sendable {
            let id: String
            let name: String
            /// Flow ids, in order.
            let route: [String]
        }

        let zones: [Zone]
        let systems: [System]
        let flows: [Flow]
        let features: [Feature]
        /// Keys in the file that the format doesn't have, with their lines. They're ignored; Health lists them.
        var unknownKeys: [FlowError] = []

        func system(_ id: String) -> System? { systems.first { $0.id == id } }
        func flow(_ id: String) -> Flow? { flows.first { $0.id == id } }
        func feature(_ id: String) -> Feature? { features.first { $0.id == id } }
        func zoneOf(system id: String) -> String? { system(id)?.zone }
    }
}
