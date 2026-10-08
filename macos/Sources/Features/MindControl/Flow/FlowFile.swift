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
            var parser = Parser(locator: Locator(data))
            if var map = parser.map(root), parser.errors.isEmpty {
                map.unknownKeys = parser.unknownKeys
                return .success(map)
            }
            // A misspelt key is often why a required one is missing.
            return .failure(FlowErrors(errors: parser.errors + parser.unknownKeys))
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
    /// Finds where things sit in the raw bytes, so a rule error can point at the right line even when
    /// ids repeat across lists (zone `ring` and system `ring`) or inside the same list (duplicates).
    /// It only runs after JSONSerialization accepted the file, so it can be lenient.
    fileprivate struct Locator {
        private let bytes: [UInt8]
        private var keyOffsets: [String: Int] = [:]
        private var itemOffsets: [String: [Int]] = [:]
        private var partOffsets: [Int: [Int]] = [:]
        /// List key → item index → field key → offset.
        private var fieldOffsets: [String: [Int: [String: Int]]] = [:]
        /// System index → part index → field key → offset.
        private var partFieldOffsets: [Int: [Int: [String: Int]]] = [:]

        init(_ data: Data) {
            bytes = Array(data)
            let root = skipWhitespace(0)
            guard byte(root) == UInt8(ascii: "{") else { return }
            for member in members(at: root) {
                keyOffsets[member.key] = member.keyStart
                guard byte(member.value) == UInt8(ascii: "[") else { continue }
                let items = elements(at: member.value)
                itemOffsets[member.key] = items
                for (index, item) in items.enumerated() where byte(item) == UInt8(ascii: "{") {
                    for field in members(at: item) {
                        fieldOffsets[member.key, default: [:]][index, default: [:]][field.key] = field.keyStart
                        guard member.key == "systems", field.key == "parts", byte(field.value) == UInt8(ascii: "[") else { continue }
                        let parts = elements(at: field.value)
                        partOffsets[index] = parts
                        for (partIndex, part) in parts.enumerated() where byte(part) == UInt8(ascii: "{") {
                            for partField in members(at: part) {
                                partFieldOffsets[index, default: [:]][partIndex, default: [:]][partField.key] = partField.keyStart
                            }
                        }
                    }
                }
            }
        }

        /// The line of a top-level key such as `"systems":`.
        func line(ofKey key: String) -> Int? {
            keyOffsets[key].map(lineNumber)
        }

        /// The line where the `index`th element of a top-level list starts.
        func line(ofItem index: Int, in key: String) -> Int? {
            itemOffsets[key].flatMap { $0.indices.contains(index) ? lineNumber($0[index]) : nil }
        }

        /// The line where the `index`th part of the `system`th system starts.
        func line(ofPart index: Int, inSystem system: Int) -> Int? {
            partOffsets[system].flatMap { $0.indices.contains(index) ? lineNumber($0[index]) : nil }
        }

        /// The line of a field's key in the `index`th element of a top-level list.
        func line(ofField field: String, item index: Int, in key: String) -> Int? {
            fieldOffsets[key]?[index]?[field].map(lineNumber)
        }

        /// The line of a field's key in the `index`th part of the `system`th system.
        func line(ofField field: String, part index: Int, inSystem system: Int) -> Int? {
            partFieldOffsets[system]?[index]?[field].map(lineNumber)
        }

        /// 1-based, counting `\n` bytes, so CRLF files count correctly.
        private func lineNumber(_ offset: Int) -> Int {
            1 + bytes.prefix(max(0, offset)).reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        }

        // MARK: Scanning

        private func byte(_ index: Int) -> UInt8? {
            bytes.indices.contains(index) ? bytes[index] : nil
        }

        private func skipWhitespace(_ start: Int) -> Int {
            var index = start
            while let b = byte(index), b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09 { index += 1 }
            return index
        }

        /// `start` is at the opening quote; returns the index after the closing one.
        private func skipString(_ start: Int) -> Int {
            var index = start + 1
            while let b = byte(index) {
                if b == UInt8(ascii: "\\") {
                    index += 2
                } else if b == UInt8(ascii: "\"") {
                    return index + 1
                } else {
                    index += 1
                }
            }
            return bytes.count
        }

        private func skipValue(_ start: Int) -> Int {
            switch byte(start) {
            case nil:
                return start
            case UInt8(ascii: "\""):
                return skipString(start)
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                var depth = 0
                var index = start
                while let b = byte(index) {
                    if b == UInt8(ascii: "\"") {
                        index = skipString(index)
                        continue
                    }
                    if b == UInt8(ascii: "{") || b == UInt8(ascii: "[") {
                        depth += 1
                    } else if b == UInt8(ascii: "}") || b == UInt8(ascii: "]") {
                        depth -= 1
                        if depth == 0 { return index + 1 }
                    }
                    index += 1
                }
                return bytes.count
            default:
                var index = start
                while let b = byte(index), ![UInt8(ascii: ","), UInt8(ascii: "]"), UInt8(ascii: "}"), 0x20, 0x0A, 0x0D, 0x09].contains(b) { index += 1 }
                return index
            }
        }

        /// The members of the object that starts at `start`.
        private func members(at start: Int) -> [(key: String, keyStart: Int, value: Int)] {
            var result: [(key: String, keyStart: Int, value: Int)] = []
            var index = skipWhitespace(start + 1)
            while byte(index) == UInt8(ascii: "\"") {
                let keyEnd = skipString(index)
                let key = String(decoding: bytes[(index + 1)..<max(index + 1, keyEnd - 1)], as: UTF8.self)
                let colon = skipWhitespace(keyEnd)
                guard byte(colon) == UInt8(ascii: ":") else { break }
                let value = skipWhitespace(colon + 1)
                result.append((key: key, keyStart: index, value: value))
                index = skipWhitespace(skipValue(value))
                guard byte(index) == UInt8(ascii: ",") else { break }
                index = skipWhitespace(index + 1)
            }
            return result
        }

        /// The start of each element of the array that starts at `start`.
        private func elements(at start: Int) -> [Int] {
            var result: [Int] = []
            var index = skipWhitespace(start + 1)
            while let b = byte(index), b != UInt8(ascii: "]") {
                result.append(index)
                index = skipWhitespace(skipValue(index))
                guard byte(index) == UInt8(ascii: ",") else { break }
                index = skipWhitespace(index + 1)
            }
            return result
        }
    }

    /// Walks the decoded JSON, collecting every rule violation with the line of the item it belongs to.
    fileprivate struct Parser {
        typealias FlowMap = MindControl.FlowMap

        let locator: Locator
        var errors: [MindControl.FlowError] = []
        /// Keys the format doesn't have. Ignored, so they don't make the file invalid.
        var unknownKeys: [MindControl.FlowError] = []

        static let topKeys = ["version", "zones", "systems", "flows", "features"]
        static let zoneKeys = ["id", "name"]
        static let systemKeys = ["id", "name", "summary", "zone", "paths", "parts", "external"]
        static let partKeys = ["id", "name", "anchor"]
        static let flowKeys = ["id", "from", "to", "kind", "carries", "via", "when"]
        static let featureKeys = ["id", "name", "route"]

        // MARK: Errors

        mutating func fail(_ message: String, line: Int? = nil) {
            errors.append(.init(line: line, message: message))
        }

        /// Notes each key of `object` not in `known`, in line order. `owner` names the object ("flow \"f\""),
        /// nil for the top level.
        mutating func noteUnknownKeys(_ object: [String: Any], known: [String], owner: String?, line: (String) -> Int?) {
            let unknown = object.keys.filter { !known.contains($0) }
                .map { (key: $0, line: line($0)) }
                .sorted { ($0.line ?? 0, $0.key) < ($1.line ?? 0, $1.key) }
            for (key, keyLine) in unknown {
                var message = "Unknown key \"\(key)\"" + (owner.map { " in \($0)" } ?? "") + " is ignored."
                if let guess = Self.nearest(key, in: known.filter { object[$0] == nil }) { message += " Did you mean \"\(guess)\"?" }
                unknownKeys.append(.init(line: keyLine, message: message))
            }
        }

        /// The known key a typo most likely meant: one edit away (two for longer keys), counting a swap of
        /// neighbours as one edit.
        static func nearest(_ key: String, in known: [String]) -> String? {
            let limit = key.count >= 5 ? 2 : 1
            var best: (key: String, distance: Int)?
            for candidate in known {
                let distance = editDistance(key.lowercased(), candidate)
                if distance <= limit, distance < (best?.distance ?? .max) { best = (candidate, distance) }
            }
            return best?.key
        }

        /// Optimal string alignment distance.
        static func editDistance(_ a: String, _ b: String) -> Int {
            let a = Array(a), b = Array(b)
            guard !a.isEmpty else { return b.count }
            guard !b.isEmpty else { return a.count }
            var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
            for i in 0...a.count { d[i][0] = i }
            for j in 0...b.count { d[0][j] = j }
            for i in 1...a.count {
                for j in 1...b.count {
                    let cost = a[i - 1] == b[j - 1] ? 0 : 1
                    d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                    if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
                }
            }
            return d[a.count][b.count]
        }

        /// How an object is named in a message: by its id, else by its place in its list.
        static func owner(_ what: String, _ item: [String: Any], fallback: String) -> String {
            (item["id"] as? String).map { "\(what) \"\($0)\"" } ?? fallback
        }

        // MARK: Field helpers

        /// The object elements of a list, each with its position in the raw list.
        mutating func objects(
            _ object: [String: Any], _ key: String, required: Bool,
            listLine: Int?, itemLine: (Int) -> Int?
        ) -> [(index: Int, object: [String: Any])] {
            guard let value = object[key] else {
                if required { fail("Missing \"\(key)\".") }
                return []
            }
            guard let array = value as? [Any] else {
                fail("\"\(key)\" must be a list.", line: listLine)
                return []
            }
            var items: [(index: Int, object: [String: Any])] = []
            for (index, item) in array.enumerated() {
                if let object = item as? [String: Any] {
                    items.append((index: index, object: object))
                } else {
                    fail("\(key)[\(index)] must be an object.", line: itemLine(index) ?? listLine)
                }
            }
            return items
        }

        mutating func id(_ object: [String: Any], what: String, label: String, line: Int?, seen: inout Set<String>) -> String? {
            guard let id = object["id"] as? String else {
                fail("\(label) is missing \"id\".", line: line)
                return nil
            }
            guard MindControl.FlowFile.isValidID(id) else {
                fail("The \(what) id \"\(id)\" may only use a-z, 0-9 and -.", line: line)
                return nil
            }
            guard seen.insert(id).inserted else {
                fail("Duplicate \(what) id \"\(id)\".", line: line)
                return nil
            }
            return id
        }

        mutating func text(_ object: [String: Any], _ key: String, required: Bool, owner: String, line: Int?) -> String? {
            switch object[key] {
            case let value as String where !value.isEmpty:
                return value
            case nil, is String:
                if required { fail("\(owner) is missing \"\(key)\".", line: line) }
                return nil
            default:
                fail("\(owner): \"\(key)\" must be text.", line: line)
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
                fail("Unsupported version \(version); this MindControl reads version 1.", line: locator.line(ofKey: "version"))
            }

            let keys = self.locator
            noteUnknownKeys(object, known: Self.topKeys, owner: nil, line: { keys.line(ofKey: $0) })

            let zones = parseZones(object)
            let zoneIDs = Set(zones.map(\.id))
            let systems = parseSystems(object, zoneIDs: zoneIDs)
            let flows = parseFlows(object)
            let features = parseFeatures(object)
            guard errors.isEmpty else { return nil }
            return FlowMap(zones: zones, systems: systems, flows: flows, features: features)
        }

        /// A top-level list's objects, with the locator closures filled in.
        mutating func topLevel(_ object: [String: Any], _ key: String, required: Bool) -> [(index: Int, object: [String: Any])] {
            let locator = self.locator
            return objects(object, key, required: required, listLine: locator.line(ofKey: key),
                           itemLine: { locator.line(ofItem: $0, in: key) })
        }

        mutating func parseZones(_ object: [String: Any]) -> [FlowMap.Zone] {
            var seen = Set<String>()
            var zones: [FlowMap.Zone] = []
            for (index, item) in topLevel(object, "zones", required: false) {
                let line = locator.line(ofItem: index, in: "zones")
                let fields = self.locator
                noteUnknownKeys(item, known: Self.zoneKeys, owner: Self.owner("zone", item, fallback: "zones[\(index)]"),
                                line: { fields.line(ofField: $0, item: index, in: "zones") ?? line })
                guard let id = id(item, what: "zone", label: "zones[\(index)]", line: line, seen: &seen),
                      let name = text(item, "name", required: true, owner: "Zone \"\(id)\"", line: line) else { continue }
                zones.append(FlowMap.Zone(id: id, name: name))
            }
            return zones
        }

        mutating func parseSystems(_ object: [String: Any], zoneIDs: Set<String>) -> [FlowMap.System] {
            var seen = Set<String>()
            var systems: [FlowMap.System] = []
            for (index, item) in topLevel(object, "systems", required: true) {
                let line = locator.line(ofItem: index, in: "systems")
                let fields = self.locator
                noteUnknownKeys(item, known: Self.systemKeys, owner: Self.owner("system", item, fallback: "systems[\(index)]"),
                                line: { fields.line(ofField: $0, item: index, in: "systems") ?? line })
                guard let id = id(item, what: "system", label: "systems[\(index)]", line: line, seen: &seen) else { continue }
                let owner = "System \"\(id)\""
                let name = text(item, "name", required: true, owner: owner, line: line)
                let summary = text(item, "summary", required: false, owner: owner, line: line)
                let zone = text(item, "zone", required: false, owner: owner, line: line)
                if let zone, !zoneIDs.contains(zone) {
                    fail("\(owner) names unknown zone \"\(zone)\".", line: line)
                }
                var paths: [String] = []
                if let value = item["paths"] {
                    if let list = value as? [String] { paths = list } else { fail("\(owner): \"paths\" must be a list of text.", line: line) }
                }
                var external = false
                if let value = item["external"] {
                    if let flag = value as? Bool { external = flag } else { fail("\(owner): \"external\" must be true or false.", line: line) }
                }
                var partIDs = Set<String>()
                var parts: [FlowMap.Part] = []
                for (partIndex, part) in objects(item, "parts", required: false, listLine: line,
                                                 itemLine: { fields.line(ofPart: $0, inSystem: index) }) {
                    let partLine = fields.line(ofPart: partIndex, inSystem: index) ?? line
                    let partOwner = (part["id"] as? String).map { "part \"\(id).\($0)\"" } ?? "\(owner) parts[\(partIndex)]"
                    noteUnknownKeys(part, known: Self.partKeys, owner: partOwner,
                                    line: { fields.line(ofField: $0, part: partIndex, inSystem: index) ?? partLine })
                    guard let partID = self.id(part, what: "part", label: "\(owner) parts[\(partIndex)]", line: partLine, seen: &partIDs),
                          let partName = text(part, "name", required: true, owner: "Part \"\(id).\(partID)\"", line: partLine) else { continue }
                    parts.append(FlowMap.Part(id: partID, name: partName,
                                              anchor: text(part, "anchor", required: false, owner: "Part \"\(id).\(partID)\"", line: partLine)))
                }
                if external, !paths.isEmpty || item["parts"] != nil {
                    fail("\(owner) is external, so it cannot have paths or parts.", line: line)
                }
                guard let name else { continue }
                systems.append(FlowMap.System(id: id, name: name, summary: summary, zone: zone, paths: paths, parts: parts, external: external))
            }
            return systems
        }

        mutating func parseFlows(_ object: [String: Any]) -> [FlowMap.Flow] {
            var seen = Set<String>()
            var flows: [FlowMap.Flow] = []
            for (index, item) in topLevel(object, "flows", required: false) {
                let line = locator.line(ofItem: index, in: "flows")
                let fields = self.locator
                noteUnknownKeys(item, known: Self.flowKeys, owner: Self.owner("flow", item, fallback: "flows[\(index)]"),
                                line: { fields.line(ofField: $0, item: index, in: "flows") ?? line })
                guard let id = id(item, what: "flow", label: "flows[\(index)]", line: line, seen: &seen) else { continue }
                let owner = "Flow \"\(id)\""
                let from = endpoint(item, "from", owner: owner, line: line)
                let to = endpoint(item, "to", owner: owner, line: line)
                let kindText = text(item, "kind", required: true, owner: owner, line: line)
                let kind = kindText.flatMap(FlowMap.Kind.init(rawValue:))
                if let kindText, kind == nil {
                    fail("\(owner): \"kind\" must be \"data\" or \"control\", not \"\(kindText)\".", line: line)
                }
                let carries = text(item, "carries", required: true, owner: owner, line: line)
                let via = text(item, "via", required: false, owner: owner, line: line)
                let when = text(item, "when", required: false, owner: owner, line: line)
                guard let from, let to, let kind, let carries else { continue }
                flows.append(FlowMap.Flow(id: id, from: from, to: to, kind: kind, carries: carries, via: via, when: when))
            }
            return flows
        }

        mutating func endpoint(_ item: [String: Any], _ key: String, owner: String, line: Int?) -> FlowMap.Endpoint? {
            guard let raw = text(item, key, required: true, owner: owner, line: line) else { return nil }
            guard let endpoint = FlowMap.Endpoint(raw) else {
                fail("\(owner): \"\(key)\" must be a system id or system.part, not \"\(raw)\".", line: line)
                return nil
            }
            return endpoint
        }

        mutating func parseFeatures(_ object: [String: Any]) -> [FlowMap.Feature] {
            var seen = Set<String>()
            var features: [FlowMap.Feature] = []
            for (index, item) in topLevel(object, "features", required: false) {
                let line = locator.line(ofItem: index, in: "features")
                let fields = self.locator
                noteUnknownKeys(item, known: Self.featureKeys, owner: Self.owner("feature", item, fallback: "features[\(index)]"),
                                line: { fields.line(ofField: $0, item: index, in: "features") ?? line })
                guard let id = id(item, what: "feature", label: "features[\(index)]", line: line, seen: &seen) else { continue }
                let owner = "Feature \"\(id)\""
                let name = text(item, "name", required: true, owner: owner, line: line)
                guard let route = item["route"] as? [String] else {
                    fail("\(owner): \"route\" must be a list of flow ids.", line: line)
                    continue
                }
                guard let name else { continue }
                features.append(FlowMap.Feature(id: id, name: name, route: route))
            }
            return features
        }
    }
}
