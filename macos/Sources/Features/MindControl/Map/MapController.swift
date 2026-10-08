import AppKit
import Combine
import QuartzCore

extension MindControl {
    /// One flow, as the side panel lists it.
    struct FlowRow: Equatable, Identifiable {
        let id: String
        let from: String
        let to: String
        let carries: String
        let kind: FlowMap.Kind
        let when: String?
        let status: FeatureStep.Status
        let via: String?
        let location: SourceLocation?
    }

    enum SidePanelContent: Equatable {
        case none
        case feature(name: String, groups: [StepGroup], unknown: [String])
        case system(name: String, summary: String?, incoming: [FlowRow], outgoing: [FlowRow], files: [String])
        case part(name: String, system: String, file: String?, stale: Bool, incoming: [FlowRow], outgoing: [FlowRow])
        case arrow(rows: [FlowRow])
        case health(HealthReport)
    }

    /// Interaction state for one open panel: view, feature, selection, focus, search, drags and transitions.
    /// Turns it into a scene for the renderer and content for the side panel.
    @MainActor
    final class MapController: ObservableObject {
        enum Selection: Equatable {
            case box(String)
            case arrow(String)
        }

        enum Focus: Equatable {
            case system(String)
            case feature(String)
        }

        private struct Transition {
            let from: MapLayout
            let to: MapLayout
            let start: CFTimeInterval
            let duration: CFTimeInterval
        }

        /// What the label plan depends on besides the scene.
        private struct LabelKey: Equatable {
            let camera: PanZoomCamera
            let viewSize: CGSize
            let scene: Int
        }

        static let transitionDuration: CFTimeInterval = 0.35
        static let pulseDuration: CFTimeInterval = 1.2
        /// How long typing must pause before the query is searched, in nanoseconds.
        static let searchPause: UInt64 = 120_000_000

        @Published var mode: SceneStyle.Mode = .map { didSet { refresh() } }
        @Published var showControl = true { didSet { refresh() } }
        @Published private(set) var selectedFeature: String? { didSet { updateFocusTarget() } }
        /// Setting it (to anything) ends a feature step's highlight.
        @Published private(set) var selection: Selection? {
            didSet {
                stepHighlight = nil
                updateFocusTarget()
            }
        }
        /// What F or the Focus button opens: the selected system (or a part's system), else the selected feature.
        /// Nil when there's nothing to focus or it has nothing to draw. Worked out when the selection, feature or
        /// map changes, since that builds a focus layout; reading it is free.
        @Published private(set) var focusTarget: Focus?
        /// How many times `focusTarget` was worked out.
        private(set) var focusTargetChecks = 0
        @Published private(set) var focus: Focus?
        /// Searched off the main actor once typing pauses for `searchDelay`; clearing it clears `results` at once.
        @Published var query = "" { didSet { if query != oldValue { scheduleSearch(after: searchDelay) } } }
        @Published private(set) var results: [SearchResult] = []
        /// Bumped to ask the search field to take keyboard focus.
        @Published private(set) var searchRequest = 0

        var onClose: () -> Void = {}
        /// Gives the map view keyboard focus again, so Esc, F and typing reach it (set by the view).
        var focusMap: () -> Void = {}
        var openFile: (URL, Int?) -> Void = { FileOpener.open($0, line: $1) }

        private(set) var root: URL?
        private(set) var map: FlowMap?
        private(set) var report = HealthReport()
        private(set) var saved: [String: CGPoint] = [:]
        private(set) var baseLayout = MapLayout(boxes: [], arrows: [])
        /// What's drawn: the main map, a focus layout, or a blend of the two mid-transition.
        private(set) var layout = MapLayout(boxes: [], arrows: []) { didSet { curves = ArrowRouter.curves(for: layout) } }
        private(set) var curves: [String: Curve] = [:]
        /// Bumped by every `refresh()`. Frames that change nothing leave it, the scene and the labels alone.
        private(set) var sceneVersion = 0
        /// How many times labels were planned (a cache skips frames where nothing moved).
        private(set) var labelPlans = 0
        /// Wait after the last keystroke before searching, in nanoseconds.
        var searchDelay: UInt64 = MapController.searchPause

        private var fade: [String: Float] = [:]
        /// The arrow of the selected feature's step last clicked in the side panel. Drawn as selected without
        /// becoming the selection, so the panel keeps listing the feature's steps.
        private var stepHighlight: String?
        private var transition: Transition?
        private var pulse: (id: String, until: CFTimeInterval)?
        private var searchIndex: FlowSearch?
        private var indexBuild: Task<Void, Never>?
        private var indexToken = 0
        private var searchTask: Task<Void, Never>?
        private var filesBySystem: [String: [String]] = [:]
        private var labelCache: (key: LabelKey, labels: [PlacedLabel])?
        private var cameraBeforeFocus: PanZoomCamera?
        private var localCamera = PanZoomCamera()
        private var loadedGeneration: Int?
        private(set) weak var renderer: Renderer?
        /// Zero until the view first lays out; the first real size fits the map.
        var viewSize = CGSize.zero

        /// Setting the camera (a pan, a zoom, a jump) stops any camera animation, which would otherwise
        /// overwrite it on the next frame.
        var camera: PanZoomCamera {
            get { renderer?.camera ?? localCamera }
            set {
                if let renderer {
                    renderer.cancelCameraAnimation()
                    renderer.camera = newValue
                } else {
                    localCamera = newValue
                }
            }
        }

        // MARK: Loading

        /// Shows a load. A repeat of the shown generation for the same folder changes nothing. Roots are compared
        /// by path: the model's end in "/", others may not.
        func show(_ loaded: Model.Loaded, root: URL) {
            let sameRoot = self.root?.path == root.path
            guard loaded.generation != loadedGeneration || !sameRoot else { return }
            let firstShow = map == nil || !sameRoot
            if !sameRoot {
                // Another project: nothing chosen in the last one applies.
                selection = nil
                selectedFeature = nil
                focus = nil
                cameraBeforeFocus = nil
                pulse = nil
                query = ""
                // The old project's index must not answer while the new one builds.
                searchIndex = nil
                results = []
            }
            loadedGeneration = loaded.generation
            self.root = root
            map = loaded.map
            report = loaded.report
            saved = loaded.saved
            var files: [String: [String]] = [:]
            for (file, owner) in loaded.report.owners { files[owner, default: []].append(file) }
            filesBySystem = files.mapValues { $0.sorted() }
            rebuildSearchIndex(map: loaded.map, report: loaded.report)
            baseLayout = FlowLayout.layout(map: loaded.map, broken: loaded.report.brokenFlows, saved: saved)
            if let id = selectedFeature, loaded.map.feature(id) == nil { selectedFeature = nil }
            transition = nil
            fade = [:]
            if let current = focus, let focused = focusLayout(current) {
                layout = focused
            } else {
                focus = nil
                cameraBeforeFocus = nil
                layout = baseLayout
            }
            if let current = selection, !exists(current) { selection = nil }
            if let step = stepHighlight, !exists(.arrow(step)) { stepHighlight = nil }
            updateFocusTarget()
            refresh()
            // The spec fits the whole map on open and on every reload; focus views keep their own framing.
            if focus == nil { fit(animated: !firstShow) }
        }

        func attach(_ renderer: Renderer) {
            let current = camera
            if let old = self.renderer, old !== renderer { old.beforeFrame = nil }
            self.renderer = renderer
            renderer.camera = current
            renderer.beforeFrame = { [weak self] now in self?.tick(now) }
            refresh()
        }

        /// Frames what's shown (or being moved to). An empty layout has nothing to frame and leaves the camera.
        func fit(animated: Bool) {
            let bounds = (transition?.to ?? layout).bounds
            guard !bounds.isNull else { return }
            move(to: PanZoomCamera.fitting(bounds, in: viewSize), animated: animated)
        }

        private func move(to target: PanZoomCamera, animated: Bool) {
            if animated, let renderer { renderer.animateCamera(to: target) } else { camera = target }
        }

        // MARK: Scene

        var style: SceneStyle {
            var style = SceneStyle()
            style.mode = mode
            style.showControl = showControl
            if let id = selectedFeature, let map, let index = map.features.firstIndex(where: { $0.id == id }) {
                style.litFlows = Set(map.features[index].route)
                style.featureColor = Palette.feature(index)
            }
            switch selection {
            case .box(let id), .arrow(let id): style.selected = id
            case nil: style.selected = stepHighlight
            }
            style.pulsed = pulse?.id
            style.fade = fade
            return style
        }

        /// Rebuilds the scene. Only called when something changed: never on an idle frame.
        func refresh() {
            sceneVersion += 1
            renderer?.setScene(FlowScene.build(layout: layout, curves: curves, report: report, style: style))
        }

        /// Called by the renderer at the start of every frame.
        func tick(_ now: CFTimeInterval) {
            var changed = false
            if let pulse, now >= pulse.until {
                self.pulse = nil
                changed = true
            }
            if let transition {
                let t = min(1, max(0, (now - transition.start) / transition.duration))
                if t >= 1 {
                    layout = transition.to
                    fade = [:]
                    self.transition = nil
                } else {
                    let eased = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
                    (layout, fade) = Self.blend(from: transition.from, to: transition.to, t: eased)
                }
                changed = true
            }
            if changed { refresh() }
        }

        /// Boxes in both layouts slide between their rects; boxes only in `from` fade out, only in `to` fade in.
        static func blend(from: MapLayout, to: MapLayout, t: CGFloat) -> (MapLayout, [String: Float]) {
            var fade: [String: Float] = [:]
            var boxes: [MapLayout.Box] = []
            var fromBoxes: [String: MapLayout.Box] = [:]
            for box in from.boxes where fromBoxes[box.id] == nil { fromBoxes[box.id] = box }
            let toIDs = Set(to.boxes.map(\.id))
            for box in from.boxes where !toIDs.contains(box.id) {
                boxes.append(box)
                fade[box.id] = Float(1 - t)
            }
            for var box in to.boxes {
                if let old = fromBoxes[box.id] {
                    box.rect = CGRect(x: old.rect.minX + (box.rect.minX - old.rect.minX) * t,
                                      y: old.rect.minY + (box.rect.minY - old.rect.minY) * t,
                                      width: old.rect.width + (box.rect.width - old.rect.width) * t,
                                      height: old.rect.height + (box.rect.height - old.rect.height) * t)
                } else {
                    fade[box.id] = Float(t)
                }
                boxes.append(box)
            }
            return (MapLayout(boxes: boxes, arrows: to.arrows, fixedLevel: to.fixedLevel), fade)
        }

        // MARK: Features, focus, escape

        /// Selecting the selected feature again clears it. Choosing one clears a selected box or arrow, so the
        /// side panel opens the feature's steps.
        func selectFeature(_ id: String?) {
            selectedFeature = id == selectedFeature ? nil : id
            if selectedFeature != nil { selection = nil }
            stepHighlight = nil
            refresh()
        }

        var breadcrumb: [String] {
            var path = [root?.lastPathComponent ?? ""]
            switch focus {
            case .system(let id): path.append(map?.system(id)?.name ?? id)
            case .feature(let id): path.append(map?.feature(id)?.name ?? id)
            case nil: break
            }
            return path
        }

        private func focusLayout(_ target: Focus) -> MapLayout? {
            guard let map else { return nil }
            switch target {
            case .system(let id): return FocusLayout.system(id, map: map, broken: report.brokenFlows)
            case .feature(let id): return FocusLayout.feature(id, map: map, broken: report.brokenFlows)
            }
        }

        private func updateFocusTarget() {
            focusTargetChecks += 1
            let target: Focus?
            if case .box(let id) = selection, let system = systemID(of: id) {
                target = .system(system)
            } else if let feature = selectedFeature {
                target = .feature(feature)
            } else {
                target = nil
            }
            let next = target.flatMap { focusLayout($0) == nil ? nil : $0 }
            if next != focusTarget { focusTarget = next }
        }

        /// F: focus `focusTarget`, if any.
        func enterFocus() {
            if let target = focusTarget { enterFocus(target) }
        }

        /// Does nothing when the subject has nothing to draw.
        func enterFocus(_ target: Focus) {
            guard let next = focusLayout(target) else { return }
            if focus == nil { cameraBeforeFocus = camera }
            focus = target
            startTransition(to: next)
            move(to: PanZoomCamera.fitting(next.bounds, in: viewSize), animated: true)
        }

        func exitFocus() {
            guard focus != nil else { return }
            focus = nil
            startTransition(to: baseLayout)
            if let back = cameraBeforeFocus {
                move(to: back, animated: true)
            } else if !baseLayout.bounds.isNull {
                move(to: PanZoomCamera.fitting(baseLayout.bounds, in: viewSize), animated: true)
            }
            cameraBeforeFocus = nil
        }

        private func leaveFocus() {
            if focus != nil { exitFocus() }
        }

        private func startTransition(to next: MapLayout) {
            guard renderer != nil else {
                transition = nil
                layout = next
                fade = [:]
                refresh()
                return
            }
            transition = Transition(from: layout, to: next, start: CACurrentMediaTime(), duration: Self.transitionDuration)
        }

        /// Esc: clear search, then leave focus, then clear the feature or selection. False means close MindControl.
        func escape() -> Bool {
            if !query.isEmpty {
                query = ""
                return true
            }
            if focus != nil {
                exitFocus()
                return true
            }
            if selectedFeature != nil || selection != nil {
                selectedFeature = nil
                selection = nil
                refresh()
                return true
            }
            return false
        }

        // MARK: Search

        func beginSearch(with text: String) {
            query += text
            searchRequest += 1
        }

        /// Enter in the search field: search now (results wait for typing to pause), then go to the first result.
        func submitSearch() {
            flushSearch()
            if let first = results.first { navigate(to: first) }
        }

        /// Searches the query now with the index as it stands, skipping the typing pause (Enter in the field).
        func flushSearch() {
            searchTask?.cancel()
            searchTask = nil
            results = searchIndex?.search(query) ?? []
        }

        /// Returns once the index build and any pending search have finished.
        func searchSettled() async {
            await indexBuild?.value
            await searchTask?.value
        }

        /// Builds the index off the main actor, once per load, then searches the current query against it.
        /// The previous index keeps answering until the new one is ready.
        private func rebuildSearchIndex(map: FlowMap, report: HealthReport) {
            indexToken += 1
            let token = indexToken
            indexBuild = Task { [weak self] in
                let index = await Task.detached(priority: .userInitiated) { FlowSearch(map: map, report: report) }.value
                guard let self, token == self.indexToken else { return }
                self.searchIndex = index
                self.scheduleSearch(after: 0)
            }
        }

        private func scheduleSearch(after delay: UInt64) {
            searchTask?.cancel()
            let text = query
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                searchTask = nil
                results = []
                return
            }
            searchTask = Task { [weak self] in
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                // No index yet: its build searches the query when it lands.
                guard !Task.isCancelled, let index = self?.searchIndex else { return }
                let found = await Task.detached(priority: .userInitiated) { index.search(text) }.value
                guard !Task.isCancelled, let self, self.query == text else { return }
                self.results = found
            }
        }

        /// Enter on a result: leave focus, move to it, select and pulse it.
        /// A result whose subject the current map lacks (one left from an older index) is ignored.
        func navigate(to result: SearchResult) {
            guard let map, Self.contains(result.target, map: map, layout: baseLayout) else { return }
            query = ""
            leaveFocus()
            switch result.target {
            case .feature(let id):
                selectedFeature = id
                selection = nil
                frameFeature(id)
            case .system(let id):
                reveal(id, minZoom: 0.6)
            case .part(let key):
                reveal(key, minZoom: 1.3)
            case .file(_, let system?):
                reveal(system, minZoom: 0.6)
            case .file(_, nil):
                selection = nil
                mode = .health
            }
            refresh()
        }

        private func frameFeature(_ id: String) {
            guard let map, let feature = map.feature(id) else { return }
            let systems = Set(feature.route.compactMap { map.flow($0) }.flatMap { [$0.from.system, $0.to.system] })
            let rect = baseLayout.boxes.filter { $0.kind == .system && systems.contains($0.id) }.reduce(CGRect.null) { $0.union($1.rect) }
            if !rect.isNull { move(to: PanZoomCamera.fitting(rect, in: viewSize), animated: true) }
        }

        /// Select and pulse a box on the main map, and move to it.
        private func reveal(_ id: String, minZoom: CGFloat) {
            guard let box = baseLayout.box(id) else { return }
            selection = .box(id)
            pulse = (id, CACurrentMediaTime() + Self.pulseDuration)
            move(to: PanZoomCamera(center: CGPoint(x: box.rect.midX, y: box.rect.midY), zoom: max(camera.zoom, minZoom)), animated: true)
        }

        /// A side panel step was clicked: move to that flow's arrow. A step on the selected feature's route is
        /// highlighted and the panel keeps the feature's steps; any other flow becomes the selection. A flow the
        /// focus view doesn't draw is shown on the main map. A hidden control arrow is shown. Zooms past the
        /// systems-to-parts cross-fade so the part-level arrow shows in full.
        func goToStep(_ flowID: String) {
            let id = "flow:\(flowID)"
            if focus != nil, !(transition?.to ?? layout).arrows.contains(where: { $0.id == id }) { exitFocus() }
            // Mid-transition, aim at where the arrow will be, not where it is.
            let target = transition?.to ?? layout
            guard let curve = transition == nil ? curves[id] : ArrowRouter.curves(for: target)[id],
                  let arrow = target.arrows.first(where: { $0.id == id }) else { return }
            if let feature = selectedFeature.flatMap({ map?.feature($0) }), feature.route.contains(flowID) {
                selection = nil
                stepHighlight = id
            } else {
                selection = .arrow(id)
            }
            if arrow.kind == .control, !showControl { showControl = true }
            let zoom = target.fixedLevel ? camera.zoom : max(camera.zoom, ZoomLevels.systemsToParts.upperBound)
            move(to: PanZoomCamera(center: curve.mid, zoom: zoom), animated: true)
            refresh()
        }

        /// Health view: move to whatever an issue is about. A subject is a bare id, unique only within its own
        /// list (a flow and a system may share one), so the issue's kind says which list it's from.
        func goToIssue(_ issue: HealthReport.Issue) {
            let subject = issue.subject
            switch issue.kind {
            case .pathTie:
                openSource(subject)
                return
            case .staleAnchor:
                leaveFocus()
                reveal(subject, minZoom: 1.3)
            case .staleVia, .unverified:
                goToStep(subject)
            case .unknownReference:
                // A flow naming an unknown system or part is broken; a feature naming an unknown flow is not.
                if report.brokenFlows.contains(subject), let flow = map?.flow(subject) {
                    leaveFocus()
                    if let end = [flow.from, flow.to].lazy.compactMap({ self.drawnBox(for: $0) }).first {
                        reveal(end, minZoom: end.contains(".") ? 1.3 : 0.6)
                    }
                } else if map?.feature(subject) != nil {
                    leaveFocus()
                    selectedFeature = subject
                    selection = nil
                    frameFeature(subject)
                } else if map?.flow(subject) != nil {
                    goToStep(subject)
                }
            case .density:
                leaveFocus()
                // "map" is the whole map, unless a system with that id is the one with too many parts.
                if let system = map?.system(subject), system.parts.count > FlowCheck.maxPartsPerSystem {
                    reveal(subject, minZoom: 0.6)
                } else if subject == "map" {
                    fit(animated: true)
                } else {
                    reveal(subject, minZoom: 0.6)
                }
            }
            refresh()
        }

        /// The main-map box for an endpoint: its part, else its system; nil when neither exists.
        private func drawnBox(for endpoint: FlowMap.Endpoint) -> String? {
            if baseLayout.box(endpoint.description) != nil { return endpoint.description }
            return baseLayout.box(endpoint.system) != nil ? endpoint.system : nil
        }

        func open(_ location: SourceLocation) {
            guard let root else { return }
            openFile(root.appendingPathComponent(location.file), location.line)
        }

        func openSource(_ path: String) {
            guard let root else { return }
            openFile(root.appendingPathComponent(path), nil)
        }

        // MARK: Pointer input (view points, top-left origin)

        func hit(at point: CGPoint) -> FlowPicking.Hit? {
            FlowPicking.hit(camera.toWorld(point, viewSize: viewSize), layout: layout, curves: curves, zoom: camera.zoom, showControl: showControl)
        }

        func click(at point: CGPoint) {
            switch hit(at: point) {
            case .box(let id): selection = .box(id)
            case .arrow(let id): selection = .arrow(id)
            case nil: selection = nil
            }
            refresh()
        }

        func doubleClick(at point: CGPoint) {
            switch hit(at: point) {
            case .box(let id) where id.contains("."):
                if let file = report.anchorFiles[id] { openSource(file) }
            case .box(let id):
                selection = .box(id)
                enterFocus(.system(id))
            case .arrow(let id):
                guard let flowID = layout.arrows.first(where: { $0.id == id })?.flowIDs.first,
                      let location = report.viaLocations[flowID] else { return }
                open(location)
            case nil:
                break
            }
        }

        func zoom(by factor: CGFloat, about point: CGPoint) {
            var next = camera
            next.zoom(by: factor, about: point, viewSize: viewSize)
            camera = next
        }

        func pan(by delta: CGSize) {
            var next = camera
            next.pan(byScreen: delta)
            camera = next
        }

        /// The system a mouse-down at `point` would move: the system itself, a part's system, or the system an
        /// arrow between two of its own parts sits in. Nil when that can't be dragged (then the drag pans).
        func dragTarget(at point: CGPoint) -> String? {
            let system: String?
            switch hit(at: point) {
            case .box(let id):
                system = systemID(of: id)
            case .arrow(let id):
                guard let arrow = layout.arrows.first(where: { $0.id == id }), let from = systemID(of: arrow.from),
                      from == systemID(of: arrow.to) else { return nil }
                system = from
            case nil:
                system = nil
            }
            guard let system, canDrag(system) else { return nil }
            return system
        }

        func canDrag(_ id: String) -> Bool {
            focus == nil && baseLayout.box(id)?.kind == .system
        }

        func drag(system id: String, byScreen delta: CGSize) {
            guard canDrag(id), let rect = baseLayout.box(id)?.rect, let map else { return }
            renderer?.cancelCameraAnimation()
            saved[id] = CGPoint(x: rect.minX + delta.width / camera.zoom, y: rect.minY + delta.height / camera.zoom)
            baseLayout = FlowLayout.layout(map: map, broken: report.brokenFlows, saved: saved)
            // A transition back from focus would overwrite the dragged layout next frame.
            transition = nil
            fade = [:]
            layout = baseLayout
            refresh()
        }

        func endDrag(_ id: String) {
            guard let root else { return }
            try? LayoutStore.write(saved, root: root)
        }

        /// Labels for the current camera. Planned again only when the camera, view size or scene changed.
        func labels() -> [PlacedLabel] {
            let key = LabelKey(camera: camera, viewSize: viewSize, scene: sceneVersion)
            if let cache = labelCache, cache.key == key { return cache.labels }
            labelPlans += 1
            let planned = LabelPlanner.plan(FlowLabels.candidates(layout: layout, curves: curves, camera: camera, viewSize: viewSize,
                                                                  litFlows: style.litFlows, showControl: showControl),
                                            viewport: viewSize, measure: LabelOverlayView.measure)
            labelCache = (key, planned)
            return planned
        }

        // MARK: Side panel

        var sidePanel: SidePanelContent {
            guard let map else { return .none }
            if mode == .health, selection == nil { return .health(report) }
            switch selection {
            case .arrow(let id):
                let ids = layout.arrows.first { $0.id == id }?.flowIDs ?? []
                return .arrow(rows: ids.compactMap(row(for:)))
            case .box(let id) where !id.hasPrefix("zone:") && id.contains("."):
                guard let systemID = systemID(of: id), let system = map.system(systemID),
                      let part = system.part(String(id.dropFirst(systemID.count + 1))) else { return .none }
                let touching = map.flows.filter { $0.from.description == id || $0.to.description == id }
                return .part(name: part.name, system: system.name, file: report.anchorFiles[id], stale: report.staleParts.contains(id),
                             incoming: touching.filter { $0.to.description == id }.compactMap { row(for: $0.id) },
                             outgoing: touching.filter { $0.from.description == id }.compactMap { row(for: $0.id) })
            case .box(let id):
                guard let system = map.system(id) else { return .none }
                return .system(name: system.name, summary: system.summary,
                               incoming: map.flows.filter { $0.to.system == id && $0.from.system != id }.compactMap { row(for: $0.id) },
                               outgoing: map.flows.filter { $0.from.system == id && $0.to.system != id }.compactMap { row(for: $0.id) },
                               files: filesBySystem[id] ?? [])
            case nil:
                break
            }
            if let id = selectedFeature, let feature = map.feature(id) {
                let steps = FeatureSteps.groups(for: feature, map: map, report: report)
                return .feature(name: feature.name, groups: steps.groups, unknown: steps.unknown)
            }
            return .none
        }

        func row(for flowID: String) -> FlowRow? {
            guard let map, let flow = map.flow(flowID), !report.brokenFlows.contains(flowID) else { return nil }
            let status: FeatureStep.Status = report.staleFlows.contains(flowID) ? .stale
                : report.unverifiedFlows.contains(flowID) ? .unverified : .ok
            return FlowRow(id: flowID, from: FeatureSteps.name(of: flow.from, in: map), to: FeatureSteps.name(of: flow.to, in: map),
                           carries: flow.carries, kind: flow.kind, when: flow.when, status: status, via: flow.via,
                           location: report.viaLocations[flowID])
        }

        // MARK: Helpers

        private static func contains(_ target: SearchResult.Target, map: FlowMap, layout: MapLayout) -> Bool {
            switch target {
            case .feature(let id): return map.feature(id) != nil
            case .system(let id): return map.system(id) != nil
            case .part(let key): return layout.box(key)?.kind == .part
            case .file(_, let system?): return map.system(system) != nil
            case .file(_, nil): return true
            }
        }

        func systemID(of boxID: String) -> String? {
            guard !boxID.hasPrefix("zone:") else { return nil }
            return boxID.split(separator: ".").first.map(String.init)
        }

        private func exists(_ selection: Selection) -> Bool {
            switch selection {
            case .box(let id): return layout.box(id) != nil
            case .arrow(let id): return layout.arrows.contains { $0.id == id }
            }
        }
    }
}
