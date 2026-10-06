#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias Model = MindControl.Model
private typealias FileTree = MindControl.FileTree
private typealias ScanError = MindControl.ScanError

/// Counts scan calls from any thread.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
struct ModelTests {
    private let pwd = URL(fileURLWithPath: "/tmp/mc-model-test")

    private func tree(_ files: [String], total: Int? = nil) -> FileTree {
        FileTree(rootName: "proj", rootPath: "/tmp/mc-model-test", files: files, totalFileCount: total ?? files.count)
    }

    @Test func nilPwdIsNoProject() {
        let model = Model(scan: { _ in Issue.record("must not scan"); throw ScanError.noDirectory("") })
        model.load(pwd: nil)
        #expect(model.state == .noProject)
        #expect(model.graph == nil)
    }

    @Test func successPublishesGraph() async {
        let files = ["a.swift", "src/b.swift"]
        let model = Model(scan: { [files] _ in FileTree(rootName: "proj", rootPath: "/tmp/mc-model-test", files: files, totalFileCount: 2) })
        model.load(pwd: pwd)
        #expect(model.state == .scanning)
        await model.loadingTask?.value
        #expect(model.state == .ready(tree(files)))
        #expect(model.graph?.nodes.count == 4)     // root, a.swift, src, src/b.swift
        #expect(model.graphVersion == 1)
    }

    @Test func emptyProject() async {
        let model = Model(scan: { _ in FileTree(rootName: "proj", rootPath: "/tmp/mc-model-test", files: [], totalFileCount: 0) })
        model.load(pwd: pwd)
        await model.loadingTask?.value
        #expect(model.state == .empty("proj"))
        #expect(model.graph == nil)
    }

    @Test func failurePublishesMessage() async {
        let model = Model(scan: { _ in throw ScanError.noDirectory("/gone") })
        model.load(pwd: pwd)
        await model.loadingTask?.value
        #expect(model.state == .failed("Can't read /gone."))
    }

    @Test func cachedRootSkipsRescan() async {
        let counter = CallCounter()
        let model = Model(scan: { _ in
            counter.increment()
            return FileTree(rootName: "proj", rootPath: "/tmp/mc-model-test", files: ["x.swift"], totalFileCount: 1)
        })
        model.load(pwd: pwd)
        await model.loadingTask?.value
        model.load(pwd: pwd)
        await model.loadingTask?.value
        #expect(counter.count == 1)
        #expect(model.graphVersion == 2)           // cache hit still republishes so the renderer re-frames
        if case .ready = model.state {} else { Issue.record("expected ready, got \(model.state)") }
    }
}
#endif
