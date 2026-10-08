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

## The flow file

`.mindcontrol/flow.json` at the project root (the git root, or the terminal's
folder outside git). Committed with the code. Dragged positions go in
`.mindcontrol/layout.json`, which MindControl writes.

```json
{
  "version": 1,
  "systems": [
    { "id": "audio", "name": "Audio", "summary": "Mic capture, the words-heard check, playback.",
      "paths": ["app/Sources/Audio/**"],
      "parts": [
        { "id": "capture", "name": "AudioCapture", "anchor": "AudioCapture" },
        { "id": "gate",    "name": "SpeechGate",   "anchor": "SpeechGate" },
        { "id": "relay",   "name": "pipe",         "anchor": "relay/src/pipe.ts" }
      ] },
    { "id": "openai", "name": "OpenAI Realtime", "external": true }
  ],
  "flows": [
    { "id": "pcm", "from": "audio.capture", "to": "agent", "kind": "data", "carries": "PCM16 24 kHz" },
    { "id": "begin", "from": "tap", "to": "audio.capture", "kind": "control", "carries": "begin / end" }
  ],
  "features": [
    { "id": "speech", "name": "A press becomes speech", "route": ["press", "event", "begin", "pcm"] }
  ]
}
```

Rules:

- `id`s are lowercase letters, digits and `-`, unique within their list. A part
  is addressed as `system.part`.
- `version` is 1. Any other value is an error naming the supported version.
- A system has a `name`. Optional fields: `summary` (one sentence, shown in the
  side panel), `paths`, `parts` and `external`.
- `paths` are glob patterns relative to the root (`*` within a folder name,
  `**` across folders). An external system has no `paths` and no `parts`.
- A part has `id`, `name` and an optional `anchor`. An anchor containing `/`
  or a file extension is a file path relative to the root. Anything else is a
  Swift type name, which must be declared in a Swift file under the part's
  system `paths`.
- A flow has `id`, `from`, `to`, `kind` (`data` or `control`) and `carries`, a
  short phrase for what travels or what is triggered. `from` and `to` name a
  system or a `system.part`.
- A feature has `id`, `name` and `route`, an ordered list of flow ids.

## What MindControl does on open

1. **Find the project.** Same as today: git root of the terminal's working
   directory, or the directory itself.
2. **Read** `.mindcontrol/flow.json`. If it is missing, show the empty state. If
   it is invalid JSON or breaks a rule above, show the errors, each with a line
   number where one exists, and no map.
3. **Check** against the code:
   - Anchors that match nothing mark their part **stale**.
   - Flows naming an unknown system or part are listed as errors and not drawn.
     The rest of the map still draws.
   - Features naming an unknown flow are listed as errors. Their known steps
     still draw.
   - Source files (the existing `SourceFilter`) not matched by any system's
     `paths` are **unmapped**. A badge shows the count; clicking it lists the
     files.
4. **Lay out** (below) and draw.
5. **Watch** `.mindcontrol/` and reload when `flow.json` appears or changes.

## Layout

Deterministic: the same flow file and layout file always give the same picture.

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

**Look:** dark field, no star dust. Systems are rounded boxes with a soft glow.
External systems have dashed outlines and are fainter. Data arrows are solid
curves with pulses moving in the flow's direction. Control arrows are thin,
dashed, and have no pulses. Stale parts are amber. Bloom and composite as
today.

**Zoom levels:**

- **Out:** systems only. Flows between the same two systems merge into one
  thicker arrow.
- **In** (past a fixed scale): each system opens in place to show its parts and
  the flows between them. Flows that end at a part attach to that part.
- Arrow labels (`carries`) show only once their text is readable, using the
  existing label planner to avoid overlaps.

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
| Control toggle | Show or hide control arrows |
| ⌘F or typing | Search |
| Esc | Clear search, then the feature or selection, then close MindControl |

On open, and on every reload, the view fits the whole map.

**Feature bar:** one chip per feature along the top, each with its own colour
from a fixed palette, in file order.

**Side panel:** on the right. For a feature, a numbered list of its steps:
"Ring → BLE link · press DOWN / UP", with control steps marked. For a system or
part, its summary, its flows, and its files.

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
- tells Claude to keep it to about 15 systems
- tells Claude to write `.mindcontrol/flow.json`

When the file appears, the map loads by itself. If `claude` is not on the PATH,
the button's result says so and shows the prompt with a Copy button.

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
| `FlowFile` | Decode and validate `flow.json`, with line-numbered errors. |
| `FlowCheck` | Stale anchors, unknown references, unmapped files. |
| `FlowLayout` | Layered layout, part layout, saved positions. |
| `LayoutStore` | Read and write `layout.json`. |
| `FlowSearch` | Index and rank search results. |
| `PanZoomCamera` | 2D view transform, fit, animated moves. |
| `FlowRenderer` + shaders | Boxes, data and control arrows, pulses, highlight, glow. |
| `FlowPicking` | Hit-testing boxes, parts and arrows in 2D. |
| `FlowPanel` | Feature bar, side panel, search field, badges, errors, empty state, Draft with Claude. |
| `FlowWatcher` | Reload on changes in `.mindcontrol/`. |

## Errors

| Situation | Behaviour |
|---|---|
| No flow file | Empty state with Draft with Claude |
| Invalid JSON or a broken rule | Error list with line numbers; no map |
| Stale anchor | Part drawn amber; listed in the side panel |
| Unknown system or part in a flow | Listed as an error; that flow not drawn |
| Unknown flow in a feature route | Listed as an error; known steps still shown |
| Unreadable `layout.json` | Ignored; automatic layout |
| `claude` not found | Message plus the prompt with a Copy button |
| Unreadable project folder | Same message as today |

## Testing

Unit tests:

- `FlowFile`: valid files, each broken rule, and line numbers in errors.
- `FlowCheck`:
  - stale type anchors and stale file anchors
  - unknown references
  - unmapped files, counted with `SourceFilter`
- `FlowLayout`:
  - same input gives the same output
  - a data source sits left of what it feeds
  - a cycle does not reorder columns
  - external senders sit leftmost and receivers rightmost
  - saved positions override
  - control flows do not move columns
- `FlowSearch`: grouping, ranking order, and file and type resolution to a
  system or "no system".
- Feature routes become numbered steps in order, with unknown flows reported.
- `PanZoomCamera`: zoom about a point, fit, and screen↔world round trip.
- Renderer smoke test: draws a small map without Metal validation errors.

Acceptance:

1. Run Draft with Claude on Arca.
2. Check by eye that "a press becomes speech" matches the sequence diagram in
   Arca's `docs/architecture/01-utterance.md`.
3. Check that searching `CostMeter` lands on its system.

The Arca flow file is left uncommitted in Arca for the user to decide.

## Out of scope

- Live data, such as showing real traffic on arrows.
- Generating or updating the flow file without the user starting it.
- More than two levels of nesting.
- Editing flows from the map; only positions are edited.
