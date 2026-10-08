import CoreGraphics

extension MindControl {
    /// What's under a world point: a visible part, else the nearest visible arrow, else a system. Zones aren't selectable.
    enum FlowPicking {
        enum Hit: Equatable {
            case box(String)
            case arrow(String)
        }

        /// How close, in view points, the pointer must be to an arrow.
        static let arrowTolerance: CGFloat = 6

        static func hit(_ world: CGPoint, layout: MapLayout, curves: [String: Curve], zoom: CGFloat, showControl: Bool) -> Hit? {
            if layout.fixedLevel || ZoomLevels.partsVisible(at: zoom),
               let part = layout.boxes.last(where: { $0.kind == .part && $0.rect.contains(world) }) {
                return .box(part.id)
            }
            let level = ZoomLevels.arrowLevel(at: zoom, systemFloor: layout.systemFloor)
            let tolerance = arrowTolerance / max(zoom, 0.01)
            var best: (id: String, distance: CGFloat)?
            for arrow in layout.arrows where (layout.fixedLevel || arrow.level == level) && (showControl || arrow.kind == .data) {
                guard let curve = curves[arrow.id] else { continue }
                let bounds = CGRect(x: min(curve.p0.x, curve.p1.x, curve.p2.x, curve.p3.x), y: min(curve.p0.y, curve.p1.y, curve.p2.y, curve.p3.y),
                                    width: 0, height: 0)
                    .union(CGRect(x: max(curve.p0.x, curve.p1.x, curve.p2.x, curve.p3.x), y: max(curve.p0.y, curve.p1.y, curve.p2.y, curve.p3.y),
                                  width: 0, height: 0))
                    .insetBy(dx: -tolerance, dy: -tolerance)
                guard bounds.contains(world) else { continue }
                let distance = curve.distance(to: world)
                if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (arrow.id, distance) }
            }
            if let best { return .arrow(best.id) }
            if let system = layout.boxes.last(where: { $0.kind == .system && $0.rect.contains(world) }) {
                return .box(system.id)
            }
            return nil
        }
    }
}
