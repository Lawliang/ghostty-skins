#if os(macOS)
import Testing
import Metal
import QuartzCore
import CoreGraphics
@testable import Ghostty

private typealias Renderer = MindControl.Renderer
private typealias FlowScene = MindControl.FlowScene
private typealias PanZoomCamera = MindControl.PanZoomCamera

private let zoneToSystems = MindControl.ZoomLevels.zoneToSystems
private let systemsToParts = MindControl.ZoomLevels.systemsToParts

/// (MC_LEVEL_*, zoom, drawn at full strength rather than not at all), just outside each `ZoomLevels` range.
private let levelCases: [(Int32, CGFloat, Bool)] = [
    (MC_LEVEL_ZONE, zoneToSystems.lowerBound - 0.01, true), (MC_LEVEL_ZONE, zoneToSystems.upperBound + 0.01, false),
    (MC_LEVEL_SYSTEM, zoneToSystems.lowerBound - 0.01, false), (MC_LEVEL_SYSTEM, zoneToSystems.upperBound + 0.01, true),
    (MC_LEVEL_SYSTEM, systemsToParts.lowerBound - 0.01, true), (MC_LEVEL_SYSTEM, systemsToParts.upperBound + 0.01, false),
    (MC_LEVEL_PART, systemsToParts.lowerBound - 0.01, false), (MC_LEVEL_PART, systemsToParts.upperBound + 0.01, true),
    (MC_LEVEL_ALWAYS, PanZoomCamera.minZoom, true), (MC_LEVEL_ALWAYS, PanZoomCamera.maxZoom, true),
]

@MainActor
struct RendererTests {
    /// Renders one frame offscreen and returns its BGRA bytes.
    fileprivate static func renderPixels(using renderer: Renderer, width: Int = 96, height: Int = 64, pixelScale: Float = 1) throws -> [UInt8] {
        let device = renderer.device
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        let texture = try #require(device.makeTexture(descriptor: desc))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        let queue = try #require(device.makeCommandQueue())
        let cmd = try #require(queue.makeCommandBuffer())
        renderer.encodeFrame(into: cmd, output: pass, width: width, height: height, pixelScale: pixelScale, time: 1.5)
        let blit = try #require(cmd.makeBlitCommandEncoder())
        blit.synchronize(resource: texture)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        #expect(cmd.error == nil)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    /// Renders one frame offscreen and returns the average channel value, 0...1.
    fileprivate static func renderAverage(using renderer: Renderer, width: Int = 96, height: Int = 64) throws -> Double {
        let bytes = try renderPixels(using: renderer, width: width, height: height)
        return Double(bytes.reduce(0) { $0 + Int($1) }) / Double(bytes.count) / 255
    }

    /// The largest colour-channel difference between two renders at one pixel, in 8-bit levels.
    fileprivate static func difference(_ a: [UInt8], _ b: [UInt8], width: Int, x: Int, y: Int) -> Int {
        let i = (y * width + x) * 4
        return (0..<3).map { abs(Int(a[i + $0]) - Int(b[i + $0])) }.max() ?? 0
    }

    fileprivate static func box(_ rect: CGRect, fill: Float = 0, stroke: Float = 0, glow: Float = 0,
                                level: Int32 = MC_LEVEL_ALWAYS) -> MCBoxInstance {
        MCBoxInstance(origin: SIMD2(Float(rect.minX), Float(rect.minY)), size: SIMD2(Float(rect.width), Float(rect.height)),
                      fill: SIMD4(fill, fill, fill, 1), stroke: SIMD4(stroke, stroke, stroke, 1),
                      radius: 4, glow: glow, dashed: 0, level: Float(level))
    }

    fileprivate static func renderer(showing scene: FlowScene, camera: PanZoomCamera) throws -> Renderer {
        let renderer = try Renderer()
        renderer.setScene(scene)
        renderer.camera = camera
        return renderer
    }

    @Test func createsRenderer() throws {
        _ = try Renderer()
    }

    @Test func rendersBackground() throws {
        let average = try Self.renderAverage(using: try Renderer())
        #expect(average > 0)
        #expect(average < 0.4)
    }

    @Test func rendersOnePixelTarget() throws {
        _ = try Self.renderAverage(using: try Renderer(), width: 1, height: 1)
    }

    @Test func drawsTheArcaMap() throws {
        let renderer = try Renderer()
        let background = try Self.renderAverage(using: renderer)
        let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        renderer.setScene(MindControl.FlowScene.build(layout: layout, curves: MindControl.ArrowRouter.curves(for: layout),
                                                      report: .init(), style: .init()))
        renderer.camera = MindControl.PanZoomCamera.fitting(layout.bounds, in: CGSize(width: 96, height: 64), margin: 4)
        let drawn = try Self.renderAverage(using: renderer)
        #expect(drawn > background)
    }

    @Test func cameraAnimationReachesItsTarget() throws {
        let renderer = try Renderer()
        let target = MindControl.PanZoomCamera(center: CGPoint(x: 100, y: 50), zoom: 2)
        renderer.animateCamera(to: target, duration: 0.2)
        #expect(renderer.isAnimatingCamera)
        renderer.advanceCamera(to: CACurrentMediaTime() + 1)
        #expect(renderer.camera == target)
        #expect(!renderer.isAnimatingCamera)
    }

    @Test(arguments: [0, -1, CFTimeInterval.nan])
    func cameraAnimationWithNoLengthJumpsToItsTarget(duration: CFTimeInterval) throws {
        // Otherwise a negative or NaN duration never finishes and pins the camera to where it started.
        let renderer = try Renderer()
        let target = MindControl.PanZoomCamera(center: CGPoint(x: -20, y: 70), zoom: 0.5)
        renderer.animateCamera(to: target, duration: duration)
        renderer.advanceCamera(to: CACurrentMediaTime() + 1)
        #expect(renderer.camera == target)
        #expect(!renderer.isAnimatingCamera)
    }

    @Test(arguments: [Float(1), 2])
    func boxesLandWherePanZoomCameraPutsThem(pixelScale: Float) throws {
        // The shaders' world → pixel mapping is PanZoomCamera.toScreen × pixelScale, y down like the view.
        let view = CGSize(width: 96, height: 64)
        let width = Int(Float(view.width) * pixelScale), height = Int(Float(view.height) * pixelScale)
        let camera = PanZoomCamera(center: CGPoint(x: 300, y: 200), zoom: 0.5)
        let rect = CGRect(x: 220, y: 150, width: 40, height: 24)   // above and left of the centre
        var scene = FlowScene()
        scene.boxes = [Self.box(rect, fill: 0.4)]
        let drawn = try Self.renderPixels(using: try Self.renderer(showing: scene, camera: camera),
                                          width: width, height: height, pixelScale: pixelScale)
        let background = try Self.renderPixels(using: try Renderer(), width: width, height: height, pixelScale: pixelScale)
        func difference(at p: CGPoint) -> Int {
            Self.difference(drawn, background, width: width, x: Int(p.x * CGFloat(pixelScale)), y: Int(p.y * CGFloat(pixelScale)))
        }
        let centre = camera.toScreen(CGPoint(x: rect.midX, y: rect.midY), viewSize: view)
        let corner = camera.toScreen(rect.origin, viewSize: view)
        #expect(difference(at: centre) > 40)
        #expect(difference(at: CGPoint(x: corner.x + 2, y: corner.y + 2)) > 40)
        #expect(difference(at: CGPoint(x: corner.x - 2, y: corner.y + 2)) <= 1)
        #expect(difference(at: CGPoint(x: corner.x + 2, y: corner.y - 2)) <= 1)
        #expect(difference(at: CGPoint(x: centre.x, y: view.height - centre.y)) <= 1, "drawn upside down")
        #expect(difference(at: CGPoint(x: view.width - centre.x, y: centre.y)) <= 1, "drawn mirrored")
    }

    @Test(arguments: levelCases)
    func levelsShowAndHideAtTheZoomLevelsThresholds(level: Int32, zoom: CGFloat, visible: Bool) throws {
        // levelWeight in ShaderCommon.h must fade across exactly the ZoomLevels ranges.
        let camera = PanZoomCamera(center: .zero, zoom: zoom)
        let rect = CGRect(x: -50, y: -30, width: 100, height: 60)
        var scene = FlowScene()
        scene.boxes = [Self.box(rect, fill: 0.4, level: level)]
        let drawn = try Self.renderPixels(using: try Self.renderer(showing: scene, camera: camera))
        scene.boxes = [Self.box(rect, fill: visible ? 0.4 : 0, level: MC_LEVEL_ALWAYS)]
        let expected = try Self.renderPixels(using: try Self.renderer(showing: scene, camera: camera))
        #expect(Self.difference(drawn, expected, width: 96, x: 48, y: 32) <= 1)
    }

    @Test func focusViewsShowEveryLevelAtAnyZoom() throws {
        let rect = CGRect(x: -50, y: -30, width: 100, height: 60)
        var scene = FlowScene()
        scene.boxes = [Self.box(rect, fill: 0.4, level: MC_LEVEL_PART)]
        scene.fixedLevel = true
        let camera = PanZoomCamera(center: .zero, zoom: 0.1)
        let drawn = try Self.renderPixels(using: try Self.renderer(showing: scene, camera: camera))
        let background = try Self.renderPixels(using: try Renderer())
        #expect(Self.difference(drawn, background, width: 96, x: 48, y: 32) > 40)
    }

    @Test(arguments: [(Float(1), Float(0)), (0, 1), (-1, 0), (0, -1)])
    func arrowheadsPointAlongTheirArrow(dx: Float, dy: Float) throws {
        // The tip sits on the marker's position and the head trails back against its direction (y down).
        var scene = FlowScene()
        scene.markers = [MCMarkerInstance(position: SIMD2(0, 0), direction: SIMD2(dx, dy), color: SIMD4(0.3, 0.3, 0.3, 1),
                                          size: 10, shape: Float(MC_MARKER_HEAD), level: Float(MC_LEVEL_ALWAYS), pad: 0)]
        let drawn = try Self.renderPixels(using: try Self.renderer(showing: scene, camera: PanZoomCamera(center: .zero, zoom: 1)))
        let background = try Self.renderPixels(using: try Renderer())
        let behind = (x: 48 - Int(dx * 7), y: 32 - Int(dy * 7))
        let ahead = (x: 48 + Int(dx * 7), y: 32 + Int(dy * 7))
        #expect(Self.difference(drawn, background, width: 96, x: behind.x, y: behind.y) > 20)
        #expect(Self.difference(drawn, background, width: 96, x: ahead.x, y: ahead.y) <= 1)
    }

    @Test func boxGlowFadesIntoTheBackground() throws {
        // Walking in from the left edge, the first pixel the glow reaches differs from the background by only a
        // little: the glow has died out before the edge of the quad it is drawn on, so no halo has a hard rim.
        // Kept under the bloom threshold so only the glow itself is measured.
        var scene = FlowScene()
        scene.boxes = [Self.box(CGRect(x: -10, y: -10, width: 20, height: 20), stroke: 0.3, glow: 2.5)]
        let drawn = try Self.renderPixels(using: try Self.renderer(showing: scene, camera: PanZoomCamera(center: .zero, zoom: 1)))
        let background = try Self.renderPixels(using: try Renderer())
        let first = try #require((0..<48).first { Self.difference(drawn, background, width: 96, x: $0, y: 32) >= 2 })
        #expect(first > 10)
        #expect(Self.difference(drawn, background, width: 96, x: first, y: 32) <= 6)
    }

    @Test func arrowGlowFadesIntoTheBackground() throws {
        // The same for an arrow's glow and the edge of its strip. Rendered at 4× so the few points of glow span
        // enough pixels to show their profile; kept under the bloom threshold, and with no pulses.
        let scale = 4, width = 96 * 4, height = 64 * 4
        var scene = FlowScene()
        scene.arrows = [MCArrowInstance(p0: SIMD2(-40, 0), p1: SIMD2(-15, 0), p2: SIMD2(15, 0), p3: SIMD2(40, 0),
                                        color: SIMD4(0.35, 0.35, 0.35, 1), width: 1.6, dashed: 0, pulses: 0, seed: 0,
                                        level: Float(MC_LEVEL_ALWAYS), pad0: 0, pad1: 0, pad2: 0)]
        let camera = PanZoomCamera(center: .zero, zoom: 1)
        let drawn = try Self.renderPixels(using: try Self.renderer(showing: scene, camera: camera),
                                          width: width, height: height, pixelScale: Float(scale))
        let background = try Self.renderPixels(using: try Renderer(), width: width, height: height, pixelScale: Float(scale))
        // Walk down the middle column towards the arrow, which runs along view y = 32 pt.
        let column = width / 2, line = height / 2
        let first = try #require((0..<line).first { Self.difference(drawn, background, width: width, x: column, y: $0) >= 2 })
        #expect(first > line - 6 * scale, "the first lit pixel belongs to the arrow")
        #expect(Self.difference(drawn, background, width: width, x: column, y: first) <= 8)
    }
}
#endif
