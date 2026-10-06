import CoreGraphics
import simd

extension MindControl {
    /// The camera as of the last rendered frame, in view points.
    struct CameraSnapshot: Equatable {
        let viewProjection: simd_float4x4
        let viewportPoints: SIMD2<Float>
        /// projection[1][1]; converts a world radius at depth w into points.
        let projScaleY: Float
    }

    /// A node on screen, in view points with AppKit's bottom-left origin.
    struct ScreenNode: Equatable {
        let index: Int
        let point: CGPoint
        /// Projected core radius in points.
        let radius: CGFloat
        /// Clip-space w; smaller is nearer the camera.
        let depth: Float
    }

    /// Finds nodes under the pointer by projecting their centres on the CPU.
    enum Picking {
        static let minimumHitRadius: CGFloat = 8
        static let hitSlop: CGFloat = 3
        /// Matches `kMinCorePoints` in Nodes.metal.
        static let minimumCorePoints: CGFloat = 1.4

        static func project(positions: [SIMD3<Float>], radii: [Float], camera: CameraSnapshot) -> [ScreenNode] {
            let size = camera.viewportPoints
            var result: [ScreenNode] = []
            result.reserveCapacity(positions.count)
            for i in positions.indices {
                let clip = camera.viewProjection * SIMD4(positions[i], 1)
                guard clip.w > 0.01 else { continue }
                let ndc = SIMD2(clip.x, clip.y) / clip.w
                // A little past the edges, so labels can slide in as their node approaches.
                guard abs(ndc.x) <= 1.2, abs(ndc.y) <= 1.2 else { continue }
                let point = CGPoint(x: CGFloat((ndc.x * 0.5 + 0.5) * size.x), y: CGFloat((ndc.y * 0.5 + 0.5) * size.y))
                let radius = CGFloat(radii[i] * camera.projScaleY / clip.w * size.y * 0.5)
                result.append(ScreenNode(index: i, point: point, radius: max(minimumCorePoints, radius), depth: clip.w))
            }
            return result
        }

        /// The node nearest `point` within its hit radius; on a near-tie the one closer to the camera wins.
        static func nearest(to point: CGPoint, in nodes: [ScreenNode]) -> Int? {
            var best: ScreenNode?
            var bestDistance = CGFloat.infinity
            for node in nodes {
                let distance = hypot(node.point.x - point.x, node.point.y - point.y)
                guard distance <= max(minimumHitRadius, node.radius + hitSlop) else { continue }
                let tie = abs(distance - bestDistance) <= 0.5
                if distance < bestDistance - 0.5 || (tie && node.depth < (best?.depth ?? .infinity)) {
                    best = node
                    bestDistance = min(bestDistance, distance)
                }
            }
            return best?.index
        }
    }
}
