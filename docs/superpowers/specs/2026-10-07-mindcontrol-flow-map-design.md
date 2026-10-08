# MindControl flow map — design

Written 2026-10-07. Replaces the 3D file/import map described in
`2026-10-06-lostty-mindcontrol-design.md` and
`2026-10-06-mindcontrol-relationships-labels-design.md`; the sidebar
integration from those documents stays.

## Why

The 3D map drew every source file and every reference between them. It could
not answer the questions it was opened for: how the project is divided into
systems, and how data and control move between them. Imports and type
references say who knows about whom, not what travels where. In Arca, the flow
runs through callbacks (`ArcaLink.onEvent`), audio buffer streams, and network
hops (OpenAI, relay, APNs) that no file-to-file scan sees. Arca's own
`docs/architecture/01-utterance.md` shows the picture wanted. It was written by
someone who understood the meaning, not derived from code.

## Goal

A 2D data-flow map, opened from the Lostty extensions sidebar, that shows a
project's systems and how data and control move between them. Zoomed out, the
whole app fits on one screen. Search takes the view to any feature, system,
part or file. Nothing is drawn that does not describe a real flow.

## Decisions

| Question | Decision |
|---|---|
| Main unit on the map | Systems are the map. Features are coloured routes across it, also listed step by step in a side panel. |
| Source of truth | A flow file committed in the project, written by Claude and edited by people, checked against the code by MindControl on every open. |
| Project without a flow file | An empty state with a "Draft with Claude" button. |
| Depth | Two levels: systems, and the parts inside each. A part links to its file. |
| Rendering | Metal, keeping the glow, bloom and pulse look. Labels in a layer above the Metal view. |
| Layout | Automatic left-to-right layered layout. Dragged boxes are saved in a separate layout file. |
| Arrows | Data and control, drawn differently. Control arrows can be hidden with one toggle. |
| Search | Features, systems, parts, and any source file or Swift type, which resolves to its system. |
| Keeping it current | Drafting adds an upkeep rule to the project's `CLAUDE.md`; a "Refresh with Claude" button with an "updated N commits ago" counter. |
| A file matched by two systems | The more specific pattern wins; a true tie is an error. |
| Branches in a feature | Optional `when` on a flow; conditional steps grouped in the side panel. |
| Trusting arrows | Each flow names its hand-off in `via`, checked against the code. |
| Box size | Boxes are sized for their parts; zooming never moves anything. |
| Map growing too big | Soft density warnings; nothing blocked. |
| Too many visual signals | Two views: Map (how the app works) and Health (is the map accurate). |
| Zoning in | A Focus view for one system or one feature, laid out fresh. |
| Seeing what a branch changed | Later. Built for now: maps load from any git revision, ids are stable, the view switch has room for Changes. |
| The whole project at a glance | Zones: tinted regions for where systems run (ring, phone, relay, cloud). |
| Wrong folder | The header shows the project path with a Change… picker; Draft and Refresh are off at `~`, `/` and outside git. |

## The flow file

`.mindcontrol/flow.json` at the project root (the git root, or the terminal's
folder outside git). Committed with the code. Dragged positions go in
`.mindcontrol/layout.json`, which MindControl writes.

```json
{
  "version": 1,
  "zones": [
    { "id": "ring", "name": "Ring" },
    { "id": "phone", "name": "Phone" },
    { "id": "relay", "name": "Relay server" },
    { "id": "cloud", "name": "Cloud services" }
  ],
  "systems": [
    { "id": "audio", "name": "Audio", "zone": "phone",
      "summary": "Mic capture, the words-heard check, playback.",
      "paths": ["app/Sources/Audio/**"],
      "parts": [
        { "id": "capture", "name": "AudioCapture", "anchor": "AudioCapture" },
        { "id": "gate",    "name": "SpeechGate",   "anchor": "SpeechGate" },
        { "id": "relay",   "name": "pipe",         "anchor": "relay/src/pipe.ts" }
      ] },
    { "id": "openai", "name": "OpenAI Realtime", "zone": "cloud", "external": true }
  ],
  "flows": [
    { "id": "pcm", "from": "audio.capture", "to": "agent", "kind": "data",
      "carries": "PCM16 24 kHz", "via": "sendAudio" },
    { "id": "begin", "from": "tap", "to": "audio.capture", "kind": "control",
      "carries": "begin / end", "via": "beginTransmission" },
    { "id": "commit", "from": "audio.capture", "to": "agent", "kind": "control",
      "carries": "commit turn", "via": "commitTurn", "when": "words heard" },
    { "id": "discard", "from": "audio.capture", "to": "agent", "kind": "control",
      "carries": "discard turn", "via": "discardTurn", "when": "nothing heard" }
  ],
  "features": [
    { "id": "speech", "name": "A press becomes speech", "route": ["press", "event", "begin", "pcm", "commit", "discard"] }
  ]
}
```

Rules:

- `id`s are lowercase letters, digits and `-`, unique within their list. A part
  is addressed as `system.part`.
- `version` is 1. Any other value is an error naming the supported version.
- `zones` is optional. Each zone has `id` and `name`. A system's optional
  `zone` must name one of them. Systems without a zone sit in an unlabelled
  zone of their own.
- A system has a `name`. Optional fields: `summary` (one sentence, shown in the
  side panel and on the box), `zone`, `paths`, `parts` and `external`.
- `paths` are glob patterns relative to the root (`*` within a folder name,
  `**` across folders). An external system has no `paths` and no `parts`.
- A part has `id`, `name` and an optional `anchor`. An anchor containing `/`
  or a file extension is a file path relative to the root. Anything else is a
  Swift type name, which must be declared in a Swift file under the part's
  system `paths`.
- A flow has `id`, `from`, `to`, `kind` (`data` or `control`) and `carries`, a
  short phrase for what travels or what is triggered. `from` and `to` name a
  system or a `system.part`.
- A flow's optional `via` names the call, method or symbol where the hand-off
  happens. It is checked by whole-word search in the source files owned by the
  `from` system, or by the `to` system when `from` is external. A flow between
  two external systems is not checked and needs no `via`.
- A flow's optional `when` is a short condition ("words heard"). Flows sharing
  a `when` in a route form one branch.
- When a source file matches more than one system's `paths`, the pattern with
  the longest literal text before its first `*` wins
  (`app/Sources/Coordination/Journal*.swift` beats
  `app/Sources/Coordination/**`). An equal-length tie is an error naming the
  file and both systems.
- A feature has `id`, `name` and `route`, an ordered list of flow ids.

## What MindControl does on open

1. **Find the project.** Same as today: git root of the terminal's working
   directory, or the directory itself. A folder chosen with **Change…** in the
   header overrides this for that window until MindControl is closed. The
   header always shows the full project path.
2. **Read** `.mindcontrol/flow.json`. If it is missing, show the empty state. If
   it is invalid JSON or breaks a rule above, show the errors, each with a line
   number where one exists, and no map.
3. **Check** against the code:
   - Anchors that match nothing mark their part **stale**.
   - A `via` that matches nothing marks its flow **stale**, drawn amber. A flow
     with no `via` (and an internal end) is **unverified**, drawn faint.
     A found `via` records its first matching file and line.
   - Overlapping `paths` resolve by the rule above. Ties are errors.
   - Flows naming an unknown system or part are listed as errors and not drawn.
     The rest of the map still draws.
   - Features naming an unknown flow are listed as errors. Their known steps
     still draw.
   - Source files (the existing `SourceFilter`) not matched by any system's
     `paths` are **unmapped**. A badge shows the count; clicking it lists the
     files.
   - **Age**: in a git project, the number of commits since `flow.json` was
     last committed that touch any system's `paths`. Shown as "Map updated N
     commits ago", or "Map not committed yet". Hidden outside git.
   - **Density**: a warning past 20 systems, 8 parts in one system, or 60
     flows, naming which limit was passed. Nothing is blocked.
4. **Lay out** (below) and draw.
5. **Watch** `.mindcontrol/` and reload when `flow.json` appears or changes.

## Layout

Deterministic: the same flow file and layout file always give the same picture.

- **Zones first.** Zones are ordered left to right by a layered layout of the
  data flows between zones. Each zone is a block holding its systems, and the
  blocks never overlap. A zone's region is drawn as a soft tinted rectangle
  around its block, its name in large type.
- **Systems within a zone** use the rules below, scoped to that zone. Flows
  that cross zones count toward ordering through the zone's edge.

- Systems are placed in columns by the direction of **data** flows, using a
  layered layout:
  - Cycles (OpenAI ↔ agent) are broken by reversing the fewest arrows. Those
    arrows are drawn as return arrows and never change the column order.
  - External systems that only send go to the leftmost column. External
    systems that only receive go to the rightmost column.
  - Within a column, systems are ordered to reduce crossings (barycenter
    sweeps, fixed iteration count), ties broken by id.
- Control flows do not affect columns.
- Parts are laid out inside their system box the same way, on a smaller scale.
  A system box is sized to hold its parts.
- Saved positions from `layout.json` (system id → x, y) are applied last. An
  unreadable `layout.json` is ignored.

## Rendering and interaction

**Views.** A switch in the header picks the view. Map is the default. The
switch is built to hold a third view, Changes, which is not part of this
build.

- **Map** shows how the app works, with six visual signals only: zone regions,
  system boxes (dashed for external), solid data arrows with pulses, thin
  dashed control arrows, feature colours, and branch diamonds. Labels as
  below. Stale and unverified items are drawn normally here.
- **Health** shows whether the map is accurate. The app is drawn grey; only
  problems are coloured: stale parts and flows in amber, unverified flows as
  faint dashes, and errors in red. The side panel lists every issue, and the
  unmapped files, with age and density warnings at the top. Clicking an issue
  moves the view to it.
- A corner indicator in Map view reads "Map healthy" or "N issues". Clicking it
  switches to Health.

**Look:** dark field, no star dust. Systems are rounded boxes with a soft glow.
External systems have dashed outlines and are fainter. Data arrows are solid
curves with pulses moving in the flow's direction. Control arrows are thin,
dashed, and have no pulses. A flow with a `when` gets a small diamond where it
leaves its source. Bloom and composite as today. Health colours apply only in
Health view.

**Box size:** a system box is sized to hold its parts at every zoom level, so
zooming never moves anything. Zoomed out, a box shows its name, its summary,
and a faint "N parts" hint.

**Zoom levels** (three scales of one picture; the file still has two levels):

- **Farthest:** zone regions with their names, and one thick arrow per
  direction between zones. System names fade out.
- **Out:** systems with names and summaries. Flows between the same two
  systems merge into one thicker arrow.
- **In** (past a fixed scale): each system opens in place to show its parts and
  the flows between them. Flows that end at a part attach to that part.
- Arrow labels (`carries`) show only when zoomed in, or for the selected
  feature's route, using the existing label planner to avoid overlaps.

**Controls:**

| Action | Effect |
|---|---|
| Scroll / pinch | Zoom about the cursor |
| Drag background | Pan |
| Drag a system | Move it; saved to `layout.json` |
| Click a system or part | Select it; the side panel shows its summary, its flows in and out, and its files |
| Double-click a part | Open its anchor file in the default app for that file |
| Feature chip | Light up its route, dim the rest, pulse in the feature's colour, open its steps in the side panel |
| Click a step | Move the view to that flow |
| Click an arrow | Select it; the side panel shows what it carries and its `via` location |
| Double-click an arrow | Open the file at its `via` line |
| Control toggle | Show or hide control arrows |
| Focus button or F | Open Focus view for the selected system or feature |
| View switch | Map or Health |
| ⌘F or typing | Search |
| Esc | Clear search, then leave Focus view, then clear the feature or selection, then close MindControl |

On open, and on every reload, the view fits the whole map.

**Feature bar:** one chip per feature along the top, each with its own colour
from a fixed palette, in file order.

**Focus view.** A separate view for one subject, entered from the selected
system or feature and left with Esc or the path at the top ("Arca › Audio").
Boxes slide from their map positions into the focus layout and back. Focus
layouts are computed fresh; the main map's layout and `layout.json` are never
changed by them.

- **System focus:** the system is drawn large in the centre with all its parts
  and internal flows. Every system it exchanges flows with is a small labelled
  box at the edge, senders on the left and receivers on the right, with the
  crossing flows labelled.
- **Feature focus:** only the systems on the route, laid out as one
  left-to-right chain in step order. Steps with a `when` split into lanes, one
  per condition, in route order. All labels are shown.

**Side panel:** on the right. For a feature, a numbered list of its steps:
"Ring → BLE link · press DOWN / UP", with control steps marked. Consecutive
steps sharing a `when` are grouped under a header ("If words heard"). Stale and
unverified steps are marked. For a system or part, its summary, its flows, and
its files.

## Search

Matches, grouped in this order: Features, Systems, Parts, Files. Within a group,
results are ranked prefix match first, then word-start match, then substring,
then alphabetical. Case-insensitive.

- Files are the project's source files, plus Swift type names declared in them.
  A file or type result names the system that owns it, or "no system".
- Enter animates the view to the result and pulses it. A feature result also
  selects the feature. A file result selects its system. A "no system" result
  opens the unmapped list.

## Draft with Claude

The empty state reads "No flow map for *project* yet" with a **Draft with
Claude** button. The button opens a new Lostty tab in the project root running
`claude` with a bundled prompt. The prompt:

- gives the flow file format and rules above
- defines data versus control arrows
- tells Claude to read the code and any architecture docs first
- tells Claude to find the hand-off for every flow and record it in `via`
- tells Claude to use `when` for branches
- tells Claude to keep within the density limits, preferring to merge systems
- tells Claude to write `.mindcontrol/flow.json`
- tells Claude to add this rule to the project's `CLAUDE.md`, creating the
  file if needed: "When you change how data or control moves between systems,
  update `.mindcontrol/flow.json`."

Draft and Refresh are disabled when the project is the home folder, `/`, or
not inside a git repository. The panel names the reason and offers
**Change…**.

When the file appears, the map loads by itself. If `claude` is not on the PATH,
the button's result says so and shows the prompt with a Copy button.

## Refresh with Claude

Once a map exists, a **Refresh with Claude** button sits beside the age and
density badges. It opens a new tab the same way, with a second bundled prompt:

- read the current `flow.json`
- read the commits since it was last committed (`git log -p` limited to the
  systems' `paths`) and the files they touched
- update the systems, flows, routes and `via`s to match
- keep within the density limits
- leave positions alone

Outside git, the prompt reads the whole project instead.

## Code changes

Kept:

- the sidebar wiring
- `ProjectResolver`
- `SourceFilter` and `ProjectScanner`, for the unmapped list and file search
- `SwiftSymbols.declaredTypes`, for anchors and type search
- the Metal view setup, `BloomPass`, `Composite.metal`
- the label overlay and planner

Removed:

- `ConeTreeLayout`, `Relaxation`, `Graph+Stress`
- `DependencyScanner` and the import parsers, except `SwiftSymbols.declaredTypes`
- `Dust.metal`
- `OrbitCamera`, 3D `Picking`
- the current `InfoCard`, `Inspector` and `MindControlLegend`
- their tests

New, each with one job:

| Unit | Job |
|---|---|
| `FlowSource` | Read `flow.json`, `layout.json` and the source file list from the working tree or from a git revision (`git show`, `git ls-tree`). |
| `FlowFile` | Decode and validate `flow.json`, with line-numbered errors. |
| `FlowCheck` | Stale anchors and `via`s, unknown references, path overlaps, unmapped files, age, density. |
| `FlowLayout` | Zone blocks, layered layout, part layout, saved positions. |
| `FocusLayout` | System focus and feature focus layouts, with branch lanes. |
| `LayoutStore` | Read and write `layout.json`. |
| `FlowSearch` | Index and rank search results. |
| `PanZoomCamera` | 2D view transform, fit, animated moves. |
| `FlowRenderer` + shaders | Boxes, data and control arrows, pulses, highlight, glow. |
| `FlowPicking` | Hit-testing boxes, parts and arrows in 2D. |
| `FlowPanel` | View switch, feature bar, side panel, search field, health indicator, errors, empty state, Draft and Refresh. |
| `FlowWatcher` | Reload on changes in `.mindcontrol/`. |

## Errors

| Situation | Behaviour |
|---|---|
| No flow file | Empty state with Draft with Claude |
| Invalid JSON or a broken rule | Error list with line numbers; no map |
| Stale anchor | Part drawn amber; listed in the side panel |
| Stale `via` | Flow drawn amber; listed in the side panel |
| Flow without `via` | Drawn faint; marked unverified |
| Two systems tie for a file | Listed as an error naming the file and both systems; the file counts as unmapped |
| Map past a density limit | Warning badge naming the limit |
| Unknown system or part in a flow | Listed as an error; that flow not drawn |
| Unknown flow in a feature route | Listed as an error; known steps still shown |
| Unreadable `layout.json` | Ignored; automatic layout |
| `claude` not found | Message plus the prompt with a Copy button |
| Unreadable project folder | Same message as today |
| Project is `~`, `/` or outside git | Map shown if a flow file exists; Draft and Refresh disabled with the reason and Change… |

## Wrong-folder investigation

Earlier, MindControl showed the home folder after the user had `cd`'d into
Arca. The working directory comes from the shell's OSC 7 report, via
`Ghostty.App.pwdChanged` into `surfaceView.pwd`. The first plan task
reproduces this, finds where the report is lost or stale, and fixes it if the
cause is in Lostty's code. If the cause is outside Lostty, for example a
missing shell integration, the panel's path display and Change… are the
remedy, and the finding is recorded in the plan's ledger.

## Testing

Unit tests:

- `FlowFile`: valid files, each broken rule, and line numbers in errors.
- `FlowCheck`:
  - stale type anchors and stale file anchors
  - `via` found (with file and line), stale, unverified, and the external-end
    rule
  - path overlap: the more specific pattern wins; an equal tie is an error
  - unknown references
  - unmapped files, counted with `SourceFilter`
  - age from a temporary git repo; "not committed yet"; hidden outside git
  - each density warning at its limit
- `FlowFile`: zones, including a system naming an unknown zone.
- `FlowSource`: the same map loads from the working tree and from a commit.
- `FlowLayout`:
  - same input gives the same output
  - each zone's systems sit inside its block, and blocks do not overlap
  - zones are ordered by the data flows between them
  - a data source sits left of what it feeds
  - a cycle does not reorder columns
  - external senders sit leftmost and receivers rightmost
  - saved positions override
  - control flows do not move columns
- `FocusLayout`:
  - system focus puts senders left and receivers right of the subject
  - feature focus follows step order, and `when` steps split into lanes
- Health: the issue count matches the stale, unverified, error, unmapped and
  density findings.
- `FlowSearch`: grouping, ranking order, and file and type resolution to a
  system or "no system".
- Feature routes become numbered steps in order, with `when` groups and
  unknown flows reported.
- `PanZoomCamera`: zoom about a point, fit, and screen↔world round trip.
- Draft and Refresh availability: off for `~`, `/` and non-git folders, on
  for a git root; a Change… override replaces the terminal's folder.
- Renderer smoke test: draws a small map without Metal validation errors.

Acceptance:

1. Run Draft with Claude on Arca.
2. Check by eye that "a press becomes speech" matches the sequence diagram in
   Arca's `docs/architecture/01-utterance.md`.
3. Check that searching `CostMeter` lands on its system.

The Arca flow file is left uncommitted in Arca for the user to decide.

## Next: Changes view

Not part of this build. Recorded so the foundations above serve it.

A third view comparing the current branch with a base, `main` by default:

1. **Touched systems.** Files changed on the branch, mapped to the systems
   that own them, shown as glowing systems with a changed-file count.
2. **Touched flows.** Flows whose `via` location is in a changed file.
3. **Changed flows.** If `flow.json` differs, the two maps compared by id:
   added systems and flows in green, removed in red, changed `carries` or
   routes marked.

## Out of scope

- Live data, such as showing real traffic on arrows.
- Generating or updating the flow file without the user starting it.
- More than two levels of nesting.
- Editing flows from the map; only positions are edited.
- The Changes view (above).
