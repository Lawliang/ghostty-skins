import SwiftUI

extension MindControl {
    /// Full-size panel content. Rebuilt in Task 19.
    struct Panel: View {
        @ObservedObject var model: Model
        let onClose: () -> Void

        /// Matches the composite pass's outer background so the panel never flashes a different colour.
        static let background = Color(red: 0.012, green: 0.016, blue: 0.043)

        var body: some View {
            ZStack {
                Self.background
                Text("MindControl is being rebuilt.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }
}
