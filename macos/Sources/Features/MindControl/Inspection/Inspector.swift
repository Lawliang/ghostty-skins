import Combine

extension MindControl {
    /// Hover and pin state for the map. The focus is the pinned node, else the hovered one.
    @MainActor
    final class Inspector: ObservableObject {
        @Published private(set) var hovered: Int?
        @Published private(set) var pinned: Int?
        /// Called whenever `focus` changes.
        var onFocusChange: ((Int?) -> Void)?

        var focus: Int? { pinned ?? hovered }

        func hover(_ index: Int?) {
            guard hovered != index else { return }
            change { hovered = index }
        }

        /// A click on a node pins it (or unpins it if already pinned); a click on empty space unpins.
        func click(_ index: Int?) {
            change { pinned = (index == nil || pinned == index) ? nil : index }
        }

        /// Esc unpins. Returns false when nothing was pinned, so the caller can close the panel instead.
        func escape() -> Bool {
            guard pinned != nil else { return false }
            change { pinned = nil }
            return true
        }

        func reset() {
            change {
                hovered = nil
                pinned = nil
            }
        }

        private func change(_ update: () -> Void) {
            let before = focus
            update()
            if focus != before { onFocusChange?(focus) }
        }
    }
}
