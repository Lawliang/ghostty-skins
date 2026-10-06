#if os(macOS)
import Foundation
import Testing
import simd
@testable import Ghostty

private typealias ConeTreeLayout = MindControl.ConeTreeLayout
private typealias FileTree = MindControl.FileTree
private typealias Dependency = MindControl.Dependency

struct ConeTreeLayoutTests {
    private func tree(_ files: [String]) -> FileTree {
        FileTree(rootName: "proj", rootPath: "/tmp/proj", files: files.sorted(), totalFileCount: files.count)
    }

    private let sample = [
        "README.md", "Package.swift", "docs/guide.MD", "docs/notes.txt",
        "src/app/main.swift", "src/app/view.swift", "src/core/model.swift", "src/core/store.swift",
        "src/core/net/client.swift", "tests/model_tests.swift", "assets/logo.pdf",
    ]

    @Test func createsFolderNodes() {
        let graph = ConeTreeLayout.graph(for: tree(["a/b/c.swift"]))
        #expect(Set(graph.nodes.map(\.id)) == [ConeTreeLayout.rootID, "a", "a/b", "a/b/c.swift"])
        #expect(graph.nodes.first { $0.id == "a/b" }?.label == "b")
    }

    @Test func kindsByExtension() {
        let graph = ConeTreeLayout.graph(for: tree(sample))
        let kind = { (id: String) in graph.nodes.first { $0.id == id }?.kind }
        #expect(kind(ConeTreeLayout.rootID) == .root)
        #expect(kind("src") == .folder)
        #expect(kind("README.md") == .document)
        #expect(kind("docs/guide.MD") == .document)
        #expect(kind("assets/logo.pdf") == .document)
        #expect(kind("src/app/main.swift") == .source)
    }

    @Test func oneContainsEdgePerNode() {
        let graph = ConeTreeLayout.graph(for: tree(sample))
        let contains = graph.edges.filter { $0.kind == .contains }
        #expect(contains.count == graph.nodes.count - 1)
        let targets = contains.map(\.to)
        #expect(Set(targets).count == targets.count)
        #expect(!targets.contains(ConeTreeLayout.rootID))
        #expect(contains.contains { $0.from == "src/core" && $0.to == "src/core/net" })
    }

    @Test func emptyTreeIsJustTheRoot() {
        let graph = ConeTreeLayout.graph(for: tree([]))
        #expect(graph.nodes.map(\.id) == [ConeTreeLayout.rootID])
        #expect(graph.edges.isEmpty)
    }

    @Test func isDeterministic() {
        let a = ConeTreeLayout.graph(for: tree(sample))
        let b = ConeTreeLayout.graph(for: tree(sample))
        #expect(a.nodes.map(\.id) == b.nodes.map(\.id))
        #expect(a.nodes.map(\.position) == b.nodes.map(\.position))
    }

    @Test func positionsAreFiniteAndDistinct() {
        let files = (0..<300).map { "m\($0 % 6)/s\($0 % 4)/f\($0).swift" }
        let positions = ConeTreeLayout.graph(for: tree(files)).nodes.map(\.position)
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
        let graph = ConeTreeLayout.graph(for: tree(sample))
        #expect(graph.nodes.first { $0.id == ConeTreeLayout.rootID }?.position == .zero)
    }

    @Test func tenThousandFilesLayOutQuickly() {
        let files = (0..<10_000).map { "d\($0 % 50)/e\($0 % 7)/f\($0).swift" }
        let input = tree(files)
        let clock = ContinuousClock()
        var graph: MindControl.Graph?
        let elapsed = clock.measure { graph = ConeTreeLayout.graph(for: input) }
        let expectedNodes: Int = 10_000 + 50 + 350 + 1   // files + top folders + nested folders + root
        #expect(graph?.nodes.count == expectedNodes)
        #expect(elapsed < .milliseconds(200))
    }

    @Test func crowdedFilesAreDimmed() {
        let crowded = (0..<1_000).map { "big/f\($0).txt" }
        let graph = ConeTreeLayout.graph(for: tree(crowded + ["small/a.swift", "small/b.swift"]))
        let weight = { (id: String) in graph.nodes.first { $0.id == id }?.weight }
        #expect(weight("small/a.swift") == 1)
        #expect(weight("big") == 1)
        #expect((weight("big/f0.txt") ?? 1) < 0.3)
        #expect((weight("big/f0.txt") ?? 0) >= ConeTreeLayout.minimumFileWeight)
    }

    @Test func dependenciesBecomeUsesEdges() {
        let deps = [Dependency(from: "src/a.swift", to: "src/b.swift"), Dependency(from: "src/a.swift", to: "gone.swift")]
        let graph = ConeTreeLayout.graph(for: tree(["src/a.swift", "src/b.swift"]), dependencies: deps)
        let uses = graph.edges.filter { $0.kind == .uses }
        #expect(uses.count == 1)
        #expect(uses.first?.from == "src/a.swift" && uses.first?.to == "src/b.swift")
    }

    @Test func folderSizesAreRecorded() {
        let graph = ConeTreeLayout.graph(for: tree(sample))
        let size = { (id: String) in graph.nodes.first { $0.id == id }?.descendantFiles }
        #expect(size(ConeTreeLayout.rootID) == sample.count)
        #expect(size("src") == 5)
        #expect(size("src/core") == 3)
        #expect(size("README.md") == 0)
    }

    @Test func siblingClustersDoNotOverlap() {
        var files: [String] = []
        for f in 0..<6 { for i in 0..<(20 + f * 15) { files.append("top\(f)/file\(i).swift") } }
        for f in 0..<5 { for i in 0..<30 { files.append("top0/sub\(f)/file\(i).swift") } }
        let graph = ConeTreeLayout.graph(for: tree(files))
        let position = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.position) })
        func directFiles(_ folder: String) -> Int {
            files.filter { ($0 as NSString).deletingLastPathComponent == folder }.count
        }
        func expectSeparated(_ folders: [String]) {
            for i in folders.indices {
                for j in folders.indices where j > i {
                    let (a, b) = (folders[i], folders[j])
                    let gap = simd_distance(position[a]!, position[b]!)
                    let reach = ConeTreeLayout.fileBallRadius(fileCount: directFiles(a))
                        + ConeTreeLayout.fileBallRadius(fileCount: directFiles(b))
                    #expect(gap > reach, "\(a) and \(b) overlap")
                }
            }
        }
        expectSeparated((0..<6).map { "top\($0)" })
        expectSeparated((0..<5).map { "top0/sub\($0)" })
    }
}
#endif
