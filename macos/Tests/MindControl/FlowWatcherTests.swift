#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
private final class Counter {
    var value = 0
}

/// Stands in for the watcher's 0.25 s timer. It holds each debounced check until the test runs it,
/// so a busy main thread (the full suite runs in parallel) can't decide whether a stop comes
/// before or after the timer, and "nothing was reported" means the watcher looked and saw no change.
/// The watcher calls `schedule` on the main queue, and the tests use it from the main actor.
private final class HeldChecks {
    private var held: [DispatchWorkItem] = []

    lazy var schedule: MindControl.FlowWatcher.Schedule = { [weak self] _, work in self?.held.append(work) }

    /// A check is scheduled and not cancelled, so the watcher saw an event.
    var waiting: Bool { held.contains { !$0.isCancelled } }

    /// Runs the checks still waiting, as their timer would.
    func runWaiting() {
        let waiting = held.filter { !$0.isCancelled }
        held.removeAll()
        for work in waiting { work.perform() }
    }

    /// Runs every check ever scheduled, even cancelled ones. Returns how many there were.
    @discardableResult
    func runAll() -> Int {
        let all = held
        held.removeAll()
        for work in all { work.perform() }
        return all.count
    }
}

@MainActor
struct FlowWatcherTests {
    /// Waits for `condition`. The bound only matters when the test is going to fail anyway,
    /// so it is generous enough for a heavily loaded machine.
    private func waitFor(_ condition: () -> Bool, seconds: Double = 10) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    /// Waits until the watcher has seen an event and scheduled a check, then runs the check now.
    private func check(_ held: HeldChecks) async {
        await waitFor { held.waiting }
        #expect(held.waiting, "the watcher never scheduled a check")
        held.runWaiting()
    }

    // MARK: What counts (checks held and run by the test)

    @Test func reportsChangeToFlowFileOnly() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let held = HeldChecks()
        let watcher = MindControl.FlowWatcher(root: project.url, schedule: held.schedule) { count.value += 1 }
        defer { watcher.stop() }

        try project.write(".mindcontrol/layout.json", "{ \"version\": 1, \"positions\": {} }")
        await check(held)
        #expect(count.value == 0)

        try project.write(".mindcontrol/flow.json", "{ \"version\": 1 }")
        await check(held)
        #expect(count.value == 1)
    }

    @Test func noticesTheFlowFileAppearingInAFolderMadeEarlier() async throws {
        let project = try TempProject()
        let count = Counter()
        let held = HeldChecks()
        let watcher = MindControl.FlowWatcher(root: project.url, schedule: held.schedule) { count.value += 1 }
        defer { watcher.stop() }
        try FileManager.default.createDirectory(at: project.url.appendingPathComponent(".mindcontrol"), withIntermediateDirectories: true)
        await check(held)
        #expect(count.value == 0)

        try project.write(".mindcontrol/flow.json", "{}")
        await check(held)
        #expect(count.value == 1)
    }

    @Test func atomicLayoutSavesDontCount() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let held = HeldChecks()
        let watcher = MindControl.FlowWatcher(root: project.url, schedule: held.schedule) { count.value += 1 }
        defer { watcher.stop() }

        try MindControl.LayoutStore.write(["audio": CGPoint(x: 10, y: 20)], root: project.url)
        await check(held)
        try MindControl.LayoutStore.write(["audio": CGPoint(x: 30, y: 40)], root: project.url)
        await check(held)
        #expect(count.value == 0)
    }

    // MARK: Stopping (checks held and run by the test)

    @Test func stopEndsReporting() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let held = HeldChecks()
        let watcher = MindControl.FlowWatcher(root: project.url, schedule: held.schedule) { count.value += 1 }
        watcher.stop()

        try project.write(".mindcontrol/flow.json", "{ \"version\": 1 }")
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(held.runAll() == 0)
        #expect(count.value == 0)
    }

    @Test func aStopRightAfterAChangeDropsThePendingReport() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let held = HeldChecks()
        let watcher = MindControl.FlowWatcher(root: project.url, schedule: held.schedule) { count.value += 1 }

        try project.write(".mindcontrol/flow.json", "{ \"version\": 1 }")
        // The file event has arrived and its check is waiting for the timer.
        await waitFor { held.waiting }
        #expect(held.waiting)
        watcher.stop()
        #expect(!held.waiting)
        // Even if the dropped check ran anyway, it reports nothing.
        held.runAll()
        #expect(count.value == 0)
    }

    @Test func releasingTheWatcherFreesItAndEndsReporting() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let held = HeldChecks()
        var watcher: MindControl.FlowWatcher? = MindControl.FlowWatcher(root: project.url, schedule: held.schedule) { count.value += 1 }
        weak var released = watcher
        // A change in flight while the watcher goes away.
        try project.write(".mindcontrol/flow.json", "{ \"version\": 1 }")
        await waitFor { held.waiting }
        #expect(held.waiting)
        watcher = nil
        #expect(released == nil)
        held.runAll()
        #expect(count.value == 0)

        try project.write(".mindcontrol/flow.json", "{ \"version\": 2 }")
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(held.runAll() == 0)
        #expect(count.value == 0)
        _ = watcher
    }

    // MARK: The app's real 0.25 s timer on the main queue

    @Test func noticesTheFlowFileAppearing() async throws {
        let project = try TempProject()
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        defer { watcher.stop() }
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
}
#endif
