# MindControl

A 3D map of the project your terminal is in.

Click the codebase visualizer icon in the extensions sidebar on the right edge of a Lostty window.
The map fills the terminal area beside the sidebar and draws the project of the focused terminal's working directory: the git repository it belongs to
(respecting `.gitignore`), or the directory itself outside git. Folders and files are nodes; signals
travel along the branches.

- **Lines:** thin blue-grey lines mean a folder contains a file; amber curves mean one file uses
  another (imports in Zig, TypeScript/JavaScript and Python; type references in Swift; links in
  Markdown). Signals travel along amber curves toward the file being used.
- **Labels:** folder names are always shown; file names fade in as you zoom close.
- **Inspect:** hover a node to light it and everything it connects to; click to pin it and see its
  path and how many files it uses and is used by. Esc unpins; Esc again closes.
- **Orbit:** drag. **Zoom:** scroll or pinch.
- Large projects are capped at 10,000 files, keeping the shallowest ones; the status line says when.
- Nothing is drawn while the visualizer is closed.

Code lives in `macos/Sources/Features/MindControl/`: `Data/` (scanner, layout, graph model),
`Renderer/` (Metal: instanced nodes and edges, GPU signals, HDR bloom, filmic composite), and the
panel view. The sidebar (`Features/Extensions/`) hosts it; `ExtensionSidebarModel` owns its state. Tests are in `macos/Tests/MindControl/`; run them with `macos/skins-test.sh`.
