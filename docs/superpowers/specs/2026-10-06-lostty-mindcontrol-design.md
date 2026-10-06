# Lostty MindControl Panel — Design

Date: 2026-10-06
Status: Implemented
Branch: `mindcontrol` (worktree `.claude/worktrees/mindcontrol`, based on `skins` @ 7121f2c)

> **Update (2026-10-06):** the edge tab and drawer (§5) were replaced by the extensions
> sidebar from `skins`. The visualizer icon opens `MindControl.Panel` over the terminal area
> beside the sidebar; `ExtensionSidebarModel` (one per window) owns the `MindControl.Model`,
> loads it when the visualizer opens, and returns focus to the terminal when it closes.
> Esc calls `select(.codebaseVisualizer)`. `MindControlDrawer.swift` is gone.

## 1. Goal

Add MindControl to Lostty: a 3D "neural / synaptic" map of the project the focused
terminal is in. It lives behind a small tab on the right edge of the terminal
window; clicking the tab slides a drawer in from the right until it covers the
whole terminal area. Clicking the tab again (or Esc) slides it away.

This is an experiment in placement: drawer mechanics are isolated in one
container view so a bottom drawer or overlay can be tried later without
touching the renderer or data code.

The renderer architecture is the one designed and partly built in the
standalone MindControl repo (`~/projectrepos/MindControl`,
`docs/superpowers/specs/2026-10-05-metal-synaptic-renderer-design.md`). That
code is ported, not redesigned.

## 2. Success criteria

- A slim tab is visible on the right edge of every terminal window; it never
  steals keyboard focus from the terminal.
- Clicking the tab animates the drawer open to full terminal size; clicking the
  tab or pressing Esc closes it and returns focus to the last focused terminal.
- The map shows the git project of the focused terminal's working directory
  (or the directory itself outside git): root → folders → files, `.gitignore`
  respected.
- Visuals match the MindControl renderer: breathing neuron nodes, travelling
  signals, HDR bloom, depth fog, filmic tonemap.
- Lostty's own repo and Arca (~900 files) open in under 1 s on Apple Silicon and
  animate at display refresh rate.
- Zero GPU work while the drawer is closed.
- No change to terminal behaviour when the drawer is never opened.

## 3. Out of scope (later iterations)

Cross-file relationships (imports, Markdown links), node labels, hover and
selection, file watching / live updates, a keybinding or menu item, Linux/GTK.

## 4. Architecture

```
macos/Sources/Features/MindControl/
  MindControl.swift            Namespace: enum MindControl {}
  MindControlDrawer.swift      Tab + sliding drawer; open/closed state; focus hand-off
  MindControlPanel.swift       Panel content: renderer view + status label + empty/error states
  MindControlModel.swift       @MainActor ObservableObject: current root, scan state, cache
  Data/
    Graph.swift                Graph, GraphNode, GraphEdge, NodeKind (ported)
    Graph+Stress.swift         SplitMix64, stress generator (ported, used by tests)
    ProjectScanner.swift       Root resolution + file listing → FileTree
    TreeLayout.swift           FileTree → Graph with 3D positions
  Renderer/
    ShaderTypes.h              MC-prefixed shared structs (ported)
    GraphBuffers.swift         (ported)
    MatrixMath.swift           (ported)
    OrbitCamera.swift          (ported)
    Pipelines.swift            (ported)
    BloomPass.swift            (ported)
    Renderer.swift             (ported)
    MetalGraphView.swift       (ported) + pause control + Esc handling
    Shaders/
      ShaderCommon.h, Dust.metal, Edges.metal, Signals.metal,
      Nodes.metal, Bloom.metal, Composite.metal   (ported)
macos/Tests/MindControl/
  GraphBuffersTests, OrbitCameraTests, StressGraphTests, RendererTests,
  BloomPassTests (ported); ProjectScannerTests, TreeLayoutTests, ModelTests,
  DensityTests (new)
```

`macos/Sources` and `macos/Tests` are synchronized folders in
`Ghostty.xcodeproj`, so new files join the `Ghostty` and `GhosttyTests` targets
without project-file edits. The Xcode build compiles `.metal` files in the app
target into `default.metallib` (the app currently has none; Ghostty's terminal
renderer builds its shaders in Zig, separately).

### 4.1 Naming

The app module is large, so everything is namespaced:

- Swift types are nested in `enum MindControl { }` (matching `Ghostty.Surface`
  style): `MindControl.Graph`, `MindControl.Renderer`, `MindControl.OrbitCamera`, …
- C structs and macros in `ShaderTypes.h` are prefixed: `MCNodeInstance`,
  `MCEdgeInstance`, `MCFrameUniforms`, `MCBloomUniforms`, `MCCompositeUniforms`,
  `MC_BUFFER_INSTANCES/NODES/FRAME`.
- Metal entry points are prefixed `mc` (`mcNodeVertex`, `mcCompositeFragment`, …).
- `ShaderTypes.h` is imported from `Sources/App/macOS/ghostty-bridging-header.h`.

### 4.2 Integration point

`TerminalView`'s `.ready` branch already stacks views in a `ZStack` (splits, then
`UpdateOverlay`). `MindControlDrawer` is added as the last layer of that
`ZStack`, receiving the focused surface's `pwdURL` and a closure that restores
focus to `lastFocusedSurface`. This is the only edit to existing Lostty code
besides the bridging-header import.

## 5. Drawer behaviour

| State | Visual | Input |
|---|---|---|
| Closed | Tab: 22 × 64 pt, left corners rounded 8 pt, dark translucent material, a small glowing node glyph; vertically centred on the right edge. Tooltip "MindControl". | Only the tab is hit-testable; everything else passes through to the terminal. |
| Opening / closing | Drawer slides in from the right edge (spring, ~0.35 s). The tab rides on the drawer's leading edge. | Tab clickable throughout. |
| Open | Panel fills the terminal area (the full `ZStack`), opaque. Tab sits on its leading edge with the glyph flipped to "close". | Panel takes mouse/scroll/pinch; the Metal view becomes first responder so Esc closes. |

On close the panel and its Metal view are removed (no GPU work); the per-window
model keeps the scan cache. Focus returns to the last focused terminal surface.

The open/closed state is per window and not persisted.

## 6. Data

### 6.1 ProjectScanner

Input: the focused surface's `pwdURL`. Output: a `FileTree` (root name, root
path, nested folders and files, `totalFileCount`, `truncated` flag).

1. Root = `ProjectResolver.gitRoot(of: pwd)` (existing Skins helper), else `pwd`.
2. In a git repo: `git -C <root> ls-files -z --cached --others --exclude-standard`
   (tracked plus untracked-but-not-ignored). Outside git: `FileManager`
   enumeration that skips hidden entries and `node_modules`, `.build`,
   `zig-out`, `zig-cache`, `.zig-cache`, `DerivedData`, `build`, `dist`,
   `vendor`, `Pods`, `target`, with max depth 12.
3. Cap: 10,000 files. When over the cap, keep files in order of
   (depth, path) so top-level structure survives, set `truncated`, and keep
   `totalFileCount` for the status label.
4. Runs in a detached task off the main actor; the result is published on the
   main actor. A newer scan request cancels an in-flight one.

No pwd → state `.noProject`. Git or file system failure → state
`.failed(message)`. Zero files → `.empty`.

### 6.2 TreeLayout

`FileTree` → `MindControl.Graph` with deterministic positions:

- Root at the origin.
- Children of any folder are sorted by name. Each folder's subtree size
  (file count) drives spacing.
- Top-level entries sit on a sphere of radius `R0 = 4 + 0.35·√N` (N = total
  nodes), distributed with a Fibonacci spiral, largest subtrees first so big
  folders spread out.
- Deeper entries are placed on a hemisphere facing away from their parent's
  parent (so branches grow outward, not back through the root), radius
  `r = 1.0 + 0.45·√(subtree size)`. Subfolders sit at `1.6·r`, files at `r`.
- Kinds: root → `.root`; directories → `.folder`; files with extensions
  `md, markdown, txt, rst, adoc, org, pdf` → `.document`; everything else →
  `.source`.
- Edges: parent → child for every node.

### 6.3 MindControlModel

`@MainActor` `ObservableObject`, one per window. Holds `state`
(`.idle | .scanning | .ready(Graph, FileTree) | .noProject | .empty | .failed(String)`)
and a cache keyed by root path. Scans when the drawer opens (focus cannot
move to another split while the panel covers the terminal); pwd is read from the
last focused surface at open time. Cached roots render
immediately; the cache is cleared when the window closes.

## 7. Rendering

Ported unchanged from MindControl except for naming (§4.1) and:

- `Renderer.setGraph` is called whenever the model publishes a new graph; the
  camera re-frames to the new graph.
- `MetalGraphView` gains `isPaused` (bound to the drawer state) and an
  `onEscape` closure.
- Status label (top-left over the panel, small monospaced, secondary colour):
  `<root name> · 1,284 files`, or `… · showing 10,000 of 23,412 files` when
  truncated. Empty/error/no-project states show a centred one-line message over
  the background instead of a graph.

### 7.1 Density (added during tuning)

Real repos are lopsided (Lostty: 4,016 of 5,619 files under `test/`), and additive
glow saturates where hundreds of nodes overlap in projection. Two controls:

- **Per-file weight** (`GraphNode.weight` → `MCNodeInstance.intensity`): files in
  a folder with n files get `min(1, max(0.12, (30/n)^0.75))`; folders stay at 1 as
  landmarks. Nodes, edges and signals scale by it.
- **Global glow scale** (`MCFrameUniforms.glowScale`): 1 up to 400 nodes, then
  `√(400/n)`, floor 0.2. Halos, rings and edges scale fully; cores and signals
  partially; bloom strength scales with it.
- Layout: files sit in a thick shell (`0.6–1.0 × r`), `r = 1 + 0.6·√size`;
  subfolders at `2.0 × r`. Bloom threshold 1.0.

`DensityTests` pins this: a Lostty-shaped tree must render with < 3% blown-out pixels.

## 8. Error handling

- Metal unavailable or a pipeline failure: panel shows
  "MindControl needs Metal, which is unavailable on this Mac." / the pipeline
  error text. The tab still works; the terminal is unaffected.
- `git` missing or failing inside a repo: fall back to the non-git file
  enumeration rather than failing.
- Unreadable directories in the fallback are skipped silently.
- Scans never block the main thread; a cancelled scan publishes nothing.

## 9. Testing

Run with `macos/skins-test.sh <SuiteName>` (needs `zig build -Demit-macos-app=false`
once to build the xcframework). Lint with `swiftlint lint --strict --fix`.

- **Ported suites:** GraphBuffersTests, OrbitCameraTests, StressGraphTests,
  RendererTests (offscreen render: empty graph, sample graph, 1×1 target, single
  node, bloom and signals add light), BloomPassTests.
- **ProjectScannerTests** (temporary directories):
  git repo with tracked, untracked and ignored files → ignored excluded,
  untracked included; non-git directory → skip list honoured; cap → truncated,
  breadth-first survival, correct total; pwd inside a subfolder resolves to the
  git root; missing directory → `.failed`.
- **TreeLayoutTests:** deterministic for the same tree; all positions finite;
  no two nodes coincide; kinds by extension; one edge per non-root node;
  10k-file tree lays out in under 200 ms.
- **Manual:** open the drawer in Lostty on the Lostty repo and on Arca; switch
  focus between splits in different projects while open; close with Esc and
  the tab; confirm terminal typing is unaffected with the drawer closed.

## 10. Build order

1. Port renderer + data model + their tests under the new names; all green.
2. ProjectScanner + tests.
3. TreeLayout + tests.
4. MindControlModel, MindControlPanel, MindControlDrawer; wire into
   `TerminalView`; manual check in the running app.
5. Tuning pass on real projects; docs.
