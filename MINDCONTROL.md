# MindControl

A 2D data-flow map of the project your terminal is in. It shows the project's systems, grouped into
zones by where they run, and how data and control move between them. Zoomed out, the whole app fits on
one screen. Features are coloured routes across the map, listed step by step beside it. Search takes you
to any feature, system, part, file or Swift type. Nothing is drawn that doesn't describe a real flow.

## Opening it

Click **Codebase visualizer** in the extensions sidebar on the right edge of a Lostty window. The map
fills the terminal area and shows the focused terminal's project: its git root, or the folder itself
outside git. The header always shows the full path. If it's the wrong folder, click **Change…** and pick
another; that choice holds until you close MindControl.

## The flow file

The map comes from `.mindcontrol/flow.json` at the project root, committed with the code. Claude writes
it (see below), and you can edit it by hand. MindControl reloads by itself whenever the file changes.
Dragged box positions go in `.mindcontrol/layout.json`, which MindControl writes.

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
    { "id": "pcm", "from": "audio.capture", "to": "openai", "kind": "data",
      "carries": "PCM16 24 kHz", "via": "sendAudio" },
    { "id": "commit", "from": "audio.capture", "to": "openai", "kind": "control",
      "carries": "commit turn", "via": "commitTurn", "when": "words heard" }
  ],
  "features": [ { "id": "speech", "name": "A press becomes speech", "route": ["pcm", "commit"] } ]
}
```

Rules:

- `version` is 1. Ids use lowercase letters, digits and `-`, unique within their list. A part is
  addressed as `system.part`.
- `zones` are where systems run (a device, the phone, a server, the cloud). A system's `zone` must name one.
- A system has a `name`, and optionally `summary` (one sentence), `zone`, `paths`, `parts` and
  `external`. An external system (a service, hardware, the OS) has no `paths` and no `parts`.
- `paths` are globs relative to the root: `*` within a name, `**` across folders, `?` one character. A
  pattern with no wildcard names a file or a whole folder (a trailing `/` is fine).
- When two systems' patterns match the same file, the one with the longer fixed text before its first
  wildcard wins. An equal tie is an error, and that file counts as unmapped.
- A part has `id`, `name` and an optional `anchor`: a Swift type declared in the system's own files, or
  a file path (anything with `/` or an extension). A path that leads outside the project (`../`, or
  starting with `/`) is stale.
- A flow has `id`, `from`, `to`, `kind` (`data` when something is carried, `control` when one side
  triggers the other) and `carries`. `via` names the call where the hand-off happens; MindControl looks
  for it as a whole word in the `from` system's files (the `to` system's when `from` is external).
- `when` marks a conditional flow ("words heard"). Neighbouring steps in a route with the same `when`
  form one branch.
- A feature has `id`, `name` and `route`, an ordered list of flow ids.
- Keep it small: past 20 systems, 8 parts in one system, or 60 flows, MindControl warns. Nothing is blocked.

On every open MindControl checks the file against the code. An anchor or `via` it can't find marks that
part or arrow **stale**. A flow with no `via` is **unverified**. A flow naming an unknown system or part
isn't drawn, and a feature naming an unknown flow lights the rest of its route; both are listed in
Health. Source files no system owns are **unmapped**. A key the format doesn't have (`"flow"`, `"whne"`)
is ignored, not an error: Health lists it with its line and, for a near miss, the key you probably
meant, and clicking it opens `flow.json` at that line. In git, the header shows how many commits have
touched the systems' paths since `flow.json` was last committed (nothing when no system has paths or
git can't count them). Invalid JSON or a broken rule shows a list of errors with line numbers instead of
the map. A valid file with no systems says "This map has no systems yet."

## Views and controls

- **Map / Health.** Map shows how the app works. Health greys the map and colours only problems: stale
  parts (and their systems) and stale arrows in amber, unverified flows as faint dashes. The side panel
  lists every issue, problems in orange and warnings (density, unknown keys) in yellow, then the
  unmapped files. Click an issue to go to it: the map moves to it and highlights it, and the list
  stays. Click a file to open it. The header's "Map healthy" / "N issues", unmapped count and density warning all open Health.
- **Zoom levels.** Farthest out you see zones and one thick arrow per direction between them (on a map
  with no zones, or no flows between them, systems keep their names and arrows instead). Closer,
  systems appear with their names and summaries, and flows between two systems merge into one arrow.
  Closer still, each system opens to show its parts, and arrows attach to the parts they connect.
  Boxes never move as you zoom. Arrow labels show up close, and always on the selected feature's route.
  A label slides along its arrow when the middle is taken.
- **Arrows.** Data arrows are solid with pulses. Control arrows are thin and dashed; the **Control**
  checkbox hides them. A diamond marks a conditional flow. Arrows route around boxes in their way.
- **Feature chips.** Click a chip to light up its route, dim the rest and list its numbered steps in the
  side panel, grouped under "If …" for each branch. Click a step to go to its arrow. Click the chip again
  to clear it.
- **Selecting.** Click a system, part or arrow to see its summary, its flows in and out, and its files.
  Click a file to open it.
- **Focus (F or the Focus button).** Opens the selected system or feature on its own. System focus puts
  the system large in the middle with senders left and receivers right. Feature focus lays out the
  route's systems as one chain in step order, with each condition in its own lane and its arrows bending
  into it. Boxes slide in and out. Leave with Esc or by clicking the path in the header.
- **Search (⌘F, or just start typing).** Results are grouped as Features, Systems, Parts and Files, and
  update when you pause. A file or Swift type names the system that owns it, or "no system". Enter or a
  click goes to the result and pulses it; a "no system" result opens Health.
- **Moving around.** Scroll or pinch to zoom about the cursor. Drag the background to pan. Drag a system
  to move it; its position is saved to `layout.json`.
- **Double-click** a part to open its anchor file, an arrow to open the file at its `via` line, or a
  system to focus it.
- **Opening files.** A file opens in its default app only when that app is a known editor (Xcode, VS
  Code, Cursor, Windsurf, Zed, Sublime Text, BBEdit, Nova, CotEditor, TextEdit, JetBrains IDEs, MacVim,
  Emacs). Anything else (a script whose default app would run it, an executable, a `.command`,
  `.terminal` or `.mobileconfig` file, …) opens in Xcode, or TextEdit without Xcode. Xcode opens at the
  line. Folders are shown in Finder, and nothing outside the project is opened.
- **Esc** clears the search, then leaves Focus, then clears the feature or selection, then closes
  MindControl.

## Draft and Refresh with Claude

With no flow file, MindControl shows "No flow map for *project* yet" and a **Draft with Claude** button.
It opens a new Lostty tab in the project running `claude` with a bundled prompt. Claude reads the code
and docs, writes `.mindcontrol/flow.json`, and adds this line to the project's `CLAUDE.md` if it isn't
there already: "When you change how data or control moves between systems, update
`.mindcontrol/flow.json`." The map appears as soon as the file is saved.

Once a map exists, **Refresh with Claude** in the header does the same with a second prompt: Claude
reads the commits since `flow.json` was last committed and updates the map to match, keeping ids and
leaving `layout.json` alone.

Both buttons are off when the project is your home folder, `/`, or outside git. The panel says why in
orange (under Draft, or beside Refresh in the header) and offers **Change…**. If `claude` isn't on your shell's PATH, MindControl shows the prompt with a
**Copy Prompt** button instead.

## Where the code lives

Under `macos/Sources/Features/MindControl/`:

- `MindControlModel.swift`: finding the project, loading and reloading it, Change….
- `MindControlPanel.swift`, `PanelFocus.swift`: the panel, empty and error states, keyboard focus.
- `Flow/`: reading, validating and checking `flow.json` (age, ownership, globs, watcher, git).
- `Layout/`: the main layout, Focus layouts, arrow routing, `layout.json`.
- `Map/`: interaction state (`MapController`), header, feature bar, search box, side panel.
- `Renderer/`: Metal drawing, pan and zoom, hit testing, bloom.
- `Labels/`: text labels over the map and where they go.
- `Search/`: the search index and ranking.
- `Claude/`: the Draft and Refresh prompts, launching `claude`, opening files.
- `Data/`: the source file list and Swift type names.

The sidebar (`Features/Extensions/`) hosts the panel. `Ghostty/Surface View/SurfaceView_AppKit.swift`
keeps a terminal from taking clicks meant for the panel layered over it.

## Running the tests

Tests are in `macos/Tests/MindControl/`. Run one suite with `macos/skins-test.sh FlowLayoutTests`, or
everything with `macos/skins-test.sh`. The full log is `macos/build/last-test.log`.
