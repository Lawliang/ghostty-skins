import CoreGraphics

extension MindControl {
    /// Zoom thresholds shared by labels, picking and the shaders (`levelWeight` in ShaderCommon.h).
    enum ZoomLevels {
        /// Zone arrows cross-fade to system arrows across this range; system names fade in.
        static let zoneToSystems: ClosedRange<CGFloat> = 0.22...0.34
        /// System arrows cross-fade to part arrows; part boxes fade in.
        static let systemsToParts: ClosedRange<CGFloat> = 0.85...1.15

        /// `systemFloor`: the layout has no zone arrows, so the system level reaches all the way out.
        static func arrowLevel(at zoom: CGFloat, systemFloor: Bool = false) -> MapLayout.ArrowLevel {
            zoom < 0.28 && !systemFloor ? .zone : zoom < 1.0 ? .system : .part
        }

        static func partsVisible(at zoom: CGFloat) -> Bool { zoom >= 1.0 }
    }

    enum LayoutMetrics {
        static let systemMinSize = CGSize(width: 220, height: 84)
        /// Room for a system's name and summary above its parts.
        static let header: CGFloat = 64
        static let pad: CGFloat = 20
        static let partSize = CGSize(width: 160, height: 40)
        static let partColumnGap: CGFloat = 40
        static let partRowGap: CGFloat = 14
        static let columnGap: CGFloat = 150
        static let rowGap: CGFloat = 50
        static let zonePad: CGFloat = 48
        static let zoneLabel: CGFloat = 56
        static let zoneGap: CGFloat = 140
        static let parallelSpacing: CGFloat = 14
    }

    /// Where everything sits, in world points (y down). Produced by FlowLayout or FocusLayout.
    struct MapLayout: Equatable {
        enum BoxKind: Equatable { case zone, system, part }

        struct Box: Equatable {
            let id: String
            let kind: BoxKind
            var rect: CGRect
            let title: String
            let subtitle: String?
            let external: Bool
            /// Zone palette index, or -1.
            let tint: Int
            let partCount: Int
        }

        enum ArrowLevel: Int, Equatable { case zone = 0, system = 1, part = 2 }

        struct ArrowSpec: Equatable {
            let id: String
            let level: ArrowLevel
            /// Box ids.
            let from: String
            let to: String
            let kind: FlowMap.Kind
            let flowIDs: [String]
            let label: String
            let conditional: Bool
            /// How many flows were merged into this arrow.
            let weight: Int
            /// Perpendicular push on the curve's middle, in world points. Negative bends up (y down);
            /// see `ArrowRouter.route`.
            var bend: CGFloat = 0
        }

        var boxes: [Box]
        var arrows: [ArrowSpec]
        /// True for focus layouts: every box and arrow shows at any zoom.
        var fixedLevel = false

        init(boxes: [Box], arrows: [ArrowSpec], fixedLevel: Bool = false) {
            self.boxes = boxes
            self.arrows = arrows
            self.fixedLevel = fixedLevel
        }

        func box(_ id: String) -> Box? { boxes.first { $0.id == id } }

        /// No zone arrows (no zones, or no flows between them): nothing stands in for the systems far out, so
        /// system names and arrows stay at the farthest zoom instead of leaving unnamed boxes and no arrows.
        var systemFloor: Bool { !arrows.contains { $0.level == .zone } }

        var bounds: CGRect { boxes.reduce(CGRect.null) { $0.union($1.rect) } }

        static func zoneBoxID(_ id: String) -> String { "zone:\(id)" }
    }
}
