import SwiftUI

extension MindControl {
    /// Details for the pinned node.
    struct InfoCard: View {
        let details: NodeDetails

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(details.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(details.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
            }
            .foregroundColor(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.45)))
            .padding(14)
            .allowsHitTesting(false)
        }

        private var summary: String {
            switch details.kind {
            case .root, .folder:
                return "Folder · \(details.files.formatted()) files"
            case .source, .document:
                let kind = details.kind == .document ? "Document" : "Source"
                return "\(kind) · uses \(details.uses) · used by \(details.usedBy)"
            }
        }
    }
}
