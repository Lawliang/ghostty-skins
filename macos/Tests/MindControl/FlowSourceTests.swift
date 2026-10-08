#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowSource = MindControl.FlowSource

struct FlowSourceTests {
    @Test func sameProjectFromWorkingTreeAndCommit() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        try project.write(FlowFixtures.arcaSources)
        try project.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        try project.write("docs/notes.md", "not source")
        try project.commitAll("first")
        try project.write(".mindcontrol/flow.json", "{ \"edited\": true }")

        let disk = try FlowSource.workingTree.snapshot(root: project.url)
        let head = try FlowSource.revision("HEAD").snapshot(root: project.url)

        #expect(head.flowData.map { String(decoding: $0, as: UTF8.self) } == FlowFixtures.arcaJSON)
        #expect(disk.flowData.map { String(decoding: $0, as: UTF8.self) } == "{ \"edited\": true }")
        #expect(disk.sourceFiles == FlowFixtures.arcaSources.keys.sorted())
        #expect(head.sourceFiles == disk.sourceFiles)
        #expect(head.read("app/Sources/Audio/SpeechGate.swift") == FlowFixtures.arcaSources["app/Sources/Audio/SpeechGate.swift"])
        #expect(disk.read("app/Sources/Audio/SpeechGate.swift") == FlowFixtures.arcaSources["app/Sources/Audio/SpeechGate.swift"])
        #expect(disk.read("missing.swift") == nil)
    }

    @Test func subfolderOfARepositoryReadsRelativeToTheChosenFolder() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        for (path, contents) in FlowFixtures.arcaSources { try project.write("sub/" + path, contents) }
        try project.write("sub/.mindcontrol/flow.json", FlowFixtures.arcaJSON)
        try project.write("other/Elsewhere.swift", "struct Elsewhere {}\n")
        try project.write("Root.swift", "struct Root {}\n")
        try project.commitAll("first")
        let sub = project.url.appendingPathComponent("sub")
        let gate = "app/Sources/Audio/SpeechGate.swift"

        for source in [FlowSource.workingTree, FlowSource.revision("HEAD")] {
            let snapshot = try source.snapshot(root: sub)
            #expect(snapshot.sourceFiles == FlowFixtures.arcaSources.keys.sorted(), "\(source)")
            #expect(snapshot.flowData.map { String(decoding: $0, as: UTF8.self) } == FlowFixtures.arcaJSON, "\(source)")
            #expect(snapshot.read(gate) == FlowFixtures.arcaSources[gate], "\(source)")
        }
    }

    @Test func subfolderUnderAnExcludedFolderNameIsFilteredRelativeToItself() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        try project.write([
            "tools/cli/Sources/Main.swift": "struct Main {}\n",
            "tools/cli/Sources/Parser.swift": "struct Parser {}\n",
            "tools/cli/Tests/ParserTests.swift": "struct ParserTests {}\n",
            "tools/cli/docs/Example.swift": "struct Example {}\n",
            "other/X.swift": "struct X {}\n",
        ])
        try project.commitAll("first")
        let cli = project.url.appendingPathComponent("tools/cli")

        let disk = try FlowSource.workingTree.snapshot(root: cli)
        let head = try FlowSource.revision("HEAD").snapshot(root: cli)
        #expect(disk.sourceFiles == ["Sources/Main.swift", "Sources/Parser.swift"])
        #expect(head.sourceFiles == disk.sourceFiles)
        #expect(disk.read("Sources/Parser.swift") == "struct Parser {}\n")
    }

    @Test func missingFlowFileIsNil() throws {
        let project = try TempProject()
        try project.write("main.swift", "let x = 1\n")
        let snapshot = try FlowSource.workingTree.snapshot(root: project.url)
        #expect(snapshot.flowData == nil)
        #expect(snapshot.layoutData == nil)
        #expect(snapshot.sourceFiles == ["main.swift"])
    }

    @Test func unknownRevisionThrows() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        try project.write("main.swift", "let x = 1\n")
        try project.commitAll("first")
        #expect(throws: MindControl.FlowSourceError.unknownRevision("nope")) {
            try FlowSource.revision("nope").snapshot(root: project.url)
        }
    }
}
#endif
