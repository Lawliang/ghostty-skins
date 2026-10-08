#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
private final class Counter {
    var value = 0
}

@MainActor
struct FlowWatcherTests {
    private func waitFor(_ condition: () -> Bool, seconds: Double = 3) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    @Test func reportsChangeToFlowFileOnly() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        defer { watcher.stop() }

        try project.write(".mindcontrol/layout.json", "{ \"version\": 1, \"positions\": {} }")
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(count.value == 0)

        try project.write(".mindcontrol/flow.json", "{ \"version\": 1 }")
        await waitFor { count.value == 1 }
        #expect(count.value == 1)
    }

    @Test func noticesTheFlowFileAppearing() async throws {
        let project = try TempProject()
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        defer { watcher.stop() }
        try project.write(".mindcontrol/flow.json", "{}")
        await waitFor { count.value >= 1 }
        #expect(count.value == 1)
    }

    @Test func noticesTheFlowFileAppearingInAFolderMadeEarlier() async throws {
        let project = try TempProject()
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        defer { watcher.stop() }
        try FileManager.default.createDirectory(at: project.url.appendingPathComponent(".mindcontrol"), withIntermediateDirectories: true)
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(count.value == 0)

        try project.write(".mindcontrol/flow.json", "{}")
        await waitFor { count.value >= 1 }
        #expect(count.value == 1)
    }

    @Test func noticesAtomicReplacesAndKeepsWatchingTheNewFile() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let flow = project.url.appendingPathComponent(".mindcontrol/flow.json")
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        defer { watcher.stop() }

        try Data("{ \"version\": 1 }".utf8).write(to: flow, options: .atomic)
        await waitFor { count.value >= 1 }
        #expect(count.value == 1)

        // An in-place write to the file that replaced the original.
        try project.write(".mindcontrol/flow.json", "{ \"version\": 2 }")
        await waitFor { count.value >= 2 }
        #expect(count.value == 2)
    }

    @Test func atomicLayoutSavesDontCount() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        defer { watcher.stop() }

        try MindControl.LayoutStore.write(["audio": CGPoint(x: 10, y: 20)], root: project.url)
        try MindControl.LayoutStore.write(["audio": CGPoint(x: 30, y: 40)], root: project.url)
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(count.value == 0)
    }

    @Test func noticesTheFlowFileBeingDeleted() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        defer { watcher.stop() }

        try FileManager.default.removeItem(at: project.url.appendingPathComponent(".mindcontrol/flow.json"))
        await waitFor { count.value >= 1 }
        #expect(count.value == 1)
    }

    @Test func stopEndsReporting() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        watcher.stop()

        try project.write(".mindcontrol/flow.json", "{ \"version\": 1 }")
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(count.value == 0)
    }

    @Test func aStopRightAfterAChangeDropsThePendingReport() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }

        try project.write(".mindcontrol/flow.json", "{ \"version\": 1 }")
        // Let the file event arrive, but stop before the debounce fires.
        try await Task.sleep(nanoseconds: 100_000_000)
        watcher.stop()
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(count.value == 0)
    }

    @Test func releasingTheWatcherFreesItAndEndsReporting() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        var watcher: MindControl.FlowWatcher? = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        weak var released = watcher
        // A change in flight while the watcher goes away.
        try project.write(".mindcontrol/flow.json", "{ \"version\": 1 }")
        try await Task.sleep(nanoseconds: 100_000_000)
        watcher = nil
        #expect(released == nil)

        try project.write(".mindcontrol/flow.json", "{ \"version\": 2 }")
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(count.value == 0)
        _ = watcher
    }
}
#endif
