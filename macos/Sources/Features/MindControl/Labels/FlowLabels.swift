import CoreGraphics

extension MindControl {
    /// Label candidates for the current zoom: zone names when far out, system names and summaries in the
    /// middle, part names and arrow labels up close; the selected feature's arrows are always labelled.
    enum FlowLabels {
        private typealias M = LayoutMetrics
        /// View points from a system's name to its summary, centre to centre. Fonts don't scale with zoom, so a gap
        /// in world points would push the summary into the name when zoomed out.
        static let summaryGap: CGFloat = 20

        static func candidates(layout: MapLayout, curves: [String: Curve], camera: PanZoomCamera, viewSize: CGSize,
                               litFlows: Set<String>, showControl: Bool) -> [LabelCandidate] {
            let zoom = camera.zoom
            let fixed = layout.fixedLevel
            func screen(_ x: CGFloat, _ y: CGFloat) -> CGPoint { camera.toScreen(CGPoint(x: x, y: y), viewSize: viewSize) }
            let systemsShown = fixed || zoom >= ZoomLevels.zoneToSystems.lowerBound
            let systemOpacity = fixed ? 1 : smooth(zoom, ZoomLevels.zoneToSystems)
            let partsShown = fixed || ZoomLevels.partsVisible(at: zoom)
            let far = !fixed && zoom < ZoomLevels.zoneToSystems.upperBound
            let arrowLevel = ZoomLevels.arrowLevel(at: zoom)
            var out: [LabelCandidate] = []

            for box in layout.boxes {
                let r = box.rect
                switch box.kind {
                case .zone:
                    // Far out the name strip is a few points tall, so the large name sits just above the zone's
                    // top-left corner instead of spilling over the zone and its neighbours.
                    let fontSize: CGFloat = far ? 22 : 14
                    let anchor = far ? screen(r.minX, r.minY).offset(0, -(4 + fontSize * 0.6))
                        : screen(r.minX + M.zonePad * 0.6, r.minY + M.zoneLabel / 2)
                    out.append(LabelCandidate(id: box.id, text: box.title, anchor: anchor, leading: true, fontSize: fontSize, bold: true,
                                              opacity: far ? 0.95 : 0.55, priority: 0, background: false, maxWidth: nil))
                case .system:
                    guard systemsShown else { continue }
                    let width = r.width * zoom - 28
                    out.append(LabelCandidate(id: box.id, text: box.title, anchor: screen(r.minX, r.minY + 24).offset(14, 0),
                                              leading: true, fontSize: 13, bold: true, opacity: systemOpacity,
                                              priority: 1, background: false, maxWidth: width))
                    // Room for the summary's line (11 pt text is 14 pt tall) inside the box, below the name. For the
                    // smallest box this is zoom 0.45; focus views have no zoom threshold, so it matters there.
                    let summaryFits = (r.height - 24) * zoom >= summaryGap + 7
                    if let summary = box.subtitle, fixed || zoom >= 0.45, summaryFits {
                        out.append(LabelCandidate(id: box.id + "#summary", text: summary,
                                                  anchor: screen(r.minX, r.minY + 24).offset(14, summaryGap), leading: true,
                                                  fontSize: 11, bold: false, opacity: 0.7 * systemOpacity,
                                                  priority: 3, background: false, maxWidth: width))
                    }
                    if box.partCount > 0, !partsShown {
                        out.append(LabelCandidate(id: box.id + "#parts", text: "\(box.partCount) part\(box.partCount == 1 ? "" : "s")",
                                                  anchor: screen(r.minX, r.maxY).offset(14, -14), leading: true, fontSize: 10.5, bold: false,
                                                  opacity: 0.5 * systemOpacity, priority: 4, background: false, maxWidth: nil))
                    }
                case .part:
                    guard partsShown else { continue }
                    out.append(LabelCandidate(id: box.id, text: box.title, anchor: screen(r.midX, r.midY), leading: false,
                                              fontSize: 11.5, bold: true, opacity: 0.95, priority: 2, background: false,
                                              maxWidth: r.width * zoom - 12))
                }
            }

            for arrow in layout.arrows where !arrow.label.isEmpty && (showControl || arrow.kind == .data) {
                guard fixed || arrow.level == arrowLevel, let curve = curves[arrow.id] else { continue }
                let lit = !litFlows.isDisjoint(with: arrow.flowIDs)
                guard fixed || lit || (arrow.level == .part && zoom >= 1.0) else { continue }
                out.append(LabelCandidate(id: arrow.id, text: arrow.label, anchor: camera.toScreen(curve.mid, viewSize: viewSize),
                                          leading: false, fontSize: 10.5, bold: false, opacity: 0.9, priority: lit ? 2 : 5,
                                          background: true, maxWidth: nil))
            }
            return out
        }

        private static func smooth(_ x: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
            let t = min(1, max(0, (x - range.lowerBound) / (range.upperBound - range.lowerBound)))
            return t * t * (3 - 2 * t)
        }
    }
}

private extension CGPoint {
    func offset(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}
