import Foundation

extension MindControl {
    /// One problem in a flow file. `line` is 1-based when known.
    struct FlowError: Equatable, Sendable, CustomStringConvertible {
        let line: Int?
        let message: String

        var description: String { line.map { "Line \($0): \(message)" } ?? message }
    }

    struct FlowErrors: Error, Equatable, Sendable {
        let errors: [FlowError]
    }

    /// Reads `.mindcontrol/flow.json`: JSON syntax first, then the format's rules. Every problem is
    /// reported, not just the first. References between systems and flows are checked later by FlowCheck.
    enum FlowFile {
        static let relativePath = ".mindcontrol/flow.json"
        static let layoutRelativePath = ".mindcontrol/layout.json"
        static let supportedVersion = 1

        static func parse(_ data: Data) -> Result<FlowMap, FlowErrors> {
            let text = String(decoding: data, as: UTF8.self)
            if let comma = trailingCommaOffset(in: data) {
                let line = Self.line(ofUTF8Offset: comma, in: text)
                return .failure(FlowErrors(errors: [FlowError(line: line, message: "Not valid JSON: trailing comma before a closing bracket.")]))
            }
            let root: Any
            do {
                root = try JSONSerialization.jsonObject(with: data)
            } catch {
                return .failure(FlowErrors(errors: [syntaxError(error as NSError, text: text)]))
            }
            var parser = Parser(text: text)
            let map = parser.map(root)
            if let map, parser.errors.isEmpty { return .success(map) }
            return .failure(FlowErrors(errors: parser.errors))
        }

        /// Newer Foundation accepts a trailing comma that strict JSON forbids; find the first one, outside strings.
        private static func trailingCommaOffset(in data: Data) -> Int? {
            var inString = false
            var escaped = false
            var pendingComma: Int?
            for (offset, byte) in data.enumerated() {
                if inString {
                    if escaped { escaped = false } else if byte == UInt8(ascii: "\\") { escaped = true } else if byte == UInt8(ascii: "\"") { inString = false }
                    continue
                }
                switch byte {
                case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"):
                    continue
                case UInt8(ascii: "]"), UInt8(ascii: "}"):
                    if let pendingComma { return pendingComma }
                case UInt8(ascii: "\""):
                    inString = true
                default:
                    break
                }
                pendingComma = byte == UInt8(ascii: ",") ? offset : nil
            }
            return nil
        }

        /// Lowercase letters, digits and `-`.
        static func isValidID(_ id: String) -> Bool {
            !id.isEmpty && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        }

        static func line(ofUTF8Offset offset: Int, in text: String) -> Int {
            1 + text.utf8.prefix(max(0, offset)).filter { $0 == UInt8(ascii: "\n") }.count
        }

        private static func syntaxError(_ error: NSError, text: String) -> FlowError {
            let detail = (error.userInfo[NSDebugDescriptionErrorKey] as? String) ?? error.localizedDescription
            var line: Int?
            if let range = detail.range(of: #"line \d+"#, options: .regularExpression) {
                line = Int(detail[range].dropFirst(5))
            } else if let index = error.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                line = Self.line(ofUTF8Offset: index, in: text)
            }
            return FlowError(line: line, message: "Not valid JSON: \(detail)")
        }
    }
}

extension MindControl.FlowFile {
    /// Walks the decoded JSON, collecting every rule violation with the best line it can find.
    fileprivate struct Parser {
        typealias FlowMap = MindControl.FlowMap

        let text: String
        var errors: [MindControl.FlowError] = []

        // MARK: Errors and lines

        mutating func fail(_ message: String, id: String? = nil, key: String? = nil) {
            errors.append(.init(line: line(id: id, key: key), message: message))
        }

        /// The line of `"id": "<id>"`, else of `"<key>":`.
        func line(id: String?, key: String?) -> Int? {
            if let id, let found = firstLine(of: #""id"\s*:\s*"\#(NSRegularExpression.escapedPattern(for: id))""#) { return found }
            if let key, let found = firstLine(of: #""\#(NSRegularExpression.escapedPattern(for: key))"\s*:"#) { return found }
            return nil
        }

        func firstLine(of pattern: String) -> Int? {
            guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
            return 1 + text[..<range.lowerBound].filter { $0 == "\n" }.count
        }

        // MARK: Field helpers

        mutating func objects(_ object: [String: Any], _ key: String, required: Bool) -> [[String: Any]] {
            guard let value = object[key] else {
                if required { fail("Missing \"\(key)\".") }
                return []
            }
            guard let array = value as? [Any] else {
                fail("\"\(key)\" must be a list.", key: key)
                return []
            }
            var items: [[String: Any]] = []
            for (index, item) in array.enumerated() {
                if let object = item as? [String: Any] {
                    items.append(object)
                } else {
                    fail("\(key)[\(index)] must be an object.", key: key)
                }
            }
            return items
        }

        mutating func id(_ object: [String: Any], what: String, label: String, listKey: String, seen: inout Set<String>) -> String? {
            guard let id = object["id"] as? String else {
                fail("\(label) is missing \"id\".", key: listKey)
                return nil
            }
            guard MindControl.FlowFile.isValidID(id) else {
                fail("The \(what) id \"\(id)\" may only use a-z, 0-9 and -.", id: id)
                return nil
            }
            guard seen.insert(id).inserted else {
                fail("Duplicate \(what) id \"\(id)\".", id: id)
                return nil
            }
            return id
        }

        mutating func text(_ object: [String: Any], _ key: String, required: Bool, owner: String, id: String?) -> String? {
            switch object[key] {
            case let value as String where !value.isEmpty:
                return value
            case nil, is String:
                if required { fail("\(owner) is missing \"\(key)\".", id: id, key: id == nil ? key : nil) }
                return nil
            default:
                fail("\(owner): \"\(key)\" must be text.", id: id)
                return nil
            }
        }

        // MARK: The map

        mutating func map(_ root: Any) -> FlowMap? {
            guard let object = root as? [String: Any] else {
                fail("The file must be a JSON object.")
                return nil
            }
            switch object["version"] {
            case let version as Int where version == MindControl.FlowFile.supportedVersion:
                break
            case nil:
                fail("Missing \"version\"; this MindControl reads version 1.")
            case let version?:
                fail("Unsupported version \(version); this MindControl reads version 1.", key: "version")
            }

            let zones = parseZones(object)
            let zoneIDs = Set(zones.map(\.id))
            let systems = parseSystems(object, zoneIDs: zoneIDs)
            let flows = parseFlows(object)
            let features = parseFeatures(object)
            guard errors.isEmpty else { return nil }
            return FlowMap(zones: zones, systems: systems, flows: flows, features: features)
        }

        mutating func parseZones(_ object: [String: Any]) -> [FlowMap.Zone] {
            var seen = Set<String>()
            return objects(object, "zones", required: false).enumerated().compactMap { index, item in
                guard let id = self.id(item, what: "zone", label: "zones[\(index)]", listKey: "zones", seen: &seen),
                      let name = text(item, "name", required: true, owner: "Zone \"\(id)\"", id: id) else { return nil }
                return FlowMap.Zone(id: id, name: name)
            }
        }

        mutating func parseSystems(_ object: [String: Any], zoneIDs: Set<String>) -> [FlowMap.System] {
            var seen = Set<String>()
            return objects(object, "systems", required: true).enumerated().compactMap { index, item in
                guard let id = self.id(item, what: "system", label: "systems[\(index)]", listKey: "systems", seen: &seen) else { return nil }
                let owner = "System \"\(id)\""
                let name = text(item, "name", required: true, owner: owner, id: id)
                let summary = text(item, "summary", required: false, owner: owner, id: id)
                let zone = text(item, "zone", required: false, owner: owner, id: id)
                if let zone, !zoneIDs.contains(zone) {
                    fail("\(owner) names unknown zone \"\(zone)\".", id: id)
                }
                var paths: [String] = []
                if let value = item["paths"] {
                    if let list = value as? [String] { paths = list } else { fail("\(owner): \"paths\" must be a list of text.", id: id) }
                }
                var external = false
                if let value = item["external"] {
                    if let flag = value as? Bool { external = flag } else { fail("\(owner): \"external\" must be true or false.", id: id) }
                }
                var partIDs = Set<String>()
                let parts: [FlowMap.Part] = objects(item, "parts", required: false).enumerated().compactMap { partIndex, part in
                    guard let partID = self.id(part, what: "part", label: "\(owner) parts[\(partIndex)]", listKey: "parts", seen: &partIDs),
                          let partName = text(part, "name", required: true, owner: "Part \"\(id).\(partID)\"", id: partID) else { return nil }
                    return FlowMap.Part(id: partID, name: partName,
                                        anchor: text(part, "anchor", required: false, owner: "Part \"\(id).\(partID)\"", id: partID))
                }
                if external, !paths.isEmpty || item["parts"] != nil {
                    fail("\(owner) is external, so it cannot have paths or parts.", id: id)
                }
                guard let name else { return nil }
                return FlowMap.System(id: id, name: name, summary: summary, zone: zone, paths: paths, parts: parts, external: external)
            }
        }

        mutating func parseFlows(_ object: [String: Any]) -> [FlowMap.Flow] {
            var seen = Set<String>()
            return objects(object, "flows", required: false).enumerated().compactMap { index, item in
                guard let id = self.id(item, what: "flow", label: "flows[\(index)]", listKey: "flows", seen: &seen) else { return nil }
                let owner = "Flow \"\(id)\""
                let from = endpoint(item, "from", owner: owner, id: id)
                let to = endpoint(item, "to", owner: owner, id: id)
                let kindText = text(item, "kind", required: true, owner: owner, id: id)
                let kind = kindText.flatMap(FlowMap.Kind.init(rawValue:))
                if let kindText, kind == nil {
                    fail("\(owner): \"kind\" must be \"data\" or \"control\", not \"\(kindText)\".", id: id)
                }
                let carries = text(item, "carries", required: true, owner: owner, id: id)
                let via = text(item, "via", required: false, owner: owner, id: id)
                let when = text(item, "when", required: false, owner: owner, id: id)
                guard let from, let to, let kind, let carries else { return nil }
                return FlowMap.Flow(id: id, from: from, to: to, kind: kind, carries: carries, via: via, when: when)
            }
        }

        mutating func endpoint(_ item: [String: Any], _ key: String, owner: String, id: String) -> FlowMap.Endpoint? {
            guard let raw = text(item, key, required: true, owner: owner, id: id) else { return nil }
            guard let endpoint = FlowMap.Endpoint(raw) else {
                fail("\(owner): \"\(key)\" must be a system id or system.part, not \"\(raw)\".", id: id)
                return nil
            }
            return endpoint
        }

        mutating func parseFeatures(_ object: [String: Any]) -> [FlowMap.Feature] {
            var seen = Set<String>()
            return objects(object, "features", required: false).enumerated().compactMap { index, item in
                guard let id = self.id(item, what: "feature", label: "features[\(index)]", listKey: "features", seen: &seen) else { return nil }
                let owner = "Feature \"\(id)\""
                let name = text(item, "name", required: true, owner: owner, id: id)
                guard let route = item["route"] as? [String] else {
                    fail("\(owner): \"route\" must be a list of flow ids.", id: id)
                    return nil
                }
                guard let name else { return nil }
                return FlowMap.Feature(id: id, name: name, route: route)
            }
        }
    }
}
