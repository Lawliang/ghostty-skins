#if os(macOS)
import Testing
@testable import Ghostty

private typealias FlowScene = MindControl.FlowScene
private typealias SceneStyle = MindControl.SceneStyle

struct FlowSceneTests {
    private let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
    private var curves: [String: MindControl.Curve] { MindControl.ArrowRouter.curves(for: layout) }

    private func build(_ style: SceneStyle = SceneStyle(), report: MindControl.HealthReport = .init()) -> FlowScene {
        FlowScene.build(layout: layout, curves: curves, report: report, style: style)
    }

    private func brightness(_ v: SIMD4<Float>) -> Float { v.x + v.y + v.z }

    @Test func gpuStructsHaveTheExpectedSizes() {
        #expect(MemoryLayout<MCBoxInstance>.stride == 64)
        #expect(MemoryLayout<MCArrowInstance>.stride == 80)
        #expect(MemoryLayout<MCMarkerInstance>.stride == 48)
        #expect(MemoryLayout<MCFrameUniforms>.stride == 32)
    }

    @Test func oneInstancePerBoxAndArrow() {
        let scene = build()
        #expect(scene.boxes.count == layout.boxes.count)
        #expect(scene.arrows.count == layout.arrows.count)
        let heads = scene.markers.filter { $0.shape == Float(MC_MARKER_HEAD) }.count
        let diamonds = scene.markers.filter { $0.shape == Float(MC_MARKER_DIAMOND) }.count
        #expect(heads == layout.arrows.count)
        #expect(diamonds == layout.arrows.filter(\.conditional).count)
    }

    @Test func hidingControlDropsControlArrows() {
        var style = SceneStyle()
        style.showControl = false
        #expect(build(style).arrows.count == layout.arrows.filter { $0.kind == .data }.count)
    }

    @Test func onlyDataArrowsPulseInMapView() {
        let scene = build()
        for (instance, spec) in zip(scene.arrows, layout.arrows) {
            #expect((instance.pulses > 0) == (spec.kind == .data), "\(spec.id)")
            #expect((instance.dashed > 0) == (spec.kind == .control), "\(spec.id)")
        }
    }

    @Test func selectedFeatureLightsItsRouteAndDimsTheRest() throws {
        var style = SceneStyle()
        style.litFlows = ["pcm"]
        style.featureColor = MindControl.Palette.feature(1)
        let scene = build(style)
        let lit = try #require(layout.arrows.firstIndex { $0.id == "flow:pcm" })
        let unlit = try #require(layout.arrows.firstIndex { $0.id == "flow:send" })
        #expect(brightness(scene.arrows[lit].color) > 4 * brightness(scene.arrows[unlit].color))
        let ble = try #require(layout.boxes.firstIndex { $0.id == "ble" })
        let audio = try #require(layout.boxes.firstIndex { $0.id == "audio" })
        #expect(brightness(scene.boxes[audio].stroke) > brightness(scene.boxes[ble].stroke))
    }

    @Test func healthViewColoursOnlyProblems() throws {
        var report = MindControl.HealthReport()
        report.staleParts = ["audio.gate"]
        report.staleFlows = ["send"]
        report.unverifiedFlows = ["press"]
        var style = SceneStyle()
        style.mode = .health
        let scene = build(style, report: report)
        let gate = try #require(layout.boxes.firstIndex { $0.id == "audio.gate" })
        let capture = try #require(layout.boxes.firstIndex { $0.id == "audio.capture" })
        #expect(scene.boxes[gate].stroke.x > scene.boxes[gate].stroke.z * 3)
        #expect(scene.boxes[capture].stroke.x < scene.boxes[capture].stroke.z * 1.5)
        let send = try #require(layout.arrows.firstIndex { $0.id == "flow:send" })
        let press = try #require(layout.arrows.firstIndex { $0.id == "flow:press" })
        #expect(scene.arrows[send].color.x > scene.arrows[send].color.z * 3)
        #expect(scene.arrows[press].dashed > 0)
        #expect(scene.arrows.allSatisfy { $0.pulses == 0 })
    }

    @Test func healthViewDrawsUnverifiedFlowsAsFaintDashesOfEitherKind() throws {
        var report = MindControl.HealthReport()
        report.unverifiedFlows = ["pcm", "press"]
        report.staleFlows = ["event", "reply"]
        var style = SceneStyle()
        style.mode = .health
        let scene = build(style, report: report)
        func arrow(_ id: String) throws -> MCArrowInstance {
            scene.arrows[try #require(layout.arrows.firstIndex { $0.id == "flow:\(id)" })]
        }
        // Healthy references of each kind: send (data), begin (control).
        let pcm = try arrow("pcm"), press = try arrow("press"), send = try arrow("send"), begin = try arrow("begin")
        #expect(pcm.dashed > 0, "an unverified data flow is dashed")
        #expect(brightness(pcm.color) < 0.5 * brightness(send.color), "an unverified data flow is fainter than a healthy one")
        #expect(press.dashed > 0)
        #expect(brightness(press.color) < 0.5 * brightness(begin.color), "an unverified control flow is fainter than a healthy one")
        // Stale flows are amber and keep their kind's line: control dashed, data solid.
        let event = try arrow("event"), reply = try arrow("reply")
        #expect(event.color.x > event.color.z * 3 && event.dashed > 0)
        #expect(reply.color.x > reply.color.z * 3 && reply.dashed == 0)
    }

    @Test func healthViewStillDimsArrowsOffTheSelectedFeature() throws {
        // The feature chip dims the rest in either view; Health keeps its own colours on the route.
        var report = MindControl.HealthReport()
        report.staleFlows = ["send"]
        var style = SceneStyle()
        style.mode = .health
        style.litFlows = ["pcm"]
        style.featureColor = MindControl.Palette.feature(1)
        let scene = build(style, report: report)
        let lit = try #require(layout.arrows.firstIndex { $0.id == "flow:pcm" })
        let unlit = try #require(layout.arrows.firstIndex { $0.id == "flow:send" })
        #expect(brightness(scene.arrows[lit].color) > 4 * brightness(scene.arrows[unlit].color))
        #expect(scene.arrows[unlit].color.x > scene.arrows[unlit].color.z * 3, "a stale arrow off the route stays amber, only dimmer")
        #expect(scene.arrows[lit].color.x < scene.arrows[lit].color.z * 1.5, "the route keeps Health's grey, not the feature colour")
    }

    @Test func partsAndArrowsCarryTheirZoomLevel() throws {
        let scene = build()
        let part = try #require(layout.boxes.firstIndex { $0.kind == .part })
        let zone = try #require(layout.boxes.firstIndex { $0.kind == .zone })
        #expect(scene.boxes[part].level == Float(MC_LEVEL_PART))
        #expect(scene.boxes[zone].level == Float(MC_LEVEL_ALWAYS))
        let zoneArrow = try #require(layout.arrows.firstIndex { $0.level == .zone })
        #expect(scene.arrows[zoneArrow].level == Float(MC_LEVEL_ZONE))
        #expect(!scene.fixedLevel)
    }
}
#endif
