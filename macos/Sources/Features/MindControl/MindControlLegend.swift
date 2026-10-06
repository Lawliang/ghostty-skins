import SwiftUI

extension MindControl {
    /// Explains what lines and node colours mean. Colours are sRGB approximations of the shader values.
    struct Legend: View {
        private static let contains = Color(red: 0.68, green: 0.75, blue: 0.89)
        private static let uses = Color(red: 1.0, green: 0.85, blue: 0.58)
        private static let folder = Color(red: 0.54, green: 0.74, blue: 1.0)
        private static let source = Color(red: 0.48, green: 0.93, blue: 1.0)
        private static let document = Color(red: 0.83, green: 0.63, blue: 1.0)

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                line(Self.contains, width: 1, label: "contains — folder holds file")
                line(Self.uses, width: 2, label: "uses — file depends on file")
                HStack(spacing: 10) {
                    dot(Self.folder, "folder")
                    dot(Self.source, "source")
                    dot(Self.document, "document")
                }
            }
            .font(.system(size: 10.5))
            .foregroundColor(.white.opacity(0.75))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.35)))
            .padding(14)
            .allowsHitTesting(false)
        }

        private func line(_ color: Color, width: CGFloat, label: String) -> some View {
            HStack(spacing: 8) {
                Capsule().fill(color).frame(width: 22, height: width)
                Text(label)
            }
        }

        private func dot(_ color: Color, _ label: String) -> some View {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
            }
        }
    }
}
