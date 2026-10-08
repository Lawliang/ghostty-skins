import AppKit
import SwiftUI

extension MindControl {
    /// Top bar: where you are, Change…, Map/Health, the control toggle, Focus, map health and age, Refresh.
    struct MapHeader: View {
        @ObservedObject var model: Model
        @ObservedObject var controller: MapController
        /// False while a Draft or Refresh is starting.
        let canRunClaude: Bool
        let onChange: () -> Void
        let onRefresh: () -> Void

        static let healthy = Color(red: 0.45, green: 0.85, blue: 0.6)
        static let warning = Color(red: 1, green: 0.7, blue: 0.3)

        var body: some View {
            HStack(spacing: 10) {
                // Always at least the end of the path; the badges give way first.
                breadcrumb.frame(minWidth: 110, alignment: .leading).layoutPriority(-1)
                Button("Change…", action: onChange)
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .help("Map a different folder")
                    .fixedSize()
                Spacer(minLength: 8)
                if case .ready(let project, let loaded) = model.state {
                    Picker("View", selection: $controller.mode) {
                        Text("Map").tag(SceneStyle.Mode.map)
                        Text("Health").tag(SceneStyle.Mode.health)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                    Toggle("Control", isOn: $controller.showControl)
                        .toggleStyle(.checkbox)
                        .help("Show or hide control arrows (triggers, callbacks)")
                        .fixedSize()
                    Button("Focus") { controller.enterFocus() }
                        .disabled(controller.focusTarget == nil || controller.focus != nil)
                        .help("Open the selected system or feature on its own (F)")
                        .fixedSize()
                    // Fewer badges when the panel is narrow; the health count always stays.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { badges(loaded.report, compact: false) }
                        HStack(spacing: 10) { badges(loaded.report, compact: true) }
                    }
                    Button("Refresh with Claude", action: onRefresh)
                        .disabled(!canRunClaude)
                        .help(project.claudeBlockReason ?? "Update the map from what changed in the code")
                        .fixedSize()
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.35))
        }

        @ViewBuilder
        private func badges(_ report: HealthReport, compact: Bool) -> some View {
            Button(Panel.healthText(report)) { controller.mode = .health }
                .buttonStyle(.borderless)
                .foregroundColor(report.isHealthy ? Self.healthy : Self.warning)
                .help(report.isHealthy ? "Everything on the map matches the code" : "Show what's wrong")
                .fixedSize()
            if !compact, let unmapped = Panel.unmappedText(report.unmapped.count) {
                Button(unmapped) { controller.mode = .health }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .help("Source files no system's paths cover")
                    .fixedSize()
            }
            if let dense = report.densityWarnings.first {
                Button(dense.message) { controller.mode = .health }
                    .buttonStyle(.borderless)
                    .foregroundColor(.yellow)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 240)
                    .help(report.densityWarnings.map(\.message).joined(separator: "\n"))
            }
            if !compact, let age = Panel.ageText(report.age) {
                Text(age).font(.system(size: 11)).foregroundColor(.secondary).fixedSize()
            }
        }

        /// The full project path, then the focused subject. Clicking the path leaves Focus view.
        private var breadcrumb: some View {
            HStack(spacing: 4) {
                if let project = model.project {
                    Button { controller.exitFocus() } label: {
                        Text(project.root.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.focus == nil)
                    .help(project.root.path)
                    ForEach(Array(controller.breadcrumb.dropFirst().enumerated()), id: \.offset) { _, name in
                        Text("›").foregroundColor(.secondary)
                        Text(name).fontWeight(.semibold).lineLimit(1).fixedSize()
                    }
                }
            }
        }
    }

    /// One chip per feature, in file order, each in its own colour.
    struct FeatureBar: View {
        @ObservedObject var controller: MapController

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array((controller.map?.features ?? []).enumerated()), id: \.element.id) { index, feature in
                        let color = Palette.feature(index)
                        let selected = controller.selectedFeature == feature.id
                        Button { controller.selectFeature(feature.id) } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(.sRGB, red: Self.srgb(color.x), green: Self.srgb(color.y), blue: Self.srgb(color.z)))
                                    .frame(width: 8, height: 8)
                                Text(feature.name).font(.system(size: 12, weight: selected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(selected ? 0.2 : 0.07)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(selected ? "Show the whole map again" : "Light up this feature's route and list its steps")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            // A horizontal scroll view otherwise grows to the full height and swallows clicks meant for the map.
            .fixedSize(horizontal: false, vertical: true)
        }

        /// The palette is linear; SwiftUI colours are sRGB-encoded.
        static func srgb(_ linear: Float) -> Double {
            let c = Double(max(0, min(1, linear)))
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
    }

    /// ⌘F or typing: a field plus grouped results. Enter goes to the first result; Esc clears and returns to the map.
    struct SearchBox: View {
        @ObservedObject var controller: MapController

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                SearchField(controller: controller, query: controller.query, request: controller.searchRequest)
                    .frame(height: 22)
                if !controller.results.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(controller.results.enumerated()), id: \.offset) { index, result in
                                if index == 0 || controller.results[index - 1].kind != result.kind {
                                    Text(Self.heading(result.kind))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.top, index == 0 ? 0 : 6)
                                }
                                Button {
                                    controller.navigate(to: result)
                                    controller.focusMap()
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.title).font(.system(size: 12))
                                        Text(result.detail).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: Self.listHeight(controller.results))
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.06, green: 0.07, blue: 0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                }
            }
            .frame(width: 320)
        }

        /// Tall enough for every row up to 320 points, then it scrolls. (A scroll view has no height of its own.)
        static func listHeight(_ results: [SearchResult]) -> CGFloat {
            let headings = Set(results.map(\.kind)).count
            return min(320, CGFloat(results.count) * 34 + CGFloat(headings) * 20 + 16)
        }

        static func heading(_ kind: SearchResult.Kind) -> String {
            switch kind {
            case .feature: "FEATURES"
            case .system: "SYSTEMS"
            case .part: "PARTS"
            case .file: "FILES"
            }
        }
    }

    /// The search text field. AppKit rather than a SwiftUI TextField so that when typing on the map hands the
    /// field its first letters, the cursor lands after them instead of selecting them (the next key would
    /// replace them).
    struct SearchField: NSViewRepresentable {
        let controller: MapController
        let query: String
        /// `MapController.searchRequest`; a change asks the field to take keyboard focus.
        let request: Int

        func makeCoordinator() -> Coordinator { Coordinator(controller: controller, request: request) }

        func makeNSView(context: Context) -> NSTextField {
            let field = NSTextField()
            field.placeholderString = "Search features, systems, files…"
            field.bezelStyle = .roundedBezel
            field.font = .systemFont(ofSize: 12)
            field.lineBreakMode = .byTruncatingTail
            field.usesSingleLineMode = true
            field.cell?.isScrollable = true
            field.delegate = context.coordinator
            field.stringValue = query
            return field
        }

        func updateNSView(_ field: NSTextField, context: Context) {
            context.coordinator.controller = controller
            if field.stringValue != query { field.stringValue = query }
            guard context.coordinator.request != request else { return }
            context.coordinator.request = request
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                if field.currentEditor() == nil { window.makeFirstResponder(field) }
                let end = (field.stringValue as NSString).length
                field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
            }
        }

        @MainActor
        final class Coordinator: NSObject, NSTextFieldDelegate {
            var controller: MapController
            var request: Int

            init(controller: MapController, request: Int) {
                self.controller = controller
                self.request = request
            }

            func controlTextDidChange(_ note: Notification) {
                guard let field = note.object as? NSTextField else { return }
                controller.query = field.stringValue
            }

            func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
                switch selector {
                case #selector(NSResponder.insertNewline(_:)):
                    controller.submitSearch()
                    controller.focusMap()
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    controller.query = ""
                    controller.focusMap()
                    return true
                default:
                    return false
                }
            }
        }
    }
}
