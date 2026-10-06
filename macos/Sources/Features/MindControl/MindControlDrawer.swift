import SwiftUI

extension MindControl {
    /// A slim tab on the terminal's right edge; clicking it slides the MindControl panel over the
    /// whole terminal. Placement lives only here so other drawer styles can be tried later.
    struct Drawer: View {
        /// The focused terminal's working directory, read when the drawer opens.
        let pwd: () -> URL?
        /// Hands keyboard focus back to the terminal after closing.
        let onClose: () -> Void

        @StateObject private var model = Model()
        @State private var isOpen = false

        var body: some View {
            HStack(spacing: 0) {
                DrawerTab(isOpen: isOpen, action: toggle)

                if isOpen {
                    Panel(model: model, onClose: toggle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }

        private func toggle() {
            let opening = !isOpen
            if opening { model.load(pwd: pwd()) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                isOpen = opening
            }
            if !opening { onClose() }
        }
    }

    private struct DrawerTab: View {
        static let width: CGFloat = 22
        static let height: CGFloat = 64
        private static let glow = Color(red: 0.45, green: 0.80, blue: 1.0)

        let isOpen: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: isOpen ? "chevron.right" : "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Self.glow)
                    .shadow(color: Self.glow.opacity(0.8), radius: 4)
                    .frame(width: Self.width, height: Self.height)
                    .background(
                        // Round only the leading corners: draw a wider rounded rect and clip its trailing edge.
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                            .padding(.trailing, -8)
                    )
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("MindControl")
        }
    }
}
