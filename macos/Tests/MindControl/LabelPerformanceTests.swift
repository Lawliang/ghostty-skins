#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

/// Labels are re-planned every frame on the main thread, so planning a big project must stay cheap.
@MainActor
struct LabelPerformanceTests {
    @Test func planningABigProjectFitsInAFrame() {
        var nodes: [MindControl.GraphNode] = []
        var screen: [MindControl.ScreenNode] = []
        var rng = MindControl.SplitMix64(seed: 4)
        for i in 0..<10_000 {
            let isFolder = i % 5 == 0
            nodes.append(MindControl.GraphNode(id: "dir\(i / 5)/item\(i)", label: "item\(i)", kind: isFolder ? .folder : .source,
                                               position: .zero, descendantFiles: isFolder ? 4 : 0))
            screen.append(MindControl.ScreenNode(index: i, point: CGPoint(x: CGFloat.random(in: 0...1600, using: &rng),
                                                                         y: CGFloat.random(in: 0...1000, using: &rng)),
                                                 radius: CGFloat.random(in: 1.4...4, using: &rng), depth: 1))
        }
        let input = MindControl.LabelPlanner.Input(screen: screen, nodes: nodes, focus: nil, neighbours: [],
                                                    viewport: CGSize(width: 1600, height: 1000),
                                                    measure: MindControl.LabelOverlayView.measure)
        _ = MindControl.LabelPlanner.plan(input)              // warm the size cache, as after the first frame
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = MindControl.LabelPlanner.plan(input) }
        #expect(elapsed < .milliseconds(8))                  // one 120 Hz frame
    }
}
#endif
