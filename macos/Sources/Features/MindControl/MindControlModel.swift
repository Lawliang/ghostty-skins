import Foundation

extension MindControl {
    /// Loads and watches the focused terminal's flow map. One per window. Rebuilt in Task 16.
    @MainActor
    final class Model: ObservableObject {
        @Published private(set) var pwd: URL?

        func load(pwd: URL?) { self.pwd = pwd }
    }
}
