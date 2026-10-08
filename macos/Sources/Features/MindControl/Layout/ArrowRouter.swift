import CoreGraphics

extension MindControl {
    /// A cubic Bézier in world points.
    struct Curve: Equatable {
        var p0: CGPoint
        var p1: CGPoint
        var p2: CGPoint
        var p3: CGPoint

        func point(at t: CGFloat) -> CGPoint {
            let s = 1 - t
            let a = s * s * s, b = 3 * s * s * t, c = 3 * s * t * t, d = t * t * t
            return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }

        func tangent(at t: CGFloat) -> CGVector {
            let s = 1 - t
            let a = 3 * s * s, b = 6 * s * t, c = 3 * t * t
            return CGVector(dx: a * (p1.x - p0.x) + b * (p2.x - p1.x) + c * (p3.x - p2.x),
                            dy: a * (p1.y - p0.y) + b * (p2.y - p1.y) + c * (p3.y - p2.y))
        }

        var mid: CGPoint { point(at: 0.5) }

        /// Approximate distance from `p` to the curve, sampled at 32 segments.
        func distance(to p: CGPoint) -> CGFloat {
            var best = CGFloat.greatestFiniteMagnitude
            var previous = p0
            for i in 1...32 {
                let next = point(at: CGFloat(i) / 32)
                best = min(best, Self.segmentDistance(p, previous, next))
                previous = next
            }
            return best
        }

        private static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }
    }

    /// Curves for arrow specs: out of the facing edges of the two boxes, with parallel arrows between
    /// the same two boxes spread apart so a flow and its return never overlap. When that curve passes over
    /// another box, the arrows between the pair try other edges (including a bracket out of the same side
    /// of both) and take the one crossing the fewest boxes.
    enum ArrowRouter {
        enum Side: CaseIterable, Equatable {
            case left, right, top, bottom

            /// Pointing out of the box.
            var normal: CGVector {
                switch self {
                case .left: CGVector(dx: -1, dy: 0)
                case .right: CGVector(dx: 1, dy: 0)
                case .top: CGVector(dx: 0, dy: -1)
                case .bottom: CGVector(dx: 0, dy: 1)
                }
            }

            /// Along the edge, toward +x or +y.
            var along: CGVector { normal.dx == 0 ? CGVector(dx: 1, dy: 0) : CGVector(dx: 0, dy: 1) }

            func midpoint(of r: CGRect) -> CGPoint {
                switch self {
                case .left: CGPoint(x: r.minX, y: r.midY)
                case .right: CGPoint(x: r.maxX, y: r.midY)
                case .top: CGPoint(x: r.midX, y: r.minY)
                case .bottom: CGPoint(x: r.midX, y: r.maxY)
                }
            }

            func length(of r: CGRect) -> CGFloat { normal.dx == 0 ? r.width : r.height }
        }

        /// How one arrow runs, apart from where its boxes are: the edges it leaves and enters by, in its own
        /// direction, and whether it is the facing-edge curve or a detour (with short or long handles).
        struct Route: Equatable {
            let exit: Side
            let entry: Side
            let detour: Bool
            let short: Bool
        }

        /// Every arrow's curve and the route it takes.
        struct Plan {
            var curves: [String: Curve] = [:]
            var routes: [String: Route] = [:]
            /// How many times routing tested a curve against a box: the cost of the pass.
            var boxChecks = 0
        }

        static func curves(for layout: MapLayout) -> [String: Curve] { plan(for: layout).curves }

        /// Curves that keep the given routes, so only their ends follow the boxes: a transition picks the
        /// routes once, for where the boxes end up. An arrow without a route takes its facing edges.
        static func curves(for layout: MapLayout, keeping routes: [String: Route]) -> [String: Curve] {
            var curves: [String: Curve] = [:]
            for members in groups(in: layout) {
                for member in members {
                    let route = routes[member.arrow.id] ?? facingRoute(member)
                    curves[member.arrow.id] = curve(member, route, pairFirst: members[0].pairFirst)
                }
            }
            return curves
        }

        static func plan(for layout: MapLayout) -> Plan {
            let memberGroups = groups(in: layout)
            // Facing-edge curves first; a group that has to move away from a box then sees where the others run.
            var plan = Plan()
            var lines: [String: Polyline] = [:]
            for member in memberGroups.joined() {
                let route = facingRoute(member)
                let curve = curve(member, route, pairFirst: member.pairFirst)
                plan.curves[member.arrow.id] = curve
                plan.routes[member.arrow.id] = route
                lines[member.arrow.id] = Polyline(curve)
            }
            let boxes = Boxes(layout)
            var idsByLevel: [MapLayout.ArrowLevel: [String]] = [:]
            for member in memberGroups.joined() { idsByLevel[member.arrow.level, default: []].append(member.arrow.id) }
            for members in memberGroups {
                guard let level = members.first?.arrow.level else { continue }
                let own = Set(members.map(\.arrow.id))
                let others = { [lines] in (idsByLevel[level] ?? []).filter { !own.contains($0) }.compactMap { lines[$0] } }
                guard let detour = detour(members, facing: members.compactMap { lines[$0.arrow.id] }, layout: layout, boxes: boxes,
                                          others: others, checks: &plan.boxChecks) else { continue }
                for (member, choice) in zip(members, detour) {
                    plan.curves[member.arrow.id] = choice.line.curve
                    plan.routes[member.arrow.id] = choice.route
                    lines[member.arrow.id] = choice.line
                }
            }
            return plan
        }

        static func route(from a: CGRect, to b: CGRect, offset: CGFloat, bend: CGFloat = 0) -> Curve {
            let sides = facingSides(a, b)
            return bent(facing(from: a, sides.exit, to: b, sides.entry, offset: offset), by: bend)
        }

        // MARK: - Groups

        /// One arrow of a group between the same two boxes.
        private struct Member {
            let arrow: MapLayout.ArrowSpec
            let from: CGRect
            let to: CGRect
            let offset: CGFloat
            /// The pair's ids sorted; sides and parallel shifts are worked out in these terms.
            let pairFirst: String
        }

        /// Arrows grouped by level and box pair, in first-seen order, each with its parallel offset.
        private static func groups(in layout: MapLayout) -> [[Member]] {
            var rects: [String: CGRect] = [:]
            for box in layout.boxes { rects[box.id] = box.rect }
            var groups: [String: [MapLayout.ArrowSpec]] = [:]
            var keys: [String] = []
            for arrow in layout.arrows {
                let pair = [arrow.from, arrow.to].sorted()
                let key = "\(arrow.level.rawValue)|\(pair[0])|\(pair[1])"
                if groups[key] == nil { keys.append(key) }
                groups[key, default: []].append(arrow)
            }
            return keys.map { key -> [Member] in
                let group = groups[key] ?? []
                return group.enumerated().compactMap { index, arrow in
                    guard let a = rects[arrow.from], let b = rects[arrow.to] else { return nil }
                    let offset = (CGFloat(index) - CGFloat(group.count - 1) / 2) * LayoutMetrics.parallelSpacing
                    return Member(arrow: arrow, from: a, to: b, offset: offset, pairFirst: min(arrow.from, arrow.to))
                }
            }
        }

        // MARK: - Curves

        private static func facingRoute(_ member: Member) -> Route {
            let sides = facingSides(member.from, member.to)
            return Route(exit: sides.exit, entry: sides.entry, detour: false, short: false)
        }

        /// The member's curve along `route`, bent by the arrow's `bend`.
        private static func curve(_ member: Member, _ route: Route, pairFirst: String) -> Curve {
            guard route.detour else {
                return bent(facing(from: member.from, route.exit, to: member.to, route.entry, offset: member.offset), by: member.arrow.bend)
            }
            let forward = member.arrow.from == pairFirst
            let one = forward ? member.from : member.to, two = forward ? member.to : member.from
            let sideOne = forward ? route.exit : route.entry, sideTwo = forward ? route.entry : route.exit
            let shifts = shifts(one, sideOne, two, sideTwo, offset: member.offset)
            let curve = forward
                ? sided(from: member.from, sideOne, shift: shifts.one, to: member.to, sideTwo, shift: shifts.two, extra: shifts.extra,
                        short: route.short)
                : sided(from: member.from, sideTwo, shift: shifts.two, to: member.to, sideOne, shift: shifts.one, extra: shifts.extra,
                        short: route.short)
            return bent(curve, by: member.arrow.bend)
        }

        /// Moves both control points `bend` across the chord; the ends stay put. Negative is up whichever
        /// way the arrow runs (y down), or left when the chord is closer to vertical.
        private static func bent(_ curve: Curve, by bend: CGFloat) -> Curve {
            let dx = curve.p3.x - curve.p0.x, dy = curve.p3.y - curve.p0.y
            let length = hypot(dx, dy)
            guard bend != 0, length > 0 else { return curve }
            var nx = -dy / length, ny = dx / length
            if abs(dx) >= abs(dy) ? ny < 0 : nx < 0 { nx = -nx; ny = -ny }
            var out = curve
            out.p1 = CGPoint(x: curve.p1.x + nx * bend, y: curve.p1.y + ny * bend)
            out.p2 = CGPoint(x: curve.p2.x + nx * bend, y: curve.p2.y + ny * bend)
            return out
        }

        /// Side by side boxes face each other left and right; otherwise top and bottom.
        private static func facingSides(_ a: CGRect, _ b: CGRect) -> (exit: Side, entry: Side) {
            if b.minX > a.maxX || b.maxX < a.minX { return b.midX >= a.midX ? (.right, .left) : (.left, .right) }
            return b.midY >= a.midY ? (.bottom, .top) : (.top, .bottom)
        }

        /// The facing-edge curve: both ends slid by `offset` along their edges, handles straight out.
        private static func facing(from a: CGRect, _ exit: Side, to b: CGRect, _ entry: Side, offset: CGFloat) -> Curve {
            if exit == .left || exit == .right {
                let sign: CGFloat = exit == .right ? 1 : -1
                let dy = clamp(offset, a, b, \.height)
                let start = CGPoint(x: sign > 0 ? a.maxX : a.minX, y: a.midY + dy)
                let end = CGPoint(x: sign > 0 ? b.minX : b.maxX, y: b.midY + dy)
                let k = max(40, abs(end.x - start.x) * 0.45)
                return Curve(p0: start, p1: CGPoint(x: start.x + sign * k, y: start.y),
                             p2: CGPoint(x: end.x - sign * k, y: end.y), p3: end)
            }
            let sign: CGFloat = exit == .bottom ? 1 : -1
            let dx = clamp(offset, a, b, \.width)
            let start = CGPoint(x: a.midX + dx, y: sign > 0 ? a.maxY : a.minY)
            let end = CGPoint(x: b.midX + dx, y: sign > 0 ? b.minY : b.maxY)
            let k = max(30, abs(end.y - start.y) * 0.45)
            return Curve(p0: start, p1: CGPoint(x: start.x, y: start.y + sign * k),
                         p2: CGPoint(x: end.x, y: end.y - sign * k), p3: end)
        }

        private static func clamp(_ offset: CGFloat, _ a: CGRect, _ b: CGRect, _ side: KeyPath<CGRect, CGFloat>) -> CGFloat {
            let limit = max(0, min(a[keyPath: side], b[keyPath: side]) / 2 - 4)
            return max(-limit, min(limit, offset))
        }

        /// How far each end slides along its edge for a parallel arrow, in the pair's own terms so an arrow
        /// and its return slide apart. Brackets (both ends on the same side) nest instead: the end points move
        /// apart and the bulge grows by `extra`.
        private static func shifts(_ one: CGRect, _ sideOne: Side, _ two: CGRect, _ sideTwo: Side,
                                   offset: CGFloat) -> (one: CGFloat, two: CGFloat, extra: CGFloat) {
            if sideOne == sideTwo {
                let along = sideOne.along
                let a = sideOne.midpoint(of: one), b = sideTwo.midpoint(of: two)
                let apart: CGFloat = (b.x - a.x) * along.dx + (b.y - a.y) * along.dy >= 0 ? 1 : -1
                return (-offset * apart, offset * apart, offset)
            }
            let travel = CGVector(dx: sideOne.normal.dx - sideTwo.normal.dx, dy: sideOne.normal.dy - sideTwo.normal.dy)
            let across = CGVector(dx: -travel.dy, dy: travel.dx)
            func sign(_ v: CGVector) -> CGFloat { across.dx * v.dx + across.dy * v.dy < 0 ? -1 : 1 }
            return (offset * sign(sideOne.along), offset * sign(sideTwo.along), 0)
        }

        /// A curve out of `exit` of `a` and into `entry` of `b`, each end slid along its edge (kept 4 pt from the
        /// corners). Its handles point straight out of each edge, 40 pt when `short`; a bracket's reach past the
        /// farther box.
        private static func sided(from a: CGRect, _ exit: Side, shift: CGFloat, to b: CGRect, _ entry: Side, shift endShift: CGFloat,
                                  extra: CGFloat, short: Bool) -> Curve {
            func end(_ r: CGRect, _ side: Side, _ shift: CGFloat) -> CGPoint {
                let limit = max(0, side.length(of: r) / 2 - 4)
                let slide = max(-limit, min(limit, shift))
                let mid = side.midpoint(of: r)
                return CGPoint(x: mid.x + side.along.dx * slide, y: mid.y + side.along.dy * slide)
            }
            let start = end(a, exit, shift), finish = end(b, entry, endShift)
            let distance = hypot(finish.x - start.x, finish.y - start.y)
            var kStart: CGFloat, kEnd: CGFloat
            if exit == entry {
                let n = exit.normal
                let base = (short ? 40 : max(40, distance * 0.25)) + extra
                kStart = base + max(0, (finish.x - start.x) * n.dx + (finish.y - start.y) * n.dy)
                kEnd = base + max(0, (start.x - finish.x) * n.dx + (start.y - finish.y) * n.dy)
            } else {
                kStart = short ? 40 : max(40, distance * 0.45)
                kEnd = kStart
            }
            kStart = max(10, kStart)
            kEnd = max(10, kEnd)
            return Curve(p0: start, p1: CGPoint(x: start.x + exit.normal.dx * kStart, y: start.y + exit.normal.dy * kStart),
                         p2: CGPoint(x: finish.x + entry.normal.dx * kEnd, y: finish.y + entry.normal.dy * kEnd), p3: finish)
        }

        // MARK: - Around boxes

        /// Nil when the group's facing-edge curves pass over no box. Otherwise every pair of sides, each with long
        /// and short handles, and the one crossing the fewest boxes wins. Ties go to the fewest name strips crossed
        /// (of the boxes it runs inside), then the fewest other arrows at its level crossed or met end to end, then
        /// the shortest. The facing edges win any tie with them, so nil again.
        private static func detour(_ members: [Member], facing: [Polyline], layout: MapLayout, boxes: Boxes,
                                   others: () -> [Polyline], checks: inout Int) -> [(route: Route, line: Polyline)]? {
            guard let first = members.first, facing.count == members.count else { return nil }
            let ends = [first.arrow.from, first.arrow.to]
            let level = layout.fixedLevel ? .part : first.arrow.level
            let obstacles = Obstacles(boxes, level: level, between: first.from, and: first.to, ids: ends)
            let baseline = facing.reduce(0) { $0 + obstacles.entered(by: $1, upTo: .max, checks: &checks) }
            guard baseline > 0 else { return nil }

            // Sides are chosen for the pair, so a flow and its return leave and enter by the same edges.
            var fewest = baseline - 1
            var tied: [[(route: Route, line: Polyline)]] = []
            for sideOne in Side.allCases {
                for sideTwo in Side.allCases {
                    for short in [false, true] {
                        var choices: [(route: Route, line: Polyline)] = []
                        var score = 0
                        for member in members where score <= fewest {
                            let forward = member.arrow.from == first.pairFirst
                            let route = Route(exit: forward ? sideOne : sideTwo, entry: forward ? sideTwo : sideOne, detour: true, short: short)
                            let line = Polyline(curve(member, route, pairFirst: first.pairFirst))
                            score += obstacles.entered(by: line, upTo: fewest - score, checks: &checks)
                            choices.append((route, line))
                        }
                        guard score <= fewest else { continue }
                        if score < fewest { tied = [] }
                        fewest = score
                        tied.append(choices)
                    }
                }
            }
            guard tied.count > 1 else { return tied.first }
            let strips = nameStrips(around: first.from, and: first.to, ids: ends, layout: layout)
            let stripCounts = tied.map { $0.reduce(0) { $0 + $1.line.entered(strips, upTo: .max, checks: &checks) } }
            let fewestStrips = stripCounts.min() ?? 0
            tied = zip(tied, stripCounts).filter { $0.1 == fewestStrips }.map(\.0)
            guard tied.count > 1 else { return tied.first }
            // Only arrows near the tied candidates can cross them or share an end with them.
            var reach = tied[0][0].line.bounds
            for line in tied.joined().map(\.line) { reach = reach.union(line.bounds) }
            let near = reach.grown(by: 12)
            let placed = others().filter { $0.bounds.overlaps(near) }
            var best: (choices: [(route: Route, line: Polyline)], meets: Int, length: CGFloat)?
            for choices in tied {
                let meets = choices.reduce(0) { total, choice in
                    total + placed.reduce(0) { $0 + (choice.line.sharesAnEnd(with: $1) || choice.line.crosses($1) ? 1 : 0) }
                }
                let length = choices.reduce(0) { $0 + $1.line.length }
                if let current = best, meets > current.meets || meets == current.meets && length >= current.length - 0.5 { continue }
                best = (choices, meets, length)
            }
            return best?.choices
        }

        /// The strips holding the names of the boxes the arrow runs inside: a system's header, a zone's label.
        private static func nameStrips(around a: CGRect, and b: CGRect, ids: [String], layout: MapLayout) -> [Area] {
            layout.boxes.compactMap { box -> Area? in
                guard !ids.contains(box.id), box.rect.contains(a) || box.rect.contains(b) else { return nil }
                let r = box.rect
                switch box.kind {
                case .zone: return Area(CGRect(x: r.minX, y: r.minY, width: r.width, height: min(r.height, LayoutMetrics.zoneLabel)))
                case .system: return Area(CGRect(x: r.minX, y: r.minY, width: r.width, height: min(r.height, LayoutMetrics.header)))
                case .part: return nil
                }
            }
        }

        /// A layout's boxes, prepared once per pass as a tree: zones hold their systems, systems their parts. A
        /// curve that misses a box's rect misses everything inside it, so whole zones and systems are skipped at once.
        private struct Boxes {
            let boxes: [MapLayout.Box]
            /// Each box shrunk by 1 pt, so touching an edge isn't entering.
            let areas: [Area]
            let rects: [Area]
            /// 0 for a zone, 1 a system, 2 a part: the arrow level that starts drawing it.
            let depths: [Int]
            let children: [[Int]]
            let roots: [Int]
            let indexOf: [String: Int]

            init(_ layout: MapLayout) {
                let boxes = layout.boxes
                self.boxes = boxes
                areas = boxes.map { Area($0.rect.insetBy(dx: 1, dy: 1)) }
                rects = boxes.map { Area($0.rect) }
                depths = boxes.map { box in
                    switch box.kind {
                    case .zone: 0
                    case .system: 1
                    case .part: 2
                    }
                }
                var indexOf: [String: Int] = [:]
                for (i, box) in boxes.enumerated() where indexOf[box.id] == nil { indexOf[box.id] = i }
                self.indexOf = indexOf
                // A part sits in the system its id names, a system in the zone holding it; anything not inside the
                // box it should be in is a root, so skipping a box never skips something outside it.
                let zones = boxes.indices.filter { boxes[$0].kind == .zone }
                var children = Array(repeating: [Int](), count: boxes.count)
                var roots: [Int] = []
                for (i, box) in boxes.enumerated() {
                    var parent: Int?
                    switch box.kind {
                    case .zone: parent = nil
                    case .system: parent = zones.first { boxes[$0].rect.contains(box.rect) }
                    case .part:
                        let system = box.id.split(separator: ".", maxSplits: 1).first.flatMap { indexOf[String($0)] }
                        if let system, system != i, boxes[system].kind == .system, boxes[system].rect.contains(box.rect) {
                            parent = system
                        } else {
                            parent = zones.first { boxes[$0].rect.contains(box.rect) }
                        }
                    }
                    if let parent { children[parent].append(i) } else { roots.append(i) }
                }
                self.children = children
                self.roots = roots
            }
        }

        /// The boxes an arrow at `level` must not pass over: those drawn at that level, other than the two it joins
        /// and any box holding either (a part's system, a system's zone). Its own two boxes count too, slightly
        /// shrunk so leaving an edge isn't a crossing, unless one holds the other.
        private struct Obstacles {
            let boxes: Boxes
            /// Deepest kind drawn: 0 zones, 1 systems, 2 parts.
            let depth: Int
            /// The arrow's own boxes and the boxes holding them: never obstacles, though what's inside them can be.
            let skipped: [Int]
            let roots: [Int]
            let own: [Area]

            init(_ boxes: Boxes, level: MapLayout.ArrowLevel, between a: CGRect, and b: CGRect, ids: [String]) {
                self.boxes = boxes
                let depth = level.rawValue
                self.depth = depth
                // A box holding an end holds its rect, so it is the end's ancestor or a root holding it.
                var skipped = ids.compactMap { boxes.indexOf[$0] }
                var stack = boxes.roots
                while let i = stack.popLast() {
                    let rect = boxes.boxes[i].rect
                    guard rect.contains(a) || rect.contains(b) else { continue }
                    if !skipped.contains(i) { skipped.append(i) }
                    stack += boxes.children[i]
                }
                self.skipped = skipped
                roots = boxes.roots.filter { boxes.depths[$0] <= depth }
                own = a.contains(b) || b.contains(a) ? []
                    : [a.insetBy(dx: 2, dy: 2), b.insetBy(dx: 2, dy: 2)].filter { !$0.isNull && !$0.isEmpty }.map(Area.init)
            }

            /// How many of the boxes the line passes inside, counting no further than `limit` + 1. A box the line's
            /// bounds miss is skipped with everything inside it.
            func entered(by line: Polyline, upTo limit: Int, checks: inout Int) -> Int {
                var count = line.entered(own, upTo: limit, checks: &checks)
                var stack = roots
                while count <= limit, let i = stack.popLast() {
                    checks += 1
                    guard line.touches(boxes.rects[i]) else { continue }
                    if !skipped.contains(i), line.enters(boxes.areas[i]) { count += 1 }
                    for child in boxes.children[i] where boxes.depths[child] <= depth { stack.append(child) }
                }
                return count
            }
        }
    }
}

extension MindControl.ArrowRouter {
    /// A rect as its edges, quick to test against.
    fileprivate struct Area {
        let minX, minY, maxX, maxY: CGFloat

        init(minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        init(_ r: CGRect) { self.init(minX: r.minX, minY: r.minY, maxX: r.maxX, maxY: r.maxY) }

        func overlaps(_ o: Area) -> Bool { maxX > o.minX && minX < o.maxX && maxY > o.minY && minY < o.maxY }

        func grown(by d: CGFloat) -> Area { Area(minX: minX - d, minY: minY - d, maxX: maxX + d, maxY: maxY + d) }

        func union(_ o: Area) -> Area {
            Area(minX: min(minX, o.minX), minY: min(minY, o.minY), maxX: max(maxX, o.maxX), maxY: max(maxY, o.maxY))
        }
    }

    /// A curve sampled at 16 segments, with the box around the samples.
    fileprivate struct Polyline {
        let curve: MindControl.Curve
        let points: [CGPoint]
        let bounds: Area

        init(_ curve: MindControl.Curve) {
            self.curve = curve
            var points: [CGPoint] = []
            points.reserveCapacity(17)
            var minX = CGFloat.greatestFiniteMagnitude, minY = minX, maxX = -minX, maxY = -minX
            for i in 0...16 {
                let p = curve.point(at: CGFloat(i) / 16)
                points.append(p)
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            self.points = points
            bounds = Area(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        }

        var length: CGFloat {
            var total: CGFloat = 0
            for i in 1..<points.count { total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y) }
            return total
        }

        /// How many of `boxes` the line passes inside, counting no further than `limit` + 1.
        func entered(_ boxes: [Area], upTo limit: Int, checks: inout Int) -> Int {
            var count = 0
            for box in boxes where count <= limit {
                checks += 1
                if enters(box) { count += 1 }
            }
            return count
        }

        /// Whether some segment's box overlaps `r`: cheap, and tighter than the whole line's box for a long curve
        /// passing by a large box.
        func touches(_ r: Area) -> Bool {
            guard bounds.overlaps(r) else { return false }
            var i = 1
            while i < points.count {
                let p = points[i - 1], q = points[i]
                i += 1
                if max(p.x, q.x) > r.minX, min(p.x, q.x) < r.maxX, max(p.y, q.y) > r.minY, min(p.y, q.y) < r.maxY { return true }
            }
            return false
        }

        func enters(_ r: Area) -> Bool {
            guard bounds.overlaps(r) else { return false }
            var i = 1
            while i < points.count {
                let p = points[i - 1], q = points[i]
                i += 1
                // A segment whose box only touches the rect can't reach inside it.
                if max(p.x, q.x) <= r.minX || min(p.x, q.x) >= r.maxX || max(p.y, q.y) <= r.minY || min(p.y, q.y) >= r.maxY { continue }
                if Self.segment(p, q, hits: r) { return true }
            }
            return false
        }

        /// Whether the two lines cross. Lines that only touch don't.
        func crosses(_ other: Polyline) -> Bool {
            guard bounds.grown(by: 1).overlaps(other.bounds) else { return false }
            func side(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
            let theirs = other.bounds
            for i in 1..<points.count {
                let a = points[i - 1], b = points[i]
                if max(a.x, b.x) < theirs.minX || min(a.x, b.x) > theirs.maxX
                    || max(a.y, b.y) < theirs.minY || min(a.y, b.y) > theirs.maxY { continue }
                for j in 1..<other.points.count {
                    let c = other.points[j - 1], d = other.points[j]
                    if max(c.x, d.x) < min(a.x, b.x) || min(c.x, d.x) > max(a.x, b.x)
                        || max(c.y, d.y) < min(a.y, b.y) || min(c.y, d.y) > max(a.y, b.y) { continue }
                    if side(a, b, c) * side(a, b, d) < 0, side(c, d, a) * side(c, d, b) < 0 { return true }
                }
            }
            return false
        }

        /// Whether an end lands within 12 pt of an end of `other`, where their arrowheads would mix.
        func sharesAnEnd(with other: Polyline) -> Bool {
            func near(_ a: CGPoint, _ b: CGPoint) -> Bool { (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) < 144 }
            return near(curve.p0, other.curve.p0) || near(curve.p0, other.curve.p3)
                || near(curve.p3, other.curve.p0) || near(curve.p3, other.curve.p3)
        }

        /// Liang–Barsky: whether the segment from `p` to `q` enters the rect's interior.
        private static func segment(_ p: CGPoint, _ q: CGPoint, hits r: Area) -> Bool {
            let dx = q.x - p.x, dy = q.y - p.y
            var low: CGFloat = 0, high: CGFloat = 1
            return clip(p.x - r.minX, -dx, &low, &high) && clip(r.maxX - p.x, dx, &low, &high)
                && clip(p.y - r.minY, -dy, &low, &high) && clip(r.maxY - p.y, dy, &low, &high)
        }

        private static func clip(_ edge: CGFloat, _ delta: CGFloat, _ low: inout CGFloat, _ high: inout CGFloat) -> Bool {
            if delta == 0 { return edge > 0 }
            let t = edge / delta
            if delta < 0 { low = max(low, t) } else { high = min(high, t) }
            return low < high
        }
    }
}
