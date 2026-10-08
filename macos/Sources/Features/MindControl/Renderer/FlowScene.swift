import CoreGraphics
import Foundation
import simd

extension MindControl {
    enum Palette {
        static let zoneTints: [SIMD3<Float>] = [
            SIMD3(0.30, 0.45, 1.00), SIMD3(0.55, 0.35, 1.00), SIMD3(0.20, 0.75, 0.80),
            SIMD3(0.95, 0.55, 0.30), SIMD3(0.40, 0.85, 0.45), SIMD3(0.90, 0.40, 0.65),
        ]
        static let features: [SIMD3<Float>] = [
            SIMD3(0.25, 0.65, 1.00), SIMD3(1.00, 0.55, 0.20), SIMD3(0.30, 0.90, 0.55), SIMD3(0.75, 0.45, 1.00),
            SIMD3(1.00, 0.40, 0.55), SIMD3(0.95, 0.85, 0.30), SIMD3(0.30, 0.90, 0.90), SIMD3(0.85, 0.60, 0.40),
        ]
        static var featureCount: Int { features.count }
        static let data = SIMD3<Float>(0.45, 0.66, 1.00)
        static let control = SIMD3<Float>(0.55, 0.56, 0.68)
        static let amber = SIMD3<Float>(1.00, 0.62, 0.15)
        static let grey = SIMD3<Float>(0.24, 0.26, 0.30)

        static func zone(_ index: Int) -> SIMD3<Float> {
            index < 0 ? SIMD3(0.40, 0.45, 0.60) : zoneTints[index % zoneTints.count]
        }

        static func feature(_ index: Int) -> SIMD3<Float> { features[((index % featureCount) + featureCount) % featureCount] }
    }

    /// What the scene should emphasise. Built by MapController.
    struct SceneStyle: Equatable {
        enum Mode: Equatable { case map, health }

        var mode: Mode = .map
        var showControl = true
        /// The selected feature's route; empty when no feature is selected.
        var litFlows: Set<String> = []
        var featureColor: SIMD3<Float>?
        /// A box or arrow id.
        var selected: String?
        /// A box briefly highlighted after search.
        var pulsed: String?
        /// Per-box opacity during view transitions (default 1).
        var fade: [String: Float] = [:]
    }

    /// GPU instances for one frame's worth of map.
    struct FlowScene {
        var boxes: [MCBoxInstance] = []
        var arrows: [MCArrowInstance] = []
        var markers: [MCMarkerInstance] = []
        var fixedLevel = false

        static func build(layout: MapLayout, curves: [String: Curve], report: HealthReport, style: SceneStyle) -> FlowScene {
            var scene = FlowScene()
            scene.fixedLevel = layout.fixedLevel
            let health = style.mode == .health
            let featureActive = !style.litFlows.isEmpty

            var litBoxes = Set<String>()
            if featureActive {
                for arrow in layout.arrows where !style.litFlows.isDisjoint(with: arrow.flowIDs) {
                    for id in [arrow.from, arrow.to] {
                        litBoxes.insert(id)
                        if !id.hasPrefix("zone:"), let dot = id.firstIndex(of: ".") { litBoxes.insert(String(id[..<dot])) }
                    }
                }
            }
            let staleSystems = Set(report.staleParts.compactMap { $0.split(separator: ".").first.map(String.init) })

            for box in layout.boxes {
                let tint = Palette.zone(box.tint)
                var fill = SIMD3<Float>(repeating: 0)
                var stroke = SIMD3<Float>(repeating: 0)
                var glow: Float = 0
                var radius: Float = 12
                var level = Float(MC_LEVEL_ALWAYS)
                switch box.kind {
                case .zone:
                    fill = tint * 0.03
                    stroke = tint * 0.22
                    radius = 30
                case .system:
                    fill = SIMD3(0.018, 0.024, 0.05)
                    stroke = box.external ? tint * 0.45 : mix(tint, SIMD3(0.5, 0.65, 1.0), 0.5) * 0.9
                    glow = box.external ? 0.3 : 1
                    radius = 14
                case .part:
                    fill = SIMD3(0.03, 0.04, 0.08)
                    stroke = SIMD3(0.5, 0.62, 1.0) * 0.6
                    glow = 0.4
                    radius = 8
                    level = Float(MC_LEVEL_PART)
                }
                if health {
                    fill = SIMD3(0.015, 0.016, 0.02)
                    stroke = Palette.grey * (box.kind == .zone ? 0.5 : 1)
                    glow = 0
                    let stale = (box.kind == .part && report.staleParts.contains(box.id))
                        || (box.kind == .system && staleSystems.contains(box.id))
                    if stale {
                        stroke = Palette.amber
                        glow = 1.2
                    }
                }
                var intensity: Float = 1
                if featureActive, box.kind != .zone, !litBoxes.contains(box.id) { intensity = 0.25 }
                if style.selected == box.id { stroke *= 1.8; glow += 1.5 }
                if style.pulsed == box.id { glow += 3 }
                intensity *= style.fade[box.id] ?? 1
                scene.boxes.append(MCBoxInstance(
                    origin: SIMD2(Float(box.rect.minX), Float(box.rect.minY)),
                    size: SIMD2(Float(box.rect.width), Float(box.rect.height)),
                    fill: SIMD4(fill * intensity, 1), stroke: SIMD4(stroke * intensity, 1),
                    radius: radius, glow: glow * intensity, dashed: box.external ? 1 : 0, level: level))
            }

            for arrow in layout.arrows {
                guard let curve = curves[arrow.id] else { continue }
                if arrow.kind == .control, !style.showControl { continue }
                let lit = featureActive && !style.litFlows.isDisjoint(with: arrow.flowIDs)
                var color: SIMD3<Float>
                var width: Float
                var dashed: Float = 0
                var pulses: Float = 0
                if arrow.kind == .data {
                    color = Palette.data
                    width = 1.6 + log2(Float(max(1, arrow.weight))) * 0.9
                    pulses = 1
                } else {
                    color = Palette.control * 0.8
                    width = 1
                    dashed = 1
                }
                if lit {
                    color = (style.featureColor ?? color) * 1.4
                    width += 0.6
                } else if featureActive {
                    color *= 0.12
                    pulses = 0
                }
                if health {
                    pulses = 0
                    let ids = Set(arrow.flowIDs)
                    if !ids.isDisjoint(with: report.staleFlows) {
                        color = Palette.amber   // keeps its kind's line: control dashed, data solid
                    } else if !ids.isDisjoint(with: report.unverifiedFlows) {
                        // Faint dashes of either kind: well under a healthy arrow, since control arrows are dashed anyway.
                        color = Palette.grey * 0.35
                        dashed = 1
                    } else {
                        color = Palette.grey
                    }
                    // A selected feature still lights its route and dims the rest, in Health's colours.
                    if featureActive { color *= lit ? 1.4 : 0.12 }
                }
                if style.selected == arrow.id { color *= 1.8; width += 0.8 }
                color *= min(style.fade[arrow.from] ?? 1, style.fade[arrow.to] ?? 1)
                let level = Float(arrow.level.rawValue)
                scene.arrows.append(MCArrowInstance(
                    p0: vector(curve.p0), p1: vector(curve.p1), p2: vector(curve.p2), p3: vector(curve.p3),
                    color: SIMD4(color, 1), width: width, dashed: dashed, pulses: pulses, seed: seed(arrow.id), level: level,
                    pad0: 0, pad1: 0, pad2: 0))
                scene.markers.append(MCMarkerInstance(position: vector(curve.p3), direction: direction(curve.tangent(at: 1)),
                                                      color: SIMD4(color, 1), size: 4 + width, shape: Float(MC_MARKER_HEAD),
                                                      level: level, pad: 0))
                if arrow.conditional {
                    scene.markers.append(MCMarkerInstance(position: vector(curve.point(at: 0.06)), direction: direction(curve.tangent(at: 0.06)),
                                                          color: SIMD4(color, 1), size: 5, shape: Float(MC_MARKER_DIAMOND),
                                                          level: level, pad: 0))
                }
            }
            return scene
        }

        private static func vector(_ p: CGPoint) -> SIMD2<Float> { SIMD2(Float(p.x), Float(p.y)) }

        private static func direction(_ v: CGVector) -> SIMD2<Float> {
            let length = hypot(v.dx, v.dy)
            return length > 1e-6 ? SIMD2(Float(v.dx / length), Float(v.dy / length)) : SIMD2(1, 0)
        }

        private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

        /// A stable [0, 1) value per id (FNV-1a), so pulses keep their rhythm across rebuilds.
        static func seed(_ id: String) -> Float {
            var hash: UInt32 = 2_166_136_261
            for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
            return Float(hash % 10_000) / 10_000
        }
    }
}
