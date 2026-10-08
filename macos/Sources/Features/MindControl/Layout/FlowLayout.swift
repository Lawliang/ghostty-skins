import CoreGraphics

extension MindControl {
    /// The main map: zones ordered by data flow, systems layered inside each zone, parts layered inside
    /// each system, then saved positions applied. Control flows never move anything.
    enum FlowLayout {
        private typealias M = LayoutMetrics

        static func layout(map: FlowMap, broken: Set<String>, saved: [String: CGPoint] = [:]) -> MapLayout {
            let flows = map.flows.filter { !broken.contains($0.id) }
            let data = flows.filter { $0.kind == .data }
            func zone(of system: String) -> String { map.zoneOf(system: system) ?? "" }

            // Parts within each system, and each system's size.
            var local: [String: (size: CGSize, parts: [String: CGRect])] = [:]
            for system in map.systems { local[system.id] = partLayout(system: system, flows: data) }

            // Systems within each zone.
            let incoming = Set(data.map(\.to.system)), outgoing = Set(data.map(\.from.system))
            let usedZones = Set(map.systems.map { zone(of: $0.id) })
            var blocks: [String: (size: CGSize, origins: [String: CGPoint])] = [:]
            for z in usedZones {
                let members = map.systems.filter { zone(of: $0.id) == z }
                let ids = Set(members.map(\.id))
                let edges = data.filter { ids.contains($0.from.system) && ids.contains($0.to.system) }
                    .map { Layering.Edge(from: $0.from.system, to: $0.to.system) }
                let pinFirst = Set(members.filter { $0.external && outgoing.contains($0.id) && !incoming.contains($0.id) }.map(\.id))
                let pinLast = Set(members.filter { $0.external && incoming.contains($0.id) && !outgoing.contains($0.id) }.map(\.id))
                let layered = Layering.layout(nodes: Array(ids), edges: edges, pinFirst: pinFirst, pinLast: pinLast)
                let content = place(layered.layers, size: { local[$0]?.size ?? M.systemMinSize }, columnGap: M.columnGap, rowGap: M.rowGap)
                let label = z.isEmpty ? 0 : M.zoneLabel
                blocks[z] = (CGSize(width: content.size.width + 2 * M.zonePad, height: content.size.height + 2 * M.zonePad + label),
                             content.origins.mapValues { CGPoint(x: $0.x + M.zonePad, y: $0.y + M.zonePad + label) })
            }

            // Zones, ordered by the data flowing between them.
            let zoneEdges = data.compactMap { flow -> Layering.Edge? in
                let a = zone(of: flow.from.system), b = zone(of: flow.to.system)
                return a == b ? nil : Layering.Edge(from: a, to: b)
            }
            // Zones holding only outside systems frame the map, as outside systems do inside a zone: those no
            // data flows into on the far left, those data flows into on the far right. That keeps a cycle with an
            // outside zone (phone and cloud) from reordering the columns. Control flows play no part.
            let receiving = Set(zoneEdges.map(\.to))
            let outside = usedZones.filter { z in map.systems.filter { zone(of: $0.id) == z }.allSatisfy(\.external) }
            let leftmost = outside.filter { !receiving.contains($0) }.sorted()
            let rightmost = outside.filter { receiving.contains($0) }.sorted()
            let zoneLayers = ([leftmost] + Layering.layout(nodes: Array(usedZones.subtracting(outside)), edges: zoneEdges).layers + [rightmost])
                .filter { !$0.isEmpty }
            let zoneOrigins = place(zoneLayers, size: { blocks[$0]?.size ?? .zero }, columnGap: M.zoneGap, rowGap: M.zoneGap).origins

            // World rects.
            var systemRects: [String: CGRect] = [:]
            for system in map.systems {
                let z = zone(of: system.id)
                guard let block = blocks[z], let origin = zoneOrigins[z], let inner = block.origins[system.id],
                      let size = local[system.id]?.size else { continue }
                let placed = saved[system.id] ?? CGPoint(x: origin.x + inner.x, y: origin.y + inner.y)
                systemRects[system.id] = CGRect(origin: placed, size: size)
            }

            var zoneBoxes: [MapLayout.Box] = []
            for (index, zone) in map.zones.enumerated() {
                let members = map.systems.filter { $0.zone == zone.id }.compactMap { systemRects[$0.id] }
                guard let first = members.first else { continue }
                let union = members.dropFirst().reduce(first) { $0.union($1) }
                let rect = CGRect(x: union.minX - M.zonePad, y: union.minY - M.zonePad - M.zoneLabel,
                                  width: union.width + 2 * M.zonePad, height: union.height + 2 * M.zonePad + M.zoneLabel)
                zoneBoxes.append(.init(id: MapLayout.zoneBoxID(zone.id), kind: .zone, rect: rect, title: zone.name, subtitle: nil,
                                       external: false, tint: index, partCount: 0))
            }

            var systemBoxes: [MapLayout.Box] = []
            var partBoxes: [MapLayout.Box] = []
            for system in map.systems {
                guard let rect = systemRects[system.id] else { continue }
                let tint = system.zone.flatMap { z in map.zones.firstIndex { $0.id == z } } ?? -1
                systemBoxes.append(.init(id: system.id, kind: .system, rect: rect, title: system.name, subtitle: system.summary,
                                         external: system.external, tint: tint, partCount: system.parts.count))
                for part in system.parts {
                    guard let relative = local[system.id]?.parts[part.id] else { continue }
                    partBoxes.append(.init(id: "\(system.id).\(part.id)", kind: .part, rect: relative.offsetBy(dx: rect.minX, dy: rect.minY),
                                           title: part.name, subtitle: nil, external: false, tint: tint, partCount: 0))
                }
            }

            return MapLayout(boxes: zoneBoxes + systemBoxes + partBoxes, arrows: arrows(map: map, flows: flows))
        }

        /// Parts layered by the data flowing between them, relative to the system's top-left corner.
        static func partLayout(system: FlowMap.System, flows: [FlowMap.Flow]) -> (size: CGSize, parts: [String: CGRect]) {
            guard !system.parts.isEmpty else { return (M.systemMinSize, [:]) }
            let edges = flows.filter { $0.from.system == system.id && $0.to.system == system.id }
                .compactMap { flow -> Layering.Edge? in
                    guard let a = flow.from.part, let b = flow.to.part else { return nil }
                    return Layering.Edge(from: a, to: b)
                }
            let layered = Layering.layout(nodes: system.parts.map(\.id), edges: edges)
            let content = place(layered.layers, size: { _ in M.partSize }, columnGap: M.partColumnGap, rowGap: M.partRowGap)
            let parts = content.origins.mapValues { CGRect(origin: CGPoint(x: $0.x + M.pad, y: $0.y + M.header), size: M.partSize) }
            let size = CGSize(width: max(M.systemMinSize.width, content.size.width + 2 * M.pad),
                              height: max(M.systemMinSize.height, M.header + content.size.height + M.pad))
            return (size, parts)
        }

        /// Columns left to right, each stacked top to bottom and centred against the tallest column.
        static func place(_ layers: [[String]], size: (String) -> CGSize, columnGap: CGFloat, rowGap: CGFloat) -> (size: CGSize, origins: [String: CGPoint]) {
            let heights = layers.map { column in column.map { size($0).height }.reduce(0, +) + CGFloat(max(0, column.count - 1)) * rowGap }
            let widths = layers.map { column in column.map { size($0).width }.max() ?? 0 }
            let total = heights.max() ?? 0
            var origins: [String: CGPoint] = [:]
            var x: CGFloat = 0
            for (index, column) in layers.enumerated() {
                var y = (total - heights[index]) / 2
                for node in column {
                    origins[node] = CGPoint(x: x, y: y)
                    y += size(node).height + rowGap
                }
                x += widths[index] + columnGap
            }
            return (CGSize(width: max(0, x - columnGap), height: total), origins)
        }

        /// Part-level arrows for every flow; merged arrows between systems and between zones.
        static func arrows(map: FlowMap, flows: [FlowMap.Flow]) -> [MapLayout.ArrowSpec] {
            var specs = flows.map { flow in
                MapLayout.ArrowSpec(id: "flow:\(flow.id)", level: .part, from: flow.from.description, to: flow.to.description,
                                    kind: flow.kind, flowIDs: [flow.id], label: flow.carries, conditional: flow.when != nil, weight: 1)
            }
            specs += merged(flows, level: .system, prefix: "sys") { ($0.from.system, $0.to.system) }
            let zones = Set(map.zones.map(\.id))
            specs += merged(flows, level: .zone, prefix: "zone") { flow in
                guard let a = map.zoneOf(system: flow.from.system), let b = map.zoneOf(system: flow.to.system),
                      zones.contains(a), zones.contains(b) else { return nil }
                return (MapLayout.zoneBoxID(a), MapLayout.zoneBoxID(b))
            }
            return specs
        }

        private static func merged(_ flows: [FlowMap.Flow], level: MapLayout.ArrowLevel, prefix: String,
                                   ends: (FlowMap.Flow) -> (String, String)?) -> [MapLayout.ArrowSpec] {
            var order: [String] = []
            var groups: [String: (from: String, to: String, flows: [FlowMap.Flow])] = [:]
            for flow in flows {
                guard let (from, to) = ends(flow), from != to else { continue }
                let bare = { (id: String) in id.hasPrefix("zone:") ? String(id.dropFirst(5)) : id }
                let key = "\(prefix):\(bare(from))>\(bare(to))"
                if groups[key] == nil { order.append(key); groups[key] = (from, to, []) }
                groups[key]?.flows.append(flow)
            }
            return order.compactMap { key in
                guard let group = groups[key] else { return nil }
                let lead = group.flows.first { $0.kind == .data } ?? group.flows[0]
                let extra = group.flows.count - 1
                return MapLayout.ArrowSpec(id: key, level: level, from: group.from, to: group.to,
                                           kind: group.flows.contains { $0.kind == .data } ? .data : .control,
                                           flowIDs: group.flows.map(\.id),
                                           label: level == .zone ? "" : (extra > 0 ? "\(lead.carries) +\(extra)" : lead.carries),
                                           conditional: group.flows.contains { $0.when != nil }, weight: group.flows.count)
            }
        }
    }
}
