#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowAge = MindControl.FlowAge

struct FlowAgeTests {
    @Test func hiddenOutsideGit() throws {
        let project = try TempProject()
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.arca) == .hidden)
    }

    @Test func notCommittedYet() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        try project.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.arca) == .notCommitted)
    }

    @Test func countsOnlyCommitsTouchingMappedPaths() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        try project.write(FlowFixtures.arcaSources)
        try project.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        try project.commitAll("map")
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.arca) == .commits(0))

        try project.write("app/Sources/Audio/New.swift", "struct New {}\n")
        try project.commitAll("audio change")
        try project.write("docs/notes.md", "notes\n")
        try project.commitAll("docs change")
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.arca) == .commits(1))
    }
    /// "Map up to date" would be a claim nothing was checked for: with no paths, or when git can't count, hide it.
    @Test func hiddenWhenThereIsNothingToCount() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        let json = #"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ] }"#
        try project.write(".mindcontrol/flow.json", json)
        try project.commitAll("map")
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.map(json)) == .hidden)
    }

    @Test func hiddenWhenGitCannotCount() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        // A pathspec outside the repository makes rev-list fail.
        let json = #"{ "version": 1, "systems": [ { "id": "a", "name": "A", "paths": ["../outside/**"] } ] }"#
        try project.write(".mindcontrol/flow.json", json)
        try project.commitAll("map")
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.map(json)) == .hidden)
    }
}
#endif
