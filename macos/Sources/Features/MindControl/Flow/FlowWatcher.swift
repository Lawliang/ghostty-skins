import Foundation

extension MindControl {
    /// Calls `onChange` (on the main queue) when `.mindcontrol/flow.json` appears or its contents change.
    /// Writes to `layout.json` and other files don't count.
    final class FlowWatcher {
        /// Runs a debounced check after `delay` seconds. It must run the work on the main queue.
        typealias Schedule = (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void

        /// The app's schedule: `asyncAfter` on the main queue.
        static let afterDelayOnMain: Schedule = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private let root: URL
        private let schedule: Schedule
        private let onChange: () -> Void
        private var sources: [DispatchSourceFileSystemObject] = []
        private var last: Data?
        private var pending: DispatchWorkItem?
        private var stopped = false

        /// Tests pass their own `schedule` to run the debounced check whenever they choose,
        /// so the result doesn't depend on how busy the main thread is.
        init(root: URL, schedule: @escaping Schedule = FlowWatcher.afterDelayOnMain, onChange: @escaping () -> Void) {
            self.root = root
            self.schedule = schedule
            self.onChange = onChange
            last = read()
            arm()
        }

        deinit { stop() }

        func stop() {
            stopped = true
            pending?.cancel()
            disarm()
        }

        private var flowURL: URL { root.appendingPathComponent(FlowFile.relativePath) }

        private func read() -> Data? { try? Data(contentsOf: flowURL) }

        /// Watches the root (for `.mindcontrol` appearing), the folder, and the file itself (for in-place writes).
        private func arm() {
            disarm()
            for url in [root, flowURL.deletingLastPathComponent(), flowURL] {
                let fd = open(url.path, O_EVTONLY)
                guard fd >= 0 else { continue }
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                                       eventMask: [.write, .extend, .rename, .delete, .attrib],
                                                                       queue: .main)
                source.setEventHandler { [weak self] in self?.changed() }
                source.setCancelHandler { close(fd) }
                source.resume()
                sources.append(source)
            }
        }

        private func disarm() {
            for source in sources { source.cancel() }
            sources = []
        }

        private func changed() {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.stopped else { return }
                self.arm()
                let now = self.read()
                guard now != self.last else { return }
                self.last = now
                self.onChange()
            }
            pending = work
            schedule(0.25, work)
        }
    }
}
