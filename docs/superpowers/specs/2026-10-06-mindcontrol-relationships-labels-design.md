# MindControl: Relationships, Layout, Labels — Design

Date: 2026-10-06
Status: Implemented
Branch: `mindcontrol` (Lostty worktree `.claude/worktrees/mindcontrol`)
Builds on: `2026-10-06-lostty-mindcontrol-design.md` (renderer, scanner, sidebar integration)

## 1. Goal

MindControl exists to help the user understand a project's structure and how it
ties together. After the first version, three problems block that:

1. Nodes are unlabeled.
2. Lines have no stated meaning (today every line is folder→child "contains").
3. Clusters crowd each other, so relationships are hard to discern even zoomed in.

This round adds real file-to-file relationships, a layout that gives clusters
room, and labels with hover/click inspection.

## 2. Success criteria

- Two visually distinct line types — **contains** (folder→child) and **uses**
  (file→file dependency) — explained by an on-screen legend.
- Uses-edges exist for Zig, TypeScript/JavaScript, Python, Swift, and Markdown
  links; signals travel only along uses-edges, from user toward definition.
- Sibling folder clusters never overlap; clusters are visibly separated at the
  default framing for Arca (~900 files) and Lostty (~5,600 files).
- Folder names always visible; file names appear when zoomed close; never more
  than 150 labels on screen; labels never overlap each other.
- Hover highlights a node and its direct connections and shows its path; click
  pins the highlight and shows an info card (path, kind, uses / used-by counts).
- First open of Arca completes in < 1.5 s on Apple Silicon (scan + dependencies +
  layout); frame rate stays at display refresh with labels on.

## 3. Out of scope

Search, filtering by type, live file watching, labels for every node, languages
beyond those listed, cross-module Swift resolution beyond the type-name heuristic.

## 4. Architecture changes

```
Features/MindControl/
  Data/
    Graph.swift              + EdgeKind (.contains, .uses) on GraphEdge
    DependencyScanner.swift  NEW: FileTree + root → [Dependency]
    Parsers/                 NEW: one file per language (Zig, Script, Python, Swift, Markdown)
    TreeLayout.swift         REPLACED by ConeTreeLayout.swift
    ConeTreeLayout.swift     NEW: structured placement
    Relaxation.swift         NEW: bounded force pass
  Renderer/
    ShaderTypes.h            + MCEdgeInstance.kind, MCNodeInstance.highlight
    Renderer.swift           + highlight buffer, per-frame camera snapshot for overlays
    Picking.swift            NEW: nearest node under a point (CPU projection)
    Shaders/Edges.metal      contains vs uses styling; uses drawn as curved strips
    Shaders/Signals.metal    signals on uses-edges only, following the curve
    Shaders/Nodes.metal      highlight / dim
  Labels/
    LabelPlanner.swift       NEW: which labels show where (pure, testable)
    LabelOverlayView.swift   NEW: CATextLayer pool over the Metal view
  MindControlModel.swift     pipeline: scan → dependencies → layout → graph
  MindControlPanel.swift     + legend, info card, hover/pin state
```

### 4.1 Pipeline

`Model.load` (unchanged trigger: visualizer opens) runs, off the main actor:
`ProjectScanner.scan` → `DependencyScanner.scan(tree, root)` →
`ConeTreeLayout.graph(tree, dependencies)` → `Relaxation.relax(graph)`.
Cancellation (`shouldStop`) is polled in the dependency scan and relaxation loops.
Results are cached per root as today.

## 5. Relationships

`Dependency { from: String; to: String }` — relative paths, `from` uses `to`.

| Language | Files | Rule |
|---|---|---|
| Zig | `.zig` | `@import("…")` where the argument ends in `.zig`; resolved relative to the importing file's directory. Package imports (`std`, …) ignored. |
| TS/JS | `.ts .tsx .js .jsx .mjs .cjs` | `import … from '…'`, `import '…'`, `export … from '…'`, `require('…')`, dynamic `import('…')` with a relative specifier (`./`, `../`). Resolve by trying the exact path, then `+ .ts .tsx .js .jsx .mjs .cjs`, then `/index` + those. |
| Python | `.py` | `import a.b.c` → `a/b/c.py` or `a/b/c/__init__.py` from the project root; `from x.y import z` likewise (also tries `x/y/z.py`); relative `from .m import n` / `from ..m import n` resolved from the importing file's package. |
| Swift | `.swift` | Pass 1: collect top-level declared type names per file (`class|struct|enum|protocol|actor|typealias Name`, ignoring `private`/`fileprivate` ones). Pass 2: tokenize each file's identifiers (skipping comments and string literals); for every token that names a type declared in *another* file, add `self → declaringFile`. Names declared in more than 3 files are ambiguous and skipped. |
| Markdown | `.md .markdown` | `[text](target)` and `![alt](target)` where target is relative and (after stripping `#anchor`) resolves to a file in the tree. |

Limits: files > 512 KB are skipped; at most 40 uses-edges per source file (first
40 in path order of targets) and 30,000 in total; duplicates and self-edges are
dropped. Unresolvable targets are ignored silently.

## 6. Layout

### 6.1 ConeTreeLayout (structured)

- Weight `w(v)` = 1 + number of files beneath `v`.
- Root at the origin. Each folder owns a **cone**: an axis direction and a
  half-angle. The root's cone is the full sphere.
- A folder's subfolders get child cones packed inside its cone: axes spread
  over the folder's spherical cap with a Fibonacci spiral ordered by weight
  (heaviest at the centre), child half-angle
  `θc = θparent · √(w(c) / Σw(siblings)) · 0.85`, so cone area tracks weight and
  siblings don't overlap.
- A subfolder sits along its axis at distance `d = 3 + 1.2·√w(c)` from its parent.
- A folder's own files form a compact ball around the folder: Fibonacci sphere
  of radius `rf = 0.8 + 0.35·√(files in folder)`, files distributed through the
  ball's volume (thick shell 0.55–1.0 · rf).
- Deterministic: children sorted by name before weight ordering; no randomness.

### 6.2 Relaxation (bounded force pass)

- 60 iterations, step size decaying from 0.5 to 0.05.
- Repulsion between nodes closer than `minSpacing = 0.45`, found through a
  uniform spatial hash grid (cell = minSpacing) so each iteration is ~O(n).
- Springs on uses-edges pulling endpoints toward rest length 2.5, strength
  0.02 (gentle; never collapses folder structure).
- Folders move at 20% of the step (anchors); the root never moves.
- Deterministic iteration order.

### 6.3 Node weight for brightness

Unchanged from the first round: crowded files dim
(`min(1, max(0.12, (30/n)^0.75))`); global `glowScale` unchanged.

## 7. Rendering

### 7.1 Edges

`MCEdgeInstance` gains `unsigned int kind` (0 contains, 1 uses).

- **Contains:** straight hairline, 0.5 pt core, neutral blue-grey
  `(0.42, 0.52, 0.78)`, intensity ×0.5 of today's edges.
- **Uses:** amber `(1.0, 0.68, 0.30)`, 0.9 pt core with soft glow, drawn as a
  quadratic Bézier tessellated into 12 segments (instanced strip, 26 vertices):
  control point = midpoint + `0.18 · length` along the direction perpendicular
  to the edge and the view axis, so curves bow consistently on screen.
- Draw order: contains, then uses, then signals, then nodes (all additive).

### 7.2 Signals

Only on uses-edges (carry chance 0.4 as today), travelling `from → to`, sampled
along the same Bézier. Colour: amber-white.

### 7.3 Highlight

`MCNodeInstance` gains `float highlight` (fits in existing padding; struct stays
64 bytes). Values: 1 normal; when something is focused: 1.6 for the focus node,
1.25 for direct neighbours (either edge kind), 0.12 for everything else. Edges
take the min of their endpoints' highlight (so only edges touching the focus
stay bright); signals likewise. Updated by writing the node buffer region on
hover change (CPU → shared buffer), never per frame.

## 8. Interaction and labels

### 8.1 Picking

On `mouseMoved` (tracking area on the Metal view) and on click, `Picking`
projects node centres with the last frame's view-projection and returns the
nearest node whose screen distance ≤ max(8 pt, projected core radius + 3 pt),
preferring nearer-to-camera nodes on ties. ~10k projections per move is cheap.

### 8.2 Hover, pin, info card

- Hover sets the focus (highlight §7.3) and shows a tooltip-style label with the
  node's relative path.
- Click (mouse-up within 3 pt of mouse-down) on a node pins it; click on empty
  space or Esc unpins. While pinned, hover doesn't change the focus.
- Esc with nothing pinned closes the visualizer (existing behaviour).
- Info card (SwiftUI, bottom-left of the panel) for the pinned node: name,
  relative path, kind, "uses N · used by M" (uses-edges), and for folders
  "K files".

### 8.3 Labels

`LabelPlanner` (pure) takes projected nodes and returns ≤ 150 placed labels:

1. Candidates: the focus node and its neighbours (always); all folders; files
   whose projected core radius ≥ 2.5 pt (i.e. zoomed close).
2. Priority: focus → neighbours → folders by weight → files by projected size.
3. Placement: label anchored right of the node; skip any label whose rect
   intersects an already placed one (grid-bucketed rect test); skip off-screen.
4. Opacity: folders 0.9; files fade 0 → 0.85 as projected radius goes
   2.5 → 5 pt; non-highlighted labels ×0.35 while something is focused.

`LabelOverlayView` is an `NSView` layered above the `MTKView` holding a pool of
150 `CATextLayer`s (system font; folders 12 pt semibold scaling to 14 pt by
weight, files 10.5 pt regular; white with a soft dark shadow). The renderer
publishes a camera snapshot each frame; the overlay re-plans and repositions
layers inside a `CATransaction` with actions disabled.

### 8.4 Legend

Bottom-right of the panel, small and translucent: a contains swatch ("contains"),
a uses swatch ("uses — file depends on file"), and node colour dots (folder,
source, document). Always visible while the panel is open.

## 9. Error handling

- Unreadable or non-UTF-8 files: skipped by the dependency scan.
- Parser surprises (unbalanced quotes, huge single lines): parsers are
  line/regex based, bounded by the 512 KB file-size limit, and never throw.
- A project with zero uses-edges renders exactly as before plus the legend.
- Cancellation mid-pipeline publishes nothing (existing Model behaviour).

## 10. Testing

- **Parsers** (temporary fixture projects): each language's import forms,
  relative resolution, `index`/`__init__` resolution, unresolved targets ignored,
  Swift ambiguity cutoff and comment/string skipping, Markdown anchors.
- **DependencyScanner:** per-file and total caps, dedupe, self-edges, size limit.
- **ConeTreeLayout:** deterministic; sibling folder bounding spheres don't
  intersect; root at origin; all finite.
- **Relaxation:** min pairwise distance ≥ 0.9 · minSpacing on a dense fixture;
  folders move less than files; deterministic; 10k nodes < 500 ms (Debug).
- **Picking:** known camera + nodes → expected index; empty space → nil; nearest
  wins on overlap.
- **LabelPlanner:** budget 150; no overlapping rects; focus and neighbours
  always included; files hidden when far, shown when close; off-screen skipped.
- **Renderer:** offscreen renders — uses-edges add light where contains-only
  doesn't; highlight dims non-focused regions; existing tests stay green.
- **Visual:** offscreen renders of Arca and Lostty before/after.

## 11. Build order (each phase usable on its own)

1. **Relationships:** EdgeKind, parsers, DependencyScanner, pipeline, edge
   styling (contains vs curved uses), signals on uses only, legend.
2. **Layout:** ConeTreeLayout + Relaxation replace TreeLayout.
3. **Inspection:** picking, highlight, hover/pin, info card, labels.

## 12. Refinements during implementation

1. Subfolder distance is `fileBallRadius(parent files) + 2 + 1.2·(1 + w)^0.4` (was `3 + 1.2·√w`):
   clear of the parent's file ball, and gentler growth so very large folders (Lostty's `test/`)
   don't stretch the map.
2. Relaxation's 10k-node budget is < 1.5 s in the Debug test build; it uses a sorted cell list and
   stops early once no node moves more than 0.001.
3. Uses-springs are normalised by both endpoints' link counts (`k / √(degA·degB)`), with
   `k = 0.01`, so densely linked folders keep their shape (`denselyLinkedFilesKeepTheirSpread`).
4. Python also resolves absolute imports beside the importing file.
5. Edges render from two buffers (contains, uses); `MCEdgeInstance.kind` is still stored.
6. `MCFrameUniforms.usesScale = max(0.08, (300/n)^0.75)` dims uses-edges (fully) and signals
   (partly) on projects with many dependencies; each edge's signal chance is scaled by
   `usesScale²` so the number of signals in flight stays roughly constant. Pinned by
   `DensityTests.denseDependenciesDoNotBlowOut` (differential: < 2 pts added).
7. `GraphNode.descendantFiles` (label priority, info card) and `GraphBuffers.sourceNodes`.
8. The hover "tooltip" is the focus node's label showing its relative path.
