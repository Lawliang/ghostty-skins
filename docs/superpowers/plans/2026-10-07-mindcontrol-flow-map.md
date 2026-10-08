# MindControl Flow Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace MindControl's 3D file/import map with a 2D Metal data-flow map. The map is read from a project's `.mindcontrol/flow.json`, checked against the code, and laid out as zones → systems → parts. It has Map and Health views, Focus views, search, and Draft / Refresh with Claude.

**Architecture:** Each step is a small pure-Swift unit, and each feeds the next:

1. Read the flow file (`FlowSource` → `FlowFile`).
2. Check it against the code (`FlowCheck`).
3. Lay it out (`FlowLayout` / `FocusLayout` → `MapLayout` + `ArrowRouter`).
4. Turn it into GPU instances (`FlowScene`) for a Metal renderer that keeps the existing bloom and composite passes.

A `MapController` (one per open panel) holds the interaction state: view, feature, selection, focus, search, drag and transitions. `Model` (one per window) loads and watches the project.

**Tech Stack:** Swift 5 mode, SwiftUI + AppKit, Metal (MetalKit), Foundation `JSONSerialization`, `/usr/bin/git`, Swift Testing (`import Testing`).

**Spec:** `docs/superpowers/specs/2026-10-07-mindcontrol-flow-map-design.md`

## Global Constraints

- Worktree: `~/projectrepos/lostty/.claude/worktrees/mindcontrol`, branch `mindcontrol`. All paths below are relative to it.
- Swift 5 language mode, macOS 13 deployment target. The Xcode project uses synchronized folders, so new files under `macos/Sources` and `macos/Tests` are picked up automatically. Never edit `project.pbxproj`.
- Everything lives in the `enum MindControl` namespace (`extension MindControl { … }`), files wrapped in nothing else. Test files start with `#if os(macOS)` / `@testable import Ghostty` and end with `#endif`, like the existing ones.
- C structs shared with Metal live in `macos/Sources/Features/MindControl/Renderer/ShaderTypes.h` (already imported by the bridging header), are prefixed `MC`, and macros `MC_`. Metal functions are prefixed `mc`. That header must stay valid C and valid Metal.
- No new dependencies. JSON via Foundation, git via `/usr/bin/git`.
- Run tests with `macos/skins-test.sh <Suite>` (one suite) or `.superpowers/mc-test.sh <Suite> <Suite>…` (prints per-suite pass/fail counts). Full suite: `cd macos && ./skins-test.sh`, then `grep -c "passed" build/last-test.log` and `grep -E "✘|failed" build/last-test.log`.
- Build the app: `cd macos && env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/build" build > build/last-build.log 2>&1; grep -E "error:|BUILD (SUCCEEDED|FAILED)" build/last-build.log`.
- Run the app: `open -n macos/build/Debug/Ghostty.app` (bundle `com.lawliang.ghostty-skins.debug`). Kill only the debug copy: `pkill -f "worktrees/mindcontrol/macos/build/Debug/Ghostty.app/Contents/MacOS"`.
- Never touch `/Applications/Lostty.app`. Never create a GitHub issue or PR. Never push unless the user asks. Stage files by name, never `git add -A`. Never run commands through `sh -c`.
- Commit messages start `mindcontrol: ` and end with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Flow file: `.mindcontrol/flow.json`; layout file: `.mindcontrol/layout.json`; `version` is 1.
- Density limits: more than 20 systems, more than 8 parts in one system, more than 60 flows.
- Draft and Refresh are disabled for the home folder, `/`, and folders outside git.
- Upkeep rule text added by Draft: "When you change how data or control moves between systems, update `.mindcontrol/flow.json`."
- User-facing copy is plain and active ("No flow map for arca yet", "Map healthy", "7 issues", "Map updated 23 commits ago", "Map not committed yet").

## Review Focus

1. **A flow file written by Claude with small mistakes** (a trailing comma, a wrong `kind`, a typo'd endpoint). The user should get a readable error list with line numbers, or a map with only the broken arrow missing, never a crash or a blank panel. Pinned by `FlowFileTests.trailingCommaReportsLine` and `ModelTests.brokenEndpointStillDrawsTheRest`.
2. **A large or tangled map** (cycles across zones, a system with no flows, a flow from a system to itself, a part-to-part flow inside one system). Layout must finish, stay deterministic, and not overlap boxes within a zone. Pinned by `FlowLayoutTests.selfFlowAndIsolatedSystemLayOut` and `FlowLayoutTests.zonesOrderedByDataFlowEvenWithACrossZoneCycle`.
3. **Editing `flow.json` while the panel is open,** including Claude writing it in several steps. The map reloads, and a half-written file shows errors, then recovers on the next write. Writing `layout.json` after a drag must not trigger a reload loop. Pinned by `FlowWatcherTests.reportsChangeToFlowFileOnly`.
4. **Projects that aren't Arca:** no Swift files, TypeScript-only parts with file anchors, `paths` patterns that match nothing, and an empty `features`. Pinned by `FlowCheckTests.fileAnchorsWorkWithoutSwift` and `FlowCheckTests.patternMatchingNothingIsHarmless`.
5. **Opening on the wrong folder** (home, `/`, a non-git folder, or a folder chosen with Change…). The Claude buttons are disabled with the reason, and an existing map still shows. Pinned by `ProjectGuardTests` and `ModelTests.overrideReplacesTerminalFolderUntilClosed`.

---

## File Map

Created (under `macos/Sources/Features/MindControl/`):

| File | Responsibility |
|---|---|
| `Flow/FlowMap.swift` | Decoded flow file types |
| `Flow/FlowFile.swift` | Parse and validate `flow.json`, with line-numbered errors |
| `Flow/Glob.swift` | `*` / `**` path patterns and their specificity |
| `Flow/PathOwnership.swift` | Which system owns a source file |
| `Flow/Git.swift` | Run `/usr/bin/git` and capture output |
| `Flow/FlowSource.swift` | Read flow, layout and source files from the working tree or a git revision |
| `Flow/FlowCheck.swift` | `HealthReport`: stale anchors and vias, unknown references, ties, unmapped, density |
| `Flow/FlowAge.swift` | Commits touching mapped code since `flow.json` was committed |
| `Flow/FeatureSteps.swift` | A feature's route as numbered steps grouped by `when` |
| `Flow/ProjectGuard.swift` | Whether Draft/Refresh are allowed for a folder |
| `Flow/FlowWatcher.swift` | Reload when `.mindcontrol/flow.json` changes |
| `Layout/MapLayout.swift` | Boxes, arrow specs, metrics, zoom levels |
| `Layout/Layering.swift` | Deterministic layered layout (cycle break, ranks, barycenter order) |
| `Layout/FlowLayout.swift` | Main map layout: zones, systems, parts, saved positions |
| `Layout/ArrowRouter.swift` | Bézier curves for arrow specs |
| `Layout/FocusLayout.swift` | System focus and feature focus layouts |
| `Layout/LayoutStore.swift` | Read and write `layout.json` |
| `Search/FlowSearch.swift` | Search index and ranking |
| `Renderer/PanZoomCamera.swift` | 2D camera |
| `Renderer/FlowScene.swift` | Layout + style → GPU instances; palette |
| `Renderer/FlowPicking.swift` | 2D hit testing |
| `Renderer/Shaders/Boxes.metal`, `Arrows.metal`, `Markers.metal` | Box, arrow, pulse, marker shaders |
| `Renderer/FlowMTKView.swift` | Input handling and label overlay host |
| `Labels/RectGrid.swift` | Overlap grid (moved out of `LabelPlanner.swift`) |
| `Labels/FlowLabels.swift` | Label candidates from layout and camera |
| `Map/MapController.swift` | Interaction state for one open panel |
| `Map/SidePanel.swift` | Side panel views |
| `Map/MapChrome.swift` | Header, feature bar, search, health indicator |
| `Claude/ClaudePrompts.swift` | Draft and Refresh prompts |
| `Claude/ClaudeLauncher.swift` | Availability check and launch command |
| `Claude/FileOpener.swift` | Open a file, at a line when the editor is Xcode |

Rewritten: `MindControl.swift`, `MindControlModel.swift`, `MindControlPanel.swift`, `Renderer/Renderer.swift`, `Renderer/Pipelines.swift`, `Renderer/ShaderTypes.h`, `Renderer/Shaders/ShaderCommon.h`, `Labels/LabelPlanner.swift`, `Labels/LabelOverlayView.swift`, `MINDCONTROL.md`.

Kept as they are: `Data/ProjectScanner.swift`, `Data/SourceFilter.swift`, `Data/Parsers/ParserSupport.swift`, `Renderer/BloomPass.swift`, `Renderer/Shaders/Bloom.metal`, `Renderer/Shaders/Composite.metal`.

Trimmed: `Data/Parsers/SwiftSymbols.swift` keeps only `declaredTypes`.

Deleted (Task 2): `Data/ConeTreeLayout.swift`, `Data/Relaxation.swift`, `Data/Graph.swift`, `Data/Graph+Stress.swift`, `Data/DependencyScanner.swift`, `Data/Parsers/{MarkdownLinks,PythonImports,ScriptImports,ZigImports}.swift`, `Inspection/` (all), `MindControlLegend.swift`, `Renderer/{GraphBuffers,MatrixMath,OrbitCamera,Picking,MetalGraphView}.swift`, `Renderer/Shaders/{Dust,Edges,Nodes,Signals}.metal`, and the tests `ConeTreeLayoutTests, DensityTests, DependencyScannerTests, GraphBuffersTests, InspectorTests, LabelPerformanceTests, LabelPlannerTests, OrbitCameraTests, ParserTests, PickingTests, RelaxationTests, StressGraphTests`.

Modified outside MindControl: `Features/Extensions/ExtensionSidebarModel.swift` (adds `openTab`), `Features/Extensions/ExtensionSidebarView.swift` (passes it to the panel), `Features/Terminal/TerminalController.swift` (sets it).

Tests created (under `macos/Tests/MindControl/`): `FlowTestSupport.swift`, `FlowFileTests.swift`, `GlobTests.swift`, `PathOwnershipTests.swift`, `FlowSourceTests.swift`, `FlowCheckTests.swift`, `FlowAgeTests.swift`, `FeatureStepsTests.swift`, `LayeringTests.swift`, `FlowLayoutTests.swift`, `ArrowRouterTests.swift`, `FocusLayoutTests.swift`, `LayoutStoreTests.swift`, `FlowSearchTests.swift`, `PanZoomCameraTests.swift`, `FlowSceneTests.swift`, `FlowPickingTests.swift`, `FlowLabelsTests.swift`, `ProjectGuardTests.swift`, `FlowWatcherTests.swift`, `MapControllerTests.swift`, `ClaudeLauncherTests.swift`. `ModelTests.swift` and `RendererTests.swift` are rewritten.

## The Arca example used in tests

`FlowTestSupport.swift` (Task 3) defines `arcaJSON`, a small map shaped like Arca's. Several tests use it:

- zones `ring`, `phone`, `cloud`
- systems `ring` (external, zone ring), `ble` (paths `app/Sources/BLE/**`), `tap` (no parts), `audio` (parts `capture`, `gate`), `agent`, and `openai` (external, zone cloud)
- flows `press`, `event`, `begin`, `pcm`, `check`, `commit`, `discard`, `send`, `reply`
- feature `speech`

---
### Task 1: Investigate the wrong-folder report

The spec's "Wrong-folder investigation": once, MindControl showed the home folder after the user had `cd`'d into Arca. This task reproduces it and finds where the folder report goes wrong. It changes code only if the cause is in Lostty's Swift code.

**Files:**
- Read: `macos/Sources/Features/Terminal/TerminalController.swift` (the `windowDidLoad` sidebar wiring, ~line 1018), `macos/Sources/Ghostty/Ghostty.App.swift` (search `pwdChanged`), `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (search `pwd`)
- Temporary: an `NSLog` in the `sidebar.workingDirectory` closure, removed before the task ends

**Interfaces:**
- Consumes: nothing
- Produces: a ledger line `Task 1: finding: …`, which Task 16 reads. If a code fix is made, the fix and its test.

- [ ] **Step 1: Add temporary logging**

In `TerminalController.windowDidLoad`, replace the `workingDirectory` closure body with:

```swift
sidebar.workingDirectory = { [weak self] in
    let pwd = self?.focusedSurface?.pwd
    NSLog("MindControl pwd: focused=%@ pwd=%@", String(describing: self?.focusedSurface?.id), pwd ?? "nil")
    guard let pwd, !pwd.isEmpty else { return nil }
    return URL(fileURLWithPath: pwd)
}
```

In `Ghostty.App.swift`'s `pwdChanged` handler, add `NSLog("MindControl OSC7: %@", <the new pwd string>)` at its top, using the handler's own variable for the new value.

- [ ] **Step 2: Build and run the debug app**

Run the build command from Global Constraints, then `open -n macos/build/Debug/Ghostty.app`.
Expected: `** BUILD SUCCEEDED **`, and a debug window opens.

- [ ] **Step 3: Reproduce**

In the debug window: `cd ~/projectrepos/arca`, then open the codebase visualizer from the sidebar. Then run:
`log show --last 2m --predicate 'eventMessage CONTAINS "MindControl"' --style compact | tail -20`

If you can't drive the window yourself, ask the user to do those two actions once, then run the `log show` command.

Expected outcomes, one of:
- (a) An `OSC7` line with the arca path appears, and `pwd=` shows arca. The report is fine. Then check whether the panel showed arca. If it didn't, the cause is in MindControl's load or cache: note it, because Task 16's model replaces that code.
- (b) No `OSC7` line after the `cd`. The shell isn't reporting its folder. Run `echo $GHOSTTY_SHELL_INTEGRATION_NO_SUDO; echo $TERM_PROGRAM; typeset -f precmd | head` in that window to see whether Ghostty's shell integration is loaded. The cause is outside Lostty's Swift code.
- (c) An `OSC7` line appears, but `pwd=` is stale or `focused=` names another surface. The cause is in Lostty: follow `pwdChanged` → `surfaceView.pwd` and `focusedSurface` to find where it's lost.

- [ ] **Step 4: Fix only for outcome (c)**

For (c), write a failing test in `macos/Tests/MindControl/` that drives the faulty piece (for example, the function that maps an OSC 7 payload to `pwd`). Watch it fail, fix the code, and watch it pass. For (a) and (b), change no code.

- [ ] **Step 5: Remove the logging and record the finding**

Revert both `NSLog` lines (`git diff` shows only the Step 4 fix, if any). Append to the ledger:
`Task 1: finding: <outcome letter> — <one sentence on the cause> — <fix commit or "no code change">`.

- [ ] **Step 6: Commit (only if Step 4 changed code)**

```bash
git add <the fixed file> <the new test file>
git commit -m "mindcontrol: <what the fix does>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Remove the 3D map and leave a background-only renderer

This clears the ground. After this task the panel shows the dark background and one line of text, and the tree builds with a green suite.

**Files:**
- Delete: the files listed under "Deleted (Task 2)" in the File Map
- Rewrite: `MindControl.swift`, `MindControlModel.swift`, `MindControlPanel.swift`, `Renderer/Renderer.swift`, `Renderer/Pipelines.swift`, `Renderer/ShaderTypes.h`, `Renderer/Shaders/ShaderCommon.h`, `Labels/LabelOverlayView.swift`
- Create: `Labels/RectGrid.swift`
- Delete: `Labels/LabelPlanner.swift` (it returns in Task 15)
- Trim: `Data/Parsers/SwiftSymbols.swift`, `macos/Tests/MindControl/SwiftSymbolsTests.swift`
- Rewrite: `macos/Tests/MindControl/RendererTests.swift`. Delete `macos/Tests/MindControl/ModelTests.swift` (it returns in Task 16).

**Interfaces:**
- Consumes: nothing
- Produces:
  - `MindControl.Renderer` (`@MainActor final class`, `MTKViewDelegate`):
    - `init(device:) throws`
    - `nonisolated static let hdrFormat`, `outputFormat`
    - `let device`
    - `func encodeFrame(into:output:width:height:pixelScale:time:)`
    - `var onFrame: (() -> Void)?`
  - `MindControl.Pipelines`: `composite`, `bloomPrefilter`, `bloomDownsample`, `bloomUpsample`
  - `MindControl.RectGrid` (unchanged API)
  - `MindControl.PlacedLabel(id: String, text: String, frame: CGRect, fontSize: CGFloat, isBold: Bool, opacity: CGFloat, hasBackground: Bool)`, with `frame` in flipped view points (top-left origin)
  - `MindControl.LabelOverlayView.show(_:)` and `.measure(_:_:_:)`
  - `MindControl.Model` (`@MainActor`, `ObservableObject`) with `func load(pwd: URL?)`, so `ExtensionSidebarModel` still compiles
  - `MindControl.Panel(model:onClose:)`

- [ ] **Step 1: Delete the 3D files**

```bash
cd macos/Sources/Features/MindControl
git rm -q Data/ConeTreeLayout.swift Data/Relaxation.swift Data/Graph.swift Data/Graph+Stress.swift Data/DependencyScanner.swift \
  Data/Parsers/MarkdownLinks.swift Data/Parsers/PythonImports.swift Data/Parsers/ScriptImports.swift Data/Parsers/ZigImports.swift \
  Inspection/InfoCard.swift Inspection/Inspector.swift Inspection/NodeDetails.swift MindControlLegend.swift \
  Renderer/GraphBuffers.swift Renderer/MatrixMath.swift Renderer/OrbitCamera.swift Renderer/Picking.swift Renderer/MetalGraphView.swift \
  Renderer/Shaders/Dust.metal Renderer/Shaders/Edges.metal Renderer/Shaders/Nodes.metal Renderer/Shaders/Signals.metal \
  Labels/LabelPlanner.swift
cd ../../../Tests/MindControl
git rm -q ConeTreeLayoutTests.swift DensityTests.swift DependencyScannerTests.swift GraphBuffersTests.swift InspectorTests.swift \
  LabelPerformanceTests.swift LabelPlannerTests.swift OrbitCameraTests.swift ParserTests.swift PickingTests.swift \
  RelaxationTests.swift StressGraphTests.swift ModelTests.swift
```

Then search for leftovers: `grep -rn "SplitMix64\|ScreenNode\|GraphNode\|ConeTreeLayout\|Inspector\b" macos/Sources macos/Tests`. If `SplitMix64` was defined in a deleted file and is still used, the only user was the deleted dust field, so nothing should remain. Any match left is in a file this task rewrites.

- [ ] **Step 2: Write `MindControl.swift`**

```swift
/// Namespace for the MindControl flow map: a 2D map of how a project's systems pass data and control.
enum MindControl {}
```

- [ ] **Step 3: Trim `SwiftSymbols.swift` to `declaredTypes`**

Delete `frameworkTypeNames` and `typeLikeIdentifiers(in:)`. Keep `declaration` and `declaredTypes(in:)` exactly as they are. Change the doc comment on the enum to `/// Type names a Swift file declares; used to check part anchors and to search by type.` In `SwiftSymbolsTests.swift`, delete `identifiersSkipCommentsAndStrings` and keep `declaredTypesSkipPrivateOnes`.

- [ ] **Step 4: Write `Labels/RectGrid.swift`**

Move `struct RectGrid` out of the deleted `LabelPlanner.swift`, unchanged:

```swift
import CoreGraphics

extension MindControl {
    /// Rectangles bucketed into a coarse grid for quick overlap tests.
    struct RectGrid {
        let cell: CGFloat
        private var buckets: [Int64: [CGRect]] = [:]

        init(cell: CGFloat) { self.cell = cell }

        func intersects(_ rect: CGRect) -> Bool {
            let (xs, ys) = span(of: rect)
            for x in xs {
                for y in ys {
                    if let bucket = buckets[key(x, y)], bucket.contains(where: { $0.intersects(rect) }) { return true }
                }
            }
            return false
        }

        mutating func insert(_ rect: CGRect) {
            let (xs, ys) = span(of: rect)
            for x in xs { for y in ys { buckets[key(x, y), default: []].append(rect) } }
        }

        private func span(of rect: CGRect) -> (ClosedRange<Int64>, ClosedRange<Int64>) {
            (Int64((rect.minX / cell).rounded(.down))...Int64((rect.maxX / cell).rounded(.down)),
             Int64((rect.minY / cell).rounded(.down))...Int64((rect.maxY / cell).rounded(.down)))
        }

        private func key(_ x: Int64, _ y: Int64) -> Int64 { x << 32 ^ (y & 0xFFFF_FFFF) }
    }
}
```

- [ ] **Step 5: Rewrite `Labels/LabelOverlayView.swift`**

The overlay is now flipped (top-left origin, matching the 2D camera). Labels can have a dark pill background, which arrow labels use.

```swift
import AppKit
import QuartzCore

extension MindControl {
    struct PlacedLabel: Equatable {
        let id: String
        let text: String
        /// View points, top-left origin.
        let frame: CGRect
        let fontSize: CGFloat
        let isBold: Bool
        let opacity: CGFloat
        /// Arrow labels sit on a dark pill so they stay readable over lines.
        let hasBackground: Bool
    }

    /// Text labels over the Metal view, drawn with a reusable pool of CATextLayers. Never takes the mouse.
    final class LabelOverlayView: NSView {
        private var pool: [CATextLayer] = []
        private struct SizeKey: Hashable {
            let text: String
            let size: CGFloat
            let bold: Bool
        }

        private static var sizeCache: [SizeKey: CGSize] = [:]
        static let pillPadding = CGSize(width: 6, height: 2)

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
        }

        required init?(coder: NSCoder) { nil }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        static func font(size: CGFloat, bold: Bool) -> NSFont {
            .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        }

        /// Text size, cached because labels are re-planned every frame.
        static func measure(_ text: String, _ size: CGFloat, _ bold: Bool) -> CGSize {
            let key = SizeKey(text: text, size: size, bold: bold)
            if let cached = sizeCache[key] { return cached }
            let measured = (text as NSString).size(withAttributes: [.font: font(size: size, bold: bold)])
            let result = CGSize(width: ceil(measured.width), height: ceil(measured.height))
            if sizeCache.count > 20_000 { sizeCache.removeAll() }
            sizeCache[key] = result
            return result
        }

        func show(_ labels: [PlacedLabel]) {
            guard let root = layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            while pool.count < labels.count {
                let text = CATextLayer()
                text.contentsScale = window?.backingScaleFactor ?? 2
                text.foregroundColor = NSColor.white.cgColor
                text.alignmentMode = .center
                text.cornerRadius = 4
                root.addSublayer(text)
                pool.append(text)
            }
            for (i, text) in pool.enumerated() {
                guard i < labels.count else {
                    text.isHidden = true
                    continue
                }
                let label = labels[i]
                text.isHidden = false
                if (text.string as? String) != label.text { text.string = label.text }
                // Reassigning font properties re-rasterises the text; only do it when they change.
                if text.fontSize != label.fontSize || (text.font as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) != label.isBold {
                    text.font = Self.font(size: label.fontSize, bold: label.isBold)
                    text.fontSize = label.fontSize
                }
                if label.hasBackground {
                    text.backgroundColor = NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.09, alpha: 0.85).cgColor
                    text.shadowOpacity = 0
                    text.frame = label.frame.insetBy(dx: -Self.pillPadding.width, dy: -Self.pillPadding.height)
                } else {
                    text.backgroundColor = nil
                    text.shadowColor = NSColor.black.cgColor
                    text.shadowOpacity = 0.8
                    text.shadowRadius = 2
                    text.shadowOffset = .zero
                    text.frame = label.frame
                }
                text.opacity = Float(label.opacity)
            }
            CATransaction.commit()
        }
    }
}
```

- [ ] **Step 6: Rewrite `Renderer/ShaderTypes.h` (background-only for now)**

```c
// Types shared between Swift (via the bridging header) and Metal shaders.
// Keep this file valid C and valid Metal Shading Language.
#ifndef MC_SHADER_TYPES_H
#define MC_SHADER_TYPES_H

#include <simd/simd.h>

typedef struct {
    vector_float2 sourceTexelSize;
    float threshold;
    float knee;
} MCBloomUniforms;

typedef struct {
    vector_float2 viewportSize;
    float time;
    float bloomStrength;
    float exposure;
} MCCompositeUniforms;

#endif // MC_SHADER_TYPES_H
```

- [ ] **Step 7: Rewrite `Renderer/Shaders/ShaderCommon.h`**

Keep only what Bloom and Composite use:

```c
// Helpers shared by every .metal file. Each .metal file is its own translation unit,
// so everything here is `inline`.
#ifndef MC_SHADER_COMMON_H
#define MC_SHADER_COMMON_H

#include <metal_stdlib>
#include "../ShaderTypes.h"
using namespace metal;

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

/// Triangle-strip corner for vertex 0...3: (-1,-1), (1,-1), (-1,1), (1,1).
inline float2 quadCorner(uint vid) {
    return float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
}

/// Off-screen position used to cull a primitive from the vertex shader.
inline float4 culledPosition() { return float4(2.0, 2.0, 2.0, 1.0); }

inline float hash11(float x) { return fract(sin(x * 127.1) * 43758.5453); }
inline float hash21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

inline float3 acesFitted(float3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

inline float3 linearToSRGB(float3 c) {
    c = saturate(c);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

#endif // MC_SHADER_COMMON_H
```

Open `Bloom.metal` and `Composite.metal` and confirm they use only these helpers (`FullscreenOut`, `hash21`, `acesFitted`, `linearToSRGB`). If one uses something else, copy that helper back from `git show HEAD:macos/Sources/Features/MindControl/Renderer/Shaders/ShaderCommon.h`.

- [ ] **Step 8: Rewrite `Renderer/Pipelines.swift`**

```swift
import Metal

extension MindControl {
    /// Every render pipeline the renderer uses, built once at startup.
    struct Pipelines {
        let composite: MTLRenderPipelineState
        let bloomPrefilter: MTLRenderPipelineState
        let bloomDownsample: MTLRenderPipelineState
        let bloomUpsample: MTLRenderPipelineState

        init(device: MTLDevice, library: MTLLibrary) throws {
            let hdr = Renderer.hdrFormat
            composite = try Self.make(device, library, "mcFullscreenVertex", "mcCompositeFragment", format: Renderer.outputFormat, additive: false)
            bloomPrefilter = try Self.make(device, library, "mcFullscreenVertex", "mcBloomPrefilter", format: hdr, additive: false)
            bloomDownsample = try Self.make(device, library, "mcFullscreenVertex", "mcBloomDownsample", format: hdr, additive: false)
            bloomUpsample = try Self.make(device, library, "mcFullscreenVertex", "mcBloomUpsample", format: hdr, additive: true)
        }

        static func make(_ device: MTLDevice, _ library: MTLLibrary, _ vertex: String, _ fragment: String,
                         format: MTLPixelFormat, additive: Bool) throws -> MTLRenderPipelineState {
            guard let v = library.makeFunction(name: vertex), let f = library.makeFunction(name: fragment) else {
                throw RendererError.pipeline("Missing shader function \(vertex) or \(fragment)")
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "\(vertex)/\(fragment)"
            descriptor.vertexFunction = v
            descriptor.fragmentFunction = f
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = format
            if additive {
                attachment.isBlendingEnabled = true
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceRGBBlendFactor = .one
                attachment.destinationRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .one
            }
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                throw RendererError.pipeline("\(vertex)/\(fragment): \(error.localizedDescription)")
            }
        }
    }
}
```

- [ ] **Step 9: Write the failing renderer tests**

Replace `macos/Tests/MindControl/RendererTests.swift` with:

```swift
#if os(macOS)
import Testing
import Metal
@testable import Ghostty

private typealias Renderer = MindControl.Renderer

@MainActor
struct RendererTests {
    /// Renders one frame offscreen and returns the average channel value, 0...1.
    static func renderAverage(using renderer: Renderer, width: Int = 96, height: Int = 64) throws -> Double {
        let device = renderer.device
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        let texture = try #require(device.makeTexture(descriptor: desc))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        let queue = try #require(device.makeCommandQueue())
        let cmd = try #require(queue.makeCommandBuffer())
        renderer.encodeFrame(into: cmd, output: pass, width: width, height: height, pixelScale: 1, time: 1.5)
        let blit = try #require(cmd.makeBlitCommandEncoder())
        blit.synchronize(resource: texture)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        #expect(cmd.error == nil)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return Double(bytes.reduce(0) { $0 + Int($1) }) / Double(bytes.count) / 255
    }

    @Test func createsRenderer() throws {
        _ = try Renderer()
    }

    @Test func rendersBackground() throws {
        let average = try Self.renderAverage(using: try Renderer())
        #expect(average > 0)
        #expect(average < 0.4)
    }

    @Test func rendersOnePixelTarget() throws {
        _ = try Self.renderAverage(using: try Renderer(), width: 1, height: 1)
    }
}
#endif
```

- [ ] **Step 10: Rewrite `Renderer/Renderer.swift` (background only)**

```swift
import MetalKit
import QuartzCore

extension MindControl {
    enum RendererError: LocalizedError {
        case metalUnavailable
        case pipeline(String)

        var errorDescription: String? {
            switch self {
            case .metalUnavailable: "Metal is unavailable on this Mac."
            case .pipeline(let detail): "The renderer failed to start: \(detail)"
            }
        }
    }

    /// Draws the flow map with Metal: HDR scene pass → bloom → composite into the drawable.
    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        nonisolated static let hdrFormat: MTLPixelFormat = .rgba16Float
        nonisolated static let outputFormat: MTLPixelFormat = .bgra8Unorm

        let device: MTLDevice
        private let queue: MTLCommandQueue
        private let pipelines: Pipelines
        private let bloom: BloomPass
        private var hdrTexture: MTLTexture?
        private let startTime = CACurrentMediaTime()

        var bloomStrength: Float = 0.22
        var exposure: Float = 1
        /// Called after each on-screen frame (not for offscreen renders).
        var onFrame: (() -> Void)?

        init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
            guard let device, let queue = device.makeCommandQueue() else {
                throw RendererError.metalUnavailable
            }
            let library: MTLLibrary
            do {
                library = try device.makeDefaultLibrary(bundle: Bundle(for: Renderer.self))
            } catch {
                throw RendererError.pipeline(error.localizedDescription)
            }
            self.device = device
            self.queue = queue
            self.pipelines = try Pipelines(device: device, library: library)
            self.bloom = BloomPass(device: device)
            super.init()
        }

        // MARK: MTKViewDelegate

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            let width = Int(view.drawableSize.width)
            let height = Int(view.drawableSize.height)
            guard width > 0, height > 0,
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = queue.makeCommandBuffer() else { return }
            let scale = Float(view.window?.backingScaleFactor ?? 2)
            encodeFrame(into: commandBuffer, output: pass, width: width, height: height, pixelScale: scale,
                        time: Float(CACurrentMediaTime() - startTime))
            commandBuffer.present(drawable)
            commandBuffer.commit()
            onFrame?()
        }

        // MARK: Frame encoding

        func encodeFrame(into commandBuffer: MTLCommandBuffer, output: MTLRenderPassDescriptor, width: Int, height: Int, pixelScale: Float, time: Float) {
            guard width > 0, height > 0, let hdr = hdrTarget(width: width, height: height) else { return }
            encodeScene(commandBuffer, target: hdr, width: width, height: height, pixelScale: pixelScale, time: time)
            let bloomTexture = bloom.encode(commandBuffer: commandBuffer, source: hdr, pipelines: pipelines) ?? hdr
            encodeComposite(commandBuffer, output: output, scene: hdr, bloom: bloomTexture, width: width, height: height, time: time)
        }

        /// Clears the HDR target. Task 14 draws the map here.
        private func encodeScene(_ commandBuffer: MTLCommandBuffer, target: MTLTexture, width: Int, height: Int, pixelScale: Float, time: Float) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.label = "Scene"
            encoder.endEncoding()
        }

        private func encodeComposite(_ commandBuffer: MTLCommandBuffer, output: MTLRenderPassDescriptor, scene: MTLTexture, bloom: MTLTexture, width: Int, height: Int, time: Float) {
            output.colorAttachments[0].loadAction = .dontCare
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: output) else { return }
            encoder.label = "Composite"
            var uniforms = MCCompositeUniforms(
                viewportSize: SIMD2(Float(width), Float(height)),
                time: time,
                bloomStrength: bloomStrength,
                exposure: exposure
            )
            encoder.setRenderPipelineState(pipelines.composite)
            encoder.setFragmentTexture(scene, index: 0)
            encoder.setFragmentTexture(bloom, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MCCompositeUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        // MARK: Resources

        private func hdrTarget(width: Int, height: Int) -> MTLTexture? {
            if let hdrTexture, hdrTexture.width == width, hdrTexture.height == height { return hdrTexture }
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.hdrFormat, width: width, height: height, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            hdrTexture = device.makeTexture(descriptor: desc)
            hdrTexture?.label = "HDR scene"
            return hdrTexture
        }

        func makeBuffer<T>(_ array: [T]) -> MTLBuffer? {
            guard !array.isEmpty else { return nil }
            return array.withUnsafeBytes { bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
            }
        }
    }
}
```

- [ ] **Step 11: Stub the model and panel**

`MindControlModel.swift`:

```swift
import Foundation

extension MindControl {
    /// Loads and watches the focused terminal's flow map. One per window. Rebuilt in Task 16.
    @MainActor
    final class Model: ObservableObject {
        @Published private(set) var pwd: URL?

        func load(pwd: URL?) { self.pwd = pwd }
    }
}
```

`MindControlPanel.swift`:

```swift
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
```

Search the tests outside `Tests/MindControl` for the old model API: `grep -rn "mindControl\." macos/Tests`. Any test that checks `mindControl.state` (for example in `ExtensionSidebarModel` tests) should instead check `mindControl.pwd`: when the visualizer opens, `pwd` equals the injected `workingDirectory()`.

- [ ] **Step 12: Run the renderer tests and the full suite**

Run: `.superpowers/mc-test.sh RendererTests BloomPassTests SwiftSymbolsTests ProjectScannerTests SourceFilterTests`
Expected: every suite reports `N passed, 0 failed`.

Run the full suite (Global Constraints).
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 13: Commit**

```bash
git add -u macos/Sources/Features/MindControl macos/Tests
git add macos/Sources/Features/MindControl/Labels/RectGrid.swift
git commit -m "mindcontrol: remove the 3D map, keep a background-only renderer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The flow file — types, parsing and validation

**Files:**
- Create: `macos/Sources/Features/MindControl/Flow/FlowMap.swift`, `macos/Sources/Features/MindControl/Flow/FlowFile.swift`
- Create: `macos/Tests/MindControl/FlowTestSupport.swift`, `macos/Tests/MindControl/FlowFileTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `MindControl.FlowMap` with `zones: [Zone]`, `systems: [System]`, `flows: [Flow]`, `features: [Feature]`, `system(_ id: String) -> System?`, `flow(_ id: String) -> Flow?`, `zoneOf(system: String) -> String?`
  - `FlowMap.Zone(id, name)`
  - `FlowMap.Part(id, name, anchor: String?)`
  - `FlowMap.System(id, name, summary: String?, zone: String?, paths: [String], parts: [Part], external: Bool)` with `part(_:)`
  - `FlowMap.Kind` (`.data`, `.control`)
  - `FlowMap.Endpoint(system: String, part: String?)`, with `init?(_ text: String)` and `description` (`"audio"` or `"audio.capture"`)
  - `FlowMap.Flow(id, from: Endpoint, to: Endpoint, kind, carries, via: String?, when: String?)`
  - `FlowMap.Feature(id, name, route: [String])`
  - `MindControl.FlowError(line: Int?, message: String)`; `MindControl.FlowErrors: Error { errors }`
  - `MindControl.FlowFile.parse(_ data: Data) -> Result<FlowMap, FlowErrors>`, `FlowFile.relativePath`, `FlowFile.layoutRelativePath`, `FlowFile.isValidID(_:)`
  - Tests: `FlowFixtures.arcaJSON`, `FlowFixtures.map(_:)`, `FlowFixtures.arca`, `TempProject`

- [ ] **Step 1: Write the test support file**

`macos/Tests/MindControl/FlowTestSupport.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

enum FlowFixtures {
    /// A small map shaped like Arca's speech path.
    static let arcaJSON = """
    {
      "version": 1,
      "zones": [
        { "id": "ring", "name": "Ring" },
        { "id": "phone", "name": "Phone" },
        { "id": "cloud", "name": "Cloud services" }
      ],
      "systems": [
        { "id": "ring", "name": "Ring", "zone": "ring", "external": true },
        { "id": "ble", "name": "BLE link", "zone": "phone", "paths": ["app/Sources/BLE/**"],
          "parts": [ { "id": "link", "name": "ArcaLink", "anchor": "ArcaLink" } ] },
        { "id": "tap", "name": "Tap coordinator", "zone": "phone", "paths": ["app/Sources/Coordination/Tap*.swift"] },
        { "id": "audio", "name": "Audio", "zone": "phone", "summary": "Mic capture, the words-heard check, playback.",
          "paths": ["app/Sources/Audio/**"],
          "parts": [
            { "id": "capture", "name": "AudioCapture", "anchor": "AudioCapture" },
            { "id": "gate", "name": "SpeechGate", "anchor": "SpeechGate" }
          ] },
        { "id": "agent", "name": "Realtime agent", "zone": "phone", "paths": ["app/Sources/Agent/**"],
          "parts": [ { "id": "session", "name": "RealtimeAgentSession", "anchor": "RealtimeAgentSession" } ] },
        { "id": "openai", "name": "OpenAI Realtime", "zone": "cloud", "external": true }
      ],
      "flows": [
        { "id": "press", "from": "ring", "to": "ble.link", "kind": "control", "carries": "press DOWN / UP", "via": "didUpdateValue" },
        { "id": "event", "from": "ble.link", "to": "tap", "kind": "control", "carries": "onEvent", "via": "onEvent" },
        { "id": "begin", "from": "tap", "to": "audio.capture", "kind": "control", "carries": "begin / end", "via": "beginTransmission" },
        { "id": "pcm", "from": "audio.capture", "to": "agent.session", "kind": "data", "carries": "PCM16 24 kHz", "via": "sendAudio" },
        { "id": "check", "from": "audio.capture", "to": "audio.gate", "kind": "data", "carries": "PCM buffers", "via": "append" },
        { "id": "commit", "from": "audio.capture", "to": "agent.session", "kind": "control", "carries": "commit turn", "via": "commitTurn", "when": "words heard" },
        { "id": "discard", "from": "audio.capture", "to": "agent.session", "kind": "control", "carries": "discard turn", "via": "discardTurn", "when": "nothing heard" },
        { "id": "send", "from": "agent.session", "to": "openai", "kind": "data", "carries": "audio + commit", "via": "send" },
        { "id": "reply", "from": "openai", "to": "agent.session", "kind": "data", "carries": "response audio", "via": "receive" }
      ],
      "features": [
        { "id": "speech", "name": "A press becomes speech",
          "route": ["press", "event", "begin", "pcm", "check", "commit", "discard", "send", "reply"] }
      ]
    }
    """

    static func map(_ json: String) -> MindControl.FlowMap {
        switch MindControl.FlowFile.parse(Data(json.utf8)) {
        case .success(let map): return map
        case .failure(let errors): fatalError("Fixture is invalid: \(errors.errors)")
        }
    }

    static var arca: MindControl.FlowMap { map(arcaJSON) }

    /// Source files matching `arca`'s anchors and vias.
    static let arcaSources: [String: String] = [
        "app/Sources/BLE/ArcaLink.swift": "final class ArcaLink {\n    var onEvent: ((Int) -> Void)?\n    func didUpdateValue() { onEvent?(1) }\n}\n",
        "app/Sources/Coordination/TapCoordinator.swift": "final class TapCoordinator {\n    func handle() { capture.beginTransmission() }\n}\n",
        "app/Sources/Audio/AudioCapture.swift": "final class AudioCapture {\n    func beginTransmission() {}\n    func run() {\n        agent.sendAudio()\n        gate.append()\n        agent.commitTurn()\n        agent.discardTurn()\n    }\n}\n",
        "app/Sources/Audio/SpeechGate.swift": "struct SpeechGate {\n    func append() {}\n}\n",
        "app/Sources/Agent/RealtimeAgentSession.swift": "actor RealtimeAgentSession {\n    func sendAudio() {}\n    func commitTurn() {}\n    func discardTurn() {}\n    func send() {}\n    func receive() {}\n}\n",
    ]
}

/// A fresh temporary project directory, removed when the test ends.
final class TempProject {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("mc-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ path: String, _ contents: String) throws {
        let target = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
    }

    func write(_ files: [String: String]) throws {
        for (path, contents) in files { try write(path, contents) }
    }

    @discardableResult
    func git(_ args: String...) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "-c", "user.name=Test", "-c", "user.email=test@example.com"] + args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// `git add -A && git commit`, for test repos only.
    func commitAll(_ message: String) throws {
        try git("add", "-A")
        try git("commit", "-q", "-m", message)
    }
}
#endif
```

- [ ] **Step 2: Write the failing parser tests**

`macos/Tests/MindControl/FlowFileTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowFile = MindControl.FlowFile
private typealias FlowMap = MindControl.FlowMap

struct FlowFileTests {
    private func errors(_ json: String) -> [MindControl.FlowError] {
        if case .failure(let failure) = FlowFile.parse(Data(json.utf8)) { return failure.errors }
        Issue.record("Expected errors for:\n\(json)")
        return []
    }

    @Test func parsesArcaExample() throws {
        let map = FlowFixtures.arca
        #expect(map.zones.map(\.id) == ["ring", "phone", "cloud"])
        #expect(map.systems.map(\.id) == ["ring", "ble", "tap", "audio", "agent", "openai"])
        #expect(map.system("audio")?.parts.map(\.id) == ["capture", "gate"])
        #expect(map.system("ring")?.external == true)
        let commit = try #require(map.flow("commit"))
        #expect(commit.from == FlowMap.Endpoint(system: "audio", part: "capture"))
        #expect(commit.to.description == "agent.session")
        #expect(commit.kind == .control)
        #expect(commit.when == "words heard")
        #expect(map.features.first?.route.count == 9)
        #expect(map.zoneOf(system: "openai") == "cloud")
    }

    @Test func optionalListsDefaultToEmpty() throws {
        let json = #"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ] }"#
        let map = try FlowFile.parse(Data(json.utf8)).get()
        #expect(map.zones.isEmpty && map.flows.isEmpty && map.features.isEmpty)
        #expect(map.systems.first?.paths == [] && map.systems.first?.external == false)
    }

    @Test func trailingCommaReportsLine() {
        let json = "{\n  \"version\": 1,\n  \"systems\": [\n    { \"id\": \"a\", \"name\": \"A\" },\n  ]\n}\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.message.hasPrefix("Not valid JSON") == true)
        #expect((3...6).contains(found.first?.line ?? 0))
    }

    @Test func ruleErrorPointsAtTheItemsLine() {
        let json = "{\n  \"version\": 1,\n  \"systems\": [\n    { \"id\": \"ok\", \"name\": \"OK\" },\n    { \"id\": \"audio\" }\n  ]\n}\n"
        let found = errors(json)
        #expect(found.count == 1)
        #expect(found.first?.line == 5)
        #expect(found.first?.message.contains("\"name\"") == true)
    }

    @Test(arguments: [
        (#"{ "systems": [] }"#, "version"),
        (#"{ "version": 2, "systems": [] }"#, "version 1"),
        (#"{ "version": 1 }"#, "\"systems\""),
        (#"{ "version": 1, "systems": [ { "id": "Audio", "name": "A" } ] }"#, "a-z"),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" }, { "id": "a", "name": "B" } ] }"#, "Duplicate"),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A", "zone": "nope" } ] }"#, "unknown zone"),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A", "external": true, "paths": ["x/**"] } ] }"#, "external"),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A", "parts": [ { "id": "p" } ] } ] }"#, "\"name\""),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ], "flows": [ { "id": "f", "from": "a", "to": "a", "kind": "event", "carries": "x" } ] }"#, "\"kind\""),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ], "flows": [ { "id": "f", "from": "a.b.c", "to": "a", "kind": "data", "carries": "x" } ] }"#, "\"from\""),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ], "flows": [ { "id": "f", "from": "a", "to": "a", "kind": "data" } ] }"#, "\"carries\""),
        (#"{ "version": 1, "systems": [ { "id": "a", "name": "A" } ], "features": [ { "id": "x", "name": "X", "route": "f" } ] }"#, "\"route\""),
        (#"[1, 2]"#, "JSON object"),
    ])
    func ruleViolations(json: String, expected: String) {
        let found = errors(json)
        #expect(!found.isEmpty)
        #expect(found.contains { $0.message.contains(expected) }, "\(found) should mention \(expected)")
    }

    @Test func endpointParsing() {
        #expect(FlowMap.Endpoint("audio") == FlowMap.Endpoint(system: "audio", part: nil))
        #expect(FlowMap.Endpoint("audio.capture") == FlowMap.Endpoint(system: "audio", part: "capture"))
        #expect(FlowMap.Endpoint("audio.") == nil)
        #expect(FlowMap.Endpoint("a.b.c") == nil)
        #expect(FlowMap.Endpoint("Audio") == nil)
    }
}
#endif
```

- [ ] **Step 3: Run the tests to watch them fail**

Run: `macos/skins-test.sh FlowFileTests`
Expected: build errors naming `FlowFile` / `FlowMap` (types not defined).

- [ ] **Step 4: Write `Flow/FlowMap.swift`**

```swift
import Foundation

extension MindControl {
    /// A project's flow map, decoded from `.mindcontrol/flow.json`.
    struct FlowMap: Equatable, Sendable {
        struct Zone: Equatable, Sendable {
            let id: String
            let name: String
        }

        struct Part: Equatable, Sendable {
            let id: String
            let name: String
            /// A Swift type name, or a file path relative to the project root.
            let anchor: String?
        }

        struct System: Equatable, Sendable {
            let id: String
            let name: String
            let summary: String?
            let zone: String?
            let paths: [String]
            let parts: [Part]
            let external: Bool

            func part(_ id: String) -> Part? { parts.first { $0.id == id } }
        }

        enum Kind: String, Equatable, Sendable {
            case data, control
        }

        /// `audio` (a whole system) or `audio.capture` (one of its parts).
        struct Endpoint: Hashable, Sendable, CustomStringConvertible {
            let system: String
            let part: String?

            init(system: String, part: String?) {
                self.system = system
                self.part = part
            }

            init?(_ text: String) {
                let pieces = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                guard (1...2).contains(pieces.count), pieces.allSatisfy(FlowFile.isValidID) else { return nil }
                system = pieces[0]
                part = pieces.count == 2 ? pieces[1] : nil
            }

            var description: String { part.map { "\(system).\($0)" } ?? system }
        }

        struct Flow: Equatable, Sendable {
            let id: String
            let from: Endpoint
            let to: Endpoint
            let kind: Kind
            /// What travels, or what is triggered.
            let carries: String
            /// The call or symbol where the hand-off happens.
            let via: String?
            /// The condition this step depends on, e.g. "words heard".
            let when: String?
        }

        struct Feature: Equatable, Sendable {
            let id: String
            let name: String
            /// Flow ids, in order.
            let route: [String]
        }

        let zones: [Zone]
        let systems: [System]
        let flows: [Flow]
        let features: [Feature]

        func system(_ id: String) -> System? { systems.first { $0.id == id } }
        func flow(_ id: String) -> Flow? { flows.first { $0.id == id } }
        func feature(_ id: String) -> Feature? { features.first { $0.id == id } }
        func zoneOf(system id: String) -> String? { system(id)?.zone }
    }
}
```

- [ ] **Step 5: Write `Flow/FlowFile.swift`**

```swift
import Foundation

extension MindControl {
    /// One problem in a flow file. `line` is 1-based when known.
    struct FlowError: Equatable, Sendable, CustomStringConvertible {
        let line: Int?
        let message: String

        var description: String { line.map { "Line \($0): \(message)" } ?? message }
    }

    struct FlowErrors: Error, Equatable, Sendable {
        let errors: [FlowError]
    }

    /// Reads `.mindcontrol/flow.json`: JSON syntax first, then the format's rules. Every problem is
    /// reported, not just the first. References between systems and flows are checked later by FlowCheck.
    enum FlowFile {
        static let relativePath = ".mindcontrol/flow.json"
        static let layoutRelativePath = ".mindcontrol/layout.json"
        static let supportedVersion = 1

        static func parse(_ data: Data) -> Result<FlowMap, FlowErrors> {
            let text = String(decoding: data, as: UTF8.self)
            let root: Any
            do {
                root = try JSONSerialization.jsonObject(with: data)
            } catch {
                return .failure(FlowErrors(errors: [syntaxError(error as NSError, text: text)]))
            }
            var parser = Parser(text: text)
            let map = parser.map(root)
            if let map, parser.errors.isEmpty { return .success(map) }
            return .failure(FlowErrors(errors: parser.errors))
        }

        /// Lowercase letters, digits and `-`.
        static func isValidID(_ id: String) -> Bool {
            !id.isEmpty && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        }

        static func line(ofUTF8Offset offset: Int, in text: String) -> Int {
            1 + text.utf8.prefix(max(0, offset)).filter { $0 == UInt8(ascii: "\n") }.count
        }

        private static func syntaxError(_ error: NSError, text: String) -> FlowError {
            let detail = (error.userInfo[NSDebugDescriptionErrorKey] as? String) ?? error.localizedDescription
            var line: Int?
            if let range = detail.range(of: #"line \d+"#, options: .regularExpression) {
                line = Int(detail[range].dropFirst(5))
            } else if let index = error.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                line = Self.line(ofUTF8Offset: index, in: text)
            }
            return FlowError(line: line, message: "Not valid JSON: \(detail)")
        }
    }
}

extension MindControl.FlowFile {
    private typealias FlowMap = MindControl.FlowMap

    /// Walks the decoded JSON, collecting every rule violation with the best line it can find.
    fileprivate struct Parser {
        let text: String
        var errors: [MindControl.FlowError] = []

        // MARK: Errors and lines

        mutating func fail(_ message: String, id: String? = nil, key: String? = nil) {
            errors.append(.init(line: line(id: id, key: key), message: message))
        }

        /// The line of `"id": "<id>"`, else of `"<key>":`.
        func line(id: String?, key: String?) -> Int? {
            if let id, let found = firstLine(of: #""id"\s*:\s*"\#(NSRegularExpression.escapedPattern(for: id))""#) { return found }
            if let key, let found = firstLine(of: #""\#(NSRegularExpression.escapedPattern(for: key))"\s*:"#) { return found }
            return nil
        }

        func firstLine(of pattern: String) -> Int? {
            guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
            return 1 + text[..<range.lowerBound].filter { $0 == "\n" }.count
        }

        // MARK: Field helpers

        mutating func objects(_ object: [String: Any], _ key: String, required: Bool) -> [[String: Any]] {
            guard let value = object[key] else {
                if required { fail("Missing \"\(key)\".") }
                return []
            }
            guard let array = value as? [Any] else {
                fail("\"\(key)\" must be a list.", key: key)
                return []
            }
            var items: [[String: Any]] = []
            for (index, item) in array.enumerated() {
                if let object = item as? [String: Any] {
                    items.append(object)
                } else {
                    fail("\(key)[\(index)] must be an object.", key: key)
                }
            }
            return items
        }

        mutating func id(_ object: [String: Any], what: String, label: String, listKey: String, seen: inout Set<String>) -> String? {
            guard let id = object["id"] as? String else {
                fail("\(label) is missing \"id\".", key: listKey)
                return nil
            }
            guard MindControl.FlowFile.isValidID(id) else {
                fail("The \(what) id \"\(id)\" may only use a-z, 0-9 and -.", id: id)
                return nil
            }
            guard seen.insert(id).inserted else {
                fail("Duplicate \(what) id \"\(id)\".", id: id)
                return nil
            }
            return id
        }

        mutating func text(_ object: [String: Any], _ key: String, required: Bool, owner: String, id: String?) -> String? {
            switch object[key] {
            case let value as String where !value.isEmpty:
                return value
            case nil, is String:
                if required { fail("\(owner) is missing \"\(key)\".", id: id, key: id == nil ? key : nil) }
                return nil
            default:
                fail("\(owner): \"\(key)\" must be text.", id: id)
                return nil
            }
        }

        // MARK: The map

        mutating func map(_ root: Any) -> FlowMap? {
            guard let object = root as? [String: Any] else {
                fail("The file must be a JSON object.")
                return nil
            }
            switch object["version"] {
            case let version as Int where version == MindControl.FlowFile.supportedVersion:
                break
            case nil:
                fail("Missing \"version\"; this MindControl reads version 1.")
            case let version?:
                fail("Unsupported version \(version); this MindControl reads version 1.", key: "version")
            }

            let zones = parseZones(object)
            let zoneIDs = Set(zones.map(\.id))
            let systems = parseSystems(object, zoneIDs: zoneIDs)
            let flows = parseFlows(object)
            let features = parseFeatures(object)
            guard errors.isEmpty else { return nil }
            return FlowMap(zones: zones, systems: systems, flows: flows, features: features)
        }

        mutating func parseZones(_ object: [String: Any]) -> [FlowMap.Zone] {
            var seen = Set<String>()
            return objects(object, "zones", required: false).enumerated().compactMap { index, item in
                guard let id = self.id(item, what: "zone", label: "zones[\(index)]", listKey: "zones", seen: &seen),
                      let name = text(item, "name", required: true, owner: "Zone \"\(id)\"", id: id) else { return nil }
                return FlowMap.Zone(id: id, name: name)
            }
        }

        mutating func parseSystems(_ object: [String: Any], zoneIDs: Set<String>) -> [FlowMap.System] {
            var seen = Set<String>()
            return objects(object, "systems", required: true).enumerated().compactMap { index, item in
                guard let id = self.id(item, what: "system", label: "systems[\(index)]", listKey: "systems", seen: &seen) else { return nil }
                let owner = "System \"\(id)\""
                let name = text(item, "name", required: true, owner: owner, id: id)
                let summary = text(item, "summary", required: false, owner: owner, id: id)
                let zone = text(item, "zone", required: false, owner: owner, id: id)
                if let zone, !zoneIDs.contains(zone) {
                    fail("\(owner) names unknown zone \"\(zone)\".", id: id)
                }
                var paths: [String] = []
                if let value = item["paths"] {
                    if let list = value as? [String] { paths = list } else { fail("\(owner): \"paths\" must be a list of text.", id: id) }
                }
                var external = false
                if let value = item["external"] {
                    if let flag = value as? Bool { external = flag } else { fail("\(owner): \"external\" must be true or false.", id: id) }
                }
                var partIDs = Set<String>()
                let parts: [FlowMap.Part] = objects(item, "parts", required: false).enumerated().compactMap { partIndex, part in
                    guard let partID = self.id(part, what: "part", label: "\(owner) parts[\(partIndex)]", listKey: "parts", seen: &partIDs),
                          let partName = text(part, "name", required: true, owner: "Part \"\(id).\(partID)\"", id: partID) else { return nil }
                    return FlowMap.Part(id: partID, name: partName,
                                        anchor: text(part, "anchor", required: false, owner: "Part \"\(id).\(partID)\"", id: partID))
                }
                if external, !paths.isEmpty || item["parts"] != nil {
                    fail("\(owner) is external, so it cannot have paths or parts.", id: id)
                }
                guard let name else { return nil }
                return FlowMap.System(id: id, name: name, summary: summary, zone: zone, paths: paths, parts: parts, external: external)
            }
        }

        mutating func parseFlows(_ object: [String: Any]) -> [FlowMap.Flow] {
            var seen = Set<String>()
            return objects(object, "flows", required: false).enumerated().compactMap { index, item in
                guard let id = self.id(item, what: "flow", label: "flows[\(index)]", listKey: "flows", seen: &seen) else { return nil }
                let owner = "Flow \"\(id)\""
                let from = endpoint(item, "from", owner: owner, id: id)
                let to = endpoint(item, "to", owner: owner, id: id)
                let kindText = text(item, "kind", required: true, owner: owner, id: id)
                let kind = kindText.flatMap(FlowMap.Kind.init(rawValue:))
                if let kindText, kind == nil {
                    fail("\(owner): \"kind\" must be \"data\" or \"control\", not \"\(kindText)\".", id: id)
                }
                let carries = text(item, "carries", required: true, owner: owner, id: id)
                let via = text(item, "via", required: false, owner: owner, id: id)
                let when = text(item, "when", required: false, owner: owner, id: id)
                guard let from, let to, let kind, let carries else { return nil }
                return FlowMap.Flow(id: id, from: from, to: to, kind: kind, carries: carries, via: via, when: when)
            }
        }

        mutating func endpoint(_ item: [String: Any], _ key: String, owner: String, id: String) -> FlowMap.Endpoint? {
            guard let raw = text(item, key, required: true, owner: owner, id: id) else { return nil }
            guard let endpoint = FlowMap.Endpoint(raw) else {
                fail("\(owner): \"\(key)\" must be a system id or system.part, not \"\(raw)\".", id: id)
                return nil
            }
            return endpoint
        }

        mutating func parseFeatures(_ object: [String: Any]) -> [FlowMap.Feature] {
            var seen = Set<String>()
            return objects(object, "features", required: false).enumerated().compactMap { index, item in
                guard let id = self.id(item, what: "feature", label: "features[\(index)]", listKey: "features", seen: &seen) else { return nil }
                let owner = "Feature \"\(id)\""
                let name = text(item, "name", required: true, owner: owner, id: id)
                guard let route = item["route"] as? [String] else {
                    fail("\(owner): \"route\" must be a list of flow ids.", id: id)
                    return nil
                }
                guard let name else { return nil }
                return FlowMap.Feature(id: id, name: name, route: route)
            }
        }
    }
}
```

- [ ] **Step 6: Run the tests to watch them pass**

Run: `macos/skins-test.sh FlowFileTests`
Expected: `** TEST SUCCEEDED **`.

If `trailingCommaReportsLine` fails only on the line range, print `found.first` in the failure, check which line Foundation reports, and widen the range to cover it. Record a ledger ruling, because Foundation's message format is outside our control.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/MindControl/Flow/FlowMap.swift macos/Sources/Features/MindControl/Flow/FlowFile.swift \
  macos/Tests/MindControl/FlowTestSupport.swift macos/Tests/MindControl/FlowFileTests.swift
git commit -m "mindcontrol: read and validate .mindcontrol/flow.json

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 4: Path patterns and ownership

**Files:**
- Create: `macos/Sources/Features/MindControl/Flow/Glob.swift`, `macos/Sources/Features/MindControl/Flow/PathOwnership.swift`
- Create: `macos/Tests/MindControl/GlobTests.swift`, `macos/Tests/MindControl/PathOwnershipTests.swift`

**Interfaces:**
- Consumes: `FlowMap` (Task 3)
- Produces:
  - `MindControl.Glob.regex(for pattern: String) -> NSRegularExpression`
  - `Glob.matches(_ pattern: String, _ path: String) -> Bool`
  - `Glob.literalPrefixLength(_ pattern: String) -> Int`
  - `MindControl.PathOwnership(map:)` with `owner(of path: String) -> Owner`, where `Owner` is `.system(String)`, `.none` or `.tie([String])` (ids sorted)

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/GlobTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

private typealias Glob = MindControl.Glob

struct GlobTests {
    @Test(arguments: [
        ("app/Sources/Audio/**", "app/Sources/Audio/A.swift", true),
        ("app/Sources/Audio/**", "app/Sources/Audio/sub/B.swift", true),
        ("app/Sources/Audio/**", "app/Sources/AudioX/A.swift", false),
        ("app/*/A.swift", "app/x/A.swift", true),
        ("app/*/A.swift", "app/x/y/A.swift", false),
        ("**/*.ts", "relay/src/pipe.ts", true),
        ("**/*.ts", "pipe.ts", true),
        ("relay/src/pipe.ts", "relay/src/pipe.ts", true),
        ("relay/src", "relay/src/pipe.ts", true),
        ("relay/src", "relay/srcx/pipe.ts", false),
        ("app/Coordination/Journal*.swift", "app/Coordination/JournalUploader.swift", true),
        ("app/Coordination/Journal*.swift", "app/Coordination/Chat.swift", false),
        ("a.b/*", "aXb/c", false),
    ])
    func matching(pattern: String, path: String, expected: Bool) {
        #expect(Glob.matches(pattern, path) == expected)
    }

    @Test func literalPrefixCountsUpToFirstStar() {
        #expect(Glob.literalPrefixLength("app/Coordination/Journal*.swift") == "app/Coordination/Journal".count)
        #expect(Glob.literalPrefixLength("app/Coordination/**") == "app/Coordination/".count)
        #expect(Glob.literalPrefixLength("relay/src/pipe.ts") == "relay/src/pipe.ts".count)
        #expect(Glob.literalPrefixLength("**/*.ts") == 0)
    }
}
#endif
```

`macos/Tests/MindControl/PathOwnershipTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

private typealias PathOwnership = MindControl.PathOwnership

struct PathOwnershipTests {
    private func ownership(_ systems: String) -> PathOwnership {
        PathOwnership(map: FlowFixtures.map(#"{ "version": 1, "systems": [\#(systems)] }"#))
    }

    @Test func moreSpecificPatternWins() {
        let owners = ownership(#"""
        { "id": "core", "name": "Core", "paths": ["app/Coordination/**"] },
        { "id": "journal", "name": "Journal", "paths": ["app/Coordination/Journal*.swift"] }
        """#)
        #expect(owners.owner(of: "app/Coordination/Journal.swift") == .system("journal"))
        #expect(owners.owner(of: "app/Coordination/Chat.swift") == .system("core"))
    }

    @Test func equalSpecificityIsATie() {
        let owners = ownership(#"""
        { "id": "b", "name": "B", "paths": ["app/A/*.swift"] },
        { "id": "a", "name": "A", "paths": ["app/A/*.swift"] }
        """#)
        #expect(owners.owner(of: "app/A/x.swift") == .tie(["a", "b"]))
    }

    @Test func twoPatternsOfOneSystemAreNotATie() {
        let owners = ownership(#"{ "id": "a", "name": "A", "paths": ["app/*.swift", "app/*.swift"] }"#)
        #expect(owners.owner(of: "app/x.swift") == .system("a"))
    }

    @Test func unmatchedFileHasNoOwner() {
        let owners = ownership(#"{ "id": "a", "name": "A", "paths": ["app/**"] }"#)
        #expect(owners.owner(of: "relay/src/pipe.ts") == .none)
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `.superpowers/mc-test.sh GlobTests PathOwnershipTests`
Expected: build errors: `Glob` and `PathOwnership` are not defined.

- [ ] **Step 3: Write `Flow/Glob.swift`**

```swift
import Foundation

extension MindControl {
    /// Path patterns relative to the project root: `*` matches within one folder name, `**` across
    /// folders (including none), `?` one character. A pattern with no wildcard also matches everything
    /// inside it when it names a folder.
    enum Glob {
        static func regex(for pattern: String) -> NSRegularExpression {
            var out = "^"
            let chars = Array(pattern)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                    if i + 2 < chars.count, chars[i + 2] == "/" {
                        out += "(?:.*/)?"
                        i += 3
                    } else {
                        out += ".*"
                        i += 2
                    }
                } else if c == "*" {
                    out += "[^/]*"
                    i += 1
                } else if c == "?" {
                    out += "[^/]"
                    i += 1
                } else {
                    out += NSRegularExpression.escapedPattern(for: String(c))
                    i += 1
                }
            }
            if !pattern.contains("*"), !pattern.contains("?") {
                out += "(?:/.*)?"
            }
            out += "$"
            // swiftlint:disable:next force_try
            return try! NSRegularExpression(pattern: out)
        }

        static func matches(_ pattern: String, _ path: String) -> Bool {
            matches(regex(for: pattern), path)
        }

        static func matches(_ regex: NSRegularExpression, _ path: String) -> Bool {
            regex.firstMatch(in: path, range: NSRange(location: 0, length: (path as NSString).length)) != nil
        }

        /// How much of the pattern is fixed text before its first wildcard; longer is more specific.
        static func literalPrefixLength(_ pattern: String) -> Int {
            guard let index = pattern.firstIndex(where: { $0 == "*" || $0 == "?" }) else { return pattern.count }
            return pattern.distance(from: pattern.startIndex, to: index)
        }
    }
}
```

- [ ] **Step 4: Write `Flow/PathOwnership.swift`**

```swift
import Foundation

extension MindControl {
    /// Which system owns a source file: the system whose matching pattern is most specific.
    struct PathOwnership {
        enum Owner: Equatable, Sendable {
            case system(String)
            case none
            /// Two or more systems match equally specifically. Ids sorted.
            case tie([String])
        }

        private struct Entry {
            let system: String
            let regex: NSRegularExpression
            let specificity: Int
        }

        private let entries: [Entry]

        init(map: FlowMap) {
            entries = map.systems.flatMap { system in
                system.paths.map { Entry(system: system.id, regex: Glob.regex(for: $0), specificity: Glob.literalPrefixLength($0)) }
            }
        }

        func owner(of path: String) -> Owner {
            var best = -1
            var winners: [String] = []
            for entry in entries where Glob.matches(entry.regex, path) {
                if entry.specificity > best {
                    best = entry.specificity
                    winners = [entry.system]
                } else if entry.specificity == best, !winners.contains(entry.system) {
                    winners.append(entry.system)
                }
            }
            switch winners.count {
            case 0: return .none
            case 1: return .system(winners[0])
            default: return .tie(winners.sorted())
            }
        }
    }
}
```

- [ ] **Step 5: Run the tests to watch them pass**

Run: `.superpowers/mc-test.sh GlobTests PathOwnershipTests`
Expected: both suites report `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/MindControl/Flow/Glob.swift macos/Sources/Features/MindControl/Flow/PathOwnership.swift \
  macos/Tests/MindControl/GlobTests.swift macos/Tests/MindControl/PathOwnershipTests.swift
git commit -m "mindcontrol: path patterns, most specific system owns a file

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Read a project from the working tree or a git revision

This is the foundation for the future Changes view: the same reader loads "the map on `main`" and "the map on disk".

**Files:**
- Create: `macos/Sources/Features/MindControl/Flow/Git.swift`, `macos/Sources/Features/MindControl/Flow/FlowSource.swift`
- Create: `macos/Tests/MindControl/FlowSourceTests.swift`

**Interfaces:**
- Consumes: `ProjectScanner` and `SourceFilter` (existing), `FlowFile.relativePath` and `FlowFile.layoutRelativePath` (Task 3)
- Produces:
  - `MindControl.Git.run(_ root: URL, _ args: [String]) -> Data?` (stdout when the exit status is 0)
  - `Git.isRepository(_ root: URL) -> Bool`
  - `MindControl.FlowSnapshot(root: URL, flowData: Data?, layoutData: Data?, sourceFiles: [String], read: @Sendable (String) -> String?)`
  - `MindControl.FlowSource` (`.workingTree`, `.revision(String)`) with `snapshot(root: URL) throws -> FlowSnapshot`
  - `MindControl.FlowSourceError.unknownRevision(String)`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/FlowSourceTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowSource = MindControl.FlowSource

struct FlowSourceTests {
    @Test func sameProjectFromWorkingTreeAndCommit() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        try project.write(FlowFixtures.arcaSources)
        try project.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        try project.write("docs/notes.md", "not source")
        try project.commitAll("first")
        try project.write(".mindcontrol/flow.json", "{ \"edited\": true }")

        let disk = try FlowSource.workingTree.snapshot(root: project.url)
        let head = try FlowSource.revision("HEAD").snapshot(root: project.url)

        #expect(head.flowData.map { String(decoding: $0, as: UTF8.self) } == FlowFixtures.arcaJSON)
        #expect(disk.flowData.map { String(decoding: $0, as: UTF8.self) } == "{ \"edited\": true }")
        #expect(disk.sourceFiles == FlowFixtures.arcaSources.keys.sorted())
        #expect(head.sourceFiles == disk.sourceFiles)
        #expect(head.read("app/Sources/Audio/SpeechGate.swift") == FlowFixtures.arcaSources["app/Sources/Audio/SpeechGate.swift"])
        #expect(disk.read("app/Sources/Audio/SpeechGate.swift") == FlowFixtures.arcaSources["app/Sources/Audio/SpeechGate.swift"])
        #expect(disk.read("missing.swift") == nil)
    }

    @Test func missingFlowFileIsNil() throws {
        let project = try TempProject()
        try project.write("main.swift", "let x = 1\n")
        let snapshot = try FlowSource.workingTree.snapshot(root: project.url)
        #expect(snapshot.flowData == nil)
        #expect(snapshot.layoutData == nil)
        #expect(snapshot.sourceFiles == ["main.swift"])
    }

    @Test func unknownRevisionThrows() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        try project.write("main.swift", "let x = 1\n")
        try project.commitAll("first")
        #expect(throws: MindControl.FlowSourceError.unknownRevision("nope")) {
            try FlowSource.revision("nope").snapshot(root: project.url)
        }
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh FlowSourceTests`
Expected: build errors: `FlowSource` is not defined.

- [ ] **Step 3: Write `Flow/Git.swift`**

```swift
import Foundation

extension MindControl {
    enum Git {
        /// Runs `/usr/bin/git -C root args…`; returns stdout when git exits 0, else nil.
        static func run(_ root: URL, _ args: [String]) -> Data? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path] + args
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            // Read before waiting so a large output can't fill the pipe and deadlock.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        }

        static func isRepository(_ root: URL) -> Bool {
            run(root, ["rev-parse", "--is-inside-work-tree"]) != nil
        }
    }
}
```

- [ ] **Step 4: Write `Flow/FlowSource.swift`**

```swift
import Foundation

extension MindControl {
    /// Everything the flow map reads from a project, at one point in time.
    struct FlowSnapshot: Sendable {
        let root: URL
        let flowData: Data?
        let layoutData: Data?
        /// Feature source files (SourceFilter), relative to the root, sorted.
        let sourceFiles: [String]
        /// Contents of a file relative to the root, or nil.
        let read: @Sendable (String) -> String?
    }

    enum FlowSourceError: Error, Equatable {
        case unknownRevision(String)
    }

    /// Where a snapshot comes from: the files on disk, or a git revision (for comparing branches later).
    enum FlowSource: Equatable, Sendable {
        case workingTree
        case revision(String)

        func snapshot(root: URL) throws -> FlowSnapshot {
            switch self {
            case .workingTree:
                let files = try ProjectScanner().scan(pwd: root, shouldStop: { false }).files
                let read: @Sendable (String) -> String? = { path in
                    try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                }
                return FlowSnapshot(root: root,
                                    flowData: try? Data(contentsOf: root.appendingPathComponent(FlowFile.relativePath)),
                                    layoutData: try? Data(contentsOf: root.appendingPathComponent(FlowFile.layoutRelativePath)),
                                    sourceFiles: files, read: read)

            case .revision(let revision):
                guard Git.run(root, ["rev-parse", "--verify", "--quiet", "\(revision)^{commit}"]) != nil else {
                    throw FlowSourceError.unknownRevision(revision)
                }
                let listing = Git.run(root, ["ls-tree", "-r", "-z", "--name-only", revision]) ?? Data()
                let files = String(decoding: listing, as: UTF8.self).split(separator: "\0").map(String.init)
                    .filter(SourceFilter.isFeatureSource).sorted()
                let show: @Sendable (String) -> Data? = { path in Git.run(root, ["show", "\(revision):\(path)"]) }
                return FlowSnapshot(root: root,
                                    flowData: show(FlowFile.relativePath),
                                    layoutData: show(FlowFile.layoutRelativePath),
                                    sourceFiles: files,
                                    read: { path in show(path).map { String(decoding: $0, as: UTF8.self) } })
            }
        }
    }
}
```

`ProjectScanner().scan` resolves the git root itself. Here `root` is already the project root, so the returned files are relative to it. Check that the call matches `ProjectScanner.scan(pwd:shouldStop:)` (`macos/Sources/Features/MindControl/Data/ProjectScanner.swift:46`). It uses `.files`, the sorted kept list.

- [ ] **Step 5: Run the tests to watch them pass**

Run: `macos/skins-test.sh FlowSourceTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/Features/MindControl/Flow/Git.swift macos/Sources/Features/MindControl/Flow/FlowSource.swift \
  macos/Tests/MindControl/FlowSourceTests.swift
git commit -m "mindcontrol: read a project's flow files from disk or a git revision

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Check the map against the code (HealthReport)

**Files:**
- Create: `macos/Sources/Features/MindControl/Flow/FlowCheck.swift`
- Create: `macos/Tests/MindControl/FlowCheckTests.swift`

**Interfaces:**
- Consumes: `FlowMap` (Task 3), `PathOwnership` (Task 4), `FlowSnapshot` (Task 5), `SwiftSymbols.declaredTypes(in:)` (existing)
- Produces:
  - `MindControl.SourceLocation(file: String, line: Int)`
  - `MindControl.HealthReport` with:
    - `issues: [Issue]`, where `Issue(kind: IssueKind, subject: String, message: String)` and `IssueKind` is one of `.staleAnchor`, `.staleVia`, `.unverified`, `.unknownReference`, `.pathTie`, `.density`
    - `unmapped: [String]`
    - `age: Age` (`.hidden`, `.notCommitted`, `.commits(Int)`)
    - `staleParts`, `staleFlows`, `unverifiedFlows`, `brokenFlows: Set<String>` (part keys are `"system.part"`)
    - `viaLocations: [String: SourceLocation]`
    - `owners: [String: String]` (file → system)
    - `typeFiles: [String: String]` (Swift type → file)
    - `anchorFiles: [String: String]` (`"system.part"` → file)
    - `issueCount: Int`, `isHealthy: Bool`, `densityWarnings: [Issue]`
  - `MindControl.FlowCheck.run(map:snapshot:) -> HealthReport`, `FlowCheck.maxSystems = 20`, `maxPartsPerSystem = 8`, `maxFlows = 60`, `FlowCheck.isFileAnchor(_:)`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/FlowCheckTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowCheck = MindControl.FlowCheck
private typealias HealthReport = MindControl.HealthReport

struct FlowCheckTests {
    private func snapshot(_ files: [String: String]) -> MindControl.FlowSnapshot {
        MindControl.FlowSnapshot(root: URL(fileURLWithPath: "/tmp/mc-check"), flowData: nil, layoutData: nil,
                                 sourceFiles: files.keys.sorted(), read: { files[$0] })
    }

    private func check(_ map: MindControl.FlowMap = FlowFixtures.arca, _ files: [String: String] = FlowFixtures.arcaSources) -> HealthReport {
        FlowCheck.run(map: map, snapshot: snapshot(files))
    }

    @Test func healthyArcaHasNoIssues() {
        let report = check()
        #expect(report.issues == [])
        #expect(report.unmapped == [])
        #expect(report.isHealthy)
        #expect(report.viaLocations["pcm"] == MindControl.SourceLocation(file: "app/Sources/Audio/AudioCapture.swift", line: 4))
        #expect(report.viaLocations["reply"]?.file == "app/Sources/Agent/RealtimeAgentSession.swift")
        #expect(report.owners["app/Sources/Coordination/TapCoordinator.swift"] == "tap")
        #expect(report.anchorFiles["audio.gate"] == "app/Sources/Audio/SpeechGate.swift")
        #expect(report.typeFiles["ArcaLink"] == "app/Sources/BLE/ArcaLink.swift")
    }

    @Test func renamedTypeMakesAnchorStale() {
        var files = FlowFixtures.arcaSources
        files["app/Sources/Audio/SpeechGate.swift"] = "struct Gate {}\n"
        let report = check(FlowFixtures.arca, files)
        #expect(report.staleParts == ["audio.gate"])
        #expect(report.issues.contains { $0.kind == .staleAnchor && $0.subject == "audio.gate" })
    }

    @Test func typeAnchorMustBeDeclaredInItsOwnSystem() {
        var files = FlowFixtures.arcaSources
        files["app/Sources/Audio/SpeechGate.swift"] = nil
        files["app/Sources/Agent/SpeechGate.swift"] = "struct SpeechGate {}\n"
        #expect(check(FlowFixtures.arca, files).staleParts.contains("audio.gate"))
    }

    @Test func fileAnchorsWorkWithoutSwift() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [
            { "id": "relay", "name": "Relay", "paths": ["relay/src/**"],
              "parts": [ { "id": "pipe", "name": "pipe", "anchor": "relay/src/pipe.ts" },
                         { "id": "gone", "name": "gone", "anchor": "relay/src/gone.ts" } ] },
            { "id": "apns", "name": "APNs", "external": true } ],
          "flows": [ { "id": "push", "from": "relay.pipe", "to": "apns", "kind": "data", "carries": "alert", "via": "push" } ] }
        """#)
        let report = check(map, ["relay/src/pipe.ts": "export function push() {}\n"])
        #expect(report.anchorFiles["relay.pipe"] == "relay/src/pipe.ts")
        #expect(report.staleParts == ["relay.gone"])
        #expect(report.viaLocations["push"] == MindControl.SourceLocation(file: "relay/src/pipe.ts", line: 1))
    }

    @Test func missingViaIsStaleAndNoViaIsUnverified() {
        var files = FlowFixtures.arcaSources
        files["app/Sources/Audio/AudioCapture.swift"] = "final class AudioCapture {\n    func beginTransmission() {}\n}\n"
        let report = check(FlowFixtures.arca, files)
        #expect(report.staleFlows.isSuperset(of: ["pcm", "check", "commit", "discard"]))

        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A", "paths": ["a/**"] }, { "id": "x", "name": "X", "external": true },
                       { "id": "y", "name": "Y", "external": true } ],
          "flows": [ { "id": "f", "from": "a", "to": "x", "kind": "data", "carries": "c" },
                     { "id": "g", "from": "x", "to": "y", "kind": "data", "carries": "c" } ] }
        """#)
        let second = check(map, ["a/main.swift": "let x = 1\n"])
        #expect(second.unverifiedFlows == ["f"])
        #expect(second.staleFlows.isEmpty)
        #expect(second.issues.filter { $0.kind == .unverified }.map(\.subject) == ["f"])
    }

    @Test func unknownReferencesBreakOnlyThatFlow() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A", "paths": ["a/**"], "parts": [ { "id": "p", "name": "P" } ] } ],
          "flows": [ { "id": "ok", "from": "a.p", "to": "a", "kind": "data", "carries": "c", "via": "x" },
                     { "id": "bad", "from": "a.q", "to": "nope", "kind": "data", "carries": "c" } ],
          "features": [ { "id": "f", "name": "F", "route": ["ok", "ghost"] } ] }
        """#)
        let report = check(map, ["a/main.swift": "let x = 1\n"])
        #expect(report.brokenFlows == ["bad"])
        #expect(report.issues.contains { $0.kind == .unknownReference && $0.subject == "bad" && $0.message.contains("nope") && $0.message.contains("a.q") })
        #expect(report.issues.contains { $0.kind == .unknownReference && $0.subject == "f" && $0.message.contains("ghost") })
        #expect(report.viaLocations["ok"] != nil)
    }

    @Test func pathTieIsReportedAndUnmapped() {
        let map = FlowFixtures.map(#"""
        { "version": 1, "systems": [ { "id": "a", "name": "A", "paths": ["app/*.swift"] },
                                     { "id": "b", "name": "B", "paths": ["app/*.swift"] } ] }
        """#)
        let report = check(map, ["app/x.swift": "let x = 1\n"])
        #expect(report.unmapped == ["app/x.swift"])
        #expect(report.issues.contains { $0.kind == .pathTie && $0.message.contains("a") && $0.message.contains("b") })
    }

    @Test func unmappedFilesCountAsOneIssue() {
        var files = FlowFixtures.arcaSources
        files["app/Sources/Other/X.swift"] = "let x = 1\n"
        files["app/Sources/Other/Y.swift"] = "let y = 1\n"
        let report = check(FlowFixtures.arca, files)
        #expect(report.unmapped == ["app/Sources/Other/X.swift", "app/Sources/Other/Y.swift"])
        #expect(report.issueCount == 1)
    }

    @Test func patternMatchingNothingIsHarmless() {
        let map = FlowFixtures.map(#"{ "version": 1, "systems": [ { "id": "a", "name": "A", "paths": ["nothing/**"] } ] }"#)
        let report = check(map, [:])
        #expect(report.isHealthy)
    }

    @Test func densityWarningsAtTheirLimits() {
        let systems = (0...20).map { #"{ "id": "s\#($0)", "name": "S\#($0)" }"# }
        let parts = (0...8).map { #"{ "id": "p\#($0)", "name": "P\#($0)" }"# }.joined(separator: ",")
        let flows = (0...60).map { #"{ "id": "f\#($0)", "from": "s0", "to": "s1", "kind": "data", "carries": "c" }"# }
        let json = #"{ "version": 1, "systems": [\#(systems.joined(separator: ",")), { "id": "big", "name": "Big", "parts": [\#(parts)] }], "flows": [\#(flows.joined(separator: ","))] }"#
        let warnings = check(FlowFixtures.map(json), [:]).densityWarnings.map(\.message)
        #expect(warnings.count == 3)
        #expect(warnings.contains { $0.contains("22 systems") })
        #expect(warnings.contains { $0.contains("Big has 9 parts") })
        #expect(warnings.contains { $0.contains("61 flows") })
    }

    @Test(arguments: [("relay/src/pipe.ts", true), ("AudioCapture", false), ("Package.swift", true), ("README", false)])
    func fileAnchorDetection(anchor: String, isFile: Bool) {
        #expect(FlowCheck.isFileAnchor(anchor) == isFile)
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh FlowCheckTests`
Expected: build errors: `FlowCheck` and `HealthReport` are not defined.

- [ ] **Step 3: Write `Flow/FlowCheck.swift`**

```swift
import Foundation

extension MindControl {
    struct SourceLocation: Equatable, Sendable {
        let file: String
        /// 1-based.
        let line: Int
    }

    /// Whether a flow map still matches the code, plus the lookups search and the side panel need.
    struct HealthReport: Equatable, Sendable {
        enum IssueKind: String, Equatable, Sendable {
            case staleAnchor, staleVia, unverified, unknownReference, pathTie, density
        }

        struct Issue: Equatable, Sendable {
            let kind: IssueKind
            /// A part key ("audio.gate"), flow id, feature id, file path, or "map" for density.
            let subject: String
            let message: String
        }

        enum Age: Equatable, Sendable {
            case hidden
            case notCommitted
            case commits(Int)
        }

        var issues: [Issue] = []
        var unmapped: [String] = []
        var age: Age = .hidden
        var staleParts: Set<String> = []
        var staleFlows: Set<String> = []
        var unverifiedFlows: Set<String> = []
        /// Flows naming an unknown system or part; they are not drawn.
        var brokenFlows: Set<String> = []
        var viaLocations: [String: SourceLocation] = [:]
        /// Source file → owning system id; files with no single owner are absent.
        var owners: [String: String] = [:]
        /// Swift type name → declaring file (the first by path order).
        var typeFiles: [String: String] = [:]
        /// Part key ("audio.capture") → the file its anchor resolves to.
        var anchorFiles: [String: String] = [:]

        var densityWarnings: [Issue] { issues.filter { $0.kind == .density } }
        /// Every issue, plus one for the unmapped list as a whole.
        var issueCount: Int { issues.count + (unmapped.isEmpty ? 0 : 1) }
        var isHealthy: Bool { issueCount == 0 }
    }

    enum FlowCheck {
        static let maxSystems = 20
        static let maxPartsPerSystem = 8
        static let maxFlows = 60

        /// An anchor with a `/` or a file extension is a path; anything else is a Swift type name.
        static func isFileAnchor(_ anchor: String) -> Bool {
            anchor.contains("/") || !(anchor as NSString).pathExtension.isEmpty
        }

        static func run(map: FlowMap, snapshot: FlowSnapshot) -> HealthReport {
            var report = HealthReport()
            var contents: [String: String] = [:]
            func source(_ file: String) -> String? {
                if let cached = contents[file] { return cached }
                let text = snapshot.read(file)
                if let text { contents[file] = text }
                return text
            }

            // Ownership and unmapped files.
            let ownership = PathOwnership(map: map)
            var filesBySystem: [String: [String]] = [:]
            for file in snapshot.sourceFiles {
                switch ownership.owner(of: file) {
                case .system(let id):
                    report.owners[file] = id
                    filesBySystem[id, default: []].append(file)
                case .none:
                    report.unmapped.append(file)
                case .tie(let ids):
                    report.unmapped.append(file)
                    report.issues.append(.init(kind: .pathTie, subject: file,
                                               message: "\(file) matches \(ids.joined(separator: " and ")) equally. Make one pattern more specific."))
                }
            }

            // Swift types, globally and per owning system.
            var typesBySystem: [String: [String: String]] = [:]
            for file in snapshot.sourceFiles where file.hasSuffix(".swift") {
                guard let text = source(file) else { continue }
                for type in SwiftSymbols.declaredTypes(in: text) {
                    if report.typeFiles[type] == nil { report.typeFiles[type] = file }
                    if let owner = report.owners[file], typesBySystem[owner]?[type] == nil {
                        typesBySystem[owner, default: [:]][type] = file
                    }
                }
            }

            // Part anchors.
            let sourceSet = Set(snapshot.sourceFiles)
            for system in map.systems {
                for part in system.parts {
                    guard let anchor = part.anchor else { continue }
                    let key = "\(system.id).\(part.id)"
                    if isFileAnchor(anchor) {
                        if sourceSet.contains(anchor) || snapshot.read(anchor) != nil {
                            report.anchorFiles[key] = anchor
                        } else {
                            report.staleParts.insert(key)
                            report.issues.append(.init(kind: .staleAnchor, subject: key, message: "\(part.name): file \(anchor) not found."))
                        }
                    } else if let file = typesBySystem[system.id]?[anchor] {
                        report.anchorFiles[key] = file
                    } else {
                        report.staleParts.insert(key)
                        report.issues.append(.init(kind: .staleAnchor, subject: key,
                                                   message: "\(part.name): type \(anchor) isn't declared in \(system.name)'s files."))
                    }
                }
            }

            // References.
            func resolves(_ endpoint: FlowMap.Endpoint) -> Bool {
                guard let system = map.system(endpoint.system) else { return false }
                return endpoint.part.map { system.part($0) != nil } ?? true
            }
            for flow in map.flows {
                let unknown = [flow.from, flow.to].filter { !resolves($0) }.map(\.description)
                guard !unknown.isEmpty else { continue }
                report.brokenFlows.insert(flow.id)
                report.issues.append(.init(kind: .unknownReference, subject: flow.id,
                                           message: "Flow \(flow.id) names unknown \(unknown.joined(separator: " and ")); it isn't drawn."))
            }
            for feature in map.features {
                let unknown = feature.route.filter { map.flow($0) == nil }
                guard !unknown.isEmpty else { continue }
                report.issues.append(.init(kind: .unknownReference, subject: feature.id,
                                           message: "\(feature.name) names unknown flows: \(unknown.joined(separator: ", "))."))
            }

            // Hand-offs.
            for flow in map.flows where !report.brokenFlows.contains(flow.id) {
                guard let from = map.system(flow.from.system), let to = map.system(flow.to.system) else { continue }
                if from.external, to.external { continue }
                let searched = from.external ? to : from
                guard let via = flow.via else {
                    report.unverifiedFlows.insert(flow.id)
                    report.issues.append(.init(kind: .unverified, subject: flow.id,
                                               message: "Flow \(flow.id) has no via. Add the call where \(flow.carries) is handed over."))
                    continue
                }
                if let location = find(word: via, in: filesBySystem[searched.id] ?? [], source: source) {
                    report.viaLocations[flow.id] = location
                } else {
                    report.staleFlows.insert(flow.id)
                    report.issues.append(.init(kind: .staleVia, subject: flow.id,
                                               message: "Flow \(flow.id): \(via) isn't found in \(searched.name)'s files."))
                }
            }

            // Density.
            if map.systems.count > maxSystems {
                report.issues.append(.init(kind: .density, subject: "map",
                                           message: "Map is getting dense: \(map.systems.count) systems (limit \(maxSystems)). Consider merging."))
            }
            for system in map.systems where system.parts.count > maxPartsPerSystem {
                report.issues.append(.init(kind: .density, subject: system.id,
                                           message: "\(system.name) has \(system.parts.count) parts (limit \(maxPartsPerSystem)). Consider merging."))
            }
            if map.flows.count > maxFlows {
                report.issues.append(.init(kind: .density, subject: "map",
                                           message: "Map is getting dense: \(map.flows.count) flows (limit \(maxFlows)). Consider merging."))
            }
            return report
        }

        /// First whole-word match of `word`, searching `files` in order.
        static func find(word: String, in files: [String], source: (String) -> String?) -> SourceLocation? {
            guard let regex = try? NSRegularExpression(pattern: #"\b\#(NSRegularExpression.escapedPattern(for: word))\b"#) else { return nil }
            for file in files {
                guard let text = source(file) else { continue }
                let ns = text as NSString
                guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
                let line = 1 + ns.substring(to: match.range.location).filter { $0 == "\n" }.count
                return SourceLocation(file: file, line: line)
            }
            return nil
        }
    }
}
```

Note: `func source` is a nested function that captures and mutates `contents`, so pass it as `source: source`. If the Swift 5 compiler rejects passing a nested function that captures a mutable local as a non-escaping argument, turn the cache into a small `final class SourceCache { var contents: [String: String] }` local instance and keep the same behaviour.

- [ ] **Step 4: Run the tests to watch them pass**

Run: `macos/skins-test.sh FlowCheckTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/Flow/FlowCheck.swift macos/Tests/MindControl/FlowCheckTests.swift
git commit -m "mindcontrol: check flow maps against the code

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Map age

**Files:**
- Create: `macos/Sources/Features/MindControl/Flow/FlowAge.swift`
- Create: `macos/Tests/MindControl/FlowAgeTests.swift`

**Interfaces:**
- Consumes: `Git` (Task 5), `HealthReport.Age` (Task 6), `FlowFile.relativePath` (Task 3)
- Produces: `MindControl.FlowAge.age(root: URL, map: FlowMap) -> HealthReport.Age`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/FlowAgeTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowAge = MindControl.FlowAge

struct FlowAgeTests {
    @Test func hiddenOutsideGit() throws {
        let project = try TempProject()
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.arca) == .hidden)
    }

    @Test func notCommittedYet() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        try project.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.arca) == .notCommitted)
    }

    @Test func countsOnlyCommitsTouchingMappedPaths() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        try project.write(FlowFixtures.arcaSources)
        try project.write(".mindcontrol/flow.json", FlowFixtures.arcaJSON)
        try project.commitAll("map")
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.arca) == .commits(0))

        try project.write("app/Sources/Audio/New.swift", "struct New {}\n")
        try project.commitAll("audio change")
        try project.write("docs/notes.md", "notes\n")
        try project.commitAll("docs change")
        #expect(FlowAge.age(root: project.url, map: FlowFixtures.arca) == .commits(1))
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh FlowAgeTests`
Expected: build error: `FlowAge` is not defined.

- [ ] **Step 3: Write `Flow/FlowAge.swift`**

```swift
import Foundation

extension MindControl {
    /// How far the code has moved since the flow map was last committed.
    enum FlowAge {
        static func age(root: URL, map: FlowMap) -> HealthReport.Age {
            guard Git.isRepository(root) else { return .hidden }
            guard let log = Git.run(root, ["log", "-1", "--format=%H", "--", FlowFile.relativePath]) else { return .notCommitted }
            let sha = String(decoding: log, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sha.isEmpty else { return .notCommitted }
            let pathspecs = map.systems.flatMap(\.paths).map { ":(glob)\($0)" }
            guard !pathspecs.isEmpty,
                  let output = Git.run(root, ["rev-list", "--count", "\(sha)..HEAD", "--"] + pathspecs) else { return .commits(0) }
            return .commits(Int(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
        }
    }
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `macos/skins-test.sh FlowAgeTests`
Expected: `** TEST SUCCEEDED **`.

Git's `:(glob)` pathspec treats `**` like our `Glob`, but a pattern with no wildcard only matches that exact path or folder. That is the same meaning, so no conversion is needed.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/Flow/FlowAge.swift macos/Tests/MindControl/FlowAgeTests.swift
git commit -m "mindcontrol: count commits to mapped code since the map changed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Feature routes as numbered steps

**Files:**
- Create: `macos/Sources/Features/MindControl/Flow/FeatureSteps.swift`
- Create: `macos/Tests/MindControl/FeatureStepsTests.swift`

**Interfaces:**
- Consumes: `FlowMap` (Task 3), `HealthReport` (Task 6)
- Produces:
  - `MindControl.FeatureStep(number: Int, flowID: String, from: String, to: String, carries: String, kind: FlowMap.Kind, when: String?, status: Status)`, where `Status` is `.ok`, `.stale` or `.unverified`
  - `MindControl.StepGroup(when: String?, steps: [FeatureStep])`
  - `MindControl.FeatureSteps.groups(for:map:report:) -> (groups: [StepGroup], unknown: [String])`
  - `FeatureSteps.name(of: FlowMap.Endpoint, in: FlowMap) -> String`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/FeatureStepsTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FeatureSteps = MindControl.FeatureSteps

struct FeatureStepsTests {
    @Test func speechStepsGroupByCondition() throws {
        let map = FlowFixtures.arca
        let feature = try #require(map.feature("speech"))
        let result = FeatureSteps.groups(for: feature, map: map, report: MindControl.HealthReport())
        #expect(result.unknown == [])
        #expect(result.groups.map(\.when) == [nil, "words heard", "nothing heard", nil])
        #expect(result.groups.map { $0.steps.map(\.flowID) } == [["press", "event", "begin", "pcm", "check"], ["commit"], ["discard"], ["send", "reply"]])
        #expect(result.groups.flatMap(\.steps).map(\.number) == Array(1...9))
        let first = try #require(result.groups.first?.steps.first)
        #expect(first.from == "Ring")
        #expect(first.to == "BLE link › ArcaLink")
        #expect(first.carries == "press DOWN / UP")
        #expect(first.kind == .control)
    }

    @Test func statusComesFromTheReport() throws {
        let map = FlowFixtures.arca
        var report = MindControl.HealthReport()
        report.staleFlows = ["pcm"]
        report.unverifiedFlows = ["press"]
        let steps = FeatureSteps.groups(for: try #require(map.feature("speech")), map: map, report: report).groups.flatMap(\.steps)
        #expect(steps.first { $0.flowID == "pcm" }?.status == .stale)
        #expect(steps.first { $0.flowID == "press" }?.status == .unverified)
        #expect(steps.first { $0.flowID == "event" }?.status == .ok)
    }

    @Test func unknownAndBrokenFlowsAreListedNotNumbered() {
        let map = FlowFixtures.arca
        var report = MindControl.HealthReport()
        report.brokenFlows = ["event"]
        let feature = MindControl.FlowMap.Feature(id: "f", name: "F", route: ["press", "ghost", "event", "begin"])
        let result = FeatureSteps.groups(for: feature, map: map, report: report)
        #expect(result.unknown == ["ghost", "event"])
        #expect(result.groups.flatMap(\.steps).map(\.number) == [1, 2])
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh FeatureStepsTests`
Expected: build error: `FeatureSteps` is not defined.

- [ ] **Step 3: Write `Flow/FeatureSteps.swift`**

```swift
import Foundation

extension MindControl {
    struct FeatureStep: Equatable, Sendable {
        enum Status: Equatable, Sendable { case ok, stale, unverified }

        let number: Int
        let flowID: String
        let from: String
        let to: String
        let carries: String
        let kind: FlowMap.Kind
        let when: String?
        let status: Status
    }

    /// Consecutive steps sharing one `when`.
    struct StepGroup: Equatable, Sendable {
        let when: String?
        var steps: [FeatureStep]
    }

    enum FeatureSteps {
        /// The feature's route as numbered steps. Flows that don't exist or can't be drawn are listed in `unknown`.
        static func groups(for feature: FlowMap.Feature, map: FlowMap, report: HealthReport) -> (groups: [StepGroup], unknown: [String]) {
            var groups: [StepGroup] = []
            var unknown: [String] = []
            var number = 0
            for id in feature.route {
                guard let flow = map.flow(id), !report.brokenFlows.contains(id) else {
                    unknown.append(id)
                    continue
                }
                number += 1
                let status: FeatureStep.Status = report.staleFlows.contains(id) ? .stale
                    : report.unverifiedFlows.contains(id) ? .unverified : .ok
                let step = FeatureStep(number: number, flowID: id, from: name(of: flow.from, in: map), to: name(of: flow.to, in: map),
                                       carries: flow.carries, kind: flow.kind, when: flow.when, status: status)
                if let last = groups.indices.last, groups[last].when == flow.when {
                    groups[last].steps.append(step)
                } else {
                    groups.append(StepGroup(when: flow.when, steps: [step]))
                }
            }
            return (groups, unknown)
        }

        /// "Audio" for a system, "Audio › AudioCapture" for a part.
        static func name(of endpoint: FlowMap.Endpoint, in map: FlowMap) -> String {
            guard let system = map.system(endpoint.system) else { return endpoint.description }
            guard let partID = endpoint.part else { return system.name }
            return "\(system.name) › \(system.part(partID)?.name ?? partID)"
        }
    }
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `macos/skins-test.sh FeatureStepsTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/Flow/FeatureSteps.swift macos/Tests/MindControl/FeatureStepsTests.swift
git commit -m "mindcontrol: feature routes as numbered, condition-grouped steps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 9: Layered layout

**Files:**
- Create: `macos/Sources/Features/MindControl/Layout/Layering.swift`
- Create: `macos/Tests/MindControl/LayeringTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `MindControl.Layering.Edge(from: String, to: String)` (Hashable)
  - `MindControl.Layering.Result` with `rank: [String: Int]`, `order: [String: Int]`, `reversed: Set<Edge>`, `layers: [[String]]`
  - `Layering.layout(nodes: [String], edges: [Edge], pinFirst: Set<String> = [], pinLast: Set<String> = []) -> Result`

**Ruling carried from the spec:** the spec says cycles are "broken by reversing the fewest arrows". Finding the true minimum is NP-hard, so this uses a deterministic depth-first pass: it starts from source nodes, takes ids in sorted order, and reverses back edges. Ledger this as `Task 9: Ruling: DFS feedback-arc heuristic instead of a minimum — exact minimum is NP-hard; output is deterministic — cost if wrong: an occasional extra return arrow`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/LayeringTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

private typealias Layering = MindControl.Layering
private typealias Edge = MindControl.Layering.Edge

struct LayeringTests {
    @Test func chainRanksLeftToRight() {
        let result = Layering.layout(nodes: ["c", "a", "b"], edges: [Edge(from: "a", to: "b"), Edge(from: "b", to: "c")])
        #expect(result.rank == ["a": 0, "b": 1, "c": 2])
        #expect(result.layers == [["a"], ["b"], ["c"]])
    }

    @Test func cycleIsBrokenFromTheSource() {
        let result = Layering.layout(nodes: ["a", "b", "x"],
                                     edges: [Edge(from: "a", to: "b"), Edge(from: "b", to: "a"), Edge(from: "x", to: "a")])
        #expect(result.rank == ["x": 0, "a": 1, "b": 2])
        #expect(result.reversed == [Edge(from: "b", to: "a")])
    }

    @Test func pinnedSendersFirstAndReceiversLast() {
        let result = Layering.layout(nodes: ["s", "a", "b", "r"],
                                     edges: [Edge(from: "s", to: "a"), Edge(from: "a", to: "b"), Edge(from: "a", to: "r")],
                                     pinFirst: ["s"], pinLast: ["r"])
        #expect(result.rank["s"] == 0)
        #expect(result.rank["r"] == 3)
        #expect(result.rank["b"] == 2)
    }

    @Test func orderingRemovesACrossing() {
        let result = Layering.layout(nodes: ["a", "b", "c", "d"], edges: [Edge(from: "a", to: "d"), Edge(from: "b", to: "c")])
        #expect(result.layers[0] == ["a", "b"])
        #expect(result.layers[1] == ["d", "c"])
        #expect(result.order["d"] == 0)
    }

    @Test func sameResultForShuffledInput() {
        let nodes = ["a", "b", "c", "d", "e"]
        let edges = [Edge(from: "a", to: "c"), Edge(from: "b", to: "c"), Edge(from: "c", to: "d"), Edge(from: "d", to: "b"), Edge(from: "a", to: "e")]
        let first = Layering.layout(nodes: nodes, edges: edges)
        let second = Layering.layout(nodes: nodes.reversed(), edges: edges.reversed())
        #expect(first == second)
    }

    @Test func selfLoopsUnknownNodesAndEmptyInputAreIgnored() {
        let result = Layering.layout(nodes: ["a"], edges: [Edge(from: "a", to: "a"), Edge(from: "a", to: "ghost")])
        #expect(result.rank == ["a": 0])
        #expect(Layering.layout(nodes: [], edges: []).layers.isEmpty)
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh LayeringTests`
Expected: build error: `Layering` is not defined.

- [ ] **Step 3: Write `Layout/Layering.swift`**

```swift
import Foundation

extension MindControl {
    /// A deterministic layered (Sugiyama-style) layout: break cycles, rank by longest path, then order
    /// each rank by barycenter sweeps to reduce crossings. Ties always fall back to ids.
    enum Layering {
        struct Edge: Hashable, Sendable {
            let from: String
            let to: String
        }

        struct Result: Equatable, Sendable {
            /// Column index, 0 on the left.
            let rank: [String: Int]
            /// Position within its rank, 0 at the top.
            let order: [String: Int]
            /// Edges that point against the columns to break cycles; drawn as return arrows.
            let reversed: Set<Edge>
            let layers: [[String]]
        }

        static let sweeps = 4

        static func layout(nodes: [String], edges: [Edge], pinFirst: Set<String> = [], pinLast: Set<String> = []) -> Result {
            let nodes = Array(Set(nodes)).sorted()
            guard !nodes.isEmpty else { return Result(rank: [:], order: [:], reversed: [], layers: []) }
            let nodeSet = Set(nodes)

            var unique: [Edge] = []
            var seen = Set<Edge>()
            for edge in edges.sorted(by: { ($0.from, $0.to) < ($1.from, $1.to) })
            where edge.from != edge.to && nodeSet.contains(edge.from) && nodeSet.contains(edge.to) && seen.insert(edge).inserted {
                unique.append(edge)
            }

            // 1. Break cycles: depth-first from sources, reversing edges back onto the stack.
            var successors: [String: [String]] = [:]
            for edge in unique { successors[edge.from, default: []].append(edge.to) }
            var state: [String: Int] = [:]   // 1 on the stack, 2 finished
            var reversed = Set<Edge>()
            func visit(_ node: String) {
                state[node] = 1
                for next in successors[node] ?? [] {
                    switch state[next] {
                    case nil: visit(next)
                    case 1: reversed.insert(Edge(from: node, to: next))
                    default: break
                    }
                }
                state[node] = 2
            }
            let hasIncoming = Set(unique.map(\.to))
            for node in nodes where !hasIncoming.contains(node) && state[node] == nil { visit(node) }
            for node in nodes where state[node] == nil { visit(node) }
            let dag = unique.map { reversed.contains($0) ? Edge(from: $0.to, to: $0.from) : $0 }

            // 2. Rank by longest path.
            var indegree = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
            var out: [String: [String]] = [:]
            for edge in dag {
                indegree[edge.to, default: 0] += 1
                out[edge.from, default: []].append(edge.to)
            }
            var rank = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
            var queue = nodes.filter { indegree[$0] == 0 }
            var head = 0
            while head < queue.count {
                let node = queue[head]
                head += 1
                for next in (out[node] ?? []).sorted() {
                    rank[next] = max(rank[next] ?? 0, (rank[node] ?? 0) + 1)
                    indegree[next, default: 0] -= 1
                    if indegree[next] == 0 { queue.append(next) }
                }
            }

            // 3. Pins: senders in the first column, receivers after everything else.
            for node in pinFirst where nodeSet.contains(node) { rank[node] = 0 }
            let unpinned = nodes.filter { !pinLast.contains($0) }
            if let lastUnpinned = unpinned.compactMap({ rank[$0] }).max() {
                for node in nodes where pinLast.contains(node) { rank[node] = max(rank[node] ?? 0, lastUnpinned + 1) }
            }

            // Close gaps so columns are 0, 1, 2… with none empty.
            let distinct = Array(Set(rank.values)).sorted()
            let compact = Dictionary(uniqueKeysWithValues: distinct.enumerated().map { ($1, $0) })
            for node in nodes { rank[node] = compact[rank[node] ?? 0] ?? 0 }

            // 4. Order within ranks by barycenter sweeps.
            var layers = Array(repeating: [String](), count: distinct.count)
            for node in nodes { layers[rank[node] ?? 0].append(node) }
            var predecessors: [String: [String]] = [:]
            var followers: [String: [String]] = [:]
            for edge in dag {
                predecessors[edge.to, default: []].append(edge.from)
                followers[edge.from, default: []].append(edge.to)
            }
            var position: [String: Double] = [:]
            func reindex() {
                for layer in layers { for (index, node) in layer.enumerated() { position[node] = Double(index) } }
            }
            func reorder(_ layer: [String], by neighbours: [String: [String]]) -> [String] {
                layer.map { node -> (node: String, bary: Double, current: Double) in
                    let current = position[node] ?? 0
                    let linked = neighbours[node] ?? []
                    let bary = linked.isEmpty ? current : linked.map { position[$0] ?? 0 }.reduce(0, +) / Double(linked.count)
                    return (node, bary, current)
                }
                .sorted { ($0.bary, $0.current, $0.node) < ($1.bary, $1.current, $1.node) }
                .map(\.node)
            }
            reindex()
            for _ in 0..<sweeps {
                for r in layers.indices.dropFirst() {
                    layers[r] = reorder(layers[r], by: predecessors)
                    reindex()
                }
                for r in layers.indices.dropLast().reversed() {
                    layers[r] = reorder(layers[r], by: followers)
                    reindex()
                }
            }

            var order: [String: Int] = [:]
            for layer in layers { for (index, node) in layer.enumerated() { order[node] = index } }
            return Result(rank: rank, order: order, reversed: reversed, layers: layers)
        }
    }
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `macos/skins-test.sh LayeringTests`
Expected: `** TEST SUCCEEDED **`.

If `orderingRemovesACrossing` reports `["c", "d"]`, the up-sweep has undone the down-sweep. Check that the down-sweep uses `predecessors`, the up-sweep uses `followers`, and both re-index after each layer.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/Layout/Layering.swift macos/Tests/MindControl/LayeringTests.swift
git commit -m "mindcontrol: deterministic layered layout

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Ledger the Task 9 ruling above in the same call.

---

### Task 10: The main map layout, arrow routing and saved positions

**Files:**
- Create: `macos/Sources/Features/MindControl/Layout/MapLayout.swift`, `Layout/FlowLayout.swift`, `Layout/ArrowRouter.swift`, `Layout/LayoutStore.swift` (all under `macos/Sources/Features/MindControl/`)
- Create: `macos/Tests/MindControl/FlowLayoutTests.swift`, `macos/Tests/MindControl/ArrowRouterTests.swift`, `macos/Tests/MindControl/LayoutStoreTests.swift`

**Interfaces:**
- Consumes: `FlowMap` (Task 3), `Layering` (Task 9)
- Produces:
  - `MindControl.ZoomLevels`:
    - `zoneToSystems: ClosedRange<CGFloat>` (0.22...0.34)
    - `systemsToParts: ClosedRange<CGFloat>` (0.85...1.15)
    - `arrowLevel(at:) -> MapLayout.ArrowLevel`
    - `partsVisible(at:) -> Bool`
  - `MindControl.LayoutMetrics`: constants
  - `MindControl.MapLayout`:
    - `boxes: [Box]`, `arrows: [ArrowSpec]`, `fixedLevel: Bool`
    - `box(_:) -> Box?`, `bounds: CGRect`, `static zoneBoxID(_:) -> String`
    - `Box(id, kind: BoxKind, rect, title, subtitle: String?, external: Bool, tint: Int, partCount: Int)`, where `BoxKind` is `.zone`, `.system` or `.part`
    - `ArrowLevel`: `.zone`, `.system`, `.part`
    - `ArrowSpec(id, level, from, to, kind: FlowMap.Kind, flowIDs: [String], label: String, conditional: Bool, weight: Int)`
  - `MindControl.FlowLayout.layout(map:broken:saved:) -> MapLayout`
  - `MindControl.FlowLayout.arrows(map:flows:) -> [MapLayout.ArrowSpec]`
  - `MindControl.Curve(p0, p1, p2, p3)` with `point(at:)`, `tangent(at:)`, `mid`, `distance(to:)`
  - `MindControl.ArrowRouter.curves(for: MapLayout) -> [String: Curve]` (keyed by arrow id)
  - `MindControl.LayoutStore.decode(_ data: Data?) -> [String: CGPoint]`, `.encode(_:) -> Data`, `.write(_:root:) throws`

**ID conventions** (used by every later task):
- a system box's id is the system id (`audio`)
- a part box's id is `system.part` (`audio.capture`)
- a zone box's id is `zone:<id>`
- arrow ids are `flow:<flowID>` (part level), `sys:<a>><b>` (system level) and `zone:<a>><b>` (zone level)

- [ ] **Step 1: Write the failing layout tests**

`macos/Tests/MindControl/FlowLayoutTests.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias FlowLayout = MindControl.FlowLayout
private typealias MapLayout = MindControl.MapLayout
private typealias FlowMap = MindControl.FlowMap

struct FlowLayoutTests {
    private func rect(_ layout: MapLayout, _ id: String) -> CGRect {
        layout.box(id)?.rect ?? .null
    }

    @Test func sameInputSameOutput() {
        #expect(FlowLayout.layout(map: FlowFixtures.arca, broken: []) == FlowLayout.layout(map: FlowFixtures.arca, broken: []))
    }

    @Test func zonesOrderedByDataFlowEvenWithACrossZoneCycle() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        let ring = rect(layout, "zone:ring"), phone = rect(layout, "zone:phone"), cloud = rect(layout, "zone:cloud")
        #expect(ring.maxX < phone.minX)
        #expect(phone.maxX < cloud.minX)
    }

    @Test func zonesContainTheirSystemsAndDoNotOverlap() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        let map = FlowFixtures.arca
        for system in map.systems {
            #expect(rect(layout, "zone:\(system.zone!)").contains(rect(layout, system.id)), "\(system.id)")
        }
        let zones = layout.boxes.filter { $0.kind == .zone }
        for (i, a) in zones.enumerated() { for b in zones[(i + 1)...] { #expect(!a.rect.intersects(b.rect)) } }
    }

    @Test func dataSourceSitsLeftOfWhatItFeeds() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        #expect(rect(layout, "audio").maxX < rect(layout, "agent").minX)
    }

    @Test func controlFlowsDoNotMoveSystems() {
        let arca = FlowFixtures.arca
        let dataOnly = FlowMap(zones: arca.zones, systems: arca.systems, flows: arca.flows.filter { $0.kind == .data }, features: [])
        let a = FlowLayout.layout(map: arca, broken: []), b = FlowLayout.layout(map: dataOnly, broken: [])
        for system in arca.systems { #expect(rect(a, system.id) == rect(b, system.id), "\(system.id)") }
    }

    @Test func externalSenderFirstAndReceiverLast() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "s", "name": "S", "external": true }, { "id": "a", "name": "A" }, { "id": "b", "name": "B" },
                       { "id": "c", "name": "C" }, { "id": "d", "name": "D" }, { "id": "r", "name": "R", "external": true } ],
          "flows": [ { "id": "1", "from": "s", "to": "a", "kind": "data", "carries": "x" },
                     { "id": "2", "from": "a", "to": "b", "kind": "data", "carries": "x" },
                     { "id": "3", "from": "b", "to": "c", "kind": "data", "carries": "x" },
                     { "id": "4", "from": "c", "to": "d", "kind": "data", "carries": "x" },
                     { "id": "5", "from": "a", "to": "r", "kind": "data", "carries": "x" } ] }
        """#)
        let layout = FlowLayout.layout(map: map, broken: [])
        let systems = layout.boxes.filter { $0.kind == .system }
        #expect(systems.allSatisfy { $0.id == "s" || rect(layout, "s").maxX < $0.rect.minX })
        #expect(systems.allSatisfy { $0.id == "r" || $0.rect.maxX < rect(layout, "r").minX })
    }

    @Test func partsSitInsideTheirSystemInFlowOrder() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        let audio = rect(layout, "audio")
        #expect(audio.contains(rect(layout, "audio.capture")))
        #expect(audio.contains(rect(layout, "audio.gate")))
        #expect(rect(layout, "audio.capture").maxX < rect(layout, "audio.gate").minX)
        #expect(layout.box("audio")?.partCount == 2)
    }

    @Test func systemsAreSizedForTheirParts() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        #expect(rect(layout, "tap").size == MindControl.LayoutMetrics.systemMinSize)
        #expect(rect(layout, "audio").height > rect(layout, "tap").height)
    }

    @Test func savedPositionsWinAndCarryTheirParts() {
        let base = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        let moved = FlowLayout.layout(map: FlowFixtures.arca, broken: [], saved: ["audio": CGPoint(x: 5000, y: 5000)])
        #expect(rect(moved, "audio").origin == CGPoint(x: 5000, y: 5000))
        let delta = CGPoint(x: 5000 - rect(base, "audio").minX, y: 5000 - rect(base, "audio").minY)
        #expect(rect(moved, "audio.gate").origin == CGPoint(x: rect(base, "audio.gate").minX + delta.x, y: rect(base, "audio.gate").minY + delta.y))
        #expect(rect(moved, "zone:phone").contains(rect(moved, "audio")))
    }

    @Test func selfFlowAndIsolatedSystemLayOut() {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "b", "name": "B" },
                       { "id": "c", "name": "C", "parts": [ { "id": "p", "name": "P" }, { "id": "q", "name": "Q" } ] } ],
          "flows": [ { "id": "1", "from": "a", "to": "a", "kind": "data", "carries": "x" },
                     { "id": "2", "from": "c.p", "to": "c.q", "kind": "data", "carries": "x" } ] }
        """#)
        let layout = FlowLayout.layout(map: map, broken: [])
        let systems = layout.boxes.filter { $0.kind == .system }
        #expect(systems.count == 3)
        for (i, a) in systems.enumerated() { for b in systems[(i + 1)...] { #expect(!a.rect.intersects(b.rect)) } }
        #expect(layout.boxes.filter { $0.kind == .zone }.isEmpty)
    }

    @Test func arrowsAtThreeLevels() throws {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        #expect(layout.arrows.filter { $0.level == .part }.count == 9)
        let merged = try #require(layout.arrows.first { $0.id == "sys:audio>agent" })
        #expect(merged.weight == 3)
        #expect(merged.kind == .data)
        #expect(merged.label == "PCM16 24 kHz +2")
        #expect(merged.conditional)
        #expect(merged.flowIDs == ["pcm", "commit", "discard"])
        #expect(Set(layout.arrows.filter { $0.level == .zone }.map(\.id)) == ["zone:ring>phone", "zone:phone>cloud", "zone:cloud>phone"])
        #expect(layout.arrows.first { $0.id == "flow:check" }?.from == "audio.capture")
    }

    @Test func brokenFlowsAreNotDrawn() {
        let layout = FlowLayout.layout(map: FlowFixtures.arca, broken: ["pcm"])
        #expect(layout.arrows.first { $0.id == "flow:pcm" } == nil)
        #expect(layout.arrows.first { $0.id == "sys:audio>agent" }?.weight == 2)
    }
}
#endif
```

`macos/Tests/MindControl/ArrowRouterTests.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias MapLayout = MindControl.MapLayout
private typealias ArrowRouter = MindControl.ArrowRouter

struct ArrowRouterTests {
    private func box(_ id: String, _ rect: CGRect) -> MapLayout.Box {
        MapLayout.Box(id: id, kind: .system, rect: rect, title: id, subtitle: nil, external: false, tint: -1, partCount: 0)
    }

    private func arrow(_ id: String, _ from: String, _ to: String) -> MapLayout.ArrowSpec {
        MapLayout.ArrowSpec(id: id, level: .part, from: from, to: to, kind: .data, flowIDs: [id], label: id, conditional: false, weight: 1)
    }

    @Test func rightwardArrowLeavesTheRightEdge() throws {
        let layout = MapLayout(boxes: [box("a", CGRect(x: 0, y: 0, width: 100, height: 60)), box("b", CGRect(x: 300, y: 0, width: 100, height: 60))],
                               arrows: [arrow("f", "a", "b")])
        let curve = try #require(ArrowRouter.curves(for: layout)["f"])
        #expect(curve.p0 == CGPoint(x: 100, y: 30))
        #expect(curve.p3 == CGPoint(x: 300, y: 30))
        #expect(curve.point(at: 0) == curve.p0)
        #expect(curve.point(at: 1) == curve.p3)
        #expect(curve.distance(to: curve.mid) < 0.5)
    }

    @Test func returnArrowIsOffsetFromItsPartner() throws {
        let layout = MapLayout(boxes: [box("a", CGRect(x: 0, y: 0, width: 100, height: 60)), box("b", CGRect(x: 300, y: 0, width: 100, height: 60))],
                               arrows: [arrow("go", "a", "b"), arrow("back", "b", "a")])
        let curves = ArrowRouter.curves(for: layout)
        let go = try #require(curves["go"]), back = try #require(curves["back"])
        #expect(go.p0.y != back.p3.y)
        #expect(back.p0.x == 300)
    }

    @Test func stackedBoxesUseVerticalEdges() throws {
        let layout = MapLayout(boxes: [box("a", CGRect(x: 0, y: 0, width: 100, height: 60)), box("b", CGRect(x: 20, y: 200, width: 100, height: 60))],
                               arrows: [arrow("f", "a", "b")])
        let curve = try #require(ArrowRouter.curves(for: layout)["f"])
        #expect(curve.p0.y == 60)
        #expect(curve.p3.y == 200)
    }
}
#endif
```

`macos/Tests/MindControl/LayoutStoreTests.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Foundation
import Testing
@testable import Ghostty

private typealias LayoutStore = MindControl.LayoutStore

struct LayoutStoreTests {
    @Test func roundTrips() {
        let positions = ["audio": CGPoint(x: 12.5, y: -40), "ble": CGPoint(x: 0, y: 300)]
        #expect(LayoutStore.decode(LayoutStore.encode(positions)) == positions)
    }

    @Test func unreadableIsEmpty() {
        #expect(LayoutStore.decode(nil) == [:])
        #expect(LayoutStore.decode(Data("not json".utf8)) == [:])
        #expect(LayoutStore.decode(Data(#"{ "version": 1, "positions": { "a": { "x": "no" } } }"#.utf8)) == [:])
    }

    @Test func writeCreatesTheFolder() throws {
        let project = try TempProject()
        try LayoutStore.write(["a": CGPoint(x: 1, y: 2)], root: project.url)
        let data = try Data(contentsOf: project.url.appendingPathComponent(".mindcontrol/layout.json"))
        #expect(LayoutStore.decode(data) == ["a": CGPoint(x: 1, y: 2)])
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `.superpowers/mc-test.sh FlowLayoutTests ArrowRouterTests LayoutStoreTests`
Expected: build errors: `FlowLayout`, `MapLayout`, `ArrowRouter`, `LayoutStore` are not defined.

- [ ] **Step 3: Write `Layout/MapLayout.swift`**

```swift
import CoreGraphics

extension MindControl {
    /// Zoom thresholds shared by labels, picking and the shaders (`levelWeight` in ShaderCommon.h).
    enum ZoomLevels {
        /// Zone arrows cross-fade to system arrows across this range; system names fade in.
        static let zoneToSystems: ClosedRange<CGFloat> = 0.22...0.34
        /// System arrows cross-fade to part arrows; part boxes fade in.
        static let systemsToParts: ClosedRange<CGFloat> = 0.85...1.15

        static func arrowLevel(at zoom: CGFloat) -> MapLayout.ArrowLevel {
            zoom < 0.28 ? .zone : zoom < 1.0 ? .system : .part
        }

        static func partsVisible(at zoom: CGFloat) -> Bool { zoom >= 1.0 }
    }

    enum LayoutMetrics {
        static let systemMinSize = CGSize(width: 220, height: 84)
        /// Room for a system's name and summary above its parts.
        static let header: CGFloat = 64
        static let pad: CGFloat = 20
        static let partSize = CGSize(width: 160, height: 40)
        static let partColumnGap: CGFloat = 40
        static let partRowGap: CGFloat = 14
        static let columnGap: CGFloat = 150
        static let rowGap: CGFloat = 50
        static let zonePad: CGFloat = 48
        static let zoneLabel: CGFloat = 56
        static let zoneGap: CGFloat = 140
        static let parallelSpacing: CGFloat = 14
    }

    /// Where everything sits, in world points (y down). Produced by FlowLayout or FocusLayout.
    struct MapLayout: Equatable {
        enum BoxKind: Equatable { case zone, system, part }

        struct Box: Equatable {
            let id: String
            let kind: BoxKind
            var rect: CGRect
            let title: String
            let subtitle: String?
            let external: Bool
            /// Zone palette index, or -1.
            let tint: Int
            let partCount: Int
        }

        enum ArrowLevel: Int, Equatable { case zone = 0, system = 1, part = 2 }

        struct ArrowSpec: Equatable {
            let id: String
            let level: ArrowLevel
            /// Box ids.
            let from: String
            let to: String
            let kind: FlowMap.Kind
            let flowIDs: [String]
            let label: String
            let conditional: Bool
            /// How many flows were merged into this arrow.
            let weight: Int
        }

        var boxes: [Box]
        var arrows: [ArrowSpec]
        /// True for focus layouts: every box and arrow shows at any zoom.
        var fixedLevel = false

        init(boxes: [Box], arrows: [ArrowSpec], fixedLevel: Bool = false) {
            self.boxes = boxes
            self.arrows = arrows
            self.fixedLevel = fixedLevel
        }

        func box(_ id: String) -> Box? { boxes.first { $0.id == id } }

        var bounds: CGRect { boxes.reduce(CGRect.null) { $0.union($1.rect) } }

        static func zoneBoxID(_ id: String) -> String { "zone:\(id)" }
    }
}
```

- [ ] **Step 4: Write `Layout/FlowLayout.swift`**

```swift
import CoreGraphics

extension MindControl {
    /// The main map: zones ordered by data flow, systems layered inside each zone, parts layered inside
    /// each system, then saved positions applied. Control flows never move anything.
    enum FlowLayout {
        private typealias M = LayoutMetrics

        static func layout(map: FlowMap, broken: Set<String>, saved: [String: CGPoint] = [:]) -> MapLayout {
            let flows = map.flows.filter { !broken.contains($0.id) }
            let data = flows.filter { $0.kind == .data }
            func zone(of system: String) -> String { map.zoneOf(system: system) ?? "" }

            // Parts within each system, and each system's size.
            var local: [String: (size: CGSize, parts: [String: CGRect])] = [:]
            for system in map.systems { local[system.id] = partLayout(system: system, flows: data) }

            // Systems within each zone.
            let incoming = Set(data.map(\.to.system)), outgoing = Set(data.map(\.from.system))
            let usedZones = Set(map.systems.map { zone(of: $0.id) })
            var blocks: [String: (size: CGSize, origins: [String: CGPoint])] = [:]
            for z in usedZones {
                let members = map.systems.filter { zone(of: $0.id) == z }
                let ids = Set(members.map(\.id))
                let edges = data.filter { ids.contains($0.from.system) && ids.contains($0.to.system) }
                    .map { Layering.Edge(from: $0.from.system, to: $0.to.system) }
                let pinFirst = Set(members.filter { $0.external && outgoing.contains($0.id) && !incoming.contains($0.id) }.map(\.id))
                let pinLast = Set(members.filter { $0.external && incoming.contains($0.id) && !outgoing.contains($0.id) }.map(\.id))
                let layered = Layering.layout(nodes: Array(ids), edges: edges, pinFirst: pinFirst, pinLast: pinLast)
                let content = place(layered.layers, size: { local[$0]?.size ?? M.systemMinSize }, columnGap: M.columnGap, rowGap: M.rowGap)
                let label = z.isEmpty ? 0 : M.zoneLabel
                blocks[z] = (CGSize(width: content.size.width + 2 * M.zonePad, height: content.size.height + 2 * M.zonePad + label),
                             content.origins.mapValues { CGPoint(x: $0.x + M.zonePad, y: $0.y + M.zonePad + label) })
            }

            // Zones, ordered by the data flowing between them.
            let zoneEdges = data.compactMap { flow -> Layering.Edge? in
                let a = zone(of: flow.from.system), b = zone(of: flow.to.system)
                return a == b ? nil : Layering.Edge(from: a, to: b)
            }
            let zoneLayers = Layering.layout(nodes: Array(usedZones), edges: zoneEdges).layers
            let zoneOrigins = place(zoneLayers, size: { blocks[$0]?.size ?? .zero }, columnGap: M.zoneGap, rowGap: M.zoneGap).origins

            // World rects.
            var systemRects: [String: CGRect] = [:]
            for system in map.systems {
                let z = zone(of: system.id)
                guard let block = blocks[z], let origin = zoneOrigins[z], let inner = block.origins[system.id],
                      let size = local[system.id]?.size else { continue }
                let placed = saved[system.id] ?? CGPoint(x: origin.x + inner.x, y: origin.y + inner.y)
                systemRects[system.id] = CGRect(origin: placed, size: size)
            }

            var zoneBoxes: [MapLayout.Box] = []
            for (index, zone) in map.zones.enumerated() {
                let members = map.systems.filter { $0.zone == zone.id }.compactMap { systemRects[$0.id] }
                guard let first = members.first else { continue }
                let union = members.dropFirst().reduce(first) { $0.union($1) }
                let rect = CGRect(x: union.minX - M.zonePad, y: union.minY - M.zonePad - M.zoneLabel,
                                  width: union.width + 2 * M.zonePad, height: union.height + 2 * M.zonePad + M.zoneLabel)
                zoneBoxes.append(.init(id: MapLayout.zoneBoxID(zone.id), kind: .zone, rect: rect, title: zone.name, subtitle: nil,
                                       external: false, tint: index, partCount: 0))
            }

            var systemBoxes: [MapLayout.Box] = []
            var partBoxes: [MapLayout.Box] = []
            for system in map.systems {
                guard let rect = systemRects[system.id] else { continue }
                let tint = system.zone.flatMap { z in map.zones.firstIndex { $0.id == z } } ?? -1
                systemBoxes.append(.init(id: system.id, kind: .system, rect: rect, title: system.name, subtitle: system.summary,
                                         external: system.external, tint: tint, partCount: system.parts.count))
                for part in system.parts {
                    guard let relative = local[system.id]?.parts[part.id] else { continue }
                    partBoxes.append(.init(id: "\(system.id).\(part.id)", kind: .part, rect: relative.offsetBy(dx: rect.minX, dy: rect.minY),
                                           title: part.name, subtitle: nil, external: false, tint: tint, partCount: 0))
                }
            }

            return MapLayout(boxes: zoneBoxes + systemBoxes + partBoxes, arrows: arrows(map: map, flows: flows))
        }

        /// Parts layered by the data flowing between them, relative to the system's top-left corner.
        static func partLayout(system: FlowMap.System, flows: [FlowMap.Flow]) -> (size: CGSize, parts: [String: CGRect]) {
            guard !system.parts.isEmpty else { return (M.systemMinSize, [:]) }
            let edges = flows.filter { $0.from.system == system.id && $0.to.system == system.id }
                .compactMap { flow -> Layering.Edge? in
                    guard let a = flow.from.part, let b = flow.to.part else { return nil }
                    return Layering.Edge(from: a, to: b)
                }
            let layered = Layering.layout(nodes: system.parts.map(\.id), edges: edges)
            let content = place(layered.layers, size: { _ in M.partSize }, columnGap: M.partColumnGap, rowGap: M.partRowGap)
            let parts = content.origins.mapValues { CGRect(origin: CGPoint(x: $0.x + M.pad, y: $0.y + M.header), size: M.partSize) }
            let size = CGSize(width: max(M.systemMinSize.width, content.size.width + 2 * M.pad),
                              height: max(M.systemMinSize.height, M.header + content.size.height + M.pad))
            return (size, parts)
        }

        /// Columns left to right, each stacked top to bottom and centred against the tallest column.
        static func place(_ layers: [[String]], size: (String) -> CGSize, columnGap: CGFloat, rowGap: CGFloat) -> (size: CGSize, origins: [String: CGPoint]) {
            let heights = layers.map { column in column.map { size($0).height }.reduce(0, +) + CGFloat(max(0, column.count - 1)) * rowGap }
            let widths = layers.map { column in column.map { size($0).width }.max() ?? 0 }
            let total = heights.max() ?? 0
            var origins: [String: CGPoint] = [:]
            var x: CGFloat = 0
            for (index, column) in layers.enumerated() {
                var y = (total - heights[index]) / 2
                for node in column {
                    origins[node] = CGPoint(x: x, y: y)
                    y += size(node).height + rowGap
                }
                x += widths[index] + columnGap
            }
            return (CGSize(width: max(0, x - columnGap), height: total), origins)
        }

        /// Part-level arrows for every flow; merged arrows between systems and between zones.
        static func arrows(map: FlowMap, flows: [FlowMap.Flow]) -> [MapLayout.ArrowSpec] {
            var specs = flows.map { flow in
                MapLayout.ArrowSpec(id: "flow:\(flow.id)", level: .part, from: flow.from.description, to: flow.to.description,
                                    kind: flow.kind, flowIDs: [flow.id], label: flow.carries, conditional: flow.when != nil, weight: 1)
            }
            specs += merged(flows, level: .system, prefix: "sys") { ($0.from.system, $0.to.system) }
            let zones = Set(map.zones.map(\.id))
            specs += merged(flows, level: .zone, prefix: "zone") { flow in
                guard let a = map.zoneOf(system: flow.from.system), let b = map.zoneOf(system: flow.to.system),
                      zones.contains(a), zones.contains(b) else { return nil }
                return (MapLayout.zoneBoxID(a), MapLayout.zoneBoxID(b))
            }
            return specs
        }

        private static func merged(_ flows: [FlowMap.Flow], level: MapLayout.ArrowLevel, prefix: String,
                                   ends: (FlowMap.Flow) -> (String, String)?) -> [MapLayout.ArrowSpec] {
            var order: [String] = []
            var groups: [String: (from: String, to: String, flows: [FlowMap.Flow])] = [:]
            for flow in flows {
                guard let (from, to) = ends(flow), from != to else { continue }
                let bare = { (id: String) in id.hasPrefix("zone:") ? String(id.dropFirst(5)) : id }
                let key = "\(prefix):\(bare(from))>\(bare(to))"
                if groups[key] == nil { order.append(key); groups[key] = (from, to, []) }
                groups[key]?.flows.append(flow)
            }
            return order.compactMap { key in
                guard let group = groups[key] else { return nil }
                let lead = group.flows.first { $0.kind == .data } ?? group.flows[0]
                let extra = group.flows.count - 1
                return MapLayout.ArrowSpec(id: key, level: level, from: group.from, to: group.to,
                                           kind: group.flows.contains { $0.kind == .data } ? .data : .control,
                                           flowIDs: group.flows.map(\.id),
                                           label: level == .zone ? "" : (extra > 0 ? "\(lead.carries) +\(extra)" : lead.carries),
                                           conditional: group.flows.contains { $0.when != nil }, weight: group.flows.count)
            }
        }
    }
}
```

- [ ] **Step 5: Write `Layout/ArrowRouter.swift`**

```swift
import CoreGraphics

extension MindControl {
    /// A cubic Bézier in world points.
    struct Curve: Equatable {
        var p0: CGPoint
        var p1: CGPoint
        var p2: CGPoint
        var p3: CGPoint

        func point(at t: CGFloat) -> CGPoint {
            let s = 1 - t
            let a = s * s * s, b = 3 * s * s * t, c = 3 * s * t * t, d = t * t * t
            return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }

        func tangent(at t: CGFloat) -> CGVector {
            let s = 1 - t
            let a = 3 * s * s, b = 6 * s * t, c = 3 * t * t
            return CGVector(dx: a * (p1.x - p0.x) + b * (p2.x - p1.x) + c * (p3.x - p2.x),
                            dy: a * (p1.y - p0.y) + b * (p2.y - p1.y) + c * (p3.y - p2.y))
        }

        var mid: CGPoint { point(at: 0.5) }

        /// Approximate distance from `p` to the curve, sampled at 32 segments.
        func distance(to p: CGPoint) -> CGFloat {
            var best = CGFloat.greatestFiniteMagnitude
            var previous = p0
            for i in 1...32 {
                let next = point(at: CGFloat(i) / 32)
                best = min(best, Self.segmentDistance(p, previous, next))
                previous = next
            }
            return best
        }

        private static func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }
    }

    /// Curves for arrow specs: out of the facing edges of the two boxes, with parallel arrows between
    /// the same two boxes spread apart so a flow and its return never overlap.
    enum ArrowRouter {
        static func curves(for layout: MapLayout) -> [String: Curve] {
            var rects: [String: CGRect] = [:]
            for box in layout.boxes { rects[box.id] = box.rect }
            var groups: [String: [MapLayout.ArrowSpec]] = [:]
            var keys: [String] = []
            for arrow in layout.arrows {
                let pair = [arrow.from, arrow.to].sorted()
                let key = "\(arrow.level.rawValue)|\(pair[0])|\(pair[1])"
                if groups[key] == nil { keys.append(key) }
                groups[key, default: []].append(arrow)
            }
            var curves: [String: Curve] = [:]
            for key in keys {
                let group = groups[key] ?? []
                for (index, arrow) in group.enumerated() {
                    guard let a = rects[arrow.from], let b = rects[arrow.to] else { continue }
                    let offset = (CGFloat(index) - CGFloat(group.count - 1) / 2) * LayoutMetrics.parallelSpacing
                    curves[arrow.id] = route(from: a, to: b, offset: offset)
                }
            }
            return curves
        }

        static func route(from a: CGRect, to b: CGRect, offset: CGFloat) -> Curve {
            let separatedHorizontally = b.minX > a.maxX || b.maxX < a.minX
            if separatedHorizontally {
                let sign: CGFloat = b.midX >= a.midX ? 1 : -1
                let dy = clamp(offset, a, b, \.height)
                let start = CGPoint(x: sign > 0 ? a.maxX : a.minX, y: a.midY + dy)
                let end = CGPoint(x: sign > 0 ? b.minX : b.maxX, y: b.midY + dy)
                let k = max(40, abs(end.x - start.x) * 0.45)
                return Curve(p0: start, p1: CGPoint(x: start.x + sign * k, y: start.y),
                             p2: CGPoint(x: end.x - sign * k, y: end.y), p3: end)
            }
            let sign: CGFloat = b.midY >= a.midY ? 1 : -1
            let dx = clamp(offset, a, b, \.width)
            let start = CGPoint(x: a.midX + dx, y: sign > 0 ? a.maxY : a.minY)
            let end = CGPoint(x: b.midX + dx, y: sign > 0 ? b.minY : b.maxY)
            let k = max(30, abs(end.y - start.y) * 0.45)
            return Curve(p0: start, p1: CGPoint(x: start.x, y: start.y + sign * k),
                         p2: CGPoint(x: end.x, y: end.y - sign * k), p3: end)
        }

        private static func clamp(_ offset: CGFloat, _ a: CGRect, _ b: CGRect, _ side: KeyPath<CGRect, CGFloat>) -> CGFloat {
            let limit = max(0, min(a[keyPath: side], b[keyPath: side]) / 2 - 4)
            return max(-limit, min(limit, offset))
        }
    }
}
```

- [ ] **Step 6: Write `Layout/LayoutStore.swift`**

```swift
import CoreGraphics
import Foundation

extension MindControl {
    /// `.mindcontrol/layout.json`: positions the user dragged systems to. Unreadable means empty.
    enum LayoutStore {
        static func decode(_ data: Data?) -> [String: CGPoint] {
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let positions = object["positions"] as? [String: Any] else { return [:] }
            var result: [String: CGPoint] = [:]
            for (id, value) in positions {
                guard let point = value as? [String: Any], let x = point["x"] as? Double, let y = point["y"] as? Double else { return [:] }
                result[id] = CGPoint(x: x, y: y)
            }
            return result
        }

        static func encode(_ positions: [String: CGPoint]) -> Data {
            let object: [String: Any] = [
                "version": 1,
                "positions": positions.mapValues { ["x": Double($0.x), "y": Double($0.y)] },
            ]
            return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        }

        static func write(_ positions: [String: CGPoint], root: URL) throws {
            let url = root.appendingPathComponent(FlowFile.layoutRelativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encode(positions).write(to: url, options: .atomic)
        }
    }
}
```

- [ ] **Step 7: Run the tests to watch them pass**

Run: `.superpowers/mc-test.sh FlowLayoutTests ArrowRouterTests LayoutStoreTests LayeringTests`
Expected: every suite reports `0 failed`.

If `zonesOrderedByDataFlowEvenWithACrossZoneCycle` fails, print `Layering.layout` for the zone graph. The ring zone has no incoming data, so the depth-first pass must start there. If it doesn't, check that `hasIncoming` uses the deduplicated edges.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/MindControl/Layout/MapLayout.swift macos/Sources/Features/MindControl/Layout/FlowLayout.swift \
  macos/Sources/Features/MindControl/Layout/ArrowRouter.swift macos/Sources/Features/MindControl/Layout/LayoutStore.swift \
  macos/Tests/MindControl/FlowLayoutTests.swift macos/Tests/MindControl/ArrowRouterTests.swift macos/Tests/MindControl/LayoutStoreTests.swift
git commit -m "mindcontrol: lay out zones, systems and parts; route arrows; save positions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 11: Focus layouts

**Files:**
- Create: `macos/Sources/Features/MindControl/Layout/FocusLayout.swift`
- Create: `macos/Tests/MindControl/FocusLayoutTests.swift`

**Interfaces:**
- Consumes: `FlowMap` (Task 3), `MapLayout`, `LayoutMetrics`, `FlowLayout.partLayout(system:flows:)`, `FlowLayout.place` (Task 10)
- Produces:
  - `MindControl.FocusLayout.system(_ id: String, map: FlowMap, broken: Set<String>) -> MapLayout?`
  - `MindControl.FocusLayout.feature(_ id: String, map: FlowMap, broken: Set<String>) -> MapLayout?`
  - Both have `fixedLevel == true` and use the same box ids as the main map, so transitions can match boxes.

**Ruling carried from the spec:** in a system focus, a neighbour that both sends to and receives from the subject goes on the left (senders). Ledger it as `Task 11: Ruling: two-way neighbours sit with senders — the spec places senders left and receivers right but is silent on both — cost if wrong: one box on the other side`.

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/FocusLayoutTests.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias FocusLayout = MindControl.FocusLayout

struct FocusLayoutTests {
    @Test func systemFocusPutsSendersLeftAndReceiversRight() throws {
        let layout = try #require(FocusLayout.system("audio", map: FlowFixtures.arca, broken: []))
        #expect(layout.fixedLevel)
        let audio = try #require(layout.box("audio")).rect
        #expect(try #require(layout.box("tap")).rect.maxX < audio.minX)
        #expect(try #require(layout.box("agent")).rect.minX > audio.maxX)
        #expect(layout.box("audio.capture") != nil && layout.box("audio.gate") != nil)
        #expect(layout.box("openai") == nil)
        #expect(layout.box("ble") == nil)
        #expect(Set(layout.arrows.map(\.id)) == ["flow:begin", "flow:pcm", "flow:check", "flow:commit", "flow:discard"])
    }

    @Test func systemFocusOnUnknownSystemIsNil() {
        #expect(FocusLayout.system("nope", map: FlowFixtures.arca, broken: []) == nil)
    }

    @Test func featureFocusFollowsStepOrderLeftToRight() throws {
        let layout = try #require(FocusLayout.feature("speech", map: FlowFixtures.arca, broken: []))
        #expect(layout.fixedLevel)
        let order = ["ring", "ble", "tap", "audio", "agent", "openai"]
        let xs = try order.map { try #require(layout.box($0)).rect.minX }
        #expect(xs == xs.sorted())
        #expect(Set(layout.boxes.map(\.id)) == Set(order))
    }

    @Test func conditionalStepsSplitIntoLanes() throws {
        let map = FlowFixtures.map(#"""
        { "version": 1,
          "systems": [ { "id": "a", "name": "A" }, { "id": "yes", "name": "Yes" }, { "id": "no", "name": "No" } ],
          "flows": [ { "id": "y", "from": "a", "to": "yes", "kind": "control", "carries": "x", "when": "words heard" },
                     { "id": "n", "from": "a", "to": "no", "kind": "control", "carries": "x", "when": "nothing heard" } ],
          "features": [ { "id": "f", "name": "F", "route": ["y", "n"] } ] }
        """#)
        let layout = try #require(FocusLayout.feature("f", map: map, broken: []))
        let a = try #require(layout.box("a")).rect, yes = try #require(layout.box("yes")).rect, no = try #require(layout.box("no")).rect
        #expect(yes.maxY < a.midY)
        #expect(no.minY > a.midY)
        #expect(yes.minX == no.minX)
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh FocusLayoutTests`
Expected: build error: `FocusLayout` is not defined.

- [ ] **Step 3: Write `Layout/FocusLayout.swift`**

```swift
import CoreGraphics

extension MindControl {
    /// Fresh layouts for one subject. Box ids match the main map so the view can slide between them.
    enum FocusLayout {
        private typealias M = LayoutMetrics
        static let sideGap: CGFloat = 180
        static let laneGap: CGFloat = 70

        /// The system large in the middle with all its parts; senders on the left, receivers on the right.
        static func system(_ id: String, map: FlowMap, broken: Set<String>) -> MapLayout? {
            guard let subject = map.system(id) else { return nil }
            let flows = map.flows.filter { !broken.contains($0.id) }
            let local = FlowLayout.partLayout(system: subject, flows: flows.filter { $0.kind == .data })
            let subjectRect = CGRect(origin: .zero, size: local.size)

            var senders: [String] = []
            var receivers: [String] = []
            for flow in flows {
                let fromSubject = flow.from.system == id, toSubject = flow.to.system == id
                if toSubject, !fromSubject, !senders.contains(flow.from.system) { senders.append(flow.from.system) }
                if fromSubject, !toSubject, !receivers.contains(flow.to.system) { receivers.append(flow.to.system) }
            }
            receivers.removeAll { senders.contains($0) }

            func column(_ ids: [String], x: CGFloat) -> [MapLayout.Box] {
                let height = CGFloat(ids.count) * M.systemMinSize.height + CGFloat(max(0, ids.count - 1)) * M.rowGap
                var y = subjectRect.midY - height / 2
                return ids.compactMap { neighbour in
                    guard let system = map.system(neighbour) else { return nil }
                    defer { y += M.systemMinSize.height + M.rowGap }
                    return MapLayout.Box(id: system.id, kind: .system, rect: CGRect(origin: CGPoint(x: x, y: y), size: M.systemMinSize),
                                         title: system.name, subtitle: nil, external: system.external, tint: tint(system, map), partCount: 0)
                }
            }

            var boxes = [MapLayout.Box(id: subject.id, kind: .system, rect: subjectRect, title: subject.name, subtitle: subject.summary,
                                       external: subject.external, tint: tint(subject, map), partCount: subject.parts.count)]
            for part in subject.parts {
                guard let rect = local.parts[part.id] else { continue }
                boxes.append(.init(id: "\(subject.id).\(part.id)", kind: .part, rect: rect, title: part.name, subtitle: nil,
                                   external: false, tint: tint(subject, map), partCount: 0))
            }
            boxes += column(senders, x: subjectRect.minX - sideGap - M.systemMinSize.width)
            boxes += column(receivers, x: subjectRect.maxX + sideGap)

            let shown = Set(boxes.map(\.id))
            let arrows = flows.filter { $0.from.system == id || $0.to.system == id }.compactMap { flow -> MapLayout.ArrowSpec? in
                let from = shown.contains(flow.from.description) ? flow.from.description : flow.from.system
                let to = shown.contains(flow.to.description) ? flow.to.description : flow.to.system
                guard shown.contains(from), shown.contains(to), from != to else { return nil }
                return MapLayout.ArrowSpec(id: "flow:\(flow.id)", level: .part, from: from, to: to, kind: flow.kind, flowIDs: [flow.id],
                                           label: flow.carries, conditional: flow.when != nil, weight: 1)
            }
            return MapLayout(boxes: boxes, arrows: arrows, fixedLevel: true)
        }

        /// Only the route's systems, one column each in step order; conditional steps get their own lanes.
        static func feature(_ id: String, map: FlowMap, broken: Set<String>) -> MapLayout? {
            guard let feature = map.feature(id) else { return nil }
            let steps = feature.route.compactMap { map.flow($0) }.filter { !broken.contains($0.id) }
            var conditions: [String] = []
            var placed: [String: CGPoint] = [:]
            var orderPlaced: [String] = []
            var column = 0
            for flow in steps {
                if let when = flow.when, !conditions.contains(when) { conditions.append(when) }
                for system in [flow.from.system, flow.to.system] where placed[system] == nil {
                    let lane = lane(for: system == flow.to.system ? flow.when : nil, conditions: conditions)
                    placed[system] = CGPoint(x: CGFloat(column) * (M.systemMinSize.width + M.columnGap),
                                             y: CGFloat(lane) * (M.systemMinSize.height + laneGap))
                    orderPlaced.append(system)
                    column += 1
                }
            }
            // Systems first reached in parallel lanes share a column.
            var columnOf: [String: CGFloat] = [:]
            var lastX: CGFloat = -1
            var lastWasLane = false
            for system in orderPlaced {
                guard let point = placed[system] else { continue }
                let inLane = point.y != 0
                if inLane, lastWasLane {
                    columnOf[system] = lastX
                } else {
                    lastX = lastX < 0 ? 0 : lastX + M.systemMinSize.width + M.columnGap
                    columnOf[system] = lastX
                }
                lastWasLane = inLane
            }

            let boxes: [MapLayout.Box] = orderPlaced.compactMap { systemID in
                guard let system = map.system(systemID), let point = placed[systemID], let x = columnOf[systemID] else { return nil }
                return MapLayout.Box(id: system.id, kind: .system, rect: CGRect(origin: CGPoint(x: x, y: point.y), size: M.systemMinSize),
                                     title: system.name, subtitle: nil, external: system.external, tint: tint(system, map), partCount: 0)
            }
            let arrows = steps.compactMap { flow -> MapLayout.ArrowSpec? in
                guard flow.from.system != flow.to.system else { return nil }
                return MapLayout.ArrowSpec(id: "flow:\(flow.id)", level: .system, from: flow.from.system, to: flow.to.system,
                                           kind: flow.kind, flowIDs: [flow.id], label: flow.carries, conditional: flow.when != nil, weight: 1)
            }
            return MapLayout(boxes: boxes, arrows: arrows, fixedLevel: true)
        }

        /// 0 for unconditional; the 1st condition above (-1), the 2nd below (+1), the 3rd above (-2)…
        static func lane(for when: String?, conditions: [String]) -> Int {
            guard let when, let index = conditions.firstIndex(of: when) else { return 0 }
            let k = index + 1
            return k % 2 == 1 ? -((k + 1) / 2) : k / 2
        }

        private static func tint(_ system: FlowMap.System, _ map: FlowMap) -> Int {
            system.zone.flatMap { z in map.zones.firstIndex { $0.id == z } } ?? -1
        }
    }
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `macos/skins-test.sh FocusLayoutTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/Layout/FocusLayout.swift macos/Tests/MindControl/FocusLayoutTests.swift
git commit -m "mindcontrol: focus layouts for one system or one feature

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Ledger the Task 11 ruling in the same call.

---

### Task 12: Search

**Files:**
- Create: `macos/Sources/Features/MindControl/Search/FlowSearch.swift`
- Create: `macos/Tests/MindControl/FlowSearchTests.swift`

**Interfaces:**
- Consumes: `FlowMap` (Task 3), `HealthReport` (Task 6, using `owners`, `typeFiles` and `unmapped`)
- Produces:
  - `MindControl.SearchResult(kind: Kind, title: String, detail: String, target: Target)`
    - `Kind` is `.feature`, `.system`, `.part` or `.file`, compared in that order
    - `Target` is `.feature(String)`, `.system(String)`, `.part(String)` (a `"system.part"` key) or `.file(path: String, system: String?)`
  - `MindControl.FlowSearch(map:report:)` with `search(_ query: String, limit: Int = 40) -> [SearchResult]`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/FlowSearchTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FlowSearch = MindControl.FlowSearch

struct FlowSearchTests {
    private var search: FlowSearch {
        var report = MindControl.HealthReport()
        report.owners = ["app/Sources/Audio/AudioCapture.swift": "audio", "app/Sources/Coordination/CostMeter.swift": "tap"]
        report.typeFiles = ["AudioCapture": "app/Sources/Audio/AudioCapture.swift", "CostMeter": "app/Sources/Coordination/CostMeter.swift"]
        report.unmapped = ["app/Sources/Other/Stray.swift"]
        return FlowSearch(map: FlowFixtures.arca, report: report)
    }

    @Test func groupsComeInKindOrder() {
        let kinds = search.search("audio").map(\.kind)
        #expect(kinds == kinds.sorted())
        #expect(kinds.contains(.system) && kinds.contains(.part) && kinds.contains(.file))
    }

    @Test func prefixBeatsWordStartBeatsSubstring() {
        let titles = search.search("a").filter { $0.kind == .system }.map(\.title)
        // "Audio" (prefix), "Realtime agent" (word start), "Tap coordinator" (substring)
        #expect(titles.firstIndex(of: "Audio")! < titles.firstIndex(of: "Realtime agent")!)
        #expect(titles.firstIndex(of: "Realtime agent")! < titles.firstIndex(of: "Tap coordinator")!)
    }

    @Test func typeNameResolvesToItsSystem() throws {
        let result = try #require(search.search("CostMeter").first { $0.kind == .file && $0.title == "CostMeter" })
        #expect(result.target == .file(path: "app/Sources/Coordination/CostMeter.swift", system: "tap"))
        #expect(result.detail.contains("Tap coordinator"))
    }

    @Test func strayFileSaysNoSystem() throws {
        let result = try #require(search.search("stray").first)
        #expect(result.target == .file(path: "app/Sources/Other/Stray.swift", system: nil))
        #expect(result.detail.contains("no system"))
    }

    @Test func featuresAndPartsAreFound() {
        #expect(search.search("press becomes").first?.target == .feature("speech"))
        #expect(search.search("speechgate").first?.target == .part("audio.gate"))
    }

    @Test func emptyQueryFindsNothing() {
        #expect(search.search("  ").isEmpty)
    }

    @Test func caseInsensitive() {
        #expect(search.search("AUDIO").first?.title == "Audio")
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh FlowSearchTests`
Expected: build error: `FlowSearch` is not defined.

- [ ] **Step 3: Write `Search/FlowSearch.swift`**

```swift
import Foundation

extension MindControl {
    struct SearchResult: Equatable {
        enum Kind: Int, Comparable {
            case feature, system, part, file
            static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
        }

        enum Target: Equatable {
            case feature(String)
            case system(String)
            /// "system.part"
            case part(String)
            case file(path: String, system: String?)
        }

        let kind: Kind
        let title: String
        let detail: String
        let target: Target
    }

    /// Features, systems, parts, source files and Swift types. Ranked prefix, then word start, then
    /// substring, then alphabetical; grouped by kind.
    struct FlowSearch {
        private struct Entry {
            let result: SearchResult
            /// Lowercased text matched against.
            let keys: [String]
        }

        private let entries: [Entry]

        init(map: FlowMap, report: HealthReport) {
            var entries: [Entry] = []
            for feature in map.features {
                entries.append(Entry(result: .init(kind: .feature, title: feature.name, detail: "Feature", target: .feature(feature.id)),
                                     keys: [feature.name.lowercased(), feature.id]))
            }
            for system in map.systems {
                entries.append(Entry(result: .init(kind: .system, title: system.name, detail: system.summary ?? "System",
                                                   target: .system(system.id)),
                                     keys: [system.name.lowercased(), system.id]))
                for part in system.parts {
                    entries.append(Entry(result: .init(kind: .part, title: part.name, detail: system.name,
                                                       target: .part("\(system.id).\(part.id)")),
                                         keys: [part.name.lowercased(), part.id, (part.anchor ?? "").lowercased()]))
                }
            }
            func systemName(_ id: String?) -> String { id.flatMap { map.system($0)?.name } ?? "no system" }
            for file in (Array(report.owners.keys) + report.unmapped).sorted() {
                let owner = report.owners[file]
                entries.append(Entry(result: .init(kind: .file, title: (file as NSString).lastPathComponent,
                                                   detail: "\(file) · \(systemName(owner))", target: .file(path: file, system: owner)),
                                     keys: [(file as NSString).lastPathComponent.lowercased(), file.lowercased()]))
            }
            for (type, file) in report.typeFiles.sorted(by: { $0.key < $1.key }) {
                let owner = report.owners[file]
                entries.append(Entry(result: .init(kind: .file, title: type, detail: "\(file) · \(systemName(owner))",
                                                   target: .file(path: file, system: owner)),
                                     keys: [type.lowercased()]))
            }
            self.entries = entries
        }

        func search(_ query: String, limit: Int = 40) -> [SearchResult] {
            let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
            guard !needle.isEmpty else { return [] }
            let scored = entries.compactMap { entry -> (score: Int, result: SearchResult)? in
                let best = entry.keys.compactMap { Self.score(needle, in: $0) }.min()
                return best.map { ($0, entry.result) }
            }
            return scored.sorted {
                ($0.result.kind.rawValue, $0.score, $0.result.title.lowercased(), $0.result.detail)
                    < ($1.result.kind.rawValue, $1.score, $1.result.title.lowercased(), $1.result.detail)
            }
            .prefix(limit).map(\.result)
        }

        /// 0 prefix, 1 a word starts with it, 2 contains it; nil no match.
        static func score(_ needle: String, in key: String) -> Int? {
            if key.hasPrefix(needle) { return 0 }
            let words = key.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            if words.contains(where: { $0.hasPrefix(needle) }) { return 1 }
            if key.contains(needle) { return 2 }
            return nil
        }
    }
}
```

Word starts are split on non-alphanumerics only, and keys are lowercased. So camelCase boundaries ("Cost**M**eter") count as substrings, not word starts. That is acceptable, because the full type name is also matched as a prefix.

- [ ] **Step 4: Run the tests to watch them pass**

Run: `macos/skins-test.sh FlowSearchTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/Search/FlowSearch.swift macos/Tests/MindControl/FlowSearchTests.swift
git commit -m "mindcontrol: search features, systems, parts, files and types

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: The 2D camera

**Files:**
- Create: `macos/Sources/Features/MindControl/Renderer/PanZoomCamera.swift`
- Create: `macos/Tests/MindControl/PanZoomCameraTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `MindControl.PanZoomCamera` with:
  - `center: CGPoint`, `zoom: CGFloat`, `minZoom = 0.08`, `maxZoom = 4`
  - `toScreen(_:viewSize:)`, `toWorld(_:viewSize:)` (view points, top-left origin)
  - `mutating zoom(by:about:viewSize:)`, `mutating pan(byScreen:)`
  - `static fitting(_ rect: CGRect, in viewSize: CGSize, margin: CGFloat = 56) -> PanZoomCamera`
  - `static interpolate(_ a:, _ b:, t:) -> PanZoomCamera`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/PanZoomCameraTests.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias Camera = MindControl.PanZoomCamera

struct PanZoomCameraTests {
    private let view = CGSize(width: 800, height: 600)

    @Test func screenWorldRoundTrip() {
        let camera = Camera(center: CGPoint(x: 120, y: -40), zoom: 1.7)
        let world = CGPoint(x: 333, y: 21)
        let back = camera.toWorld(camera.toScreen(world, viewSize: view), viewSize: view)
        #expect(abs(back.x - world.x) < 1e-9 && abs(back.y - world.y) < 1e-9)
        #expect(camera.toScreen(camera.center, viewSize: view) == CGPoint(x: 400, y: 300))
    }

    @Test func zoomKeepsThePointUnderTheCursor() {
        var camera = Camera(center: .zero, zoom: 1)
        let cursor = CGPoint(x: 650, y: 120)
        let before = camera.toWorld(cursor, viewSize: view)
        camera.zoom(by: 2.5, about: cursor, viewSize: view)
        let after = camera.toWorld(cursor, viewSize: view)
        #expect(abs(before.x - after.x) < 1e-9 && abs(before.y - after.y) < 1e-9)
        #expect(camera.zoom == 2.5)
    }

    @Test func zoomIsClamped() {
        var camera = Camera(center: .zero, zoom: 1)
        camera.zoom(by: 1000, about: .zero, viewSize: view)
        #expect(camera.zoom == Camera.maxZoom)
        camera.zoom(by: 0.00001, about: .zero, viewSize: view)
        #expect(camera.zoom == Camera.minZoom)
    }

    @Test func panMovesOppositeToTheDrag() {
        var camera = Camera(center: .zero, zoom: 2)
        camera.pan(byScreen: CGSize(width: 100, height: -40))
        #expect(camera.center == CGPoint(x: -50, y: 20))
    }

    @Test func fitShowsTheWholeRect() {
        let rect = CGRect(x: -500, y: 100, width: 2000, height: 400)
        let camera = Camera.fitting(rect, in: view)
        let topLeft = camera.toScreen(CGPoint(x: rect.minX, y: rect.minY), viewSize: view)
        let bottomRight = camera.toScreen(CGPoint(x: rect.maxX, y: rect.maxY), viewSize: view)
        #expect(topLeft.x >= 0 && topLeft.y >= 0 && bottomRight.x <= view.width && bottomRight.y <= view.height)
        #expect(camera.center == CGPoint(x: rect.midX, y: rect.midY))
    }

    @Test func interpolationHitsBothEnds() {
        let a = Camera(center: .zero, zoom: 0.5), b = Camera(center: CGPoint(x: 100, y: 50), zoom: 2)
        #expect(Camera.interpolate(a, b, t: 0) == a)
        #expect(Camera.interpolate(a, b, t: 1) == b)
        #expect(abs(Camera.interpolate(a, b, t: 0.5).zoom - 1) < 1e-9)
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh PanZoomCameraTests`
Expected: build error: `PanZoomCamera` is not defined.

- [ ] **Step 3: Write `Renderer/PanZoomCamera.swift`**

```swift
import CoreGraphics
import Foundation

extension MindControl {
    /// World (points, y down) ↔ view (points, top-left origin). `center` is the world point at the view's centre.
    struct PanZoomCamera: Equatable {
        static let minZoom: CGFloat = 0.08
        static let maxZoom: CGFloat = 4

        var center: CGPoint = .zero
        var zoom: CGFloat = 1

        func toScreen(_ p: CGPoint, viewSize: CGSize) -> CGPoint {
            CGPoint(x: (p.x - center.x) * zoom + viewSize.width / 2, y: (p.y - center.y) * zoom + viewSize.height / 2)
        }

        func toWorld(_ p: CGPoint, viewSize: CGSize) -> CGPoint {
            CGPoint(x: (p.x - viewSize.width / 2) / zoom + center.x, y: (p.y - viewSize.height / 2) / zoom + center.y)
        }

        mutating func zoom(by factor: CGFloat, about screen: CGPoint, viewSize: CGSize) {
            let anchor = toWorld(screen, viewSize: viewSize)
            zoom = min(Self.maxZoom, max(Self.minZoom, zoom * factor))
            let moved = toWorld(screen, viewSize: viewSize)
            center.x += anchor.x - moved.x
            center.y += anchor.y - moved.y
        }

        /// Drag by a screen delta (top-left origin): the world follows the pointer.
        mutating func pan(byScreen delta: CGSize) {
            center.x -= delta.width / zoom
            center.y -= delta.height / zoom
        }

        static func fitting(_ rect: CGRect, in viewSize: CGSize, margin: CGFloat = 56) -> PanZoomCamera {
            guard !rect.isNull, rect.width > 0, rect.height > 0, viewSize.width > 0, viewSize.height > 0 else {
                return PanZoomCamera(center: rect.isNull ? .zero : CGPoint(x: rect.midX, y: rect.midY), zoom: 1)
            }
            let zoom = min((viewSize.width - 2 * margin) / rect.width, (viewSize.height - 2 * margin) / rect.height)
            return PanZoomCamera(center: CGPoint(x: rect.midX, y: rect.midY), zoom: min(maxZoom, max(minZoom, zoom)))
        }

        /// Centre linearly, zoom in log space so the motion feels even.
        static func interpolate(_ a: PanZoomCamera, _ b: PanZoomCamera, t: CGFloat) -> PanZoomCamera {
            if t <= 0 { return a }
            if t >= 1 { return b }
            return PanZoomCamera(center: CGPoint(x: a.center.x + (b.center.x - a.center.x) * t, y: a.center.y + (b.center.y - a.center.y) * t),
                                 zoom: exp(log(a.zoom) + (log(b.zoom) - log(a.zoom)) * t))
        }
    }
}
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: `macos/skins-test.sh PanZoomCameraTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/Renderer/PanZoomCamera.swift macos/Tests/MindControl/PanZoomCameraTests.swift
git commit -m "mindcontrol: 2D pan and zoom camera

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 14: Draw the map in Metal

**Files:**
- Modify: `macos/Sources/Features/MindControl/Renderer/ShaderTypes.h`, `Renderer/Shaders/ShaderCommon.h`, `Renderer/Pipelines.swift`, `Renderer/Renderer.swift`
- Create: `Renderer/FlowScene.swift`, `Renderer/Shaders/Boxes.metal`, `Renderer/Shaders/Arrows.metal`, `Renderer/Shaders/Markers.metal`
- Create: `macos/Tests/MindControl/FlowSceneTests.swift`
- Modify: `macos/Tests/MindControl/RendererTests.swift`

**Interfaces:**
- Consumes: `MapLayout`, `Curve`, `ArrowRouter` (Task 10), `HealthReport` (Task 6), `PanZoomCamera` (Task 13)
- Produces:
  - C structs `MCBoxInstance` (64 bytes), `MCArrowInstance` (80), `MCMarkerInstance` (48), `MCFrameUniforms` (32)
  - Macros `MC_LEVEL_ZONE/SYSTEM/PART/ALWAYS` and `MC_MARKER_HEAD/DIAMOND`
  - `MindControl.Palette`:
    - `zone(_:)`, `feature(_:) -> SIMD3<Float>`, `featureCount`
    - `data`, `control`, `amber`, `grey`
  - `MindControl.SceneStyle`:
    - `mode: Mode` (`.map`, `.health`), `showControl: Bool`
    - `litFlows: Set<String>`, `featureColor: SIMD3<Float>?`
    - `selected: String?`, `pulsed: String?`, `fade: [String: Float]`
  - `MindControl.FlowScene` with `boxes`, `arrows`, `markers`, `fixedLevel`, and `static build(layout:curves:report:style:) -> FlowScene`
  - `Renderer`:
    - `var camera: PanZoomCamera`, `func setScene(_:)`
    - `func animateCamera(to:duration:)`, `var isAnimatingCamera: Bool`
    - `var beforeFrame: ((CFTimeInterval) -> Void)?`

- [ ] **Step 1: Write the failing scene tests**

`macos/Tests/MindControl/FlowSceneTests.swift`:

```swift
#if os(macOS)
import Testing
@testable import Ghostty

private typealias FlowScene = MindControl.FlowScene
private typealias SceneStyle = MindControl.SceneStyle

struct FlowSceneTests {
    private let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
    private var curves: [String: MindControl.Curve] { MindControl.ArrowRouter.curves(for: layout) }

    private func build(_ style: SceneStyle = SceneStyle(), report: MindControl.HealthReport = .init()) -> FlowScene {
        FlowScene.build(layout: layout, curves: curves, report: report, style: style)
    }

    private func brightness(_ v: SIMD4<Float>) -> Float { v.x + v.y + v.z }

    @Test func gpuStructsHaveTheExpectedSizes() {
        #expect(MemoryLayout<MCBoxInstance>.stride == 64)
        #expect(MemoryLayout<MCArrowInstance>.stride == 80)
        #expect(MemoryLayout<MCMarkerInstance>.stride == 48)
        #expect(MemoryLayout<MCFrameUniforms>.stride == 32)
    }

    @Test func oneInstancePerBoxAndArrow() {
        let scene = build()
        #expect(scene.boxes.count == layout.boxes.count)
        #expect(scene.arrows.count == layout.arrows.count)
        let heads = scene.markers.filter { $0.shape == Float(MC_MARKER_HEAD) }.count
        let diamonds = scene.markers.filter { $0.shape == Float(MC_MARKER_DIAMOND) }.count
        #expect(heads == layout.arrows.count)
        #expect(diamonds == layout.arrows.filter(\.conditional).count)
    }

    @Test func hidingControlDropsControlArrows() {
        var style = SceneStyle()
        style.showControl = false
        #expect(build(style).arrows.count == layout.arrows.filter { $0.kind == .data }.count)
    }

    @Test func onlyDataArrowsPulseInMapView() {
        let scene = build()
        for (instance, spec) in zip(scene.arrows, layout.arrows) {
            #expect((instance.pulses > 0) == (spec.kind == .data), "\(spec.id)")
            #expect((instance.dashed > 0) == (spec.kind == .control), "\(spec.id)")
        }
    }

    @Test func selectedFeatureLightsItsRouteAndDimsTheRest() throws {
        var style = SceneStyle()
        style.litFlows = ["pcm"]
        style.featureColor = MindControl.Palette.feature(1)
        let scene = build(style)
        let lit = try #require(layout.arrows.firstIndex { $0.id == "flow:pcm" })
        let unlit = try #require(layout.arrows.firstIndex { $0.id == "flow:send" })
        #expect(brightness(scene.arrows[lit].color) > 4 * brightness(scene.arrows[unlit].color))
        let ble = try #require(layout.boxes.firstIndex { $0.id == "ble" })
        let audio = try #require(layout.boxes.firstIndex { $0.id == "audio" })
        #expect(brightness(scene.boxes[audio].stroke) > brightness(scene.boxes[ble].stroke))
    }

    @Test func healthViewColoursOnlyProblems() throws {
        var report = MindControl.HealthReport()
        report.staleParts = ["audio.gate"]
        report.staleFlows = ["send"]
        report.unverifiedFlows = ["press"]
        var style = SceneStyle()
        style.mode = .health
        let scene = build(style, report: report)
        let gate = try #require(layout.boxes.firstIndex { $0.id == "audio.gate" })
        let capture = try #require(layout.boxes.firstIndex { $0.id == "audio.capture" })
        #expect(scene.boxes[gate].stroke.x > scene.boxes[gate].stroke.z * 3)
        #expect(scene.boxes[capture].stroke.x < scene.boxes[capture].stroke.z * 1.5)
        let send = try #require(layout.arrows.firstIndex { $0.id == "flow:send" })
        let press = try #require(layout.arrows.firstIndex { $0.id == "flow:press" })
        #expect(scene.arrows[send].color.x > scene.arrows[send].color.z * 3)
        #expect(scene.arrows[press].dashed > 0)
        #expect(scene.arrows.allSatisfy { $0.pulses == 0 })
    }

    @Test func partsAndArrowsCarryTheirZoomLevel() throws {
        let scene = build()
        let part = try #require(layout.boxes.firstIndex { $0.kind == .part })
        let zone = try #require(layout.boxes.firstIndex { $0.kind == .zone })
        #expect(scene.boxes[part].level == Float(MC_LEVEL_PART))
        #expect(scene.boxes[zone].level == Float(MC_LEVEL_ALWAYS))
        let zoneArrow = try #require(layout.arrows.firstIndex { $0.level == .zone })
        #expect(scene.arrows[zoneArrow].level == Float(MC_LEVEL_ZONE))
        #expect(!scene.fixedLevel)
    }
}
#endif
```

Add to `RendererTests` (inside the struct):

```swift
    @Test func drawsTheArcaMap() throws {
        let renderer = try Renderer()
        let background = try Self.renderAverage(using: renderer)
        let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
        renderer.setScene(MindControl.FlowScene.build(layout: layout, curves: MindControl.ArrowRouter.curves(for: layout),
                                                      report: .init(), style: .init()))
        renderer.camera = MindControl.PanZoomCamera.fitting(layout.bounds, in: CGSize(width: 96, height: 64), margin: 4)
        let drawn = try Self.renderAverage(using: renderer)
        #expect(drawn > background)
    }

    @Test func cameraAnimationReachesItsTarget() throws {
        let renderer = try Renderer()
        let target = MindControl.PanZoomCamera(center: CGPoint(x: 100, y: 50), zoom: 2)
        renderer.animateCamera(to: target, duration: 0.2)
        #expect(renderer.isAnimatingCamera)
        renderer.advanceCamera(to: CACurrentMediaTime() + 1)
        #expect(renderer.camera == target)
        #expect(!renderer.isAnimatingCamera)
    }
```

Add `import QuartzCore` and `import CoreGraphics` at the top of `RendererTests.swift`.

- [ ] **Step 2: Run them to watch them fail**

Run: `.superpowers/mc-test.sh FlowSceneTests RendererTests`
Expected: build errors: `MCBoxInstance`, `FlowScene`, `SceneStyle`, `setScene` are not defined.

- [ ] **Step 3: Add the GPU types to `ShaderTypes.h`**

Insert after `#include <simd/simd.h>`:

```c
#define MC_BUFFER_INSTANCES 0
#define MC_BUFFER_FRAME 1
#define MC_ARROW_SEGMENTS 24   // arrows are cubic Béziers tessellated into this many segments

#define MC_LEVEL_ZONE 0        // drawn when zoomed far out
#define MC_LEVEL_SYSTEM 1
#define MC_LEVEL_PART 2        // drawn when zoomed in
#define MC_LEVEL_ALWAYS 3

#define MC_MARKER_HEAD 0
#define MC_MARKER_DIAMOND 1

typedef struct {
    vector_float2 origin;      // world, top-left
    vector_float2 size;        // world
    vector_float4 fill;        // linear HDR rgb; a unused
    vector_float4 stroke;
    float radius;              // world
    float glow;
    float dashed;              // 1 for external systems
    float level;               // MC_LEVEL_*
} MCBoxInstance;

typedef struct {
    vector_float2 p0;          // world; cubic Bézier control points
    vector_float2 p1;
    vector_float2 p2;
    vector_float2 p3;
    vector_float4 color;
    float width;               // points
    float dashed;
    float pulses;              // 1 draws travelling pulses (data arrows)
    float seed;                // [0, 1)
    float level;               // MC_LEVEL_*
    float pad0;
    float pad1;
    float pad2;
} MCArrowInstance;

typedef struct {
    vector_float2 position;    // world
    vector_float2 direction;   // unit, world
    vector_float4 color;
    float size;                // points
    float shape;               // MC_MARKER_*
    float level;
    float pad;
} MCMarkerInstance;

typedef struct {
    vector_float2 viewportSize;  // drawable pixels
    vector_float2 center;        // world point at the view centre
    float zoom;                  // view points per world point
    float pixelScale;            // backing scale factor
    float time;                  // seconds since launch
    float fixedLevel;            // 1 in focus views: zoom levels don't hide anything
} MCFrameUniforms;
```

- [ ] **Step 4: Add helpers to `ShaderCommon.h`**

Insert before `#endif`:

```c
/// World point → drawable pixels, top-left origin. Matches PanZoomCamera.toScreen × pixelScale.
inline float2 worldToPixels(float2 p, constant MCFrameUniforms& u) {
    return (p - u.center) * u.zoom * u.pixelScale + u.viewportSize * 0.5;
}

inline float4 pixelsToClip(float2 px, constant MCFrameUniforms& u) {
    return float4(px.x / u.viewportSize.x * 2.0 - 1.0, 1.0 - px.y / u.viewportSize.y * 2.0, 0.0, 1.0);
}

/// How visible something at `level` is at the current zoom. Mirrors MindControl.ZoomLevels.
inline float levelWeight(float level, constant MCFrameUniforms& u) {
    if (u.fixedLevel > 0.5 || level > 2.5) return 1.0;
    float toSystems = smoothstep(0.22, 0.34, u.zoom);
    float toParts = smoothstep(0.85, 1.15, u.zoom);
    if (level < 0.5) return 1.0 - toSystems;
    if (level < 1.5) return toSystems * (1.0 - toParts);
    return toParts;
}

inline float2 bezier(float2 p0, float2 p1, float2 p2, float2 p3, float t) {
    float s = 1.0 - t;
    return s * s * s * p0 + 3.0 * s * s * t * p1 + 3.0 * s * t * t * p2 + t * t * t * p3;
}

inline float2 bezierTangent(float2 p0, float2 p1, float2 p2, float2 p3, float t) {
    float s = 1.0 - t;
    return 3.0 * s * s * (p1 - p0) + 6.0 * s * t * (p2 - p1) + 3.0 * t * t * (p3 - p2);
}
```

- [ ] **Step 5: Write `Shaders/Boxes.metal`**

```metal
#include "ShaderCommon.h"

// Zones, systems and parts: SDF rounded rectangles with a fill, a crisp stroke and an outer glow.

constant float kGlowPoints = 22.0;
constant float kStrokePoints = 1.1;

struct BoxOut {
    float4 position [[position]];
    float2 local;        // pixels from the box centre
    float2 halfSize;     // pixels
    float radius;        // pixels
    float3 fill;
    float3 stroke;
    float glow;
    float dashed;
    float weight;
    float pixelScale;
};

vertex BoxOut mcBoxVertex(uint vid [[vertex_id]],
                          uint iid [[instance_id]],
                          const device MCBoxInstance* boxes [[buffer(MC_BUFFER_INSTANCES)]],
                          constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    BoxOut out = {};
    MCBoxInstance b = boxes[iid];
    float weight = levelWeight(b.level, u);
    if (weight < 0.01) { out.position = culledPosition(); return out; }

    float2 minPx = worldToPixels(b.origin, u);
    float2 maxPx = worldToPixels(b.origin + b.size, u);
    float2 centre = (minPx + maxPx) * 0.5;
    float2 halfSize = (maxPx - minPx) * 0.5;
    float2 local = quadCorner(vid) * (halfSize + kGlowPoints * u.pixelScale);

    out.position = pixelsToClip(centre + local, u);
    out.local = local;
    out.halfSize = halfSize;
    out.radius = min(b.radius * u.zoom * u.pixelScale, min(halfSize.x, halfSize.y));
    out.fill = b.fill.rgb;
    out.stroke = b.stroke.rgb;
    out.glow = b.glow;
    out.dashed = b.dashed;
    out.weight = weight;
    out.pixelScale = u.pixelScale;
    return out;
}

inline float roundedBox(float2 p, float2 halfSize, float r) {
    float2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

fragment float4 mcBoxFragment(BoxOut in [[stage_in]]) {
    float d = roundedBox(in.local, in.halfSize, in.radius);   // pixels, negative inside
    float inside = 1.0 - smoothstep(-1.0, 1.0, d);
    float strokeHalf = kStrokePoints * in.pixelScale * 0.5;
    float stroke = 1.0 - smoothstep(strokeHalf - 1.0, strokeHalf + 1.0, abs(d));
    if (in.dashed > 0.5) {
        stroke *= step(0.45, fract((in.local.x + in.local.y) / (9.0 * in.pixelScale)));
    }
    float outside = max(d, 0.0) / in.pixelScale;
    float glow = exp(-outside / 7.0) * (1.0 - inside) * in.glow * 0.35;
    float3 rgb = in.fill * inside + in.stroke * (stroke * 1.4 + glow);
    return float4(rgb * in.weight, 0.0);
}
```

- [ ] **Step 6: Write `Shaders/Arrows.metal`**

```metal
#include "ShaderCommon.h"

// Arrows are cubic Béziers drawn as triangle strips of (MC_ARROW_SEGMENTS + 1) * 2 vertices.
// Data arrows are solid and carry two pulses travelling from source to target; control arrows are dashed.

constant float kFeatherPoints = 3.0;
constant float kPulseHalfWidth = 6.0;

struct ArrowOut {
    float4 position [[position]];
    float3 color;
    float across [[center_no_perspective]];   // pixels from the centreline
    float along;                              // 0 at the source, 1 at the target
    float lengthPx;
    float halfWidth;                          // pixels
    float dashed;
    float seed;
    float time;
    float pixelScale;
    float weight;
};

inline ArrowOut arrowStrip(uint vid, MCArrowInstance a, constant MCFrameUniforms& u, float halfQuadPoints) {
    ArrowOut out = {};
    float t = float(vid / 2) / float(MC_ARROW_SEGMENTS);
    float side = (vid & 1) ? 1.0 : -1.0;
    float2 p = worldToPixels(bezier(a.p0, a.p1, a.p2, a.p3, t), u);
    float2 tangent = bezierTangent(a.p0, a.p1, a.p2, a.p3, t);
    float len = length(tangent);
    float2 dir = len > 1e-4 ? tangent / len : float2(1.0, 0.0);
    float2 normal = float2(-dir.y, dir.x);
    float halfQuad = halfQuadPoints * u.pixelScale;
    out.position = pixelsToClip(p + normal * side * halfQuad, u);
    out.across = side * halfQuad;
    out.along = t;
    out.lengthPx = length(worldToPixels(a.p3, u) - worldToPixels(a.p0, u)) * 1.15;
    out.halfWidth = a.width * 0.5 * u.pixelScale;
    out.color = a.color.rgb;
    out.dashed = a.dashed;
    out.seed = a.seed;
    out.time = u.time;
    out.pixelScale = u.pixelScale;
    return out;
}

vertex ArrowOut mcArrowVertex(uint vid [[vertex_id]],
                              uint iid [[instance_id]],
                              const device MCArrowInstance* arrows [[buffer(MC_BUFFER_INSTANCES)]],
                              constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    MCArrowInstance a = arrows[iid];
    float weight = levelWeight(a.level, u);
    if (weight < 0.01) { ArrowOut out = {}; out.position = culledPosition(); return out; }
    ArrowOut out = arrowStrip(vid, a, u, a.width * 0.5 + kFeatherPoints);
    out.weight = weight;
    return out;
}

fragment float4 mcArrowFragment(ArrowOut in [[stage_in]]) {
    float d = abs(in.across);
    float core = 1.0 - smoothstep(in.halfWidth - 0.75, in.halfWidth + 0.75, d);
    float glow = exp(-d * d / (in.pixelScale * in.pixelScale * 6.0)) * 0.25;
    float dash = in.dashed > 0.5 ? step(0.4, fract(in.along * in.lengthPx / (8.0 * in.pixelScale))) : 1.0;
    return float4(in.color * (core + glow) * dash * in.weight, 0.0);
}

vertex ArrowOut mcPulseVertex(uint vid [[vertex_id]],
                              uint iid [[instance_id]],
                              const device MCArrowInstance* arrows [[buffer(MC_BUFFER_INSTANCES)]],
                              constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    MCArrowInstance a = arrows[iid];
    float weight = levelWeight(a.level, u);
    if (a.pulses < 0.5 || weight < 0.01) { ArrowOut out = {}; out.position = culledPosition(); return out; }
    ArrowOut out = arrowStrip(vid, a, u, kPulseHalfWidth);
    out.weight = weight;
    return out;
}

fragment float4 mcPulseFragment(ArrowOut in [[stage_in]]) {
    float period = mix(2.2, 3.4, hash11(in.seed * 7.3 + 0.1));
    float trail = 0.0;
    for (int k = 0; k < 2; k++) {
        float head = fract(in.time / period + in.seed + 0.5 * float(k));
        float behind = (head - in.along) * in.lengthPx / in.pixelScale;   // points
        trail += behind >= 0.0 ? exp(-behind / 22.0) : exp(behind * 0.8);
    }
    float across = in.across / in.pixelScale;
    float profile = exp(-across * across * 0.35);
    float ends = smoothstep(0.0, 0.04, in.along) * (1.0 - smoothstep(0.96, 1.0, in.along));
    return float4(in.color * trail * profile * ends * 1.6 * in.weight, 0.0);
}
```

- [ ] **Step 7: Write `Shaders/Markers.metal`**

```metal
#include "ShaderCommon.h"

// Arrowheads at arrow targets and diamonds where a conditional arrow leaves its source.

struct MarkerOut {
    float4 position [[position]];
    float2 local;      // marker units: +x along the arrow
    float3 color;
    float shape;
    float weight;
};

vertex MarkerOut mcMarkerVertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device MCMarkerInstance* markers [[buffer(MC_BUFFER_INSTANCES)]],
                                constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    MarkerOut out = {};
    MCMarkerInstance m = markers[iid];
    float weight = levelWeight(m.level, u);
    if (weight < 0.01) { out.position = culledPosition(); return out; }
    float2 dir = length(m.direction) > 1e-4 ? normalize(m.direction) : float2(1.0, 0.0);
    float2 normal = float2(-dir.y, dir.x);
    float2 corner = quadCorner(vid) * 1.6;
    float sizePx = m.size * u.pixelScale;
    out.position = pixelsToClip(worldToPixels(m.position, u) + (dir * corner.x + normal * corner.y) * sizePx, u);
    out.local = corner;
    out.color = m.color.rgb;
    out.shape = m.shape;
    out.weight = weight;
    return out;
}

fragment float4 mcMarkerFragment(MarkerOut in [[stage_in]]) {
    float2 p = in.local;
    float d;
    if (in.shape < 0.5) {
        // Arrowhead: tip at the origin pointing +x, base 1.4 units back, 0.8 half-width at the base.
        d = max(max(p.x, -1.4 - p.x), abs(p.y) - 0.8 * (-p.x) / 1.4);
    } else {
        d = abs(p.x) + abs(p.y) - 0.9;
    }
    float shape = 1.0 - smoothstep(-0.08, 0.08, d);
    return float4(in.color * shape * 1.3 * in.weight, 0.0);
}
```

- [ ] **Step 8: Add the pipelines**

In `Pipelines.swift`, add four properties and build them in `init` before `composite`:

```swift
        let boxes: MTLRenderPipelineState
        let arrows: MTLRenderPipelineState
        let pulses: MTLRenderPipelineState
        let markers: MTLRenderPipelineState
```

```swift
            boxes = try Self.make(device, library, "mcBoxVertex", "mcBoxFragment", format: hdr, additive: true)
            arrows = try Self.make(device, library, "mcArrowVertex", "mcArrowFragment", format: hdr, additive: true)
            pulses = try Self.make(device, library, "mcPulseVertex", "mcPulseFragment", format: hdr, additive: true)
            markers = try Self.make(device, library, "mcMarkerVertex", "mcMarkerFragment", format: hdr, additive: true)
```

- [ ] **Step 9: Write `Renderer/FlowScene.swift`**

```swift
import CoreGraphics
import Foundation
import simd

extension MindControl {
    enum Palette {
        static let zoneTints: [SIMD3<Float>] = [
            SIMD3(0.30, 0.45, 1.00), SIMD3(0.55, 0.35, 1.00), SIMD3(0.20, 0.75, 0.80),
            SIMD3(0.95, 0.55, 0.30), SIMD3(0.40, 0.85, 0.45), SIMD3(0.90, 0.40, 0.65),
        ]
        static let features: [SIMD3<Float>] = [
            SIMD3(0.25, 0.65, 1.00), SIMD3(1.00, 0.55, 0.20), SIMD3(0.30, 0.90, 0.55), SIMD3(0.75, 0.45, 1.00),
            SIMD3(1.00, 0.40, 0.55), SIMD3(0.95, 0.85, 0.30), SIMD3(0.30, 0.90, 0.90), SIMD3(0.85, 0.60, 0.40),
        ]
        static var featureCount: Int { features.count }
        static let data = SIMD3<Float>(0.45, 0.66, 1.00)
        static let control = SIMD3<Float>(0.55, 0.56, 0.68)
        static let amber = SIMD3<Float>(1.00, 0.62, 0.15)
        static let grey = SIMD3<Float>(0.24, 0.26, 0.30)

        static func zone(_ index: Int) -> SIMD3<Float> {
            index < 0 ? SIMD3(0.40, 0.45, 0.60) : zoneTints[index % zoneTints.count]
        }

        static func feature(_ index: Int) -> SIMD3<Float> { features[((index % featureCount) + featureCount) % featureCount] }
    }

    /// What the scene should emphasise. Built by MapController.
    struct SceneStyle: Equatable {
        enum Mode: Equatable { case map, health }

        var mode: Mode = .map
        var showControl = true
        /// The selected feature's route; empty when no feature is selected.
        var litFlows: Set<String> = []
        var featureColor: SIMD3<Float>?
        /// A box or arrow id.
        var selected: String?
        /// A box briefly highlighted after search.
        var pulsed: String?
        /// Per-box opacity during view transitions (default 1).
        var fade: [String: Float] = [:]
    }

    /// GPU instances for one frame's worth of map.
    struct FlowScene {
        var boxes: [MCBoxInstance] = []
        var arrows: [MCArrowInstance] = []
        var markers: [MCMarkerInstance] = []
        var fixedLevel = false

        static func build(layout: MapLayout, curves: [String: Curve], report: HealthReport, style: SceneStyle) -> FlowScene {
            var scene = FlowScene()
            scene.fixedLevel = layout.fixedLevel
            let health = style.mode == .health
            let featureActive = !style.litFlows.isEmpty

            var litBoxes = Set<String>()
            if featureActive {
                for arrow in layout.arrows where !style.litFlows.isDisjoint(with: arrow.flowIDs) {
                    for id in [arrow.from, arrow.to] {
                        litBoxes.insert(id)
                        if !id.hasPrefix("zone:"), let dot = id.firstIndex(of: ".") { litBoxes.insert(String(id[..<dot])) }
                    }
                }
            }
            let staleSystems = Set(report.staleParts.compactMap { $0.split(separator: ".").first.map(String.init) })

            for box in layout.boxes {
                let tint = Palette.zone(box.tint)
                var fill = SIMD3<Float>(repeating: 0)
                var stroke = SIMD3<Float>(repeating: 0)
                var glow: Float = 0
                var radius: Float = 12
                var level = Float(MC_LEVEL_ALWAYS)
                switch box.kind {
                case .zone:
                    fill = tint * 0.03
                    stroke = tint * 0.22
                    radius = 30
                case .system:
                    fill = SIMD3(0.018, 0.024, 0.05)
                    stroke = box.external ? tint * 0.45 : mix(tint, SIMD3(0.5, 0.65, 1.0), 0.5) * 0.9
                    glow = box.external ? 0.3 : 1
                    radius = 14
                case .part:
                    fill = SIMD3(0.03, 0.04, 0.08)
                    stroke = SIMD3(0.5, 0.62, 1.0) * 0.6
                    glow = 0.4
                    radius = 8
                    level = Float(MC_LEVEL_PART)
                }
                if health {
                    fill = SIMD3(0.015, 0.016, 0.02)
                    stroke = Palette.grey * (box.kind == .zone ? 0.5 : 1)
                    glow = 0
                    let stale = (box.kind == .part && report.staleParts.contains(box.id))
                        || (box.kind == .system && staleSystems.contains(box.id))
                    if stale {
                        stroke = Palette.amber
                        glow = 1.2
                    }
                }
                var intensity: Float = 1
                if featureActive, box.kind != .zone, !litBoxes.contains(box.id) { intensity = 0.25 }
                if style.selected == box.id { stroke *= 1.8; glow += 1.5 }
                if style.pulsed == box.id { glow += 3 }
                intensity *= style.fade[box.id] ?? 1
                scene.boxes.append(MCBoxInstance(
                    origin: SIMD2(Float(box.rect.minX), Float(box.rect.minY)),
                    size: SIMD2(Float(box.rect.width), Float(box.rect.height)),
                    fill: SIMD4(fill * intensity, 1), stroke: SIMD4(stroke * intensity, 1),
                    radius: radius, glow: glow * intensity, dashed: box.external ? 1 : 0, level: level))
            }

            for arrow in layout.arrows {
                guard let curve = curves[arrow.id] else { continue }
                if arrow.kind == .control, !style.showControl { continue }
                let lit = featureActive && !style.litFlows.isDisjoint(with: arrow.flowIDs)
                var color: SIMD3<Float>
                var width: Float
                var dashed: Float = 0
                var pulses: Float = 0
                if arrow.kind == .data {
                    color = Palette.data
                    width = 1.6 + log2(Float(max(1, arrow.weight))) * 0.9
                    pulses = 1
                } else {
                    color = Palette.control * 0.8
                    width = 1
                    dashed = 1
                }
                if lit {
                    color = (style.featureColor ?? color) * 1.4
                    width += 0.6
                } else if featureActive {
                    color *= 0.12
                    pulses = 0
                }
                if health {
                    pulses = 0
                    let ids = Set(arrow.flowIDs)
                    if !ids.isDisjoint(with: report.staleFlows) {
                        color = Palette.amber
                        dashed = 0
                    } else if !ids.isDisjoint(with: report.unverifiedFlows) {
                        color = Palette.data * 0.35
                        dashed = 1
                    } else {
                        color = Palette.grey
                    }
                }
                if style.selected == arrow.id { color *= 1.8; width += 0.8 }
                color *= min(style.fade[arrow.from] ?? 1, style.fade[arrow.to] ?? 1)
                let level = Float(arrow.level.rawValue)
                scene.arrows.append(MCArrowInstance(
                    p0: vector(curve.p0), p1: vector(curve.p1), p2: vector(curve.p2), p3: vector(curve.p3),
                    color: SIMD4(color, 1), width: width, dashed: dashed, pulses: pulses, seed: seed(arrow.id), level: level,
                    pad0: 0, pad1: 0, pad2: 0))
                scene.markers.append(MCMarkerInstance(position: vector(curve.p3), direction: direction(curve.tangent(at: 1)),
                                                      color: SIMD4(color, 1), size: 4 + width, shape: Float(MC_MARKER_HEAD),
                                                      level: level, pad: 0))
                if arrow.conditional {
                    scene.markers.append(MCMarkerInstance(position: vector(curve.point(at: 0.06)), direction: direction(curve.tangent(at: 0.06)),
                                                          color: SIMD4(color, 1), size: 5, shape: Float(MC_MARKER_DIAMOND),
                                                          level: level, pad: 0))
                }
            }
            return scene
        }

        private static func vector(_ p: CGPoint) -> SIMD2<Float> { SIMD2(Float(p.x), Float(p.y)) }

        private static func direction(_ v: CGVector) -> SIMD2<Float> {
            let length = hypot(v.dx, v.dy)
            return length > 1e-6 ? SIMD2(Float(v.dx / length), Float(v.dy / length)) : SIMD2(1, 0)
        }

        private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

        /// A stable [0, 1) value per id (FNV-1a), so pulses keep their rhythm across rebuilds.
        static func seed(_ id: String) -> Float {
            var hash: UInt32 = 2_166_136_261
            for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
            return Float(hash % 10_000) / 10_000
        }
    }
}
```

- [ ] **Step 10: Draw the scene in `Renderer.swift`**

Add these stored properties to `Renderer`:

```swift
        var camera = PanZoomCamera()
        /// Called at the start of each on-screen frame with the frame time (drives view transitions).
        var beforeFrame: ((CFTimeInterval) -> Void)?
        private var cameraAnimation: (from: PanZoomCamera, to: PanZoomCamera, start: CFTimeInterval, duration: CFTimeInterval)?
        private var boxBuffer: MTLBuffer?
        private var arrowBuffer: MTLBuffer?
        private var markerBuffer: MTLBuffer?
        private var boxCount = 0
        private var arrowCount = 0
        private var markerCount = 0
        private var fixedLevel = false
        private static let arrowVertexCount = (Int(MC_ARROW_SEGMENTS) + 1) * 2
```

Add these methods:

```swift
        func setScene(_ scene: FlowScene) {
            boxBuffer = makeBuffer(scene.boxes)
            arrowBuffer = makeBuffer(scene.arrows)
            markerBuffer = makeBuffer(scene.markers)
            boxCount = scene.boxes.count
            arrowCount = scene.arrows.count
            markerCount = scene.markers.count
            fixedLevel = scene.fixedLevel
        }

        var isAnimatingCamera: Bool { cameraAnimation != nil }

        func animateCamera(to target: PanZoomCamera, duration: CFTimeInterval = 0.45) {
            cameraAnimation = (camera, target, CACurrentMediaTime(), duration)
        }

        /// Moves an animating camera to where it should be at `now`.
        func advanceCamera(to now: CFTimeInterval) {
            guard let animation = cameraAnimation else { return }
            let raw = min(1, max(0, (now - animation.start) / animation.duration))
            let eased = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
            camera = PanZoomCamera.interpolate(animation.from, animation.to, t: CGFloat(eased))
            if raw >= 1 { cameraAnimation = nil }
        }
```

In `draw(in:)`, before `encodeFrame`:

```swift
            let now = CACurrentMediaTime()
            beforeFrame?(now)
            advanceCamera(to: now)
```

and pass `time: Float(now - startTime)`.

Replace `encodeScene` with:

```swift
        private func encodeScene(_ commandBuffer: MTLCommandBuffer, target: MTLTexture, width: Int, height: Int, pixelScale: Float, time: Float) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.label = "Scene"

            var frame = MCFrameUniforms(viewportSize: SIMD2(Float(width), Float(height)),
                                        center: SIMD2(Float(camera.center.x), Float(camera.center.y)),
                                        zoom: Float(camera.zoom), pixelScale: pixelScale, time: time,
                                        fixedLevel: fixedLevel ? 1 : 0)
            let frameIndex = Int(MC_BUFFER_FRAME)
            encoder.setVertexBytes(&frame, length: MemoryLayout<MCFrameUniforms>.stride, index: frameIndex)
            encoder.setFragmentBytes(&frame, length: MemoryLayout<MCFrameUniforms>.stride, index: frameIndex)
            let instances = Int(MC_BUFFER_INSTANCES)

            if let boxBuffer {
                encoder.setRenderPipelineState(pipelines.boxes)
                encoder.setVertexBuffer(boxBuffer, offset: 0, index: instances)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: boxCount)
            }
            if let arrowBuffer {
                encoder.setVertexBuffer(arrowBuffer, offset: 0, index: instances)
                encoder.setRenderPipelineState(pipelines.arrows)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: Self.arrowVertexCount, instanceCount: arrowCount)
                encoder.setRenderPipelineState(pipelines.pulses)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: Self.arrowVertexCount, instanceCount: arrowCount)
            }
            if let markerBuffer {
                encoder.setRenderPipelineState(pipelines.markers)
                encoder.setVertexBuffer(markerBuffer, offset: 0, index: instances)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: markerCount)
            }
            encoder.endEncoding()
        }
```

The camera works in view points, so `PanZoomCamera.zoom` is points-per-world-point. In tests, `renderAverage` passes `pixelScale: 1`, so the 96×64 target is treated as a 96×64-point view. That is why `drawsTheArcaMap` fits to `CGSize(width: 96, height: 64)`.

- [ ] **Step 11: Run the tests to watch them pass**

Run: `.superpowers/mc-test.sh FlowSceneTests RendererTests BloomPassTests`
Expected: every suite reports `0 failed`.

If `gpuStructsHaveTheExpectedSizes` fails, the C struct field order differs from Step 3. Fix the header, not the test: Metal reads the same bytes, and the sizes assert the layout both sides agree on.

- [ ] **Step 12: Commit**

```bash
git add macos/Sources/Features/MindControl/Renderer/ShaderTypes.h macos/Sources/Features/MindControl/Renderer/Shaders/ShaderCommon.h \
  macos/Sources/Features/MindControl/Renderer/Shaders/Boxes.metal macos/Sources/Features/MindControl/Renderer/Shaders/Arrows.metal \
  macos/Sources/Features/MindControl/Renderer/Shaders/Markers.metal macos/Sources/Features/MindControl/Renderer/Pipelines.swift \
  macos/Sources/Features/MindControl/Renderer/Renderer.swift macos/Sources/Features/MindControl/Renderer/FlowScene.swift \
  macos/Tests/MindControl/FlowSceneTests.swift macos/Tests/MindControl/RendererTests.swift
git commit -m "mindcontrol: draw zones, systems, parts and flowing arrows in Metal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 15: Picking and labels

**Files:**
- Create: `macos/Sources/Features/MindControl/Renderer/FlowPicking.swift`, `Labels/LabelPlanner.swift` (new generic planner), `Labels/FlowLabels.swift`
- Create: `macos/Tests/MindControl/FlowPickingTests.swift`, `macos/Tests/MindControl/FlowLabelsTests.swift`

**Interfaces:**
- Consumes: `MapLayout`, `Curve`, `ArrowRouter`, `ZoomLevels`, `LayoutMetrics` (Task 10), `PanZoomCamera` (Task 13), `RectGrid` and `PlacedLabel` / `LabelOverlayView` (Task 2)
- Produces:
  - `MindControl.FlowPicking.hit(_ world: CGPoint, layout:curves:zoom:showControl:) -> Hit?`, where `Hit` is `.box(String)` or `.arrow(String)`
  - `MindControl.LabelCandidate(id, text, anchor: CGPoint, leading: Bool, fontSize, bold, opacity, priority: Int, background: Bool, maxWidth: CGFloat?)`
  - `MindControl.LabelPlanner.plan(_ candidates: [LabelCandidate], viewport: CGSize, measure:) -> [PlacedLabel]`, `LabelPlanner.budget = 150`
  - `MindControl.FlowLabels.candidates(layout:curves:camera:viewSize:litFlows:showControl:) -> [LabelCandidate]`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/FlowPickingTests.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias FlowPicking = MindControl.FlowPicking

struct FlowPickingTests {
    private let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
    private var curves: [String: MindControl.Curve] { MindControl.ArrowRouter.curves(for: layout) }

    private func centre(_ id: String) -> CGPoint {
        let rect = layout.box(id)!.rect
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test func partsAreHitOnlyWhenZoomedIn() {
        let point = centre("audio.gate")
        #expect(FlowPicking.hit(point, layout: layout, curves: curves, zoom: 1.3, showControl: true) == .box("audio.gate"))
        #expect(FlowPicking.hit(point, layout: layout, curves: curves, zoom: 0.5, showControl: true) == .box("audio"))
    }

    @Test func arrowsAreHitAtTheirOwnLevel() throws {
        let mid = try #require(curves["flow:pcm"]).mid
        #expect(FlowPicking.hit(mid, layout: layout, curves: curves, zoom: 1.5, showControl: true) == .arrow("flow:pcm"))
        let merged = try #require(curves["sys:audio>agent"]).mid
        #expect(FlowPicking.hit(merged, layout: layout, curves: curves, zoom: 0.6, showControl: true) == .arrow("sys:audio>agent"))
    }

    @Test func hiddenControlArrowsAreNotHit() throws {
        let mid = try #require(curves["flow:event"]).mid
        #expect(FlowPicking.hit(mid, layout: layout, curves: curves, zoom: 1.5, showControl: true) == .arrow("flow:event"))
        #expect(FlowPicking.hit(mid, layout: layout, curves: curves, zoom: 1.5, showControl: false) != .arrow("flow:event"))
    }

    @Test func emptySpaceAndZonesHitNothing() {
        let zone = layout.box("zone:phone")!.rect
        let insideZoneOnly = CGPoint(x: zone.minX + 4, y: zone.minY + 4)
        #expect(FlowPicking.hit(insideZoneOnly, layout: layout, curves: curves, zoom: 0.6, showControl: true) == nil)
        #expect(FlowPicking.hit(CGPoint(x: -99_999, y: -99_999), layout: layout, curves: curves, zoom: 1, showControl: true) == nil)
    }
}
#endif
```

`macos/Tests/MindControl/FlowLabelsTests.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias LabelPlanner = MindControl.LabelPlanner
private typealias LabelCandidate = MindControl.LabelCandidate
private typealias FlowLabels = MindControl.FlowLabels

struct FlowLabelsTests {
    private let view = CGSize(width: 1200, height: 800)
    private let layout = MindControl.FlowLayout.layout(map: FlowFixtures.arca, broken: [])
    private static func measure(_ text: String, _ size: CGFloat, _ bold: Bool) -> CGSize { CGSize(width: CGFloat(text.count) * 6, height: 14) }

    private func texts(zoom: CGFloat, lit: Set<String> = []) -> Set<String> {
        let curves = MindControl.ArrowRouter.curves(for: layout)
        var camera = MindControl.PanZoomCamera.fitting(layout.bounds, in: view)
        camera.zoom = zoom
        let candidates = FlowLabels.candidates(layout: layout, curves: curves, camera: camera, viewSize: view, litFlows: lit, showControl: true)
        return Set(candidates.map(\.text))
    }

    @Test func farZoomShowsOnlyZones() {
        let shown = texts(zoom: 0.15)
        #expect(shown.contains("Phone"))
        #expect(!shown.contains("Audio"))
        #expect(!shown.contains("PCM16 24 kHz"))
    }

    @Test func middleZoomShowsSystemsAndPartHints() {
        let shown = texts(zoom: 0.6)
        #expect(shown.contains("Audio"))
        #expect(shown.contains("2 parts"))
        #expect(!shown.contains("SpeechGate"))
        #expect(!shown.contains("PCM16 24 kHz"))
    }

    @Test func nearZoomShowsPartsAndArrowLabels() {
        let shown = texts(zoom: 1.3)
        #expect(shown.contains("SpeechGate"))
        #expect(shown.contains("PCM16 24 kHz"))
        #expect(!shown.contains("2 parts"))
    }

    @Test func selectedFeatureLabelsItsArrowsAtAnyArrowLevel() {
        #expect(texts(zoom: 0.6, lit: ["pcm"]).contains("PCM16 24 kHz +2"))
    }

    @Test func plannerNeverOverlapsAndPrefersPriority() {
        let a = LabelCandidate(id: "a", text: "low", anchor: CGPoint(x: 100, y: 100), leading: false, fontSize: 11, bold: false,
                               opacity: 1, priority: 5, background: false, maxWidth: nil)
        let b = LabelCandidate(id: "b", text: "high", anchor: CGPoint(x: 102, y: 101), leading: false, fontSize: 11, bold: false,
                               opacity: 1, priority: 1, background: false, maxWidth: nil)
        let placed = LabelPlanner.plan([a, b], viewport: view, measure: Self.measure)
        #expect(placed.map(\.id) == ["b"])
    }

    @Test func plannerTruncatesToMaxWidthAndSkipsOffscreen() {
        let long = LabelCandidate(id: "l", text: "Mic capture, the words-heard check, playback.", anchor: CGPoint(x: 10, y: 10), leading: true,
                                  fontSize: 11, bold: false, opacity: 1, priority: 1, background: false, maxWidth: 60)
        let off = LabelCandidate(id: "o", text: "gone", anchor: CGPoint(x: -500, y: 10), leading: true, fontSize: 11, bold: false,
                                 opacity: 1, priority: 1, background: false, maxWidth: nil)
        let placed = LabelPlanner.plan([long, off], viewport: view, measure: Self.measure)
        #expect(placed.count == 1)
        #expect(placed[0].text.hasSuffix("…"))
        #expect(placed[0].frame.width <= 60)
    }

    @Test func plannerRespectsBudget() {
        let many = (0..<400).map { i in
            LabelCandidate(id: "\(i)", text: "x", anchor: CGPoint(x: CGFloat(i % 40) * 30 + 5, y: CGFloat(i / 40) * 30 + 5), leading: true,
                           fontSize: 11, bold: false, opacity: 1, priority: 1, background: false, maxWidth: nil)
        }
        #expect(LabelPlanner.plan(many, viewport: view, measure: Self.measure).count == LabelPlanner.budget)
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `.superpowers/mc-test.sh FlowPickingTests FlowLabelsTests`
Expected: build errors: `FlowPicking`, `LabelCandidate`, `LabelPlanner`, `FlowLabels` are not defined.

- [ ] **Step 3: Write `Renderer/FlowPicking.swift`**

```swift
import CoreGraphics

extension MindControl {
    /// What's under a world point: a visible part, else the nearest visible arrow, else a system. Zones aren't selectable.
    enum FlowPicking {
        enum Hit: Equatable {
            case box(String)
            case arrow(String)
        }

        /// How close, in view points, the pointer must be to an arrow.
        static let arrowTolerance: CGFloat = 6

        static func hit(_ world: CGPoint, layout: MapLayout, curves: [String: Curve], zoom: CGFloat, showControl: Bool) -> Hit? {
            if layout.fixedLevel || ZoomLevels.partsVisible(at: zoom),
               let part = layout.boxes.last(where: { $0.kind == .part && $0.rect.contains(world) }) {
                return .box(part.id)
            }
            let level = ZoomLevels.arrowLevel(at: zoom)
            let tolerance = arrowTolerance / max(zoom, 0.01)
            var best: (id: String, distance: CGFloat)?
            for arrow in layout.arrows where (layout.fixedLevel || arrow.level == level) && (showControl || arrow.kind == .data) {
                guard let curve = curves[arrow.id] else { continue }
                let bounds = CGRect(x: min(curve.p0.x, curve.p1.x, curve.p2.x, curve.p3.x), y: min(curve.p0.y, curve.p1.y, curve.p2.y, curve.p3.y),
                                    width: 0, height: 0)
                    .union(CGRect(x: max(curve.p0.x, curve.p1.x, curve.p2.x, curve.p3.x), y: max(curve.p0.y, curve.p1.y, curve.p2.y, curve.p3.y),
                                  width: 0, height: 0))
                    .insetBy(dx: -tolerance, dy: -tolerance)
                guard bounds.contains(world) else { continue }
                let distance = curve.distance(to: world)
                if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (arrow.id, distance) }
            }
            if let best { return .arrow(best.id) }
            if let system = layout.boxes.last(where: { $0.kind == .system && $0.rect.contains(world) }) {
                return .box(system.id)
            }
            return nil
        }
    }
}
```

- [ ] **Step 4: Write `Labels/LabelPlanner.swift`**

```swift
import CoreGraphics
import Foundation

extension MindControl {
    struct LabelCandidate: Equatable {
        let id: String
        let text: String
        /// View points, top-left origin. The label's left-middle when `leading`, else its centre.
        let anchor: CGPoint
        let leading: Bool
        let fontSize: CGFloat
        let bold: Bool
        let opacity: CGFloat
        /// Lower wins when two labels would overlap.
        let priority: Int
        let background: Bool
        let maxWidth: CGFloat?
    }

    /// Chooses which labels show: by priority, never overlapping, on screen, within the budget.
    enum LabelPlanner {
        static let budget = 150

        static func plan(_ candidates: [LabelCandidate], viewport: CGSize, measure: (String, CGFloat, Bool) -> CGSize) -> [PlacedLabel] {
            let ordered = candidates.enumerated().sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }.map(\.element)
            var occupied = RectGrid(cell: 64)
            var placed: [PlacedLabel] = []
            for candidate in ordered {
                if placed.count >= budget { break }
                guard candidate.opacity > 0.02 else { continue }
                var text = candidate.text
                var size = measure(text, candidate.fontSize, candidate.bold)
                if let maxWidth = candidate.maxWidth {
                    guard maxWidth > 12 else { continue }
                    while size.width > maxWidth, text.count > 1 {
                        text = String(text.dropLast(text.hasSuffix("…") ? 2 : 1)) + "…"
                        size = measure(text, candidate.fontSize, candidate.bold)
                    }
                    if size.width > maxWidth { continue }
                }
                let origin = candidate.leading
                    ? CGPoint(x: candidate.anchor.x, y: candidate.anchor.y - size.height / 2)
                    : CGPoint(x: candidate.anchor.x - size.width / 2, y: candidate.anchor.y - size.height / 2)
                let frame = CGRect(origin: origin, size: size)
                let footprint = candidate.background
                    ? frame.insetBy(dx: -LabelOverlayView.pillPadding.width, dy: -LabelOverlayView.pillPadding.height)
                    : frame
                guard footprint.maxX > 0, footprint.minX < viewport.width, footprint.maxY > 0, footprint.minY < viewport.height,
                      !occupied.intersects(footprint) else { continue }
                occupied.insert(footprint)
                placed.append(PlacedLabel(id: candidate.id, text: text, frame: frame, fontSize: candidate.fontSize,
                                          isBold: candidate.bold, opacity: candidate.opacity, hasBackground: candidate.background))
            }
            return placed
        }
    }
}
```

- [ ] **Step 5: Write `Labels/FlowLabels.swift`**

```swift
import CoreGraphics

extension MindControl {
    /// Label candidates for the current zoom: zone names when far out, system names and summaries in the
    /// middle, part names and arrow labels up close; the selected feature's arrows are always labelled.
    enum FlowLabels {
        private typealias M = LayoutMetrics

        static func candidates(layout: MapLayout, curves: [String: Curve], camera: PanZoomCamera, viewSize: CGSize,
                               litFlows: Set<String>, showControl: Bool) -> [LabelCandidate] {
            let zoom = camera.zoom
            let fixed = layout.fixedLevel
            func screen(_ x: CGFloat, _ y: CGFloat) -> CGPoint { camera.toScreen(CGPoint(x: x, y: y), viewSize: viewSize) }
            let systemsShown = fixed || zoom >= ZoomLevels.zoneToSystems.lowerBound
            let systemOpacity = fixed ? 1 : smooth(zoom, ZoomLevels.zoneToSystems)
            let partsShown = fixed || ZoomLevels.partsVisible(at: zoom)
            let far = !fixed && zoom < ZoomLevels.zoneToSystems.upperBound
            let arrowLevel = ZoomLevels.arrowLevel(at: zoom)
            var out: [LabelCandidate] = []

            for box in layout.boxes {
                let r = box.rect
                switch box.kind {
                case .zone:
                    out.append(LabelCandidate(id: box.id, text: box.title, anchor: screen(r.minX + M.zonePad * 0.6, r.minY + M.zoneLabel / 2),
                                              leading: true, fontSize: far ? 22 : 14, bold: true, opacity: far ? 0.95 : 0.55,
                                              priority: 0, background: false, maxWidth: nil))
                case .system:
                    guard systemsShown else { continue }
                    let width = r.width * zoom - 28
                    out.append(LabelCandidate(id: box.id, text: box.title, anchor: screen(r.minX, r.minY + 24).offset(14, 0),
                                              leading: true, fontSize: 13, bold: true, opacity: systemOpacity,
                                              priority: 1, background: false, maxWidth: width))
                    if let summary = box.subtitle, fixed || zoom >= 0.45 {
                        out.append(LabelCandidate(id: box.id + "#summary", text: summary, anchor: screen(r.minX, r.minY + 44).offset(14, 0),
                                                  leading: true, fontSize: 11, bold: false, opacity: 0.7 * systemOpacity,
                                                  priority: 3, background: false, maxWidth: width))
                    }
                    if box.partCount > 0, !partsShown {
                        out.append(LabelCandidate(id: box.id + "#parts", text: "\(box.partCount) part\(box.partCount == 1 ? "" : "s")",
                                                  anchor: screen(r.minX, r.maxY).offset(14, -14), leading: true, fontSize: 10.5, bold: false,
                                                  opacity: 0.5 * systemOpacity, priority: 4, background: false, maxWidth: nil))
                    }
                case .part:
                    guard partsShown else { continue }
                    out.append(LabelCandidate(id: box.id, text: box.title, anchor: screen(r.midX, r.midY), leading: false,
                                              fontSize: 11.5, bold: true, opacity: 0.95, priority: 2, background: false,
                                              maxWidth: r.width * zoom - 12))
                }
            }

            for arrow in layout.arrows where !arrow.label.isEmpty && (showControl || arrow.kind == .data) {
                guard fixed || arrow.level == arrowLevel, let curve = curves[arrow.id] else { continue }
                let lit = !litFlows.isDisjoint(with: arrow.flowIDs)
                guard fixed || lit || (arrow.level == .part && zoom >= 1.0) else { continue }
                out.append(LabelCandidate(id: arrow.id, text: arrow.label, anchor: camera.toScreen(curve.mid, viewSize: viewSize),
                                          leading: false, fontSize: 10.5, bold: false, opacity: 0.9, priority: lit ? 2 : 5,
                                          background: true, maxWidth: nil))
            }
            return out
        }

        private static func smooth(_ x: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
            let t = min(1, max(0, (x - range.lowerBound) / (range.upperBound - range.lowerBound)))
            return t * t * (3 - 2 * t)
        }
    }
}

private extension CGPoint {
    func offset(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}
```

- [ ] **Step 6: Run the tests to watch them pass**

Run: `.superpowers/mc-test.sh FlowPickingTests FlowLabelsTests`
Expected: both suites report `0 failed`.

`middleZoomShowsSystemsAndPartHints` depends on the camera, which is fitted and then forced to `zoom = 0.6`. Some systems can then be off screen, but `candidates` doesn't cull. Culling is the planner's job, so the test checks candidates, not placed labels.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/MindControl/Renderer/FlowPicking.swift macos/Sources/Features/MindControl/Labels/LabelPlanner.swift \
  macos/Sources/Features/MindControl/Labels/FlowLabels.swift macos/Tests/MindControl/FlowPickingTests.swift macos/Tests/MindControl/FlowLabelsTests.swift
git commit -m "mindcontrol: 2D picking and zoom-aware labels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: Load and watch the project (Model, ProjectGuard, FlowWatcher)

**Files:**
- Create: `macos/Sources/Features/MindControl/Flow/ProjectGuard.swift`, `Flow/FlowWatcher.swift`
- Rewrite: `macos/Sources/Features/MindControl/MindControlModel.swift`
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarModel.swift`
- Create: `macos/Tests/MindControl/ProjectGuardTests.swift`, `macos/Tests/MindControl/FlowWatcherTests.swift`, `macos/Tests/MindControl/ModelTests.swift`

**Interfaces:**
- Consumes:
  - `FlowSource`, `FlowSnapshot`, `Git` (Task 5)
  - `FlowFile` (Task 3)
  - `FlowCheck` (Task 6)
  - `FlowAge` (Task 7)
  - `LayoutStore` (Task 10)
  - `ProjectScanner.projectRoot(for:)` (existing)
  - Task 1's finding: if it was outcome (a), the old model's cache was the cause, and this rewrite removes caching entirely
- Produces:
  - `MindControl.ProjectGuard.claudeBlockReason(root:home:isGit:) -> String?`
  - `MindControl.FlowWatcher(root: URL, onChange: @escaping () -> Void)` with `stop()`
  - `MindControl.Model`:
    - `State`: `.idle`, `.noProject`, `.loading(Project)`, `.noFlowFile(Project)`, `.invalid(Project, [FlowError])`, `.ready(Project, Loaded)`, `.failed(String)`
    - `Project(root: URL, name: String, claudeBlockReason: String?)`
    - `Loaded(map: FlowMap, report: HealthReport, saved: [String: CGPoint], generation: Int)`
    - `load(pwd:)`, `choose(root:)`, `reload()`, `close()`
    - `var project: Project?`, `var loadingTask: Task<Void, Never>?`
  - `ExtensionSidebarModel` calls `mindControl.close()` when the visualizer closes

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/ProjectGuardTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias ProjectGuard = MindControl.ProjectGuard

struct ProjectGuardTests {
    @Test func homeFolderIsBlocked() {
        let reason = ProjectGuard.claudeBlockReason(root: URL(fileURLWithPath: "/Users/someone"), home: "/Users/someone", isGit: { _ in true })
        #expect(reason?.contains("home folder") == true)
    }

    @Test func diskRootIsBlocked() {
        #expect(ProjectGuard.claudeBlockReason(root: URL(fileURLWithPath: "/"), home: "/Users/someone", isGit: { _ in true }) != nil)
    }

    @Test func nonGitFolderIsBlocked() {
        let reason = ProjectGuard.claudeBlockReason(root: URL(fileURLWithPath: "/tmp/x"), home: "/Users/someone", isGit: { _ in false })
        #expect(reason?.contains("git") == true)
    }

    @Test func gitProjectIsAllowed() throws {
        let project = try TempProject()
        try project.git("init", "-q")
        #expect(ProjectGuard.claudeBlockReason(root: project.url, home: "/Users/someone") == nil)
    }
}
#endif
```

`macos/Tests/MindControl/FlowWatcherTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

@MainActor
private final class Counter {
    var value = 0
}

@MainActor
struct FlowWatcherTests {
    private func waitFor(_ condition: () -> Bool, seconds: Double = 3) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    @Test func reportsChangeToFlowFileOnly() async throws {
        let project = try TempProject()
        try project.write(".mindcontrol/flow.json", "{}")
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        defer { watcher.stop() }

        try project.write(".mindcontrol/layout.json", "{ \"version\": 1, \"positions\": {} }")
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(count.value == 0)

        try project.write(".mindcontrol/flow.json", "{ \"version\": 1 }")
        await waitFor { count.value == 1 }
        #expect(count.value == 1)
    }

    @Test func noticesTheFlowFileAppearing() async throws {
        let project = try TempProject()
        let count = Counter()
        let watcher = MindControl.FlowWatcher(root: project.url) { count.value += 1 }
        defer { watcher.stop() }
        try project.write(".mindcontrol/flow.json", "{}")
        await waitFor { count.value >= 1 }
        #expect(count.value == 1)
    }
}
#endif
```

`macos/Tests/MindControl/ModelTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias Model = MindControl.Model
private typealias FlowSnapshot = MindControl.FlowSnapshot

@MainActor
struct ModelTests {
    private let pwd = URL(fileURLWithPath: "/tmp/mc-model-test")

    private func model(json: String?, files: [String: String] = FlowFixtures.arcaSources,
                       age: MindControl.HealthReport.Age = .commits(3), blocked: String? = nil) -> Model {
        Model(snapshot: { root in
                  FlowSnapshot(root: root, flowData: json.map { Data($0.utf8) }, layoutData: nil,
                               sourceFiles: files.keys.sorted(), read: { files[$0] })
              },
              age: { _, _ in age },
              guardReason: { _ in blocked },
              watch: false)
    }

    @Test func nilPwdIsNoProject() {
        let model = model(json: nil)
        model.load(pwd: nil)
        #expect(model.state == .noProject)
    }

    @Test func missingFlowFile() async {
        let model = model(json: nil, blocked: "This folder isn't a git repository.")
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .noFlowFile(let project) = model.state else { Issue.record("\(model.state)"); return }
        #expect(project.name == "mc-model-test")
        #expect(project.claudeBlockReason == "This folder isn't a git repository.")
    }

    @Test func invalidFileShowsErrors() async {
        let model = model(json: "{ \"version\": 1 }")
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .invalid(_, let errors) = model.state else { Issue.record("\(model.state)"); return }
        #expect(errors.contains { $0.message.contains("systems") })
    }

    @Test func readyCarriesMapReportAndAge() async {
        let model = model(json: FlowFixtures.arcaJSON)
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .ready(_, let loaded) = model.state else { Issue.record("\(model.state)"); return }
        #expect(loaded.map == FlowFixtures.arca)
        #expect(loaded.report.isHealthy)
        #expect(loaded.report.age == .commits(3))
    }

    @Test func brokenEndpointStillDrawsTheRest() async {
        let json = FlowFixtures.arcaJSON.replacingOccurrences(of: #""to": "agent.session", "kind": "data", "carries": "PCM16"#,
                                                              with: #""to": "agent.nope", "kind": "data", "carries": "PCM16"#)
        let model = model(json: json)
        model.load(pwd: pwd)
        await model.loadingTask?.value
        guard case .ready(_, let loaded) = model.state else { Issue.record("\(model.state)"); return }
        #expect(loaded.report.brokenFlows == ["pcm"])
        let layout = MindControl.FlowLayout.layout(map: loaded.map, broken: loaded.report.brokenFlows)
        #expect(layout.arrows.first { $0.id == "flow:pcm" } == nil)
        #expect(layout.arrows.contains { $0.id == "flow:send" })
    }

    @Test func overrideReplacesTerminalFolderUntilClosed() async {
        let model = model(json: nil)
        model.load(pwd: URL(fileURLWithPath: "/tmp/mc-a"))
        model.choose(root: URL(fileURLWithPath: "/tmp/mc-b"))
        await model.loadingTask?.value
        #expect(model.project?.root.path == "/tmp/mc-b")
        model.load(pwd: URL(fileURLWithPath: "/tmp/mc-a"))
        await model.loadingTask?.value
        #expect(model.project?.root.path == "/tmp/mc-b")
        model.close()
        model.load(pwd: URL(fileURLWithPath: "/tmp/mc-a"))
        await model.loadingTask?.value
        #expect(model.project?.root.path == "/tmp/mc-a")
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `.superpowers/mc-test.sh ProjectGuardTests FlowWatcherTests ModelTests`
Expected: build errors: `ProjectGuard`, `FlowWatcher`, and `Model(snapshot:age:guardReason:watch:)` are not defined.

- [ ] **Step 3: Write `Flow/ProjectGuard.swift`**

```swift
import Foundation

extension MindControl {
    /// Keeps Draft and Refresh with Claude away from folders where they'd do harm or make no sense.
    enum ProjectGuard {
        /// Why Claude can't draft or refresh a map here, or nil when it can.
        static func claudeBlockReason(root: URL, home: String = NSHomeDirectory(),
                                      isGit: (URL) -> Bool = Git.isRepository) -> String? {
            let path = canonical(root.path)
            if path == canonical(home) { return "This is your home folder. Choose a project folder." }
            if path == "/" { return "This is the top of the disk. Choose a project folder." }
            if !isGit(root) { return "This folder isn't a git repository, so Claude can't draft or refresh its map." }
            return nil
        }

        private static func canonical(_ path: String) -> String {
            URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        }
    }
}
```

- [ ] **Step 4: Write `Flow/FlowWatcher.swift`**

```swift
import Foundation

extension MindControl {
    /// Calls `onChange` (on the main queue) when `.mindcontrol/flow.json` appears or its contents change.
    /// Writes to `layout.json` and other files don't count.
    final class FlowWatcher {
        private let root: URL
        private let onChange: () -> Void
        private var sources: [DispatchSourceFileSystemObject] = []
        private var last: Data?
        private var pending: DispatchWorkItem?
        private var stopped = false

        init(root: URL, onChange: @escaping () -> Void) {
            self.root = root
            self.onChange = onChange
            last = read()
            arm()
        }

        deinit { stop() }

        func stop() {
            stopped = true
            pending?.cancel()
            disarm()
        }

        private var flowURL: URL { root.appendingPathComponent(FlowFile.relativePath) }

        private func read() -> Data? { try? Data(contentsOf: flowURL) }

        /// Watches the root (for `.mindcontrol` appearing), the folder, and the file itself (for in-place writes).
        private func arm() {
            disarm()
            for url in [root, flowURL.deletingLastPathComponent(), flowURL] {
                let fd = open(url.path, O_EVTONLY)
                guard fd >= 0 else { continue }
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                                       eventMask: [.write, .extend, .rename, .delete, .attrib],
                                                                       queue: .main)
                source.setEventHandler { [weak self] in self?.changed() }
                source.setCancelHandler { close(fd) }
                source.resume()
                sources.append(source)
            }
        }

        private func disarm() {
            for source in sources { source.cancel() }
            sources = []
        }

        private func changed() {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.stopped else { return }
                self.arm()
                let now = self.read()
                guard now != self.last else { return }
                self.last = now
                self.onChange()
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}
```

- [ ] **Step 5: Rewrite `MindControlModel.swift`**

```swift
import CoreGraphics
import Foundation

extension MindControl {
    /// Loads the focused terminal's flow map off the main thread, and reloads when the flow file changes.
    /// One per window.
    @MainActor
    final class Model: ObservableObject {
        struct Project: Equatable {
            let root: URL
            let name: String
            /// Why Draft/Refresh with Claude are off here, or nil.
            let claudeBlockReason: String?
        }

        struct Loaded: Equatable {
            let map: FlowMap
            let report: HealthReport
            let saved: [String: CGPoint]
            /// Changes on every load, so views can tell a reload from a repeat.
            let generation: Int
        }

        enum State: Equatable {
            case idle
            case noProject
            case loading(Project)
            case noFlowFile(Project)
            case invalid(Project, [FlowError])
            case ready(Project, Loaded)
            case failed(String)
        }

        enum Outcome: Sendable {
            case none
            case invalid([FlowError])
            case ready(FlowMap, HealthReport, [String: CGPoint])
        }

        @Published private(set) var state: State = .idle
        private(set) var loadingTask: Task<Void, Never>?

        private let snapshot: @Sendable (URL) throws -> FlowSnapshot
        private let age: @Sendable (URL, FlowMap) -> HealthReport.Age
        private let guardReason: @Sendable (URL) -> String?
        private let watch: Bool
        private var terminalPwd: URL?
        private var override: URL?
        private var watcher: FlowWatcher?
        private var watchedRoot: URL?
        private var generation = 0

        init(snapshot: @escaping @Sendable (URL) throws -> FlowSnapshot = { try FlowSource.workingTree.snapshot(root: $0) },
             age: @escaping @Sendable (URL, FlowMap) -> HealthReport.Age = { FlowAge.age(root: $0, map: $1) },
             guardReason: @escaping @Sendable (URL) -> String? = { ProjectGuard.claudeBlockReason(root: $0) },
             watch: Bool = true) {
            self.snapshot = snapshot
            self.age = age
            self.guardReason = guardReason
            self.watch = watch
        }

        var project: Project? {
            switch state {
            case .loading(let project), .noFlowFile(let project), .invalid(let project, _), .ready(let project, _): project
            case .idle, .noProject, .failed: nil
            }
        }

        /// The terminal's folder; ignored while a folder chosen with Change… is in effect.
        func load(pwd: URL?) {
            terminalPwd = pwd
            reload()
        }

        /// Change…: map this folder until MindControl closes.
        func choose(root: URL) {
            override = root
            reload()
        }

        /// MindControl closed: forget the chosen folder and stop watching.
        func close() {
            override = nil
            watcher?.stop()
            watcher = nil
            watchedRoot = nil
        }

        func reload() {
            guard let target = override ?? terminalPwd else {
                loadingTask?.cancel()
                state = .noProject
                return
            }
            let root = override ?? ProjectScanner.projectRoot(for: target)
            let project = Project(root: root, name: root.lastPathComponent, claudeBlockReason: guardReason(root))
            loadingTask?.cancel()
            if case .ready(let current, _) = state, current == project {
                // Keep showing the map while it reloads.
            } else {
                state = .loading(project)
            }
            generation += 1
            let current = generation
            let snapshot = self.snapshot, age = self.age
            let work = Task.detached(priority: .userInitiated) { () -> Result<Outcome, Error> in
                Result { try Self.compute(root: root, snapshot: snapshot, age: age) }
            }
            loadingTask = Task { [weak self] in
                let result = await work.value
                guard let self, !Task.isCancelled, current == self.generation else { return }
                switch result {
                case .success(.none): self.state = .noFlowFile(project)
                case .success(.invalid(let errors)): self.state = .invalid(project, errors)
                case .success(.ready(let map, let report, let saved)):
                    self.state = .ready(project, Loaded(map: map, report: report, saved: saved, generation: current))
                case .failure(let error): self.state = .failed(Self.message(for: error))
                }
                if self.watch { self.watch(root) }
            }
        }

        nonisolated static func compute(root: URL, snapshot: (URL) throws -> FlowSnapshot,
                                        age: (URL, FlowMap) -> HealthReport.Age) throws -> Outcome {
            let snap = try snapshot(root)
            guard let data = snap.flowData else { return .none }
            switch FlowFile.parse(data) {
            case .failure(let failure):
                return .invalid(failure.errors)
            case .success(let map):
                var report = FlowCheck.run(map: map, snapshot: snap)
                report.age = age(root, map)
                return .ready(map, report, LayoutStore.decode(snap.layoutData))
            }
        }

        private func watch(_ root: URL) {
            guard watchedRoot != root else { return }
            watcher?.stop()
            watchedRoot = root
            watcher = FlowWatcher(root: root) { [weak self] in self?.reload() }
        }

        private static func message(for error: Error) -> String {
            switch error {
            case ScanError.noDirectory(let path), ScanError.unreadable(let path): "Can't read \(path)."
            default: error.localizedDescription
            }
        }
    }
}
```

A folder chosen with Change… is used as-is, not resolved to its git root: the user picked it deliberately.

- [ ] **Step 6: Close the model when the visualizer closes**

In `macos/Sources/Features/Extensions/ExtensionSidebarModel.swift`, inside `setActive(_:)`, after the existing `load(pwd:)` block, add:

```swift
        if previous == .codebaseVisualizer, ext != .codebaseVisualizer {
            mindControl.close()
        }
```

Find the sidebar model's tests: `grep -rln "ExtensionSidebarModel" macos/Tests`. In that file, add a test: select `.codebaseVisualizer`, call `mindControl.choose(root:)` with `/tmp/mc-x`, close it with `select(.codebaseVisualizer)` again, reopen it with `workingDirectory` returning `/tmp/mc-y`, await `mindControl.loadingTask?.value`, and expect `mindControl.project?.root.path == "/tmp/mc-y"`. If no such test file exists, create `macos/Tests/MindControl/SidebarIntegrationTests.swift` with that test. Watch it fail before Step 6's edit, then pass after it.

- [ ] **Step 7: Run the tests to watch them pass**

Run: `.superpowers/mc-test.sh ProjectGuardTests FlowWatcherTests ModelTests`, plus the sidebar test's suite name.
Expected: every suite reports `0 failed`.

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/Features/MindControl/Flow/ProjectGuard.swift macos/Sources/Features/MindControl/Flow/FlowWatcher.swift \
  macos/Sources/Features/MindControl/MindControlModel.swift macos/Sources/Features/Extensions/ExtensionSidebarModel.swift \
  macos/Tests/MindControl/ProjectGuardTests.swift macos/Tests/MindControl/FlowWatcherTests.swift macos/Tests/MindControl/ModelTests.swift \
  <the sidebar test file>
git commit -m "mindcontrol: load, check and watch a project's flow map

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 17: The map controller and the Metal view

**Files:**
- Create: `macos/Sources/Features/MindControl/Map/MapController.swift`, `Renderer/FlowMTKView.swift`, `Claude/FileOpener.swift`
- Create: `macos/Tests/MindControl/MapControllerTests.swift`

**Interfaces:**
- Consumes:
  - `Model.Loaded` (Task 16)
  - `FlowLayout`, `ArrowRouter`, `LayoutStore`, `MapLayout` (Task 10)
  - `FocusLayout` (Task 11)
  - `FlowSearch`, `SearchResult` (Task 12)
  - `PanZoomCamera` (Task 13)
  - `FlowScene`, `SceneStyle`, `Palette`, `Renderer` (Task 14)
  - `FlowPicking`, `FlowLabels`, `LabelPlanner` (Task 15)
  - `FeatureSteps`, `FeatureStep`, `StepGroup` (Task 8)
  - `LabelOverlayView` (Task 2)
- Produces:
  - `MindControl.FlowRow(id, from, to, carries, kind, when, status: FeatureStep.Status, via: String?, location: SourceLocation?)`
  - `MindControl.SidePanelContent`: `.none`, `.feature(name:groups:unknown:)`, `.system(name:summary:incoming:outgoing:files:)`, `.part(name:system:file:stale:incoming:outgoing:)`, `.arrow(rows:)`, `.health(HealthReport)`
  - `MindControl.MapController` (`@MainActor`, `ObservableObject`):
    - `Selection`: `.box(String)`, `.arrow(String)`; `Focus`: `.system(String)`, `.feature(String)`
    - published: `mode`, `showControl`, `selectedFeature`, `selection`, `focus`, `query`, `results`, `searchRequest`
    - `onClose`, `openFile: (URL, Int?) -> Void`
    - read-only state: `root`, `map`, `report`, `saved`, `baseLayout`, `layout`, `curves`
    - `camera` (get/set), `viewSize`, `style: SceneStyle`, `sidePanel: SidePanelContent`, `breadcrumb: [String]`
    - `show(_:root:)`, `attach(_:)`, `refresh()`, `tick(_:)`, `fit(animated:)`
    - `selectFeature(_:)`, `enterFocus()`, `enterFocus(_:)`, `exitFocus()`, `escape() -> Bool`, `beginSearch(with:)`, `navigate(to:)`, `goToStep(_ flowID:)`, `goToIssue(_:)`, `open(_ location: SourceLocation)`, `openSource(_ path: String)`
    - `hit(at:)`, `click(at:)`, `doubleClick(at:)`, `zoom(by:about:)`, `pan(by:)`, `canDrag(_:)`, `drag(system:byScreen:)`, `endDrag(_:)`, `labels() -> [PlacedLabel]`
    - `static blend(from:to:t:) -> (MapLayout, [String: Float])`
  - `MindControl.FlowMetalView(renderer:controller:)` (`NSViewRepresentable`)
  - `MindControl.FileOpener.open(_ url: URL, line: Int?)`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/MapControllerTests.swift`:

```swift
#if os(macOS)
import CoreGraphics
import Foundation
import Testing
@testable import Ghostty

private typealias MapController = MindControl.MapController

@MainActor
struct MapControllerTests {
    private func loaded(generation: Int = 1) -> MindControl.Model.Loaded {
        let files = FlowFixtures.arcaSources
        let snapshot = MindControl.FlowSnapshot(root: URL(fileURLWithPath: "/tmp/mc-ctl"), flowData: nil, layoutData: nil,
                                                sourceFiles: files.keys.sorted(), read: { files[$0] })
        return .init(map: FlowFixtures.arca, report: MindControl.FlowCheck.run(map: FlowFixtures.arca, snapshot: snapshot),
                     saved: [:], generation: generation)
    }

    private func controller(root: URL = URL(fileURLWithPath: "/tmp/mc-ctl")) -> MapController {
        let controller = MapController()
        controller.viewSize = CGSize(width: 1200, height: 800)
        controller.show(loaded(), root: root)
        return controller
    }

    @Test func showLaysOutAndFitsTheMap() {
        let c = controller()
        #expect(c.layout == c.baseLayout)
        #expect(c.baseLayout.box("audio") != nil)
        let topLeft = c.camera.toScreen(c.layout.bounds.origin, viewSize: c.viewSize)
        let bottomRight = c.camera.toScreen(CGPoint(x: c.layout.bounds.maxX, y: c.layout.bounds.maxY), viewSize: c.viewSize)
        #expect(topLeft.x >= 0 && topLeft.y >= 0 && bottomRight.x <= 1200 && bottomRight.y <= 800)
    }

    @Test func selectingAFeatureLightsItAndListsItsSteps() {
        let c = controller()
        c.selectFeature("speech")
        #expect(c.style.litFlows.count == 9)
        guard case .feature(let name, let groups, let unknown) = c.sidePanel else { Issue.record("\(c.sidePanel)"); return }
        #expect(name == "A press becomes speech")
        #expect(groups.count == 4)
        #expect(unknown.isEmpty)
        c.selectFeature("speech")
        #expect(c.selectedFeature == nil)
    }

    @Test func escapeUnwindsSearchThenFocusThenSelection() {
        let c = controller()
        c.selectFeature("speech")
        c.enterFocus(.system("audio"))
        c.query = "aud"
        #expect(c.escape())
        #expect(c.query.isEmpty)
        #expect(c.escape())
        #expect(c.focus == nil)
        #expect(c.escape())
        #expect(c.selectedFeature == nil)
        #expect(!c.escape())
    }

    @Test func focusSwapsTheLayoutAndBack() {
        let c = controller()
        c.enterFocus(.system("audio"))
        #expect(c.layout.fixedLevel)
        #expect(c.layout.box("ble") == nil)
        #expect(c.breadcrumb == ["mc-ctl", "Audio"])
        c.exitFocus()
        #expect(c.layout == c.baseLayout)
    }

    @Test func blendSlidesSharedBoxesAndFadesTheRest() throws {
        let c = controller()
        let focus = try #require(MindControl.FocusLayout.system("audio", map: FlowFixtures.arca, broken: []))
        let (mid, fade) = MapController.blend(from: c.baseLayout, to: focus, t: 0.5)
        let a = try #require(c.baseLayout.box("audio")).rect, b = try #require(focus.box("audio")).rect
        #expect(abs(try #require(mid.box("audio")).rect.minX - (a.minX + b.minX) / 2) < 1e-9)
        #expect(fade["ble"] == 0.5)
        #expect(fade["audio"] == nil)
    }

    @Test func draggingASystemSavesItsPosition() throws {
        let project = try TempProject()
        let c = controller(root: project.url)
        let before = try #require(c.baseLayout.box("audio")).rect
        c.drag(system: "audio", byScreen: CGSize(width: 100, height: 0))
        let after = try #require(c.baseLayout.box("audio")).rect
        #expect(abs(after.minX - (before.minX + 100 / c.camera.zoom)) < 1e-6)
        c.endDrag("audio")
        let data = try Data(contentsOf: project.url.appendingPathComponent(".mindcontrol/layout.json"))
        #expect(MindControl.LayoutStore.decode(data)["audio"] == after.origin)
    }

    @Test func onlySystemsOnTheMainMapCanBeDragged() {
        let c = controller()
        #expect(c.canDrag("audio"))
        #expect(!c.canDrag("audio.gate"))
        #expect(!c.canDrag("zone:phone"))
        c.enterFocus(.system("audio"))
        #expect(!c.canDrag("audio"))
    }

    @Test func searchingAFileWithNoSystemOpensHealth() {
        let c = controller()
        c.navigate(to: MindControl.SearchResult(kind: .file, title: "Stray.swift", detail: "", target: .file(path: "x/Stray.swift", system: nil)))
        #expect(c.mode == .health)
        if case .health = c.sidePanel {} else { Issue.record("\(c.sidePanel)") }
    }

    @Test func searchingASystemSelectsIt() {
        let c = controller()
        c.navigate(to: MindControl.SearchResult(kind: .system, title: "Audio", detail: "", target: .system("audio")))
        #expect(c.selection == .box("audio"))
        #expect(c.style.pulsed == "audio")
        guard case .system(let name, _, let incoming, let outgoing, let files) = c.sidePanel else { Issue.record("\(c.sidePanel)"); return }
        #expect(name == "Audio")
        #expect(incoming.map(\.id) == ["begin"])
        #expect(Set(outgoing.map(\.id)) == ["pcm", "commit", "discard"])
        #expect(files == ["app/Sources/Audio/AudioCapture.swift", "app/Sources/Audio/SpeechGate.swift"])
    }

    @Test func doubleClickingAnArrowOpensItsHandOff() throws {
        let c = controller()
        var opened: (URL, Int?)?
        c.openFile = { opened = ($0, $1) }
        let mid = try #require(c.curves["flow:pcm"]).mid
        c.camera = MindControl.PanZoomCamera(center: mid, zoom: 1.5)
        c.doubleClick(at: c.camera.toScreen(mid, viewSize: c.viewSize))
        #expect(opened?.0.path.hasSuffix("app/Sources/Audio/AudioCapture.swift") == true)
        #expect(opened?.1 == 4)
    }

    @Test func clickingAHealthIssueGoesToItsSubject() {
        let c = controller()
        c.mode = .health
        c.goToIssue(.init(kind: .staleAnchor, subject: "audio.gate", message: "SpeechGate: type missing"))
        #expect(c.selection == .box("audio.gate"))
        c.goToIssue(.init(kind: .staleVia, subject: "pcm", message: "pcm: sendAudio missing"))
        #expect(c.selection == .arrow("flow:pcm"))
    }

    @Test func reloadKeepsFocusAndDropsVanishedSelection() {
        let c = controller()
        c.enterFocus(.system("audio"))
        c.click(at: .zero)
        c.show(loaded(generation: 2), root: URL(fileURLWithPath: "/tmp/mc-ctl"))
        #expect(c.focus == .system("audio"))
        #expect(c.layout.fixedLevel)
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh MapControllerTests`
Expected: build error: `MapController` is not defined.

- [ ] **Step 3: Write `Claude/FileOpener.swift`**

```swift
import AppKit

extension MindControl {
    enum FileOpener {
        /// Opens `url` in its default app. When that app is Xcode and a line is given, opens at the line.
        static func open(_ url: URL, line: Int?) {
            if let line, let app = NSWorkspace.shared.urlForApplication(toOpen: url),
               Bundle(url: app)?.bundleIdentifier == "com.apple.dt.Xcode" {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xed")
                process.arguments = ["--line", String(line), url.path]
                if (try? process.run()) != nil { return }
            }
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 4: Write `Map/MapController.swift`**

```swift
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

        static let transitionDuration: CFTimeInterval = 0.35
        static let pulseDuration: CFTimeInterval = 1.2

        @Published var mode: SceneStyle.Mode = .map { didSet { refresh() } }
        @Published var showControl = true { didSet { refresh() } }
        @Published private(set) var selectedFeature: String?
        @Published private(set) var selection: Selection?
        @Published private(set) var focus: Focus?
        @Published var query = "" { didSet { results = searchIndex?.search(query) ?? [] } }
        @Published private(set) var results: [SearchResult] = []
        /// Bumped to ask the search field to take keyboard focus.
        @Published private(set) var searchRequest = 0

        var onClose: () -> Void = {}
        var openFile: (URL, Int?) -> Void = { FileOpener.open($0, line: $1) }

        private(set) var root: URL?
        private(set) var map: FlowMap?
        private(set) var report = HealthReport()
        private(set) var saved: [String: CGPoint] = [:]
        private(set) var baseLayout = MapLayout(boxes: [], arrows: [])
        private(set) var layout = MapLayout(boxes: [], arrows: [])
        private(set) var curves: [String: Curve] = [:]
        private var fade: [String: Float] = [:]
        private var transition: Transition?
        private var pulse: (id: String, until: CFTimeInterval)?
        private var searchIndex: FlowSearch?
        private var cameraBeforeFocus: PanZoomCamera?
        private var localCamera = PanZoomCamera()
        private var loadedGeneration: Int?
        private(set) weak var renderer: Renderer?
        /// Zero until the view first lays out; the first real size fits the map.
        var viewSize = CGSize.zero

        var camera: PanZoomCamera {
            get { renderer?.camera ?? localCamera }
            set {
                if let renderer { renderer.camera = newValue } else { localCamera = newValue }
            }
        }

        // MARK: Loading

        func show(_ loaded: Model.Loaded, root: URL) {
            guard loaded.generation != loadedGeneration || root != self.root else { return }
            let firstShow = map == nil || self.root != root
            loadedGeneration = loaded.generation
            self.root = root
            map = loaded.map
            report = loaded.report
            saved = loaded.saved
            searchIndex = FlowSearch(map: loaded.map, report: loaded.report)
            results = searchIndex?.search(query) ?? []
            baseLayout = FlowLayout.layout(map: loaded.map, broken: loaded.report.brokenFlows, saved: saved)
            if let id = selectedFeature, loaded.map.feature(id) == nil { selectedFeature = nil }
            transition = nil
            fade = [:]
            if let current = focus, let focused = focusLayout(current) {
                layout = focused
            } else {
                focus = nil
                layout = baseLayout
            }
            if let current = selection, !exists(current) { selection = nil }
            refresh()
            // The spec fits the whole map on open and on every reload; focus views keep their own framing.
            if focus == nil { fit(animated: !firstShow) }
        }

        func attach(_ renderer: Renderer) {
            self.renderer = renderer
            renderer.camera = localCamera
            renderer.beforeFrame = { [weak self] now in self?.tick(now) }
            refresh()
        }

        func fit(animated: Bool) {
            move(to: PanZoomCamera.fitting(layout.bounds, in: viewSize), animated: animated)
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
            case nil: break
            }
            style.pulsed = pulse?.id
            style.fade = fade
            return style
        }

        func refresh() {
            curves = ArrowRouter.curves(for: layout)
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

        /// Selecting the selected feature again clears it.
        func selectFeature(_ id: String?) {
            selectedFeature = id == selectedFeature ? nil : id
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

        /// F: focus the selected system (or a part's system), else the selected feature.
        func enterFocus() {
            if case .box(let id) = selection, let system = systemID(of: id) {
                enterFocus(.system(system))
            } else if let feature = selectedFeature {
                enterFocus(.feature(feature))
            }
        }

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
            move(to: cameraBeforeFocus ?? PanZoomCamera.fitting(baseLayout.bounds, in: viewSize), animated: true)
            cameraBeforeFocus = nil
        }

        private func startTransition(to next: MapLayout) {
            guard renderer != nil else {
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

        func navigate(to result: SearchResult) {
            query = ""
            if focus != nil { exitFocus() }
            switch result.target {
            case .feature(let id):
                selectedFeature = id
                if let map, let feature = map.feature(id) {
                    let systems = Set(feature.route.compactMap { map.flow($0) }.flatMap { [$0.from.system, $0.to.system] })
                    let rect = baseLayout.boxes.filter { systems.contains($0.id) }.reduce(CGRect.null) { $0.union($1.rect) }
                    if !rect.isNull { move(to: PanZoomCamera.fitting(rect, in: viewSize), animated: true) }
                }
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

        private func reveal(_ id: String, minZoom: CGFloat) {
            guard let box = baseLayout.box(id) else { return }
            selection = .box(id)
            pulse = (id, CACurrentMediaTime() + Self.pulseDuration)
            move(to: PanZoomCamera(center: CGPoint(x: box.rect.midX, y: box.rect.midY), zoom: max(camera.zoom, minZoom)), animated: true)
        }

        /// A side panel step was clicked: move to that flow's arrow and select it.
        func goToStep(_ flowID: String) {
            let id = "flow:\(flowID)"
            guard let curve = curves[id] else { return }
            selection = .arrow(id)
            move(to: PanZoomCamera(center: curve.mid, zoom: max(camera.zoom, layout.fixedLevel ? camera.zoom : 1.1)), animated: true)
            refresh()
        }

        /// Health view: move to whatever an issue is about.
        func goToIssue(_ issue: HealthReport.Issue) {
            if baseLayout.box(issue.subject) != nil {
                reveal(issue.subject, minZoom: issue.subject.contains(".") ? 1.3 : 0.6)
            } else if map?.flow(issue.subject) != nil {
                goToStep(issue.subject)
            } else if report.unmapped.contains(issue.subject) || report.owners[issue.subject] != nil {
                openSource(issue.subject)
            }
            refresh()
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

        func canDrag(_ id: String) -> Bool {
            focus == nil && baseLayout.box(id)?.kind == .system
        }

        func drag(system id: String, byScreen delta: CGSize) {
            guard canDrag(id), let rect = baseLayout.box(id)?.rect, let map else { return }
            saved[id] = CGPoint(x: rect.minX + delta.width / camera.zoom, y: rect.minY + delta.height / camera.zoom)
            baseLayout = FlowLayout.layout(map: map, broken: report.brokenFlows, saved: saved)
            layout = baseLayout
            refresh()
        }

        func endDrag(_ id: String) {
            guard let root else { return }
            try? LayoutStore.write(saved, root: root)
        }

        func labels() -> [PlacedLabel] {
            LabelPlanner.plan(FlowLabels.candidates(layout: layout, curves: curves, camera: camera, viewSize: viewSize,
                                                    litFlows: style.litFlows, showControl: showControl),
                              viewport: viewSize, measure: LabelOverlayView.measure)
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
                               files: report.owners.filter { $0.value == id }.map(\.key).sorted())
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
```

- [ ] **Step 5: Write `Renderer/FlowMTKView.swift`**

```swift
import MetalKit
import SwiftUI

extension MindControl {
    /// The Metal view: turns mouse, trackpad and keys into MapController calls and hosts the label overlay.
    final class FlowMTKView: MTKView {
        weak var controller: MapController?
        private let labels = LabelOverlayView()
        private var lastPoint: CGPoint?
        private var downPoint: CGPoint?
        private var dragSystem: String?
        private var moved = false

        override init(frame: CGRect, device: MTLDevice?) {
            super.init(frame: frame, device: device)
            setUpLabels()
        }

        required init(coder: NSCoder) {
            super.init(coder: coder)
            setUpLabels()
        }

        private func setUpLabels() {
            labels.frame = bounds
            labels.autoresizingMask = [.width, .height]
            addSubview(labels)
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Take keyboard focus so Esc, F and typing reach the map while the panel is open.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            guard let controller else { return }
            let first = controller.viewSize == .zero
            controller.viewSize = newSize
            if first { controller.fit(animated: false) }
        }

        /// View points with a top-left origin, the camera's convention.
        private func point(_ event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            return CGPoint(x: p.x, y: bounds.height - p.y)
        }

        override func keyDown(with event: NSEvent) {
            guard let controller else { return }
            if event.keyCode == 53 {
                if !controller.escape() { controller.onClose() }
                return
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty, let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return }
            if characters.lowercased() == "f", controller.query.isEmpty {
                controller.enterFocus()
            } else if characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "." }) {
                controller.beginSearch(with: characters)
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let controller else { return }
            let p = point(event)
            downPoint = p
            lastPoint = p
            moved = false
            if case .box(let id) = controller.hit(at: p), controller.canDrag(id) { dragSystem = id } else { dragSystem = nil }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let controller, let last = lastPoint, let down = downPoint else { return }
            let p = point(event)
            if hypot(p.x - down.x, p.y - down.y) > 3 { moved = true }
            guard moved else { return }
            let delta = CGSize(width: p.x - last.x, height: p.y - last.y)
            if let id = dragSystem { controller.drag(system: id, byScreen: delta) } else { controller.pan(by: delta) }
            lastPoint = p
        }

        override func mouseUp(with event: NSEvent) {
            guard let controller else { return }
            let p = point(event)
            if moved, let id = dragSystem {
                controller.endDrag(id)
            } else if !moved {
                if event.clickCount >= 2 { controller.doubleClick(at: p) } else { controller.click(at: p) }
            }
            downPoint = nil
            lastPoint = nil
            dragSystem = nil
            moved = false
        }

        override func scrollWheel(with event: NSEvent) {
            let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            controller?.zoom(by: exp(event.scrollingDeltaY * step), about: point(event))
        }

        override func magnify(with event: NSEvent) {
            controller?.zoom(by: max(0.1, 1 + event.magnification), about: point(event))
        }

        /// After each frame: re-plan labels for the current camera.
        func frameDidRender() {
            guard let controller else { return }
            labels.show(controller.labels())
        }
    }

    struct FlowMetalView: NSViewRepresentable {
        let renderer: Renderer
        let controller: MapController

        func makeNSView(context: Context) -> FlowMTKView {
            let view = FlowMTKView(frame: .zero, device: renderer.device)
            view.controller = controller
            view.delegate = renderer
            view.colorPixelFormat = Renderer.outputFormat
            view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            view.framebufferOnly = true
            view.preferredFramesPerSecond = 120
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderer.onFrame = { [weak view] in view?.frameDidRender() }
            controller.attach(renderer)
            return view
        }

        func updateNSView(_ view: FlowMTKView, context: Context) {
            view.controller = controller
        }
    }
}
```

Scroll direction: the old 3D view zoomed with `exp(-deltaY·step)` because it moved a camera distance. Here zoom is a magnification, so scrolling up (positive `scrollingDeltaY`) zooms in with `exp(+deltaY·step)`. Check this by hand in Task 19 and flip the sign if it feels inverted. Ledger the result.

- [ ] **Step 6: Run the tests to watch them pass**

Run: `macos/skins-test.sh MapControllerTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/MindControl/Map/MapController.swift macos/Sources/Features/MindControl/Renderer/FlowMTKView.swift \
  macos/Sources/Features/MindControl/Claude/FileOpener.swift macos/Tests/MindControl/MapControllerTests.swift
git commit -m "mindcontrol: map controller for selection, focus, search, drags and transitions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 18: Draft and Refresh with Claude (prompts, launcher, opening a tab)

**Files:**
- Create: `macos/Sources/Features/MindControl/Claude/ClaudePrompts.swift`, `Claude/ClaudeLauncher.swift`
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarModel.swift`, `macos/Sources/Features/Terminal/TerminalController.swift`
- Create: `macos/Tests/MindControl/ClaudeLauncherTests.swift`

**Interfaces:**
- Consumes: `FlowCheck.maxSystems/maxPartsPerSystem/maxFlows` (Task 6)
- Produces:
  - `MindControl.ClaudePrompts.Kind` (`.draft`, `.refresh`)
  - `ClaudePrompts.draft(projectName:) -> String`, `ClaudePrompts.refresh(projectName:) -> String`, `ClaudePrompts.upkeepRule`
  - `MindControl.ClaudeLauncher.isInstalled(command:shell:) -> Bool`
  - `ClaudeLauncher.writePrompt(_:) throws -> URL`
  - `ClaudeLauncher.command(promptFile:) -> String`
  - `ClaudeLauncher.shellQuote(_:) -> String`
  - `ExtensionSidebarModel.openTab: (URL, String) -> Void` (a directory and initial input), set by `TerminalController`

- [ ] **Step 1: Write the failing tests**

`macos/Tests/MindControl/ClaudeLauncherTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias ClaudeLauncher = MindControl.ClaudeLauncher
private typealias ClaudePrompts = MindControl.ClaudePrompts

struct ClaudeLauncherTests {
    @Test func findsCommandsInTheLoginShell() {
        #expect(ClaudeLauncher.isInstalled(command: "ls", shell: "/bin/zsh"))
        #expect(!ClaudeLauncher.isInstalled(command: "mc-definitely-missing-command", shell: "/bin/zsh"))
    }

    @Test func commandQuotesThePromptPath() {
        let command = ClaudeLauncher.command(promptFile: URL(fileURLWithPath: "/tmp/it's here.md"))
        #expect(command == "claude \"$(cat '/tmp/it'\\''s here.md')\"\n")
    }

    @Test func promptIsWrittenToATemporaryFile() throws {
        let url = try ClaudeLauncher.writePrompt("hello")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "hello")
    }

    @Test func draftPromptCarriesTheRules() {
        let prompt = ClaudePrompts.draft(projectName: "arca")
        for needle in ["arca", ".mindcontrol/flow.json", "\"via\"", "\"when\"", "\"control\"", "\"data\"", "20 systems", "8 parts",
                       "60 flows", "CLAUDE.md", ClaudePrompts.upkeepRule, "\"version\": 1"] {
            #expect(prompt.contains(needle), "draft prompt should mention \(needle)")
        }
    }

    @Test func refreshPromptReadsChangesAndLeavesPositionsAlone() {
        let prompt = ClaudePrompts.refresh(projectName: "arca")
        for needle in ["arca", "git log", ".mindcontrol/flow.json", "layout.json", "\"via\""] {
            #expect(prompt.contains(needle), "refresh prompt should mention \(needle)")
        }
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh ClaudeLauncherTests`
Expected: build errors: `ClaudeLauncher` and `ClaudePrompts` are not defined.

- [ ] **Step 3: Write `Claude/ClaudePrompts.swift`**

```swift
import Foundation

extension MindControl {
    /// The instructions Draft and Refresh with Claude hand to `claude`.
    enum ClaudePrompts {
        enum Kind { case draft, refresh }

        static let upkeepRule = "When you change how data or control moves between systems, update `.mindcontrol/flow.json`."

        static func draft(projectName: String) -> String {
            """
            You are drafting a MindControl flow map for the project "\(projectName)" in this folder.

            MindControl draws how a project's systems pass data and control to each other. Write `.mindcontrol/flow.json` \
            describing this project. Read the code and any architecture docs (docs/, README, CLAUDE.md, AGENTS.md) first.

            \(formatAndRules)

            ## Steps

            1. Read the code and the docs.
            2. Write `.mindcontrol/flow.json`.
            3. Add this line to the project's CLAUDE.md (create the file if it's missing), under a "MindControl" heading if there's no better place:
               \(upkeepRule)
            4. Check the file is valid JSON, for example with `python3 -m json.tool .mindcontrol/flow.json`.

            MindControl reloads the map as soon as the file is saved.
            """
        }

        static func refresh(projectName: String) -> String {
            """
            You are refreshing the MindControl flow map for the project "\(projectName)" in this folder.

            1. Read `.mindcontrol/flow.json`.
            2. Read what changed since it was last committed: find the commit with \
            `git log -1 --format=%H -- .mindcontrol/flow.json`, then read `git log -p <that commit>..HEAD -- <the systems' paths>` \
            and the files those commits touched. If the file was never committed, read the whole project.
            3. Update systems, parts, flows, feature routes and every "via" so they match the code. Keep each id that still means \
            the same thing; saved positions and the user's habits depend on them.
            4. Don't touch `.mindcontrol/layout.json`.
            5. Check the file is valid JSON, for example with `python3 -m json.tool .mindcontrol/flow.json`.

            \(formatAndRules)
            """
        }

        static let formatAndRules = """
        ## Format

        ```json
        {
          "version": 1,
          "zones": [ { "id": "phone", "name": "Phone" }, { "id": "cloud", "name": "Cloud services" } ],
          "systems": [
            { "id": "audio", "name": "Audio", "zone": "phone", "summary": "Mic capture, the words-heard check, playback.",
              "paths": ["app/Sources/Audio/**"],
              "parts": [ { "id": "capture", "name": "AudioCapture", "anchor": "AudioCapture" } ] },
            { "id": "openai", "name": "OpenAI Realtime", "zone": "cloud", "external": true }
          ],
          "flows": [
            { "id": "pcm", "from": "audio.capture", "to": "openai", "kind": "data", "carries": "PCM16 24 kHz", "via": "sendAudio" },
            { "id": "commit", "from": "audio.capture", "to": "openai", "kind": "control", "carries": "commit turn",
              "via": "commitTurn", "when": "words heard" }
          ],
          "features": [ { "id": "speech", "name": "A press becomes speech", "route": ["pcm", "commit"] } ]
        }
        ```

        ## Rules

        - "version" is 1.
        - ids use lowercase letters, digits and "-", and are unique within their list. A part is addressed as "system.part".
        - Zones are where systems run: a device, the phone, a server, the cloud. Give every system a zone.
        - A system is one real unit of the codebase with one job. "summary" is one sentence. "paths" are glob patterns \
        relative to the project root ("*" within a folder name, "**" across folders) for the source files it owns. When one \
        folder holds several systems, give each a more specific pattern than the folder's catch-all; two equally specific \
        patterns matching one file is an error.
        - "external": true marks things outside this codebase: services, hardware, the OS. External systems have no paths or parts.
        - "parts" are a system's main pieces, at most 8 parts per system. "anchor" is a type name declared in that system's \
        Swift files, or a file path for other languages.
        - A flow is one arrow. Use "kind": "data" when something is carried (audio, a transcript, JSON, a reply), and \
        "kind": "control" when one side triggers the other (a callback, begin and end, a command) and little or nothing is carried.
        - "carries" is a short phrase for what travels or what is triggered.
        - "via" is the function, method or symbol where the hand-off happens, spelled exactly as in the sending system's \
        code (for a flow from an external system, the receiving system's code). Find it in the code; never guess. MindControl \
        checks it and marks the arrow stale if it isn't there.
        - "when" is a short condition for flows that only happen sometimes. Flows sharing a "when" form one branch.
        - "features" are the main things the product does, each a "route" of flow ids in order.
        - Keep the map small: at most 20 systems, at most 8 parts in a system, at most 60 flows. Merge systems rather than add more.
        - Leave out docs, scripts, tests, tooling and anything that doesn't move data or control.
        """
    }
}
```

`20 systems`, `8 parts` and `60 flows` must match `FlowCheck.maxSystems`, `maxPartsPerSystem` and `maxFlows`. The test asserts the text, so a later change to either side shows up.

- [ ] **Step 4: Write `Claude/ClaudeLauncher.swift`**

```swift
import Foundation

extension MindControl {
    enum ClaudeLauncher {
        /// Whether `command` resolves in the user's login shell. Gives up after 5 seconds. Call off the main thread.
        static func isInstalled(command: String = "claude",
                                shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-lic", "command -v \(shellQuote(command)) >/dev/null 2>&1"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return false }
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline { usleep(50_000) }
            if process.isRunning {
                process.terminate()
                return false
            }
            return process.terminationStatus == 0
        }

        static func writePrompt(_ text: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindcontrol-prompt-\(UUID().uuidString).md")
            try Data(text.utf8).write(to: url)
            return url
        }

        /// What to type into the new tab's shell.
        static func command(promptFile: URL) -> String {
            "claude \"$(cat \(shellQuote(promptFile.path)))\"\n"
        }

        static func shellQuote(_ text: String) -> String {
            "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
    }
}
```

- [ ] **Step 5: Let the sidebar open a tab**

In `ExtensionSidebarModel`, next to `focusTerminal`:

```swift
    /// Opens a new tab in `directory` and types `input` into its shell. Set by the window's controller.
    var openTab: (_ directory: URL, _ input: String) -> Void = { _, _ in }
```

In `TerminalController.windowDidLoad`, inside the `if let sidebar` block after `sidebar.focusTerminal`:

```swift
            sidebar.openTab = { [weak self] directory, input in
                guard let self, let window = self.window else { return }
                var config = Ghostty.SurfaceConfiguration()
                config.workingDirectory = directory.path
                config.initialInput = input
                _ = TerminalController.newTab(self.ghostty, from: window, withBaseConfig: config)
            }
```

Check that `self.ghostty` is the `Ghostty.App` property that `newWindow(_:)` uses at ~line 1236 (`ghostty.newWindow(surface:)`). If the property has another name, use that.

- [ ] **Step 6: Run the tests to watch them pass**

Run: `macos/skins-test.sh ClaudeLauncherTests`
Expected: `** TEST SUCCEEDED **`.

Then build the app (Global Constraints build command).
Expected: `** BUILD SUCCEEDED **`, which shows the `TerminalController` wiring compiles.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/Features/MindControl/Claude/ClaudePrompts.swift macos/Sources/Features/MindControl/Claude/ClaudeLauncher.swift \
  macos/Sources/Features/Extensions/ExtensionSidebarModel.swift macos/Sources/Features/Terminal/TerminalController.swift \
  macos/Tests/MindControl/ClaudeLauncherTests.swift
git commit -m "mindcontrol: Draft and Refresh with Claude prompts, launched in a new tab

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 19: The panel — header, feature bar, search, side panel, empty and error states

**Files:**
- Rewrite: `macos/Sources/Features/MindControl/MindControlPanel.swift`
- Create: `macos/Sources/Features/MindControl/Map/MapChrome.swift`, `Map/SidePanel.swift`
- Modify: `macos/Sources/Features/Extensions/ExtensionSidebarView.swift` (pass `openTab`)
- Create: `macos/Tests/MindControl/PanelTextTests.swift`

**Interfaces:**
- Consumes:
  - `Model` (Task 16)
  - `MapController`, `FlowMetalView`, `SidePanelContent`, `FlowRow` (Task 17)
  - `ClaudePrompts`, `ClaudeLauncher` (Task 18)
  - `Palette` (Task 14)
  - `HealthReport` (Task 6)
  - `StepGroup` (Task 8)
- Produces:
  - `MindControl.Panel(model:onClose:openTab:)`
  - `Panel.ageText(_:) -> String?`, `Panel.healthText(_:) -> String`, `Panel.centerMessage(for:) -> String?`, `Panel.emptyTitle(_:) -> String`

- [ ] **Step 1: Write the failing text tests**

`macos/Tests/MindControl/PanelTextTests.swift`:

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias Panel = MindControl.Panel

struct PanelTextTests {
    @Test func ageCopy() {
        #expect(Panel.ageText(.hidden) == nil)
        #expect(Panel.ageText(.notCommitted) == "Map not committed yet")
        #expect(Panel.ageText(.commits(0)) == "Map up to date")
        #expect(Panel.ageText(.commits(1)) == "Map updated 1 commit ago")
        #expect(Panel.ageText(.commits(23)) == "Map updated 23 commits ago")
    }

    @Test func healthCopy() {
        var report = MindControl.HealthReport()
        #expect(Panel.healthText(report) == "Map healthy")
        report.unmapped = ["a.swift"]
        #expect(Panel.healthText(report) == "1 issue")
        report.issues = [.init(kind: .staleVia, subject: "f", message: "m")]
        #expect(Panel.healthText(report) == "2 issues")
    }

    @MainActor
    @Test func stateCopy() {
        let project = MindControl.Model.Project(root: URL(fileURLWithPath: "/tmp/arca"), name: "arca", claudeBlockReason: nil)
        #expect(Panel.centerMessage(for: .noProject) == "This terminal hasn't reported a working directory.")
        #expect(Panel.centerMessage(for: .loading(project)) == "Reading the flow map…")
        #expect(Panel.centerMessage(for: .failed("Can't read /x.")) == "Can't read /x.")
        #expect(Panel.centerMessage(for: .noFlowFile(project)) == nil)
        #expect(Panel.emptyTitle(project) == "No flow map for arca yet")
    }
}
#endif
```

- [ ] **Step 2: Run them to watch them fail**

Run: `macos/skins-test.sh PanelTextTests`
Expected: build errors: `ageText`, `healthText` and `emptyTitle` are not defined, and `Panel` has no `openTab`.

- [ ] **Step 3: Write `Map/MapChrome.swift`**

```swift
import AppKit
import SwiftUI

extension MindControl {
    /// Top bar: where you are, Change…, Map/Health, the control toggle, map health and age, Refresh.
    struct MapHeader: View {
        @ObservedObject var model: Model
        @ObservedObject var controller: MapController
        let onChange: () -> Void
        let onRefresh: () -> Void

        var body: some View {
            HStack(spacing: 10) {
                breadcrumb
                Button("Change…", action: onChange).buttonStyle(.borderless).foregroundColor(.secondary)
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
                    Button(Panel.healthText(loaded.report)) { controller.mode = .health }
                        .buttonStyle(.borderless)
                        .foregroundColor(loaded.report.isHealthy ? Color(red: 0.45, green: 0.85, blue: 0.6) : Color(red: 1, green: 0.7, blue: 0.3))
                    if let age = Panel.ageText(loaded.report.age) {
                        Text(age).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Button("Refresh with Claude", action: onRefresh)
                        .disabled(project.claudeBlockReason != nil)
                        .help(project.claudeBlockReason ?? "Update the map from what changed in the code")
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.35))
        }

        private var breadcrumb: some View {
            HStack(spacing: 4) {
                if let project = model.project {
                    Text(project.root.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(project.root.path)
                    ForEach(Array(controller.breadcrumb.dropFirst().enumerated()), id: \.offset) { _, name in
                        Text("›").foregroundColor(.secondary)
                        Button(name) { _ = controller.escape() }.buttonStyle(.borderless)
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
                                Circle().fill(Color(red: Double(color.x), green: Double(color.y), blue: Double(color.z))).frame(width: 8, height: 8)
                                Text(feature.name).font(.system(size: 12, weight: selected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }

    /// ⌘F or typing: a field plus grouped results; Enter goes to the first result.
    struct SearchBox: View {
        @ObservedObject var controller: MapController
        @FocusState private var focused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search features, systems, files…", text: $controller.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { if let first = controller.results.first { controller.navigate(to: first) } }
                    .onExitCommand { controller.query = ""; focused = false }
                if !controller.results.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(controller.results.enumerated()), id: \.offset) { index, result in
                                if index == 0 || controller.results[index - 1].kind != result.kind {
                                    Text(Self.heading(result.kind)).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                                        .padding(.top, 6)
                                }
                                Button { controller.navigate(to: result) } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.title).font(.system(size: 12))
                                        Text(result.detail).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 320)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.75)))
                }
            }
            .frame(width: 320)
            .onChange(of: controller.searchRequest) { _ in focused = true }
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
}
```

- [ ] **Step 4: Write `Map/SidePanel.swift`**

```swift
import SwiftUI

extension MindControl {
    /// Right-hand panel: a feature's steps, a system's or part's flows and files, an arrow's hand-offs, or the health list.
    struct SidePanel: View {
        @ObservedObject var controller: MapController

        var body: some View {
            let content = controller.sidePanel
            if content != .none {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) { sections(content) }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 320)
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
                    if let when = group.when { Text("If \(when)").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary) }
                    ForEach(group.steps, id: \.flowID) { step in
                        Button { controller.goToStep(step.flowID) } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(step.number).").foregroundColor(.secondary).frame(width: 22, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(step.from) → \(step.to)")
                                    Text(step.kind == .control ? "control · \(step.carries)" : step.carries)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                status(step.status)
                            }
                        }
                        .buttonStyle(.plain)
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
                    Text("Files").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    ForEach(files, id: \.self) { file in
                        Button(file) { controller.openSource(file) }.buttonStyle(.plain).font(.system(size: 11, design: .monospaced))
                    }
                }
            case .part(let name, let system, let file, let stale, let incoming, let outgoing):
                Text(name).font(.system(size: 15, weight: .semibold))
                Text(system).foregroundColor(.secondary)
                if stale { Text("Stale: its anchor wasn't found in the code.").foregroundColor(.orange) }
                if let file { Button(file) { controller.openSource(file) }.buttonStyle(.plain).font(.system(size: 11, design: .monospaced)) }
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
                        Text(issue.message).foregroundColor(issue.kind == .density ? .yellow : .orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                if !report.unmapped.isEmpty {
                    Text("\(report.unmapped.count) files belong to no system").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    ForEach(report.unmapped, id: \.self) { file in
                        Button(file) { controller.openSource(file) }.buttonStyle(.plain).font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }

        @ViewBuilder
        private func flowList(_ title: String, _ rows: [FlowRow]) -> some View {
            if !rows.isEmpty {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text("\(row.from) → \(row.to)")
                            Spacer()
                            status(row.status)
                        }
                        Text(row.kind == .control ? "control · \(row.carries)" : row.carries).foregroundColor(.secondary)
                        if let location = row.location, let via = row.via {
                            Button("\(via) · \(location.file):\(location.line)") { controller.open(location) }
                                .buttonStyle(.plain).font(.system(size: 10, design: .monospaced)).foregroundColor(.accentColor)
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
```

- [ ] **Step 5: Rewrite `MindControlPanel.swift`**

```swift
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

        struct PromptToCopy: Identifiable {
            let id = UUID()
            let text: String
        }

        /// Matches the composite pass's outer background so the panel never flashes a different colour.
        static let background = Color(red: 0.012, green: 0.016, blue: 0.043)

        var body: some View {
            ZStack(alignment: .topLeading) {
                Self.background
                if isReady, let renderer {
                    FlowMetalView(renderer: renderer, controller: controller)
                }
                VStack(spacing: 0) {
                    MapHeader(model: model, controller: controller, onChange: chooseFolder, onRefresh: { launch(.refresh) })
                    if isReady {
                        HStack(alignment: .top) {
                            FeatureBar(controller: controller)
                            SearchBox(controller: controller).padding(.trailing, 14).padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if isReady {
                    SidePanel(controller: controller)
                        .padding(.top, 92)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                if let message = rendererError ?? Self.centerMessage(for: model.state) {
                    Text(message).font(.system(size: 13)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if case .noFlowFile(let project) = model.state { emptyState(project) }
                if case .invalid(_, let errors) = model.state { errorList(errors) }
                if !isReady {
                    // Esc closes MindControl when there's no map view to catch it.
                    Button("") { onClose() }.keyboardShortcut(.cancelAction).opacity(0)
                } else {
                    Button("") { controller.beginSearch(with: "") }.keyboardShortcut("f", modifiers: .command).opacity(0)
                }
            }
            .onAppear {
                controller.onClose = onClose
                startRenderer()
                apply()
            }
            .onChange(of: model.state) { _ in apply() }
            .sheet(item: $promptToCopy) { prompt in copySheet(prompt.text) }
        }

        private var isReady: Bool {
            if case .ready = model.state { return true }
            return false
        }

        private func apply() {
            if case .ready(let project, let loaded) = model.state { controller.show(loaded, root: project.root) }
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
            panel.directoryURL = model.project?.root
            if panel.runModal() == .OK, let url = panel.url { model.choose(root: url) }
        }

        private func launch(_ kind: ClaudePrompts.Kind) {
            guard let project = model.project, project.claudeBlockReason == nil else { return }
            let prompt = kind == .draft ? ClaudePrompts.draft(projectName: project.name) : ClaudePrompts.refresh(projectName: project.name)
            Task {
                let installed = await Task.detached { ClaudeLauncher.isInstalled() }.value
                if installed, let file = try? ClaudeLauncher.writePrompt(prompt) {
                    openTab(project.root, ClaudeLauncher.command(promptFile: file))
                } else {
                    promptToCopy = PromptToCopy(text: prompt)
                }
            }
        }

        private func emptyState(_ project: Model.Project) -> some View {
            VStack(spacing: 12) {
                Text(Self.emptyTitle(project)).font(.system(size: 17, weight: .semibold))
                Text("A flow map shows how this project's systems pass data and control. Claude can draft one from the code.")
                    .foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                Button("Draft with Claude") { launch(.draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(project.claudeBlockReason != nil)
                if let reason = project.claudeBlockReason {
                    Text(reason).font(.system(size: 11)).foregroundColor(.orange)
                    Button("Change…", action: chooseFolder)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private func errorList(_ errors: [FlowError]) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("The flow map has problems").font(.system(size: 15, weight: .semibold))
                Text(FlowFile.relativePath).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                    Text(error.description).font(.system(size: 12, design: .monospaced)).foregroundColor(.orange)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private func copySheet(_ text: String) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Claude Code isn't installed").font(.system(size: 15, weight: .semibold))
                Text("Install it, or paste this prompt into any Claude session in this folder.").foregroundColor(.secondary)
                ScrollView { Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }.frame(height: 260)
                HStack {
                    Spacer()
                    Button("Copy Prompt") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    Button("Done") { promptToCopy = nil }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 560)
        }

        // MARK: Copy

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

        static func centerMessage(for state: Model.State) -> String? {
            switch state {
            case .idle, .ready, .noFlowFile, .invalid: nil
            case .noProject: "This terminal hasn't reported a working directory."
            case .loading: "Reading the flow map…"
            case .failed(let message): message
            }
        }

        static func emptyTitle(_ project: Model.Project) -> String {
            "No flow map for \(project.name) yet"
        }
    }
}
```

- [ ] **Step 6: Pass `openTab` from the sidebar**

In `ExtensionSidebarView.swift` (~line 216), change the panel's construction to:

```swift
            MindControl.Panel(model: model.mindControl, onClose: {
                // Esc; guarded so a key-repeated Esc can't reopen it.
                if model.active == .codebaseVisualizer { model.select(.codebaseVisualizer) }
            }, openTab: model.openTab)
```

- [ ] **Step 7: Run the text tests, the full suite, and build**

Run: `macos/skins-test.sh PanelTextTests`
Expected: `** TEST SUCCEEDED **`.

Run the full suite (Global Constraints).
Expected: `** TEST SUCCEEDED **`.

Build the app.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Look at it**

Copy the Arca example into a scratch git project, then open the visualizer there:

```bash
mkdir -p /tmp/mc-demo/.mindcontrol && cd /tmp/mc-demo && git init -q
```

Write `FlowFixtures.arcaJSON` (from `macos/Tests/MindControl/FlowTestSupport.swift`) to `/tmp/mc-demo/.mindcontrol/flow.json`, and the five `arcaSources` files to their paths under `/tmp/mc-demo`. Then:

```bash
pkill -f "worktrees/mindcontrol/macos/build/Debug/Ghostty.app/Contents/MacOS"; open -n macos/build/Debug/Ghostty.app
```

In the debug window: `cd /tmp/mc-demo`, then open the codebase visualizer. Check each of these, and fix whatever fails before committing:

1. Three zone regions, Ring | Phone | Cloud services, left to right, with pulses running along solid arrows.
2. Scrolling up zooms in about the cursor. If it zooms out, flip the sign in `FlowMTKView.scrollWheel` and ledger it.
3. Zooming out fades to zone names and thick arrows between zones. Zooming in shows parts and arrow labels.
4. Clicking "A press becomes speech" lights the route, dims the rest, and lists 9 steps in 4 groups with "If words heard" / "If nothing heard".
5. Pressing F with the feature selected slides into feature focus. Esc slides back.
6. Typing `speech` shows search results. Enter on SpeechGate pans to it and pulses it.
7. Dragging the Audio box moves it, and `/tmp/mc-demo/.mindcontrol/layout.json` appears.
8. Health shows "Map healthy", or lists what's wrong.
9. Editing `flow.json` (rename a system) reloads the map within a second.
10. The visualizer opened from `~` shows "No flow map for <you> yet" with Draft disabled and the home-folder reason.

- [ ] **Step 9: Commit**

```bash
git add macos/Sources/Features/MindControl/MindControlPanel.swift macos/Sources/Features/MindControl/Map/MapChrome.swift \
  macos/Sources/Features/MindControl/Map/SidePanel.swift macos/Sources/Features/Extensions/ExtensionSidebarView.swift \
  macos/Tests/MindControl/PanelTextTests.swift
git commit -m "mindcontrol: flow map panel with header, features, search, side panel and empty states

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 20: Docs, full verification, and the Arca acceptance check

**Files:**
- Rewrite: `MINDCONTROL.md`

**Interfaces:**
- Consumes: everything above
- Produces: an updated `MINDCONTROL.md`; the ledger's acceptance lines

- [ ] **Step 1: Rewrite `MINDCONTROL.md`**

Replace its contents with a short guide in this order:

1. What MindControl is (one paragraph, from the spec's Goal).
2. Opening it, and Change….
3. The flow file: path, the trimmed example from the spec, and the rules list.
4. Views and controls: Map / Health, the zoom levels, feature chips, Focus (F / Esc), search (⌘F or typing), dragging, double-click.
5. Draft and Refresh with Claude, including when they're disabled.
6. Where the code lives: the File Map's directories, one line each.
7. Running the tests: `macos/skins-test.sh <Suite>`.

Keep it under about 150 lines. Remove every mention of the 3D map, dust, cone tree and imports.

- [ ] **Step 2: Full suite and build**

Run the full suite, then the build (Global Constraints).
Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`. Record the pass count from `grep -c "Test case '.*' passed" macos/build/last-test.log` in the ledger.

- [ ] **Step 3: Commit the docs**

```bash
git add MINDCONTROL.md
git commit -m "mindcontrol: document the flow map

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Acceptance on Arca (with the user)**

This needs the user, and it writes into the Arca repo, so ask before starting:

> "Ready for the Arca check: I'll open the debug build in `~/projectrepos/arca` and press Draft with Claude. That runs Claude in a new tab, which writes `.mindcontrol/flow.json` and adds one line to Arca's CLAUDE.md. Nothing gets committed. OK to go?"

After a yes:

1. Relaunch the debug app. In its window, `cd ~/projectrepos/arca` and open the visualizer.
2. Confirm the header shows `/Users/…/projectrepos/arca`. This also re-checks Task 1's wrong-folder bug.
3. Press Draft with Claude, and let the new tab's Claude session finish.
4. Back in the first tab, the map loads by itself. Select "a press becomes speech" (or the closest feature Claude named) and compare its steps with the sequence diagram in `~/projectrepos/arca/docs/architecture/01-utterance.md`: Ring → ArcaLink → TapCoordinator → AudioCapture → SpeechGate / AudioPipeline → RealtimeAgentSession → Model, with the words-heard / nothing-heard branch.
5. Search `CostMeter` and confirm it lands on its system, or shows "no system" and opens Health.
6. Ledger: `Acceptance: speech route <matches | differs: …>; CostMeter → <system>; folder shown: <path>`.

Leave `arca/.mindcontrol/` and the CLAUDE.md line uncommitted. Whether to commit them is the user's call.

- [ ] **Step 5: Hand off**

Continue with the executing skill's final review and `superpowers:finishing-a-development-branch`. Never push, open a PR or install without being asked.
