import CoreGraphics

extension MindControl {
    /// Fresh layouts for one subject. Box ids match the main map so the view can slide between them.
    enum FocusLayout {
        private typealias M = LayoutMetrics
        static let sideGap: CGFloat = 180
        static let laneGap: CGFloat = 70
        /// From one lane's top to the next.
        static let laneStep = M.systemMinSize.height + laneGap

        /// The system large in the middle with all its parts; senders on the left, receivers on the right.
        static func system(_ id: String, map: FlowMap, broken: Set<String>) -> MapLayout? {
            guard let subject = map.system(id) else { return nil }
            let flows = map.flows.filter { drawn($0, map: map, broken: broken) }
            let local = FlowLayout.partLayout(system: subject, flows: flows.filter { $0.kind == .data })
            let subjectRect = CGRect(origin: .zero, size: local.size)

            var senders: [String] = []
            var receivers: [String] = []
            for flow in flows {
                let fromSubject = flow.from.system == id, toSubject = flow.to.system == id
                if toSubject, !fromSubject, !senders.contains(flow.from.system) { senders.append(flow.from.system) }
                if fromSubject, !toSubject, !receivers.contains(flow.to.system) { receivers.append(flow.to.system) }
            }
            receivers.removeAll { senders.contains($0) }

            func column(_ ids: [String], x: CGFloat) -> [MapLayout.Box] {
                let height = CGFloat(ids.count) * M.systemMinSize.height + CGFloat(max(0, ids.count - 1)) * M.rowGap
                var y = subjectRect.midY - height / 2
                return ids.compactMap { neighbour in
                    guard let system = map.system(neighbour) else { return nil }
                    defer { y += M.systemMinSize.height + M.rowGap }
                    return MapLayout.Box(id: system.id, kind: .system, rect: CGRect(origin: CGPoint(x: x, y: y), size: M.systemMinSize),
                                         title: system.name, subtitle: nil, external: system.external, tint: tint(system, map), partCount: 0)
                }
            }

            var boxes = [MapLayout.Box(id: subject.id, kind: .system, rect: subjectRect, title: subject.name, subtitle: subject.summary,
                                       external: subject.external, tint: tint(subject, map), partCount: subject.parts.count)]
            for part in subject.parts {
                guard let rect = local.parts[part.id] else { continue }
                boxes.append(.init(id: "\(subject.id).\(part.id)", kind: .part, rect: rect, title: part.name, subtitle: nil,
                                   external: false, tint: tint(subject, map), partCount: 0))
            }
            boxes += column(senders, x: subjectRect.minX - sideGap - M.systemMinSize.width)
            boxes += column(receivers, x: subjectRect.maxX + sideGap)

            let shown = Set(boxes.map(\.id))
            let arrows = flows.filter { $0.from.system == id || $0.to.system == id }.compactMap { flow -> MapLayout.ArrowSpec? in
                let from = shown.contains(flow.from.description) ? flow.from.description : flow.from.system
                let to = shown.contains(flow.to.description) ? flow.to.description : flow.to.system
                guard shown.contains(from), shown.contains(to), from != to else { return nil }
                return MapLayout.ArrowSpec(id: "flow:\(flow.id)", level: .part, from: from, to: to, kind: flow.kind, flowIDs: [flow.id],
                                           label: flow.carries, conditional: flow.when != nil, weight: 1)
            }
            return MapLayout(boxes: boxes, arrows: arrows, fixedLevel: true)
        }

        /// Only the route's systems, one column each in step order; conditional steps get their own lanes and
        /// their arrows bend toward them. Nil when nothing on the route can be drawn.
        static func feature(_ id: String, map: FlowMap, broken: Set<String>) -> MapLayout? {
            guard let feature = map.feature(id) else { return nil }
            // A step the route repeats is drawn once: arrow ids must be unique.
            var seen = Set<String>()
            let steps = feature.route.compactMap { map.flow($0) }
                .filter { drawn($0, map: map, broken: broken) && seen.insert($0.id).inserted }
            var conditions: [String] = []
            var placed: [String: CGPoint] = [:]
            var orderPlaced: [String] = []
            // The system whose step first reached each target.
            var reachedFrom: [String: String] = [:]
            var column = 0
            for flow in steps {
                if let when = flow.when, !conditions.contains(when) { conditions.append(when) }
                // A step's source stays on the main line; only its target moves into the condition's lane.
                for (end, system) in [flow.from.system, flow.to.system].enumerated() where placed[system] == nil {
                    let lane = lane(for: end == 1 ? flow.when : nil, conditions: conditions)
                    placed[system] = CGPoint(x: CGFloat(column) * (M.systemMinSize.width + M.columnGap),
                                             y: CGFloat(lane) * laneStep)
                    if end == 1 { reachedFrom[system] = flow.from.system }
                    orderPlaced.append(system)
                    column += 1
                }
            }
            // Systems first reached in parallel lanes share a column: each in a different lane, none reached
            // from another in the column.
            var columnOf: [String: CGFloat] = [:]
            var lastX: CGFloat = -1
            var shared: [String] = []
            for system in orderPlaced {
                guard let point = placed[system] else { continue }
                let inLane = point.y != 0
                let joins = inLane && !shared.isEmpty && !shared.contains { placed[$0]?.y == point.y || $0 == reachedFrom[system] }
                if joins {
                    columnOf[system] = lastX
                    shared.append(system)
                } else {
                    lastX = lastX < 0 ? 0 : lastX + M.systemMinSize.width + M.columnGap
                    columnOf[system] = lastX
                    shared = inLane ? [system] : []
                }
            }

            let boxes: [MapLayout.Box] = orderPlaced.compactMap { systemID in
                guard let system = map.system(systemID), let point = placed[systemID], let x = columnOf[systemID] else { return nil }
                return MapLayout.Box(id: system.id, kind: .system, rect: CGRect(origin: CGPoint(x: x, y: point.y), size: M.systemMinSize),
                                     title: system.name, subtitle: nil, external: system.external, tint: tint(system, map), partCount: 0)
            }
            guard !boxes.isEmpty else { return nil }
            // A conditional arrow bends into its condition's lane, even between systems already on the main line.
            let arrows = steps.compactMap { flow -> MapLayout.ArrowSpec? in
                guard flow.from.system != flow.to.system else { return nil }
                return MapLayout.ArrowSpec(id: "flow:\(flow.id)", level: .system, from: flow.from.system, to: flow.to.system,
                                           kind: flow.kind, flowIDs: [flow.id], label: flow.carries, conditional: flow.when != nil, weight: 1,
                                           bend: CGFloat(lane(for: flow.when, conditions: conditions)) * laneStep)
            }
            return MapLayout(boxes: boxes, arrows: arrows, fixedLevel: true)
        }

        /// 0 for unconditional; the 1st condition above (-1), the 2nd below (+1), the 3rd above (-2)…
        static func lane(for when: String?, conditions: [String]) -> Int {
            guard let when, let index = conditions.firstIndex(of: when) else { return 0 }
            let k = index + 1
            return k % 2 == 1 ? -((k + 1) / 2) : k / 2
        }

        /// Not broken, and between systems the map declares, even when no health report has marked it broken.
        private static func drawn(_ flow: FlowMap.Flow, map: FlowMap, broken: Set<String>) -> Bool {
            !broken.contains(flow.id) && map.system(flow.from.system) != nil && map.system(flow.to.system) != nil
        }

        private static func tint(_ system: FlowMap.System, _ map: FlowMap) -> Int {
            system.zone.flatMap { z in map.zones.firstIndex { $0.id == z } } ?? -1
        }
    }
}
