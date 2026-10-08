#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias Model = MindControl.Model
private typealias FlowSnapshot = MindControl.FlowSnapshot

/// Counts calls from any thread.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}

@MainActor
struct ModelTests {
    private let pwd = URL(fileURLWithPath: "/tmp/mc-model-test")

    private func model(json: String?, files: [String: String] = FlowFixtures.arcaSources,
                       age: MindControl.HealthReport.Age = .commits(3), blocked: String? = nil) -> Model {
        Model(snapshot: { root in
                  FlowSnapshot(root: root, flowData: json.map { Data($0.utf8) }, layoutData: nil,
                               sourceFiles: files.keys.sorted(), read: { files[$0] })
              },
              age: { _, _ in age },
              guardReason: { _ in blocked },
              watch: false)
    }

    private func waitFor(_ condition: () -> Bool, seconds: Double = 10) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    private func canonicalPath(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    @Test func nilPwdIsNoProject() {
        let model = model(json: nil)
        model.load(pwd: nil)
        #expect(model.state == .noProject)
    }

    @Test func missingFlowFile() async {
        let model = model(json: nil, blocked: "This folder isn't a git repository.")
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .noFlowFile(let project) = model.state else { Issue.record("\(model.state)"); return }
        #expect(project.name == "mc-model-test")
        #expect(project.claudeBlockReason == "This folder isn't a git repository.")
    }

    @Test func invalidFileShowsErrors() async {
        let model = model(json: "{ \"version\": 1 }")
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .invalid(_, let errors) = model.state else { Issue.record("\(model.state)"); return }
        #expect(errors.contains { $0.message.contains("systems") })
    }

    @Test func readyCarriesMapReportAndAge() async {
        let model = model(json: FlowFixtures.arcaJSON)
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .ready(_, let loaded) = model.state else { Issue.record("\(model.state)"); return }
        #expect(loaded.map == FlowFixtures.arca)
        #expect(loaded.report.isHealthy)
        #expect(loaded.report.age == .commits(3))
    }

    @Test func brokenEndpointStillDrawsTheRest() async {
        let json = FlowFixtures.arcaJSON.replacingOccurrences(of: #""to": "agent.session", "kind": "data", "carries": "PCM16"#,
                                                              with: #""to": "agent.nope", "kind": "data", "carries": "PCM16"#)
        let model = model(json: json)
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .ready(_, let loaded) = model.state else { Issue.record("\(model.state)"); return }
        #expect(loaded.report.brokenFlows == ["pcm"])
        let layout = MindControl.FlowLayout.layout(map: loaded.map, broken: loaded.report.brokenFlows)
        #expect(layout.arrows.first { $0.id == "flow:pcm" } == nil)
        #expect(layout.arrows.contains { $0.id == "flow:send" })
    }

    @Test func overrideReplacesTerminalFolderUntilClosed() async {
        let model = model(json: nil)
        model.load(pwd: URL(fileURLWithPath: "/tmp/mc-a"))
        model.choose(root: URL(fileURLWithPath: "/tmp/mc-b"))
        await model.loadingTask?.value
        #expect(model.project?.root.path == "/tmp/mc-b")
        model.load(pwd: URL(fileURLWithPath: "/tmp/mc-a"))
        await model.loadingTask?.value
        #expect(model.project?.root.path == "/tmp/mc-b")
        model.close()
        model.load(pwd: URL(fileURLWithPath: "/tmp/mc-a"))
        await model.loadingTask?.value
        #expect(model.project?.root.path == "/tmp/mc-a")
    }

    // MARK: Concurrency

    @Test func gitWorkRunsOffTheMainThread() async {
        let files = FlowFixtures.arcaSources
        let model = Model(snapshot: { root in
                              FlowSnapshot(root: root, flowData: Thread.isMainThread ? nil : Data(FlowFixtures.arcaJSON.utf8),
                                           layoutData: nil, sourceFiles: files.keys.sorted(), read: { files[$0] })
                          },
                          age: { _, _ in Thread.isMainThread ? .hidden : .commits(1) },
                          guardReason: { _ in Thread.isMainThread ? "ran on the main thread" : nil },
                          watch: false)
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .ready(let project, let loaded) = model.state else { Issue.record("\(model.state)"); return }
        #expect(project.claudeBlockReason == nil)
        #expect(loaded.report.age == .commits(1))
    }

    @Test func aSlowEarlierLoadNeverReplacesALaterOneAndStopsEarly() async throws {
        let files = FlowFixtures.arcaSources
        let ageCalls = Calls()
        let model = Model(snapshot: { root in
                              if root.lastPathComponent == "mc-slow" { Thread.sleep(forTimeInterval: 0.3) }
                              return FlowSnapshot(root: root, flowData: Data(FlowFixtures.arcaJSON.utf8), layoutData: nil,
                                                  sourceFiles: files.keys.sorted(), read: { files[$0] })
                          },
                          age: { _, _ in ageCalls.add(); return .commits(1) },
                          guardReason: { _ in nil },
                          watch: false)
        model.load(pwd: URL(fileURLWithPath: "/tmp/mc-slow"))
        let slow = model.loadingTask
        model.choose(root: URL(fileURLWithPath: "/tmp/mc-fast"))
        await model.loadingTask?.value
        await slow?.value
        try await Task.sleep(nanoseconds: 500_000_000)

        guard case .ready(let project, _) = model.state else { Issue.record("\(model.state)"); return }
        #expect(project.root.path == "/tmp/mc-fast")
        // The superseded load stopped after its snapshot instead of going on to count commits.
        #expect(ageCalls.value == 1)
    }

    @Test func reloadKeepsTheMapUntilTheNewOneIsReady() async {
        let model = model(json: FlowFixtures.arcaJSON)
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .ready(_, let first) = model.state else { Issue.record("\(model.state)"); return }

        model.reload()
        guard case .ready(_, let shown) = model.state else { Issue.record("\(model.state)"); return }
        #expect(shown == first)

        await model.loadingTask?.value
        guard case .ready(_, let second) = model.state else { Issue.record("\(model.state)"); return }
        #expect(second.generation != first.generation)
    }

    @Test func closeDuringALoadDropsItsResultAndDoesntWatch() async throws {
        let project = try TempProject()
        let model = Model(age: { _, _ in .hidden }, guardReason: { _ in nil })
        model.load(pwd: project.url)
        model.close()
        await model.loadingTask?.value

        try project.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        try await Task.sleep(nanoseconds: 800_000_000)
        if case .ready = model.state { Issue.record("a closed model reloaded: \(model.state)") }
        if case .noFlowFile = model.state { Issue.record("a closed model finished its load: \(model.state)") }
    }

    // MARK: Real folders

    @Test func unreadableFolderFails() async {
        let missing = URL(fileURLWithPath: "/tmp/mc-missing-\(UUID().uuidString)")
        let model = Model(age: { _, _ in .hidden }, guardReason: { _ in nil }, watch: false)
        model.load(pwd: missing)
        await model.loadingTask?.value
        #expect(model.state == .failed("Can't read \(missing.path)."))
    }

    @Test func theMapLoadsByItselfWhenTheFlowFileAppears() async throws {
        let project = try TempProject()
        try project.write(FlowFixtures.arcaSources)
        let model = Model(age: { _, _ in .hidden }, guardReason: { _ in nil })
        defer { model.close() }
        model.load(pwd: project.url)
        await model.loadingTask?.value
        guard case .noFlowFile = model.state else { Issue.record("\(model.state)"); return }

        try project.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        await waitFor { if case .ready = model.state { true } else { false } }
        guard case .ready(_, let loaded) = model.state else { Issue.record("\(model.state)"); return }
        #expect(loaded.map == FlowFixtures.arca)
    }

    @Test func closeStopsWatching() async throws {
        let project = try TempProject()
        let model = Model(age: { _, _ in .hidden }, guardReason: { _ in nil })
        model.load(pwd: project.url)
        await model.loadingTask?.value
        model.close()

        try project.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        try await Task.sleep(nanoseconds: 800_000_000)
        guard case .noFlowFile = model.state else { Issue.record("\(model.state)"); return }
    }

    @Test func folderChosenThroughASymlinkIntoARepoSubfolder() async throws {
        let repo = try TempProject()
        try repo.git("init", "-q")
        for (path, contents) in FlowFixtures.arcaSources { try repo.write("sub/" + path, contents) }
        try repo.write("sub/.mindcontrol/flow.json", FlowFixtures.arcaJSON)
        let links = try TempProject()
        let link = links.url.appendingPathComponent("sub-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo.url.appendingPathComponent("sub"))

        let model = Model(age: { _, _ in .hidden }, guardReason: { _ in nil }, watch: false)
        model.choose(root: link)
        await model.loadingTask?.value
        guard case .ready(let project, let loaded) = model.state else { Issue.record("\(model.state)"); return }
        #expect(project.root.path == canonicalPath(repo.url.appendingPathComponent("sub")))
        #expect(project.name == "sub")
        #expect(loaded.report.staleParts.isEmpty)
        #expect(loaded.report.isHealthy)
    }

    @Test func terminalFolderThroughASymlinkMapsItsGitRoot() async throws {
        let repo = try TempProject()
        try repo.git("init", "-q")
        try repo.write(FlowFixtures.arcaSources)
        try repo.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        try FileManager.default.createDirectory(at: repo.url.appendingPathComponent("tools"), withIntermediateDirectories: true)
        let links = try TempProject()
        let link = links.url.appendingPathComponent("tools-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo.url.appendingPathComponent("tools"))

        let model = Model(age: { _, _ in .hidden }, guardReason: { _ in nil }, watch: false)
        model.load(pwd: link)
        await model.loadingTask?.value
        guard case .ready(let project, let loaded) = model.state else { Issue.record("\(model.state)"); return }
        #expect(project.root.path == canonicalPath(repo.url))
        #expect(project.name == repo.url.lastPathComponent)
        #expect(loaded.report.isHealthy)
    }
}
#endif
