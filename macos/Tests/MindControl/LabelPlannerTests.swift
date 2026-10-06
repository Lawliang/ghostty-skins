#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias LabelPlanner = MindControl.LabelPlanner
private typealias ScreenNode = MindControl.ScreenNode
private typealias GraphNode = MindControl.GraphNode

struct LabelPlannerTests {
    private let measure: (String, CGFloat, Bool) -> CGSize = { text, size, _ in
        CGSize(width: CGFloat(text.count) * size * 0.6, height: size * 1.3)
    }

    private func folder(_ id: String, files: Int = 10) -> GraphNode {
        GraphNode(id: id, label: id.split(separator: "/").last.map(String.init) ?? id, kind: .folder,
                  position: .zero, descendantFiles: files)
    }

    private func file(_ id: String) -> GraphNode {
        GraphNode(id: id, label: id.split(separator: "/").last.map(String.init) ?? id, kind: .source, position: .zero)
    }

    private func screen(_ index: Int, _ x: CGFloat, _ y: CGFloat, radius: CGFloat = 4) -> ScreenNode {
        ScreenNode(index: index, point: CGPoint(x: x, y: y), radius: radius, depth: 1)
    }

    private func plan(_ nodes: [GraphNode], _ screen: [ScreenNode], focus: Int? = nil, neighbours: Set<Int> = [],
                      viewport: CGSize = CGSize(width: 800, height: 600)) -> [MindControl.PlacedLabel] {
        LabelPlanner.plan(.init(screen: screen, nodes: nodes, focus: focus, neighbours: neighbours,
                                viewport: viewport, measure: measure))
    }

    @Test func budgetIsRespected() {
        let nodes = (0..<400).map { folder("f\($0)") }
        let screen = (0..<400).map { self.screen($0, CGFloat($0 % 20) * 200, CGFloat($0 / 20) * 40) }
        #expect(plan(nodes, screen, viewport: CGSize(width: 4_000, height: 4_000)).count == LabelPlanner.budget)
    }

    @Test func labelsNeverOverlap() {
        var rng = MindControl.SplitMix64(seed: 3)
        let nodes = (0..<300).map { folder("folder\($0)") }
        let screen = (0..<300).map { self.screen($0, CGFloat.random(in: 0...800, using: &rng), CGFloat.random(in: 0...600, using: &rng)) }
        let labels = plan(nodes, screen)
        #expect(!labels.isEmpty)
        for i in labels.indices {
            for j in labels.indices where j > i {
                #expect(!labels[i].frame.intersects(labels[j].frame))
            }
        }
    }

    @Test func farFilesHiddenCloseFilesShown() {
        let nodes = [file("a/far.swift"), file("a/near.swift")]
        let labels = plan(nodes, [screen(0, 100, 100, radius: 1.4), screen(1, 300, 300, radius: 6)])
        #expect(labels.map(\.text) == ["near.swift"])
        #expect(labels.first?.opacity == 0.85)
        #expect(labels.first?.isBold == false)
    }

    @Test func foldersBeatFilesAndBiggerFoldersWin() {
        let nodes = [file("x/a.swift"), folder("small", files: 2), folder("big", files: 500)]
        // All three at the same spot: only the first placed label fits.
        let labels = plan(nodes, [screen(0, 100, 100, radius: 6), screen(1, 100, 100), screen(2, 100, 100)])
        #expect(labels.map(\.text) == ["big"])
        #expect(labels.first?.isBold == true)
    }

    @Test func focusAndNeighboursAlwaysShownAndFocusShowsItsPath() {
        let nodes = [folder("crowd", files: 900), file("src/deep/focus.swift"), file("src/other.swift")]
        let labels = plan(nodes, [screen(0, 100, 100), screen(1, 100, 100, radius: 1.4), screen(2, 400, 100, radius: 1.4)],
                          focus: 1, neighbours: [2])
        #expect(labels.map(\.text) == ["src/deep/focus.swift", "other.swift"])
        #expect(labels.allSatisfy { $0.opacity >= 0.9 })
    }

    @Test func othersDimWhileSomethingIsFocused() {
        let nodes = [folder("a"), folder("b")]
        let labels = plan(nodes, [screen(0, 100, 100), screen(1, 100, 400)], focus: 0)
        let b = labels.first { $0.text == "b" }
        #expect(abs((b?.opacity ?? 0) - 0.9 * 0.35) < 1e-6)
    }

    @Test func offscreenLabelsAreSkipped() {
        let labels = plan([folder("gone")], [screen(0, -500, 100)])
        #expect(labels.isEmpty)
    }

    @Test func labelSitsRightOfItsNode() {
        let labels = plan([folder("src")], [screen(0, 100, 100, radius: 4)])
        #expect(labels.first?.frame.minX == 100 + 4 + LabelPlanner.gap)
        #expect(abs((labels.first?.frame.midY ?? 0) - 100) < 1e-9)
    }
}
#endif
