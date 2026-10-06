#if os(macOS)
import Testing
import simd
@testable import Ghostty

private typealias Graph = MindControl.Graph
private typealias GraphNode = MindControl.GraphNode
private typealias GraphEdge = MindControl.GraphEdge
private typealias NodeKind = MindControl.NodeKind
private typealias GraphBuffers = MindControl.GraphBuffers
private typealias NodeStyle = MindControl.NodeStyle
private typealias OrbitCamera = MindControl.OrbitCamera
private typealias Renderer = MindControl.Renderer
private typealias BloomPass = MindControl.BloomPass

struct OrbitCameraTests {
    @Test func pitchIsClamped() {
        var cam = OrbitCamera()
        cam.beginDrag()
        cam.drag(dx: 0, dy: 100_000)
        #expect(cam.pitch == OrbitCamera.pitchLimit)
        cam.drag(dx: 0, dy: -100_000)
        #expect(cam.pitch == -OrbitCamera.pitchLimit)
    }

    @Test func zoomIsClamped() {
        var cam = OrbitCamera()
        cam.frame(center: .zero, radius: 10)
        cam.zoom(by: 1e6)
        #expect(cam.distance == cam.maxDistance)
        cam.zoom(by: 1e-6)
        #expect(cam.distance == cam.minDistance)
    }

    @Test func rejectsBadZoom() {
        var cam = OrbitCamera()
        let before = cam.distance
        cam.zoom(by: 0)
        cam.zoom(by: -2)
        cam.zoom(by: .nan)
        cam.zoom(by: .infinity)
        #expect(cam.distance == before)
    }

    @Test func ignoresNonFiniteDrag() {
        var cam = OrbitCamera()
        cam.beginDrag()
        cam.drag(dx: .nan, dy: .infinity)
        #expect(cam.yaw.isFinite && cam.pitch.isFinite)
    }

    @Test func inertiaDecaysToZero() {
        var cam = OrbitCamera()
        cam.beginDrag()
        cam.drag(dx: 20, dy: 5)
        cam.endDrag()
        #expect(cam.yawVelocity != 0)
        for _ in 0..<120 { cam.update(dt: 1.0 / 60) }   // 2 s, under the idle delay
        #expect(cam.yawVelocity == 0)
        #expect(cam.pitchVelocity == 0)
    }

    @Test func noFlingAfterHoldingStill() {
        var cam = OrbitCamera()
        cam.beginDrag()
        cam.drag(dx: 30, dy: 0)
        for _ in 0..<30 { cam.update(dt: 1.0 / 60) }    // held still for 0.5 s
        cam.endDrag()
        #expect(abs(cam.yawVelocity) < 0.01)
    }

    @Test func driftsOnlyAfterIdleDelay() {
        var cam = OrbitCamera()
        let start = cam.yaw
        cam.update(dt: 1)
        cam.update(dt: 1)
        #expect(cam.yaw == start)
        cam.update(dt: 2)                                // idle 4 s > 3 s
        #expect(cam.yaw > start)
    }

    @Test func inputResetsIdle() {
        var cam = OrbitCamera()
        cam.update(dt: 5)
        cam.zoom(by: 0.9)
        #expect(cam.idleTime == 0)
    }

    @Test func framesDegenerateGraph() {
        var cam = OrbitCamera()
        cam.frame(center: SIMD3(3, 3, 3), radius: 0)
        #expect(cam.target == SIMD3(3, 3, 3))
        #expect(cam.distance.isFinite && cam.distance > cam.minDistance)
        #expect(cam.minDistance > 0)
        #expect(cam.maxDistance > cam.distance)
    }

    @Test func framedGraphFitsInView() {
        var cam = OrbitCamera()
        cam.frame(center: .zero, radius: 10)
        let half = OrbitCamera.fieldOfView / 2
        #expect(cam.distance * sin(half) >= 10)
    }

    @Test func viewMatrixPutsTargetInFront() {
        var cam = OrbitCamera()
        cam.frame(center: SIMD3(1, 2, 3), radius: 5)
        let v = cam.viewMatrix * SIMD4(cam.target, 1)
        #expect(abs(v.x) < 1e-3 && abs(v.y) < 1e-3)
        #expect(abs(v.z + cam.distance) < 1e-3)
    }

    @Test func projectionMapsTargetIntoDepthRange() {
        var cam = OrbitCamera()
        cam.frame(center: .zero, radius: 5)
        let clip = cam.projectionMatrix(aspect: 16.0 / 10.0) * cam.viewMatrix * SIMD4(cam.target, 1)
        let ndcZ = clip.z / clip.w
        #expect(clip.w > 0)
        #expect(ndcZ > 0 && ndcZ < 1)
    }
}
#endif
