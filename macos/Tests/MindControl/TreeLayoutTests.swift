#if os(macOS)
import Foundation
import Testing
import simd
@testable import Ghostty

private typealias TreeLayout = MindControl.TreeLayout
private typealias FileTree = MindControl.FileTree

struct TreeLayoutTests {
    private func tree(_ files: [String]) -> FileTree {
        FileTree(rootName: "proj", rootPath: "/tmp/proj", files: files.sorted(), totalFileCount: files.count)
    }

    private let sample = [
        "README.md", "Package.swift", "docs/guide.MD", "docs/notes.txt",
        "src/app/main.swift", "src/app/view.swift", "src/core/model.swift", "src/core/store.swift",
        "src/core/net/client.swift", "tests/model_tests.swift", "assets/logo.pdf",
    ]

    @Test func createsFolderNodes() {
        let graph = TreeLayout.graph(for: tree(["a/b/c.swift"]))
        #expect(Set(graph.nodes.map(\.id)) == [TreeLayout.rootID, "a", "a/b", "a/b/c.swift"])
        #expect(graph.nodes.first { $0.id == "a/b" }?.label == "b")
    }

    @Test func kindsByExtension() {
        let graph = TreeLayout.graph(for: tree(sample))
        let kind = { (id: String) in graph.nodes.first { $0.id == id }?.kind }
        #expect(kind(TreeLayout.rootID) == .root)
        #expect(kind("src") == .folder)
        #expect(kind("README.md") == .document)
        #expect(kind("docs/guide.MD") == .document)
        #expect(kind("assets/logo.pdf") == .document)
        #expect(kind("src/app/main.swift") == .source)
    }

    @Test func oneParentEdgePerNode() {
        let graph = TreeLayout.graph(for: tree(sample))
        #expect(graph.edges.count == graph.nodes.count - 1)
        let targets = graph.edges.map(\.to)
        #expect(Set(targets).count == targets.count)
        #expect(!targets.contains(TreeLayout.rootID))
        #expect(graph.edges.contains { $0.from == "src/core" && $0.to == "src/core/net" })
    }

    @Test func emptyTreeIsJustTheRoot() {
        let graph = TreeLayout.graph(for: tree([]))
        #expect(graph.nodes.map(\.id) == [TreeLayout.rootID])
        #expect(graph.edges.isEmpty)
    }

    @Test func isDeterministic() {
        let a = TreeLayout.graph(for: tree(sample))
        let b = TreeLayout.graph(for: tree(sample))
        #expect(a.nodes.map(\.id) == b.nodes.map(\.id))
        #expect(a.nodes.map(\.position) == b.nodes.map(\.position))
    }

    @Test func positionsAreFiniteAndDistinct() {
        let files = (0..<300).map { "m\($0 % 6)/s\($0 % 4)/f\($0).swift" }
        let graph = TreeLayout.graph(for: tree(files))
        let positions = graph.nodes.map(\.position)
        #expect(positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        var closest = Float.infinity
        for i in positions.indices {
            for j in positions.indices where j > i {
                closest = min(closest, simd_distance(positions[i], positions[j]))
            }
        }
        #expect(closest > 1e-3)
    }

    @Test func rootIsAtOrigin() {
        let graph = TreeLayout.graph(for: tree(sample))
        #expect(graph.nodes.first { $0.id == TreeLayout.rootID }?.position == .zero)
    }

    @Test func tenThousandFilesLayOutQuickly() {
        let files = (0..<10_000).map { "d\($0 % 50)/e\($0 % 7)/f\($0).swift" }
        let input = tree(files)
        let clock = ContinuousClock()
        var graph: MindControl.Graph?
        let elapsed = clock.measure { graph = TreeLayout.graph(for: input) }
        let expectedNodes: Int = 10_000 + 50 + 350 + 1   // files + top folders + nested folders + root
        #expect(graph?.nodes.count == expectedNodes)
        #expect(elapsed < .milliseconds(200))
    }

    @Test func crowdedFilesAreDimmed() {
        let crowded = (0..<1_000).map { "big/f\($0).txt" }
        let graph = TreeLayout.graph(for: tree(crowded + ["small/a.swift", "small/b.swift"]))
        let weight = { (id: String) in graph.nodes.first { $0.id == id }?.weight }
        #expect(weight("small/a.swift") == 1)
        #expect(weight("big") == 1)                       // folders stay bright landmarks
        #expect((weight("big/f0.txt") ?? 1) < 0.3)
        #expect((weight("big/f0.txt") ?? 0) >= TreeLayout.minimumFileWeight)
    }
}
#endif
