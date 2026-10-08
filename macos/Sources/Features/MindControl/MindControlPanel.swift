import AppKit
import SwiftUI

extension MindControl {
    /// Full-size panel: the Metal map with its header, feature bar, search and side panel, or an empty / error state.
    struct Panel: View {
        @ObservedObject var model: Model
        let onClose: () -> Void
        var openTab: (URL, String) -> Void = { _, _ in }

        @StateObject private var controller = MapController()
        @State private var renderer: Renderer?
        @State private var rendererError: String?
        @State private var promptToCopy: PromptToCopy?
        /// True while checking for `claude` before a Draft or Refresh (up to a few seconds).
        @State private var startingClaude = false

        struct PromptToCopy: Identifiable {
            let id = UUID()
            let title: String
            let detail: String
            let text: String
        }

        /// Matches the composite pass's outer background so the panel never flashes a different colour.
        static let background = Color(red: 0.012, green: 0.016, blue: 0.043)

        var body: some View {
            ZStack {
                Self.background
                if !hasMapView {
                    // Without the map view nothing else takes keyboard focus, and keys would reach the terminal.
                    PanelFocusHolder(onEscape: onClose, state: model.state)
                }
                VStack(spacing: 0) {
                    MapHeader(model: model, controller: controller, canRunClaude: canRunClaude,
                              onChange: chooseFolder, onRefresh: { launch(.refresh) })
                    ZStack(alignment: .topLeading) {
                        if isReady { mapArea }
                        if let message = rendererError ?? Self.centerMessage(for: model.state) {
                            Text(message)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(24)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if case .noFlowFile(let project) = model.state { emptyState(project) }
                        if case .invalid(_, let errors) = model.state { errorList(errors) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if hasMapView {
                    // ⌘F while the search field or a button has focus; the map view handles it itself.
                    Button("") { controller.beginSearch(with: "") }.keyboardShortcut("f", modifiers: .command).opacity(0)
                }
            }
            .onAppear {
                controller.onClose = onClose
                startRenderer()
                apply()
            }
            .onChange(of: model.state) { _ in apply() }
            .sheet(item: $promptToCopy) { prompt in copySheet(prompt) }
        }

        /// The map, with the feature bar and search over its top edge and the side panel down its right.
        @ViewBuilder
        private var mapArea: some View {
            if let renderer {
                FlowMetalView(renderer: renderer, controller: controller)
            }
            // Below the feature bar, so the search field sits right above it and its results cover it.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SidePanel(controller: controller)
            }
            .padding(.top, 44)
            HStack(alignment: .top, spacing: 8) {
                FeatureBar(controller: controller)
                Spacer(minLength: 0)
                SearchBox(controller: controller).padding(.trailing, 14).padding(.top, 7)
            }
        }

        private var isReady: Bool {
            if case .ready = model.state { return true }
            return false
        }

        /// The map view takes keyboard focus (Esc, F, typing); without it, the focus holder does.
        private var hasMapView: Bool { isReady && renderer != nil }

        private var canRunClaude: Bool { Self.canRunClaude(in: model.state) && !startingClaude }

        private func apply() {
            guard case .ready(let project, let loaded) = model.state else { return }
            // The feature bar reads the map, which isn't published; tell the views a new one arrived.
            controller.objectWillChange.send()
            controller.show(loaded, root: project.root)
        }

        private func startRenderer() {
            guard renderer == nil, rendererError == nil else { return }
            do {
                renderer = try Renderer()
            } catch RendererError.metalUnavailable {
                rendererError = "MindControl needs Metal, which is unavailable on this Mac."
            } catch {
                rendererError = error.localizedDescription
            }
        }

        private func chooseFolder() {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Map This Folder"
            panel.message = "Choose the project folder to map."
            panel.directoryURL = model.project?.root
            if panel.runModal() == .OK, let url = panel.url { model.choose(root: url) }
        }

        /// Opens a new tab in the project running `claude` with the prompt, or, when `claude` can't be found,
        /// shows the prompt to copy. The check runs a login shell, so it happens off the main thread.
        private func launch(_ kind: ClaudePrompts.Kind) {
            guard canRunClaude, let project = model.project else { return }
            let prompt = kind == .draft ? ClaudePrompts.draft(projectName: project.name) : ClaudePrompts.refresh(projectName: project.name)
            startingClaude = true
            Task {
                let installed = await Task.detached(priority: .userInitiated) { ClaudeLauncher.isInstalled() }.value
                startingClaude = false
                // Another folder was opened meanwhile: this one's prompt no longer applies.
                guard model.project?.root.path == project.root.path else { return }
                guard installed else {
                    promptToCopy = PromptToCopy(
                        title: "Can't find Claude Code",
                        detail: Self.missingClaudeDetail(projectName: project.name),
                        text: prompt)
                    return
                }
                do {
                    openTab(project.root, ClaudeLauncher.command(promptFile: try ClaudeLauncher.writePrompt(prompt)))
                } catch {
                    promptToCopy = PromptToCopy(
                        title: "Can't save the prompt",
                        detail: Self.unsavedPromptDetail(error: error.localizedDescription, projectName: project.name),
                        text: prompt)
                }
            }
        }

        private func emptyState(_ project: Model.Project) -> some View {
            VStack(spacing: 12) {
                Text(Self.emptyTitle(project)).font(.system(size: 17, weight: .semibold))
                Text("A flow map shows how this project's systems pass data and control. Claude can draft one from the code.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button(startingClaude ? "Starting Claude…" : "Draft with Claude") { launch(.draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRunClaude)
                if let reason = project.claudeBlockReason {
                    Text(reason).font(.system(size: 11)).foregroundColor(.orange).multilineTextAlignment(.center)
                    Button("Change…", action: chooseFolder)
                }
            }
            .font(.system(size: 13))
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private func errorList(_ errors: [FlowError]) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("The flow map has problems").font(.system(size: 15, weight: .semibold))
                Text(FlowFile.relativePath).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                            Text(error.description)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.orange)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text("Fix the file and the map reloads by itself.").font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }

        private func copySheet(_ prompt: PromptToCopy) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(prompt.title).font(.system(size: 15, weight: .semibold))
                Text(prompt.detail).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    Text(prompt.text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
                HStack {
                    Spacer()
                    // Esc closes; Return copies.
                    Button("Done") { promptToCopy = nil }.keyboardShortcut(.cancelAction)
                    Button("Copy Prompt") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prompt.text, forType: .string)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 560)
        }

        // MARK: Copy and rules

        static func ageText(_ age: HealthReport.Age) -> String? {
            switch age {
            case .hidden: nil
            case .notCommitted: "Map not committed yet"
            case .commits(0): "Map up to date"
            case .commits(1): "Map updated 1 commit ago"
            case .commits(let n): "Map updated \(n) commits ago"
            }
        }

        static func healthText(_ report: HealthReport) -> String {
            switch report.issueCount {
            case 0: "Map healthy"
            case 1: "1 issue"
            case let n: "\(n) issues"
            }
        }

        static func unmappedText(_ count: Int) -> String? {
            switch count {
            case 0: nil
            case 1: "1 unmapped file"
            case let n: "\(n) unmapped files"
            }
        }

        static func centerMessage(for state: Model.State) -> String? {
            switch state {
            case .idle, .ready, .noFlowFile, .invalid: nil
            case .noProject: "This terminal hasn't reported a working directory."
            case .loading: "Reading the flow map…"
            case .failed(let message): message
            }
        }

        /// Plain text: the copy sheet doesn't render Markdown.
        static func missingClaudeDetail(projectName: String) -> String {
            "Claude Code isn't on your shell's PATH. Install it, or paste this prompt into a Claude session in \(projectName)."
        }

        static func unsavedPromptDetail(error: String, projectName: String) -> String {
            "\(error) Paste this prompt into a Claude session in \(projectName) instead."
        }

        static func emptyTitle(_ project: Model.Project) -> String {
            "No flow map for \(project.name) yet"
        }

        /// Why Refresh is off, shown beside it in the header. The empty state shows its own reason under Draft.
        static func refreshBlockedCaption(in state: Model.State) -> String? {
            if case .ready(let project, _) = state { return project.claudeBlockReason }
            return nil
        }

        /// Draft (no flow file) and Refresh (a map) need a checked folder that nothing blocks. While loading, a
        /// nil reason means "not checked yet", not "allowed".
        static func canRunClaude(in state: Model.State) -> Bool {
            switch state {
            case .noFlowFile(let project), .ready(let project, _): project.claudeBlockReason == nil
            case .idle, .noProject, .loading, .invalid, .failed: false
            }
        }
    }
}
