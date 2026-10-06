#if os(macOS)
import CoreGraphics
import Testing
import simd
@testable import Ghostty

private typealias Picking = MindControl.Picking
private typealias CameraSnapshot = MindControl.CameraSnapshot

struct PickingTests {
    /// Identity transform: world x/y in [-1, 1] map straight onto a 200 × 100 pt view.
    private let flat = CameraSnapshot(viewProjection: matrix_identity_float4x4, viewportPoints: SIMD2(200, 100), projScaleY: 1)

    private var perspective: CameraSnapshot {
        let projection = MindControl.Matrix.perspective(fovY: 1, aspect: 2, near: 0.1, far: 100)
        let view = MindControl.Matrix.lookAt(eye: SIMD3(0, 0, 10), target: .zero, up: SIMD3(0, 1, 0))
        return CameraSnapshot(viewProjection: projection * view, viewportPoints: SIMD2(200, 100), projScaleY: projection.columns.1.y)
    }

    @Test func projectsToBottomLeftOriginPoints() {
        let nodes = Picking.project(positions: [SIMD3(0, 0, 0.5), SIMD3(-1, -1, 0.5), SIMD3(1, 1, 0.5)],
                                    radii: [0.1, 0.1, 0.1], camera: flat)
        #expect(nodes.map(\.point) == [CGPoint(x: 100, y: 50), CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 100)])
        #expect(nodes[0].radius == 5)                         // 0.1 × 1 / 1 × 100 / 2
    }

    @Test func tinyNodesKeepAMinimumRadius() {
        let nodes = Picking.project(positions: [.zero], radii: [0.0001], camera: flat)
        #expect(nodes[0].radius == Picking.minimumCorePoints)
    }

    @Test func nearestWithinHitRadius() {
        let nodes = Picking.project(positions: [SIMD3(0, 0, 0.5), SIMD3(0.5, 0, 0.5)], radii: [0.01, 0.01], camera: flat)
        #expect(Picking.nearest(to: CGPoint(x: 103, y: 52), in: nodes) == 0)
        #expect(Picking.nearest(to: CGPoint(x: 148, y: 50), in: nodes) == 1)
        #expect(Picking.nearest(to: CGPoint(x: 125, y: 50), in: nodes) == nil)   // 25 pt from both
    }

    @Test func nearerNodeWinsWhenOverlapping() {
        let nodes = Picking.project(positions: [SIMD3(0, 0, -5), SIMD3(0, 0, 0)], radii: [0.2, 0.2], camera: perspective)
        #expect(Picking.nearest(to: CGPoint(x: 100, y: 50), in: nodes) == 1)
    }

    @Test func nodesBehindTheCameraAreSkipped() {
        let nodes = Picking.project(positions: [SIMD3(0, 0, 20), .zero], radii: [0.2, 0.2], camera: perspective)
        #expect(nodes.map(\.index) == [1])
    }
}
#endif
