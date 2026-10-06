import SwiftUI

extension MindControl {
    /// Full-size panel content: the 3D map plus a status line or a centred message.
    struct Panel: View {
        @ObservedObject var model: Model
        let onClose: () -> Void

        @State private var renderer: Renderer?
        @State private var rendererError: String?

        /// Matches the composite pass's outer background so the panel never flashes a different colour.
        private static let background = Color(red: 0.012, green: 0.016, blue: 0.043)
        private static let emptyGraph = Graph(nodes: [], edges: [])

        var body: some View {
            ZStack(alignment: .topLeading) {
                Self.background

                if let renderer {
                    MetalGraphView(renderer: renderer, onEscape: onClose)
                }

                if let message = rendererError ?? Self.centerMessage(for: model.state) {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let status = Self.statusText(for: model.state) {
                    Text(status)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(14)
                }
            }
            .onAppear(perform: startRenderer)
            .onChange(of: model.graphVersion) { _ in
                renderer?.setGraph(model.graph ?? Self.emptyGraph)
            }
        }

        private func startRenderer() {
            guard renderer == nil, rendererError == nil else { return }
            do {
                let renderer = try Renderer()
                renderer.setGraph(model.graph ?? Self.emptyGraph)
                self.renderer = renderer
            } catch RendererError.metalUnavailable {
                rendererError = "MindControl needs Metal, which is unavailable on this Mac."
            } catch {
                rendererError = error.localizedDescription
            }
        }

        static func statusText(for state: Model.State) -> String? {
            guard case .ready(let tree) = state else { return nil }
            if tree.totalIsLowerBound {
                return "\(tree.rootName) · showing the first \(tree.files.count.formatted()) files"
            }
            if tree.truncated {
                return "\(tree.rootName) · showing \(tree.files.count.formatted()) of \(tree.totalFileCount.formatted()) files"
            }
            return "\(tree.rootName) · \(tree.files.count.formatted()) files"
        }

        static func centerMessage(for state: Model.State) -> String? {
            switch state {
            case .idle, .ready: nil
            case .scanning: "Mapping project…"
            case .noProject: "This terminal hasn't reported a working directory."
            case .empty(let name): "\(name) has no files to map."
            case .failed(let message): message
            }
        }
    }
}
