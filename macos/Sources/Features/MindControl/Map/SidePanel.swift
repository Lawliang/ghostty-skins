import SwiftUI

extension MindControl {
    /// Right-hand panel: a feature's steps, a system's or part's flows and files, an arrow's hand-offs, or the health list.
    struct SidePanel: View {
        @ObservedObject var controller: MapController

        static let width: CGFloat = 320

        var body: some View {
            let content = controller.sidePanel
            if content != .none {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) { sections(content) }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: Self.width)
                .background(Color(red: 0.03, green: 0.04, blue: 0.08).opacity(0.92))
                .font(.system(size: 12))
            }
        }

        @ViewBuilder
        private func sections(_ content: SidePanelContent) -> some View {
            switch content {
            case .none:
                EmptyView()
            case .feature(let name, let groups, let unknown):
                Text(name).font(.system(size: 15, weight: .semibold))
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if let when = group.when {
                        Text("If \(when)").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary).padding(.top, 4)
                    }
                    ForEach(group.steps, id: \.flowID) { step in
                        Button { controller.goToStep(step.flowID) } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(step.number).").foregroundColor(.secondary).frame(width: 22, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(step.from) → \(step.to)")
                                    Text(step.kind == .control ? "control · \(step.carries)" : step.carries)
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 4)
                                status(step.status)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show this step on the map")
                    }
                }
                if !unknown.isEmpty {
                    Text("Not drawn: \(unknown.joined(separator: ", "))").foregroundColor(.orange)
                }
            case .system(let name, let summary, let incoming, let outgoing, let files):
                Text(name).font(.system(size: 15, weight: .semibold))
                if let summary { Text(summary).foregroundColor(.secondary) }
                flowList("In", incoming)
                flowList("Out", outgoing)
                if !files.isEmpty {
                    heading("Files")
                    ForEach(files, id: \.self) { file in fileButton(file) }
                }
            case .part(let name, let system, let file, let stale, let incoming, let outgoing):
                Text(name).font(.system(size: 15, weight: .semibold))
                Text(system).foregroundColor(.secondary)
                if stale { Text("Stale: its anchor wasn't found in the code.").foregroundColor(.orange) }
                if let file { fileButton(file) }
                flowList("In", incoming)
                flowList("Out", outgoing)
            case .arrow(let rows):
                flowList("Flows", rows)
            case .health(let report):
                Text(Panel.healthText(report)).font(.system(size: 15, weight: .semibold))
                if let age = Panel.ageText(report.age) { Text(age).foregroundColor(.secondary) }
                // Density warnings first, then everything else; each issue moves the view to its subject.
                ForEach(Array((report.densityWarnings + report.issues.filter { $0.kind != .density }).enumerated()), id: \.offset) { _, issue in
                    Button { controller.goToIssue(issue) } label: {
                        Text(issue.message)
                            .foregroundColor(issue.kind == .density || issue.kind == .unknownKey ? .yellow : .orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !report.unmapped.isEmpty {
                    heading(report.unmapped.count == 1 ? "1 file belongs to no system" : "\(report.unmapped.count) files belong to no system")
                    ForEach(report.unmapped, id: \.self) { file in fileButton(file) }
                }
            }
        }

        private func heading(_ text: String) -> some View {
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary).padding(.top, 4)
        }

        private func fileButton(_ file: String) -> some View {
            Button(file) { controller.openSource(file) }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .help("Open \(file)")
        }

        @ViewBuilder
        private func flowList(_ title: String, _ rows: [FlowRow]) -> some View {
            if !rows.isEmpty {
                heading(title)
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text("\(row.from) → \(row.to)")
                            Spacer(minLength: 4)
                            status(row.status)
                        }
                        Text(row.kind == .control ? "control · \(row.carries)" : row.carries).foregroundColor(.secondary)
                        if let when = row.when { Text("when \(when)").foregroundColor(.secondary) }
                        if let location = row.location, let via = row.via {
                            Button("\(via) · \(location.file):\(location.line)") { controller.open(location) }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.accentColor)
                                .help("Open the hand-off in the code")
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func status(_ status: FeatureStep.Status) -> some View {
            switch status {
            case .ok: EmptyView()
            case .stale: Text("stale").font(.system(size: 10)).foregroundColor(.orange)
            case .unverified: Text("unverified").font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }
}
