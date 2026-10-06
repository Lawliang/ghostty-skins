# MindControl

A 3D map of the project your terminal is in.

Click the small tab on the right edge of a Lostty window. A panel slides in over the terminal and
draws the project of the focused terminal's working directory: the git repository it belongs to
(respecting `.gitignore`), or the directory itself outside git. Folders and files are nodes; signals
travel along the branches.

- **Orbit:** drag. **Zoom:** scroll or pinch. **Close:** Esc or the tab.
- Large projects are capped at 10,000 files, keeping the shallowest ones; the status line says when.
- Nothing is drawn while the panel is closed.

Code lives in `macos/Sources/Features/MindControl/`: `Data/` (scanner, layout, graph model),
`Renderer/` (Metal: instanced nodes and edges, GPU signals, HDR bloom, filmic composite), and the
drawer/panel views. Tests are in `macos/Tests/MindControl/`; run them with `macos/skins-test.sh`.
