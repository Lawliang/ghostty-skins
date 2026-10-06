# Lostty MindControl Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a right-edge tab to Lostty's terminal window that expands into a full-size Metal "synaptic" 3D map of the focused terminal's project.

**Architecture:** Port the MindControl renderer (GraphBuffers → Metal instance buffers → HDR pass → bloom → composite) into `macos/Sources/Features/MindControl/` under an `enum MindControl` namespace. New data layer: `ProjectScanner` (git ls-files / directory walk → `FileTree`) → `TreeLayout` (`FileTree` → positioned `Graph`) → `MindControl.Model` (async scan, per-root cache). UI: `MindControl.Drawer` (tab + sliding panel) added as a layer in `TerminalView`'s `ZStack`.

**Tech Stack:** Swift 5 language mode (Ghostty target), SwiftUI + AppKit, MetalKit, Metal Shading Language, Swift Testing, macOS 13+.

**Spec:** `docs/superpowers/specs/2026-10-06-lostty-mindcontrol-design.md`

## Global Constraints

- All work in worktree `~/projectrepos/lostty/.claude/worktrees/mindcontrol`, branch `mindcontrol`. Never touch the main checkout's `skins` branch or its uncommitted files.
- App target: Swift 5.0, `MACOSX_DEPLOYMENT_TARGET = 13.0` — no macOS 14+ APIs (`UnevenRoundedRectangle`, `onKeyPress`, two-parameter `onChange`).
- Swift types nested in `enum MindControl`; C structs/macros prefixed `MC`/`MC_`; Metal entry points prefixed `mc`.
- Only two edits to existing Lostty files: `Sources/App/macOS/ghostty-bridging-header.h` (one import) and `Sources/Features/Terminal/TerminalView.swift` (one drawer layer).
- File cap 10,000; skip list for non-git walks: `node_modules, .build, zig-out, zig-cache, .zig-cache, DerivedData, build, dist, vendor, Pods, target`; max walk depth 12; document extensions `md, markdown, txt, rst, adoc, org, pdf`.
- Tests: `macos/skins-test.sh <Suite>` (prints failures; non-zero exit on failure). Swift tests follow the repo's style: `#if os(macOS)`, `import Testing`, `@testable import Ghostty`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Plan-level refinements to the spec

Task 6 folds these into the spec.

- **Rescan trigger:** the panel covers the terminal while open, so focus can't move to another split; the model scans on open only (spec §6.3's "rescan when focus changes while open" cannot occur). Read pwd from `lastFocusedSurface?.value?.pwd` at open time — `@FocusedValue` pwd goes nil once the Metal view takes focus.
- **Zero GPU while closed:** the panel (and its `MTKView`) is removed from the hierarchy on close rather than paused; the per-window `Model` keeps the scan cache. Same outcome as spec §5's `isPaused`, less state.
- **Esc:** handled by the Metal view; the Metal view is always present when the renderer starts (empty graph shows background + message), so Esc works in empty/error states too. If Metal itself fails, only the tab closes the panel.
- **Namespace file:** `MindControl.swift` declares `enum MindControl {}`.
- **swiftlint** is not installed on this machine; lint steps run only if `command -v swiftlint` succeeds.

## Review Focus

1. **Huge repo or `$HOME` as pwd** — scan must stay off the main thread and the cap must hold; user expects a truncated map, not a beachball. Pinned by `ProjectScannerTests.capKeepsShallowFilesFirst` and the async path in `ModelTests`.
2. **Terminal with no reported pwd** (shell integration off, fresh window) — panel shows a message, no crash. Pinned by `ModelTests.nilPwdIsNoProject`.
3. **Focus after close** — typing must go to the terminal immediately after the panel closes. Manual check in Task 5 (UI focus is not unit-testable here).
4. **pwd deleted / unreadable** — `.failed` with a readable message. Pinned by `ProjectScannerTests.missingDirectoryThrows` and `ModelTests.failurePublishesMessage`.
5. **git repo where git fails** (corrupt repo, `git` missing) — falls back to walking. Pinned by `ProjectScannerTests.brokenGitFallsBackToWalk`.

## File Map

```
macos/Sources/App/macOS/ghostty-bridging-header.h            modify: import MindControl ShaderTypes.h
macos/Sources/Features/Terminal/TerminalView.swift           modify: add MindControl.Drawer layer
macos/Sources/Features/MindControl/
  MindControl.swift                                           create: namespace
  MindControlModel.swift                                      create (Task 4)
  MindControlPanel.swift                                      create (Task 5)
  MindControlDrawer.swift                                     create (Task 5)
  Data/Graph.swift, Data/Graph+Stress.swift                   port (Task 1)
  Data/ProjectScanner.swift                                   create (Task 2)
  Data/TreeLayout.swift                                       create (Task 3)
  Renderer/ShaderTypes.h, GraphBuffers.swift, OrbitCamera.swift, Pipelines.swift,
  Renderer/BloomPass.swift, Renderer.swift, MetalGraphView.swift            port (Task 1)
  Renderer/MatrixMath.swift                                   create (Task 1)
  Renderer/Shaders/ShaderCommon.h + Dust/Edges/Signals/Nodes/Bloom/Composite.metal   port (Task 1)
macos/Tests/MindControl/
  GraphBuffersTests, OrbitCameraTests, StressGraphTests, RendererTests, BloomPassTests   port (Task 1)
  ProjectScannerTests (Task 2), TreeLayoutTests (Task 3), ModelTests (Task 4)
MINDCONTROL.md                                                create (Task 6)
```

Port sources: the standalone repo's working tree `~/projectrepos/MindControl` (branch `feat/initial-scaffold`, including its uncommitted bloom files) and, for `Signals.metal`, its plan `docs/superpowers/plans/2026-10-06-metal-synaptic-renderer.md` (Task 6 Step 3). Read them; do not modify that repo.

---

### Task 1: Port the renderer, data model, and their tests

**Files:** everything marked "port" plus `MindControl.swift`, `Renderer/MatrixMath.swift`, the bridging-header import.

**Interfaces:**
- Produces (all nested in `MindControl`): `Graph`, `GraphNode`, `GraphEdge`, `NodeKind` (`.root/.folder/.source/.document`), `Graph.sample`, `Graph.stress(nodeCount:seed:)`, `SplitMix64`, `GraphBuffers`, `NodeStyle`, `StableHash`, `Matrix.lookAt/perspective`, `OrbitCamera`, `Pipelines`, `BloomPass`, `RendererError`, `Renderer` (`init(device:) throws`, `setGraph(_:)`, `encodeFrame(into:output:width:height:pixelScale:time:)`, `bloomStrength`, `signalsEnabled`, `camera`), `GraphMTKView`, `MetalGraphView(renderer:)`.
- C (global): `MCNodeInstance`, `MCEdgeInstance`, `MCFrameUniforms`, `MCBloomUniforms`, `MCCompositeUniforms`, `MC_BUFFER_INSTANCES/NODES/FRAME`.

- [ ] **Step 1: Link the prebuilt xcframework into the worktree**

The worktree has no `GhosttyKit.xcframework` (git-ignored by `macos/.gitignore:/*.xcframework`). Symlink the main checkout's:

```bash
cd ~/projectrepos/lostty/.claude/worktrees/mindcontrol/macos
ln -s ../../../../macos/GhosttyKit.xcframework GhosttyKit.xcframework
git check-ignore -q GhosttyKit.xcframework && echo ignored
./skins-test.sh AutoSkinTests
```
Expected: `ignored`, then `✔ Test run with … passed` and `** TEST SUCCEEDED **` (baseline: the worktree builds and tests run).

- [ ] **Step 2: Write the port script** — save as `.superpowers/port.py` (scratch; `.superpowers/` must be git-ignored — add `.superpowers/` to the repo root `.gitignore` in this step if `git check-ignore .superpowers` fails, and include that in the Task 1 commit)

```python
#!/usr/bin/env python3
"""Ports MindControl sources into Lostty under the MindControl namespace. Run from the worktree root."""
import os, re, subprocess, sys

SRC = os.path.expanduser("~/projectrepos/MindControl")
SRC_PLAN = os.path.join(SRC, "docs/superpowers/plans/2026-10-06-metal-synaptic-renderer.md")
DST = "macos/Sources/Features/MindControl"
TST = "macos/Tests/MindControl"

C_TYPES = r"\b(NodeInstance|EdgeInstance|FrameUniforms|BloomUniforms|CompositeUniforms)\b"
METAL_FUNCS = ("dustVertex|dustFragment|edgeVertex|edgeFragment|signalVertex|signalFragment|"
               "nodeVertex|nodeFragment|fullscreenVertex|compositeFragment|bloomPrefilter|"
               "bloomDownsample|bloomUpsample")

def read(p): return open(p).read()
def write(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(s)

def plan_block(marker, nth=1):
    lines = read(SRC_PLAN).split("\n")
    i = next(k for k, l in enumerate(lines) if marker in l)
    count = 0
    while i < len(lines):
        if lines[i].startswith("```") and len(lines[i]) > 3:
            count += 1
            j = i + 1
            while lines[j] != "```": j += 1
            if count == nth: return "\n".join(lines[i + 1:j]) + "\n"
            i = j
        i += 1
    sys.exit(f"block not found: {marker}")

def rename_c(s):
    s = re.sub(C_TYPES, r"MC\1", s)
    s = re.sub(r"\bBUFFER_(INSTANCES|NODES|FRAME)\b", r"MC_BUFFER_\1", s)
    s = re.sub(r"\bSHADER_(TYPES|COMMON)_H\b", r"MC_SHADER_\1_H", s)
    return s

def rename_metal_funcs(s, quoted_only):
    pat = (r'"(%s)"' if quoted_only else r"\b(%s)\b") % METAL_FUNCS
    rep = (lambda m: '"mc' + m.group(1)[0].upper() + m.group(1)[1:] + '"') if quoted_only \
        else (lambda m: "mc" + m.group(1)[0].upper() + m.group(1)[1:])
    return re.sub(pat, rep, s)

def namespace_swift(s):
    """Wraps top-level declarations in `extension MindControl { }`; rewrites
    top-level `extension X {` to `extension MindControl.X {`."""
    lines = s.rstrip("\n").split("\n")
    head = []
    while lines and (lines[0].startswith("import ") or lines[0].strip() == ""):
        head.append(lines.pop(0))
    out, wrapped, in_ext = [], [], False
    def flush():
        while wrapped and wrapped[-1].strip() == "": wrapped.pop()
        while wrapped and wrapped[0].strip() == "": wrapped.pop(0)
        if wrapped:
            out.append("extension MindControl {")
            out.extend(("    " + l) if l.strip() else "" for l in wrapped)
            out.append("}")
            out.append("")
        wrapped.clear()
    for l in lines:
        if not in_ext and re.match(r"extension (\w+)", l):
            flush()
            out.append(re.sub(r"^extension (\w+)", r"extension MindControl.\1", l))
            in_ext = True
        elif in_ext:
            out.append(l)
            if l == "}":
                in_ext = False
                out.append("")
        else:
            wrapped.append(l)
    flush()
    return "\n".join(head).rstrip("\n") + "\n\n" + "\n".join(out).rstrip("\n") + "\n"

TEST_ALIASES = """
private typealias Graph = MindControl.Graph
private typealias GraphNode = MindControl.GraphNode
private typealias GraphEdge = MindControl.GraphEdge
private typealias NodeKind = MindControl.NodeKind
private typealias GraphBuffers = MindControl.GraphBuffers
private typealias NodeStyle = MindControl.NodeStyle
private typealias OrbitCamera = MindControl.OrbitCamera
private typealias Renderer = MindControl.Renderer
private typealias BloomPass = MindControl.BloomPass
"""

def port_test(s):
    s = s.replace("@testable import MindControl", "@testable import Ghostty")
    lines = s.split("\n")
    last_import = max(i for i, l in enumerate(lines) if l.startswith("import ") or l.startswith("@testable import"))
    lines.insert(last_import + 1, TEST_ALIASES.rstrip("\n"))
    return "#if os(macOS)\n" + "\n".join(lines).rstrip("\n") + "\n#endif\n"

# --- Swift sources
for rel, dst in [("MindControl/Graph/Graph.swift", "Data/Graph.swift"),
                 ("MindControl/Graph/Graph+Stress.swift", "Data/Graph+Stress.swift"),
                 ("MindControl/Renderer/GraphBuffers.swift", "Renderer/GraphBuffers.swift"),
                 ("MindControl/Renderer/OrbitCamera.swift", "Renderer/OrbitCamera.swift"),
                 ("MindControl/Renderer/Pipelines.swift", "Renderer/Pipelines.swift"),
                 ("MindControl/Renderer/BloomPass.swift", "Renderer/BloomPass.swift"),
                 ("MindControl/Renderer/Renderer.swift", "Renderer/Renderer.swift"),
                 ("MindControl/Renderer/MetalGraphView.swift", "Renderer/MetalGraphView.swift")]:
    s = read(os.path.join(SRC, rel))
    s = rename_c(s)
    if dst.endswith("Pipelines.swift"): s = rename_metal_funcs(s, quoted_only=True)
    if dst.endswith("OrbitCamera.swift"):
        s = s.replace(".lookAt(", "Matrix.lookAt(").replace(".perspective(", "Matrix.perspective(")
    if dst.endswith("BloomPass.swift"):
        s = s.replace("    static let levelCount = 5", "    nonisolated static let levelCount = 5")
    write(os.path.join(DST, dst), namespace_swift(s))

# --- C / Metal sources
write(os.path.join(DST, "Renderer/ShaderTypes.h"), rename_c(read(os.path.join(SRC, "MindControl/Renderer/ShaderTypes.h"))))
shader_dir = os.path.join(SRC, "MindControl/Renderer/Shaders")
for name in sorted(os.listdir(shader_dir)):
    s = rename_metal_funcs(rename_c(read(os.path.join(shader_dir, name))), quoted_only=False)
    write(os.path.join(DST, "Renderer/Shaders", name), s)
signals = plan_block("Step 3: Create `MindControl/Renderer/Shaders/Signals.metal`")
write(os.path.join(DST, "Renderer/Shaders/Signals.metal"), rename_metal_funcs(rename_c(signals), quoted_only=False))

# --- Tests
for name in ["GraphBuffersTests", "OrbitCameraTests", "StressGraphTests", "RendererTests", "BloomPassTests"]:
    write(os.path.join(TST, name + ".swift"), port_test(read(os.path.join(SRC, "MindControlTests", name + ".swift"))))
print("ported")
```

- [ ] **Step 3: Run the port, then add the signals test and signal drawing**

```bash
cd ~/projectrepos/lostty/.claude/worktrees/mindcontrol
python3 -I .superpowers/port.py
```
Expected: `ported`.

Append to `macos/Tests/MindControl/RendererTests.swift`, inside `struct RendererTests` (before its closing `}`):

```swift
    @Test func signalsAddLight() throws {
        let renderer = try Renderer()
        renderer.setGraph(.stress(nodeCount: 400))
        renderer.bloomStrength = 0
        renderer.signalsEnabled = false
        let off = try renderAverage(using: renderer)
        renderer.signalsEnabled = true
        let on = try renderAverage(using: renderer)
        #expect(on > off)
    }
```

- [ ] **Step 4: Create the namespace and matrix files**

`macos/Sources/Features/MindControl/MindControl.swift`:

```swift
/// Namespace for the MindControl project map: a 3D graph of the focused terminal's project.
enum MindControl {}
```

`macos/Sources/Features/MindControl/Renderer/MatrixMath.swift`:

```swift
import simd

extension MindControl {
    enum Matrix {
        /// Right-handed view matrix looking from `eye` toward `target`.
        static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
            let f = simd_normalize(target - eye)
            let s = simd_normalize(simd_cross(f, up))
            let u = simd_cross(s, f)
            return simd_float4x4(columns: (
                SIMD4(s.x, u.x, -f.x, 0),
                SIMD4(s.y, u.y, -f.y, 0),
                SIMD4(s.z, u.z, -f.z, 0),
                SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
            ))
        }

        /// Right-handed perspective projection with Metal's [0, 1] clip-space depth.
        static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
            let y = 1 / tan(fovY * 0.5)
            let x = y / aspect
            let z = far / (near - far)
            return simd_float4x4(columns: (
                SIMD4(x, 0, 0, 0),
                SIMD4(0, y, 0, 0),
                SIMD4(0, 0, z, -1),
                SIMD4(0, 0, z * near, 0)
            ))
        }
    }
}
```

- [ ] **Step 5: Run the ported tests to watch them fail**

```bash
cd macos && ./skins-test.sh GraphBuffersTests; cd ..
```
Expected: FAIL with compile errors about `MCNodeInstance` (bridging header not yet importing `ShaderTypes.h`) and missing signals pipeline members (`signalsEnabled`).

- [ ] **Step 6: Bridging-header import**

Append to `macos/Sources/App/macOS/ghostty-bridging-header.h`:

```c
#import "../../Features/MindControl/Renderer/ShaderTypes.h"
```

- [ ] **Step 7: Wire signals into the ported Pipelines and Renderer**

In `Renderer/Pipelines.swift`, add after `let edges: MTLRenderPipelineState`:

```swift
        let signals: MTLRenderPipelineState
```

and after the `edges = try make(...)` line:

```swift
            signals = try make("mcSignalVertex", "mcSignalFragment", format: hdr, additive: true)
```

In `Renderer/Renderer.swift`, add after `var bloomStrength: Float = 0.22`:

```swift
        var signalsEnabled = true
```

and in `encodeScene`, directly after the edge pass's `drawPrimitives(... instanceCount: edgeCount)` line:

```swift
                if signalsEnabled {
                    encoder.setRenderPipelineState(pipelines.signals)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: edgeCount)
                }
```

(Indentation is one level deeper than in the source repo because of the namespace wrapper.)

- [ ] **Step 8: Run every ported suite**

```bash
cd macos
for s in GraphBuffersTests OrbitCameraTests StressGraphTests BloomPassTests RendererTests; do ./skins-test.sh $s; done
cd ..
```
Expected: each prints `** TEST SUCCEEDED **` — GraphBuffers 8, OrbitCamera 12, StressGraph 4 (one parameterised), BloomPass 3, Renderer 7 tests.

If a ported test fails, debug the port (names, namespace, isolation) — never edit expectations. Known risk: `Bundle(for: Renderer.self)` must resolve to the app bundle that contains `default.metallib`; if `makeDefaultLibrary(bundle:)` throws, check that the `.metal` files are members of the `Ghostty` target (synchronized `Sources` group) and that the app product contains `Contents/Resources/default.metallib`.

- [ ] **Step 9: Lint (if available) and commit**

```bash
command -v swiftlint >/dev/null && (cd macos && swiftlint lint --strict --fix Sources/Features/MindControl Tests/MindControl)
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl macos/Sources/App/macOS/ghostty-bridging-header.h .gitignore
git commit -m "mindcontrol: port Metal synaptic renderer and graph model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: ProjectScanner

**Files:**
- Create: `macos/Sources/Features/MindControl/Data/ProjectScanner.swift`
- Test: `macos/Tests/MindControl/ProjectScannerTests.swift`

**Interfaces:**
- Consumes: `ProjectResolver.gitRoot(of: String) -> String?` (existing, Skins).
- Produces: `MindControl.FileTree { rootName: String; rootPath: String; files: [String] (relative, "/"-separated, sorted); totalFileCount: Int; truncated: Bool }` (`Equatable, Sendable`); `MindControl.ScanError.noDirectory(String)`; `MindControl.ProjectScanner { var fileCap: Int; static let defaultFileCap = 10_000; static func projectRoot(for: URL) -> URL; func scan(pwd: URL) throws -> FileTree }`.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/ProjectScannerTests.swift`

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias ProjectScanner = MindControl.ProjectScanner
private typealias ScanError = MindControl.ScanError

struct ProjectScannerTests {
    /// A fresh temporary directory, removed when the test ends.
    private final class TempDir {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("mc-scan-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }

        func file(_ path: String) throws {
            let target = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: target)
        }

        @discardableResult
        func git(_ args: String...) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", url.path] + args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
    }

    @Test func gitRepoRespectsIgnoreAndIncludesUntracked() throws {
        let dir = try TempDir()
        try dir.git("init", "-q")
        try dir.file(".gitignore")
        try Data("ignored/\n*.log\n".utf8).write(to: dir.url.appendingPathComponent(".gitignore"))
        try dir.file("src/main.swift")
        try dir.file("README.md")
        try dir.file("ignored/secret.txt")
        try dir.file("debug.log")
        try dir.git("add", "src/main.swift", ".gitignore")
        let tree = try ProjectScanner().scan(pwd: dir.url)
        #expect(tree.files == [".gitignore", "README.md", "src/main.swift"])
        #expect(tree.totalFileCount == 3)
        #expect(!tree.truncated)
    }

    @Test func subfolderPwdResolvesToGitRoot() throws {
        let dir = try TempDir()
        try dir.git("init", "-q")
        try dir.file("top.txt")
        try dir.file("deep/inner/file.swift")
        let tree = try ProjectScanner().scan(pwd: dir.url.appendingPathComponent("deep/inner"))
        #expect(tree.rootName == dir.url.lastPathComponent)
        #expect(tree.files.contains("top.txt"))
    }

    @Test func plainDirectoryHonoursSkipList() throws {
        let dir = try TempDir()
        try dir.file("app/main.zig")
        try dir.file("node_modules/pkg/index.js")
        try dir.file("zig-out/bin/app")
        try dir.file(".hidden/config")
        try dir.file(".env")
        let tree = try ProjectScanner().scan(pwd: dir.url)
        #expect(tree.files == ["app/main.zig"])
    }

    @Test func plainDirectoryStopsAtMaxDepth() throws {
        let dir = try TempDir()
        let deep = (1...14).map { "d\($0)" }.joined(separator: "/")
        try dir.file(deep + "/too-deep.txt")
        try dir.file("d1/shallow.txt")
        let tree = try ProjectScanner().scan(pwd: dir.url)
        #expect(tree.files == ["d1/shallow.txt"])
    }

    @Test func capKeepsShallowFilesFirst() throws {
        let dir = try TempDir()
        try dir.file("z-top.txt")
        for i in 0..<5 { try dir.file("a/b/deep\(i).txt") }
        var scanner = ProjectScanner()
        scanner.fileCap = 3
        let tree = try scanner.scan(pwd: dir.url)
        #expect(tree.files.count == 3)
        #expect(tree.files.contains("z-top.txt"))
        #expect(tree.totalFileCount == 6)
        #expect(tree.truncated)
    }

    @Test func brokenGitFallsBackToWalk() throws {
        let dir = try TempDir()
        try dir.file(".git")          // a `.git` file that isn't a valid gitdir pointer
        try dir.file("main.c")
        let tree = try ProjectScanner().scan(pwd: dir.url)
        #expect(tree.files == ["main.c"])
    }

    @Test func missingDirectoryThrows() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(throws: ScanError.noDirectory(missing.path)) {
            try ProjectScanner().scan(pwd: missing)
        }
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure**

Run: `cd macos && ./skins-test.sh ProjectScannerTests; cd ..`
Expected: FAIL, `cannot find type 'ProjectScanner' in scope` (via the typealias).

- [ ] **Step 3: Implement `macos/Sources/Features/MindControl/Data/ProjectScanner.swift`**

```swift
import Foundation

extension MindControl {
    /// A project's files as sorted, "/"-separated paths relative to the root.
    struct FileTree: Equatable, Sendable {
        let rootName: String
        let rootPath: String
        let files: [String]
        /// Files found before the cap was applied.
        let totalFileCount: Int

        var truncated: Bool { files.count < totalFileCount }
    }

    enum ScanError: Error, Equatable {
        case noDirectory(String)
    }

    /// Lists the files of the project containing a working directory.
    struct ProjectScanner {
        static let defaultFileCap = 10_000
        static let maxWalkDepth = 12
        static let skippedDirectories: Set<String> = [
            "node_modules", ".build", "zig-out", "zig-cache", ".zig-cache",
            "DerivedData", "build", "dist", "vendor", "Pods", "target",
        ]

        var fileCap = ProjectScanner.defaultFileCap

        /// The git root containing `pwd`, or `pwd` itself outside git.
        static func projectRoot(for pwd: URL) -> URL {
            if let root = ProjectResolver.gitRoot(of: pwd.path) {
                return URL(fileURLWithPath: root)
            }
            return pwd
        }

        func scan(pwd: URL) throws -> FileTree {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: pwd.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ScanError.noDirectory(pwd.path)
            }

            let root = Self.projectRoot(for: pwd)
            let isGit = ProjectResolver.gitRoot(of: pwd.path) != nil
            let all = (isGit ? try? Self.gitFiles(root: root) : nil) ?? Self.walk(root: root)

            // Over the cap, keep the shallowest files so the top-level structure survives.
            let kept = all.count <= fileCap ? all : Array(all.sorted { a, b in
                let da = a.split(separator: "/").count, db = b.split(separator: "/").count
                return da != db ? da < db : a < b
            }.prefix(fileCap))

            return FileTree(rootName: root.lastPathComponent, rootPath: root.path, files: kept.sorted(), totalFileCount: all.count)
        }

        /// Tracked plus untracked-but-not-ignored files.
        private static func gitFiles(root: URL) throws -> [String] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            // Read before waiting so a large listing can't fill the pipe and deadlock.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ScanError.noDirectory(root.path) }
            return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
        }

        private static func walk(root: URL) -> [String] {
            guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }
            var files: [String] = []
            while let relative = enumerator.nextObject() as? String {
                let name = (relative as NSString).lastPathComponent
                let isDirectory = (enumerator.fileAttributes?[.type] as? FileAttributeType) == .typeDirectory
                if name.hasPrefix(".") {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
                if isDirectory {
                    if skippedDirectories.contains(name) || enumerator.level >= maxWalkDepth {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                files.append(relative)
            }
            return files
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd macos && ./skins-test.sh ProjectScannerTests; cd ..`
Expected: 7 tests PASS. If `plainDirectoryStopsAtMaxDepth` keeps the deep file, check `enumerator.level` semantics (level of the item just returned: 1 for top-level entries) and adjust the comparison, not the test.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/Data/ProjectScanner.swift macos/Tests/MindControl/ProjectScannerTests.swift
git commit -m "mindcontrol: scan the focused terminal's project files

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: TreeLayout

**Files:**
- Create: `macos/Sources/Features/MindControl/Data/TreeLayout.swift`
- Test: `macos/Tests/MindControl/TreeLayoutTests.swift`

**Interfaces:**
- Consumes: `FileTree` (Task 2); `Graph`, `GraphNode`, `GraphEdge`, `NodeKind` (Task 1).
- Produces: `MindControl.TreeLayout.graph(for: FileTree) -> Graph`, `TreeLayout.documentExtensions: Set<String>`, `TreeLayout.rootID = "."`. Node IDs are relative paths (folders without trailing slash); labels are last path components.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/TreeLayoutTests.swift`

```swift
#if os(macOS)
import Foundation
import Testing
import simd
@testable import Ghostty

private typealias TreeLayout = MindControl.TreeLayout
private typealias FileTree = MindControl.FileTree

struct TreeLayoutTests {
    private func tree(_ files: [String]) -> FileTree {
        FileTree(rootName: "proj", rootPath: "/tmp/proj", files: files.sorted(), totalFileCount: files.count)
    }

    private let sample = [
        "README.md", "Package.swift", "docs/guide.MD", "docs/notes.txt",
        "src/app/main.swift", "src/app/view.swift", "src/core/model.swift", "src/core/store.swift",
        "src/core/net/client.swift", "tests/model_tests.swift", "assets/logo.pdf",
    ]

    @Test func createsFolderNodes() {
        let graph = TreeLayout.graph(for: tree(["a/b/c.swift"]))
        #expect(Set(graph.nodes.map(\.id)) == [TreeLayout.rootID, "a", "a/b", "a/b/c.swift"])
        #expect(graph.nodes.first { $0.id == "a/b" }?.label == "b")
    }

    @Test func kindsByExtension() {
        let graph = TreeLayout.graph(for: tree(sample))
        let kind = { (id: String) in graph.nodes.first { $0.id == id }?.kind }
        #expect(kind(TreeLayout.rootID) == .root)
        #expect(kind("src") == .folder)
        #expect(kind("README.md") == .document)
        #expect(kind("docs/guide.MD") == .document)
        #expect(kind("assets/logo.pdf") == .document)
        #expect(kind("src/app/main.swift") == .source)
    }

    @Test func oneParentEdgePerNode() {
        let graph = TreeLayout.graph(for: tree(sample))
        #expect(graph.edges.count == graph.nodes.count - 1)
        let targets = graph.edges.map(\.to)
        #expect(Set(targets).count == targets.count)
        #expect(!targets.contains(TreeLayout.rootID))
        #expect(graph.edges.contains { $0.from == "src/core" && $0.to == "src/core/net" })
    }

    @Test func emptyTreeIsJustTheRoot() {
        let graph = TreeLayout.graph(for: tree([]))
        #expect(graph.nodes.map(\.id) == [TreeLayout.rootID])
        #expect(graph.edges.isEmpty)
    }

    @Test func isDeterministic() {
        let a = TreeLayout.graph(for: tree(sample))
        let b = TreeLayout.graph(for: tree(sample))
        #expect(a.nodes.map(\.id) == b.nodes.map(\.id))
        #expect(a.nodes.map(\.position) == b.nodes.map(\.position))
    }

    @Test func positionsAreFiniteAndDistinct() {
        let files = (0..<300).map { "m\($0 % 6)/s\($0 % 4)/f\($0).swift" }
        let graph = TreeLayout.graph(for: tree(files))
        let positions = graph.nodes.map(\.position)
        #expect(positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        var closest = Float.infinity
        for i in positions.indices {
            for j in positions.indices where j > i {
                closest = min(closest, simd_distance(positions[i], positions[j]))
            }
        }
        #expect(closest > 1e-3)
    }

    @Test func rootIsAtOrigin() {
        let graph = TreeLayout.graph(for: tree(sample))
        #expect(graph.nodes.first { $0.id == TreeLayout.rootID }?.position == .zero)
    }

    @Test func tenThousandFilesLayOutQuickly() {
        let files = (0..<10_000).map { "d\($0 % 50)/e\($0 % 7)/f\($0).swift" }
        let input = tree(files)
        let clock = ContinuousClock()
        var graph: MindControl.Graph?
        let elapsed = clock.measure { graph = TreeLayout.graph(for: input) }
        #expect(graph?.nodes.count == 10_000 + 50 + 350 + 1)
        #expect(elapsed < .milliseconds(200))
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure**

Run: `cd macos && ./skins-test.sh TreeLayoutTests; cd ..`
Expected: FAIL, `cannot find type 'TreeLayout'`.

- [ ] **Step 3: Implement `macos/Sources/Features/MindControl/Data/TreeLayout.swift`**

```swift
import Foundation
import simd

extension MindControl {
    /// Places a project's folder tree in 3D: top-level entries on a sphere around the root,
    /// deeper entries on hemispheres that face away from their grandparent so branches grow outward.
    enum TreeLayout {
        static let rootID = "."
        static let documentExtensions: Set<String> = ["md", "markdown", "txt", "rst", "adoc", "org", "pdf"]

        private final class Folder {
            let id: String
            var folders: [String: Folder] = [:]
            var files: [String] = []
            /// Files and folders beneath this folder, used for spacing.
            var size = 0

            init(id: String) { self.id = id }
        }

        private enum Entry {
            case folder(Folder)
            case file(String)

            var weight: Int {
                switch self {
                case .folder(let f): f.size + 1
                case .file: 1
                }
            }
        }

        static func graph(for tree: FileTree) -> Graph {
            let root = Folder(id: rootID)
            for path in tree.files {
                var folder = root
                let parts = path.split(separator: "/").map(String.init)
                for (depth, part) in parts.dropLast().enumerated() {
                    let id = parts[0...depth].joined(separator: "/")
                    if let existing = folder.folders[part] {
                        folder = existing
                    } else {
                        let created = Folder(id: id)
                        folder.folders[part] = created
                        folder = created
                    }
                }
                folder.files.append(path)
            }
            computeSize(root)

            var nodes = [GraphNode(id: rootID, label: tree.rootName, kind: .root, position: .zero)]
            var edges: [GraphEdge] = []
            nodes.reserveCapacity(root.size + 1)
            edges.reserveCapacity(root.size)

            let total = Float(root.size + 1)
            let rootRadius = 4 + 0.35 * total.squareRoot()
            // Largest subtrees first, so the Fibonacci spiral spreads the big folders apart.
            let topLevel = entries(of: root).sorted { $0.weight > $1.weight }
            for (i, entry) in topLevel.enumerated() {
                let direction = fibonacciSphere(index: i, count: topLevel.count)
                place(entry, at: direction * rootRadius, outward: direction, parent: rootID, nodes: &nodes, edges: &edges)
            }
            return Graph(nodes: nodes, edges: edges)
        }

        private static func computeSize(_ folder: Folder) {
            folder.size = folder.files.count
            for child in folder.folders.values {
                computeSize(child)
                folder.size += child.size + 1
            }
        }

        /// Subfolders then files, each sorted by name.
        private static func entries(of folder: Folder) -> [Entry] {
            folder.folders.keys.sorted().map { .folder(folder.folders[$0]!) } + folder.files.sorted().map { .file($0) }
        }

        private static func place(_ entry: Entry, at position: SIMD3<Float>, outward: SIMD3<Float>, parent: String,
                                  nodes: inout [GraphNode], edges: inout [GraphEdge]) {
            switch entry {
            case .file(let path):
                nodes.append(GraphNode(id: path, label: (path as NSString).lastPathComponent, kind: kind(for: path), position: position))
                edges.append(GraphEdge(from: parent, to: path))

            case .folder(let folder):
                nodes.append(GraphNode(id: folder.id, label: (folder.id as NSString).lastPathComponent, kind: .folder, position: position))
                edges.append(GraphEdge(from: parent, to: folder.id))

                let children = entries(of: folder)
                let radius = 1.0 + 0.45 * Float(folder.size).squareRoot()
                for (i, child) in children.enumerated() {
                    let direction = hemisphere(index: i, count: children.count, facing: outward)
                    let distance: Float
                    if case .folder = child { distance = radius * 1.6 } else { distance = radius }
                    place(child, at: position + direction * distance, outward: direction, parent: folder.id, nodes: &nodes, edges: &edges)
                }
            }
        }

        private static func kind(for path: String) -> NodeKind {
            documentExtensions.contains((path as NSString).pathExtension.lowercased()) ? .document : .source
        }

        private static let goldenAngle = Float.pi * (3 - Float(5).squareRoot())

        private static func fibonacciSphere(index: Int, count: Int) -> SIMD3<Float> {
            let y = count == 1 ? 0 : 1 - (Float(index) / Float(count - 1)) * 2
            let r = max(0, 1 - y * y).squareRoot()
            let theta = goldenAngle * Float(index)
            return SIMD3(cos(theta) * r, y, sin(theta) * r)
        }

        /// Unit vectors spread over the hemisphere around `facing`; the first points straight along it.
        private static func hemisphere(index: Int, count: Int, facing: SIMD3<Float>) -> SIMD3<Float> {
            let t = count == 1 ? 0 : Float(index) / Float(count - 1) * 0.95
            let cosTheta = 1 - t
            let sinTheta = max(0, 1 - cosTheta * cosTheta).squareRoot()
            let phi = goldenAngle * Float(index)

            let up = simd_normalize(facing)
            let reference: SIMD3<Float> = abs(up.y) < 0.99 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let tangent = simd_normalize(simd_cross(up, reference))
            let bitangent = simd_cross(up, tangent)
            return simd_normalize(tangent * (sinTheta * cos(phi)) + up * cosTheta + bitangent * (sinTheta * sin(phi)))
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd macos && ./skins-test.sh TreeLayoutTests; cd ..`
Expected: 8 tests PASS. (Debug builds are unoptimised; if only the 200 ms timing test fails, profile `graph(for:)` before relaxing anything — the spec's budget is for the real build, so a Debug-only miss under 2× may be ruled acceptable in the ledger.)

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/Data/TreeLayout.swift macos/Tests/MindControl/TreeLayoutTests.swift
git commit -m "mindcontrol: lay out the project tree in 3D

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: MindControl.Model

**Files:**
- Create: `macos/Sources/Features/MindControl/MindControlModel.swift`
- Test: `macos/Tests/MindControl/ModelTests.swift`

**Interfaces:**
- Consumes: `ProjectScanner`, `FileTree`, `ScanError` (Task 2); `TreeLayout` (Task 3); `Graph` (Task 1).
- Produces: `@MainActor final class MindControl.Model: ObservableObject` with `enum State: Equatable { case idle, scanning, ready(FileTree), noProject, empty(String), failed(String) }`, `@Published private(set) var state`, `private(set) var graph: Graph?`, `@Published private(set) var graphVersion: Int`, `private(set) var loadingTask: Task<Void, Never>?`, `init(scan: @escaping @Sendable (URL) throws -> FileTree = …)`, `func load(pwd: URL?)`.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/ModelTests.swift`

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias Model = MindControl.Model
private typealias FileTree = MindControl.FileTree
private typealias ScanError = MindControl.ScanError

/// Counts scan calls from any thread.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
struct ModelTests {
    private let pwd = URL(fileURLWithPath: "/tmp/mc-model-test")

    private func tree(_ files: [String], total: Int? = nil) -> FileTree {
        FileTree(rootName: "proj", rootPath: "/tmp/mc-model-test", files: files, totalFileCount: total ?? files.count)
    }

    @Test func nilPwdIsNoProject() {
        let model = Model(scan: { _ in Issue.record("must not scan"); throw ScanError.noDirectory("") })
        model.load(pwd: nil)
        #expect(model.state == .noProject)
        #expect(model.graph == nil)
    }

    @Test func successPublishesGraph() async {
        let files = ["a.swift", "src/b.swift"]
        let model = Model(scan: { [files] _ in FileTree(rootName: "proj", rootPath: "/tmp/mc-model-test", files: files, totalFileCount: 2) })
        model.load(pwd: pwd)
        #expect(model.state == .scanning)
        await model.loadingTask?.value
        #expect(model.state == .ready(tree(files)))
        #expect(model.graph?.nodes.count == 4)     // root, a.swift, src, src/b.swift
        #expect(model.graphVersion == 1)
    }

    @Test func emptyProject() async {
        let model = Model(scan: { _ in FileTree(rootName: "proj", rootPath: "/tmp/mc-model-test", files: [], totalFileCount: 0) })
        model.load(pwd: pwd)
        await model.loadingTask?.value
        #expect(model.state == .empty("proj"))
        #expect(model.graph == nil)
    }

    @Test func failurePublishesMessage() async {
        let model = Model(scan: { _ in throw ScanError.noDirectory("/gone") })
        model.load(pwd: pwd)
        await model.loadingTask?.value
        #expect(model.state == .failed("Can't read /gone."))
    }

    @Test func cachedRootSkipsRescan() async {
        let counter = CallCounter()
        let model = Model(scan: { _ in
            counter.increment()
            return FileTree(rootName: "proj", rootPath: "/tmp/mc-model-test", files: ["x.swift"], totalFileCount: 1)
        })
        model.load(pwd: pwd)
        await model.loadingTask?.value
        model.load(pwd: pwd)
        await model.loadingTask?.value
        #expect(counter.count == 1)
        #expect(model.graphVersion == 2)           // cache hit still republishes so the renderer re-frames
        if case .ready = model.state {} else { Issue.record("expected ready, got \(model.state)") }
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure**

Run: `cd macos && ./skins-test.sh ModelTests; cd ..`
Expected: FAIL, `'Model' is not a member type of enum 'Ghostty.MindControl'`.

- [ ] **Step 3: Implement `macos/Sources/Features/MindControl/MindControlModel.swift`**

```swift
import Foundation

extension MindControl {
    /// Scans the focused terminal's project off the main thread and publishes its graph.
    /// One per window; caches graphs by project root.
    @MainActor
    final class Model: ObservableObject {
        enum State: Equatable {
            case idle
            case scanning
            case ready(FileTree)
            case noProject
            case empty(String)
            case failed(String)
        }

        @Published private(set) var state: State = .idle
        /// Bumped whenever `graph` is (re)published, so views can react without Graph being Equatable.
        @Published private(set) var graphVersion = 0
        private(set) var graph: Graph?
        private(set) var loadingTask: Task<Void, Never>?

        private let scan: @Sendable (URL) throws -> FileTree
        private var cache: [String: (tree: FileTree, graph: Graph)] = [:]

        init(scan: @escaping @Sendable (URL) throws -> FileTree = { try ProjectScanner().scan(pwd: $0) }) {
            self.scan = scan
        }

        func load(pwd: URL?) {
            loadingTask?.cancel()
            loadingTask = nil

            guard let pwd else {
                state = .noProject
                publish(nil)
                return
            }

            let key = ProjectScanner.projectRoot(for: pwd).path
            if let hit = cache[key] {
                apply(hit.tree, hit.graph)
                return
            }

            state = .scanning
            let scan = self.scan
            loadingTask = Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) { () -> Result<(FileTree, Graph), Error> in
                    Result {
                        let tree = try scan(pwd)
                        return (tree, TreeLayout.graph(for: tree))
                    }
                }.value
                guard !Task.isCancelled, let self else { return }
                switch result {
                case .success(let (tree, graph)):
                    self.cache[key] = (tree, graph)
                    self.apply(tree, graph)
                case .failure(let error):
                    self.state = .failed(Self.message(for: error))
                    self.publish(nil)
                }
            }
        }

        private func apply(_ tree: FileTree, _ graph: Graph) {
            if tree.files.isEmpty {
                state = .empty(tree.rootName)
                publish(nil)
            } else {
                state = .ready(tree)
                publish(graph)
            }
        }

        private func publish(_ graph: Graph?) {
            self.graph = graph
            graphVersion += 1
        }

        private static func message(for error: Error) -> String {
            if case ScanError.noDirectory(let path) = error { return "Can't read \(path)." }
            return error.localizedDescription
        }
    }
}
```

Note `nilPwdIsNoProject` and `failurePublishesMessage` also bump `graphVersion`; tests don't assert it there, by design (any publish is a redraw).

- [ ] **Step 4: Run tests**

Run: `cd macos && ./skins-test.sh ModelTests; cd ..`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/Features/MindControl/MindControlModel.swift macos/Tests/MindControl/ModelTests.swift
git commit -m "mindcontrol: async project model with per-root cache

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Panel, drawer, and TerminalView wiring

**Files:**
- Create: `macos/Sources/Features/MindControl/MindControlPanel.swift`, `MindControlDrawer.swift`
- Modify: `macos/Sources/Features/MindControl/Renderer/MetalGraphView.swift`, `macos/Sources/Features/Terminal/TerminalView.swift`
- Test: `macos/Tests/MindControl/ModelTests.swift` (panel text)

**Interfaces:**
- Consumes: `Model` (Task 4), `Renderer`, `MetalGraphView`, `GraphMTKView` (Task 1); `Ghostty.SurfaceView.pwd: String?`, `Ghostty.moveFocus(to:)` (existing).
- Produces: `MindControl.Panel(model:onClose:)` with `static func statusText(for: Model.State) -> String?` and `static func centerMessage(for: Model.State) -> String?`; `MindControl.Drawer(pwd: @escaping () -> URL?, onClose: @escaping () -> Void)`; `MetalGraphView(renderer:onEscape:)`.

- [ ] **Step 1: Write the failing panel-text tests** — append inside `struct ModelTests`:

```swift
    @Test func panelTexts() {
        let full = tree(["a.swift", "b.swift"])
        #expect(MindControl.Panel.statusText(for: .ready(full)) == "proj · 2 files")
        let capped = tree(Array(repeating: "x", count: 3), total: 12_345)
        #expect(MindControl.Panel.statusText(for: .ready(capped)) == "proj · showing 3 of 12,345 files")
        #expect(MindControl.Panel.statusText(for: .scanning) == nil)

        #expect(MindControl.Panel.centerMessage(for: .ready(full)) == nil)
        #expect(MindControl.Panel.centerMessage(for: .scanning) == "Mapping project…")
        #expect(MindControl.Panel.centerMessage(for: .noProject) == "This terminal hasn't reported a working directory.")
        #expect(MindControl.Panel.centerMessage(for: .empty("proj")) == "proj has no files to map.")
        #expect(MindControl.Panel.centerMessage(for: .failed("Can't read /x.")) == "Can't read /x.")
    }
```

Run: `cd macos && ./skins-test.sh ModelTests; cd ..`
Expected: FAIL, `'Panel' is not a member type`.

- [ ] **Step 2: Add Esc handling to `Renderer/MetalGraphView.swift`**

Inside `final class GraphMTKView: MTKView` (after `var renderer: Renderer?`):

```swift
        var onEscape: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {   // Escape
                onEscape?()
            } else {
                super.keyDown(with: event)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Take keyboard focus so Esc reaches us while the panel is open.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
```

In `struct MetalGraphView`, add a property after `let renderer: Renderer`:

```swift
        var onEscape: (() -> Void)?
```

in `makeNSView`, after `view.renderer = renderer`:

```swift
            view.onEscape = onEscape
```

and replace the empty `updateNSView` body:

```swift
        func updateNSView(_ view: GraphMTKView, context: Context) {
            view.onEscape = onEscape
        }
```

- [ ] **Step 3: Create `macos/Sources/Features/MindControl/MindControlPanel.swift`**

```swift
import SwiftUI

extension MindControl {
    /// Full-size panel content: the 3D map plus a status line or a centred message.
    struct Panel: View {
        @ObservedObject var model: Model
        let onClose: () -> Void

        @State private var renderer: Renderer?
        @State private var rendererError: String?

        /// Matches the composite pass's outer background so the panel never flashes a different colour.
        private static let background = Color(red: 0.012, green: 0.016, blue: 0.043)
        private static let emptyGraph = Graph(nodes: [], edges: [])

        var body: some View {
            ZStack(alignment: .topLeading) {
                Self.background

                if let renderer {
                    MetalGraphView(renderer: renderer, onEscape: onClose)
                }

                if let message = rendererError ?? Self.centerMessage(for: model.state) {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let status = Self.statusText(for: model.state) {
                    Text(status)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(14)
                }
            }
            .onAppear(perform: startRenderer)
            .onChange(of: model.graphVersion) { _ in
                renderer?.setGraph(model.graph ?? Self.emptyGraph)
            }
        }

        private func startRenderer() {
            guard renderer == nil, rendererError == nil else { return }
            do {
                let renderer = try Renderer()
                renderer.setGraph(model.graph ?? Self.emptyGraph)
                self.renderer = renderer
            } catch RendererError.metalUnavailable {
                rendererError = "MindControl needs Metal, which is unavailable on this Mac."
            } catch {
                rendererError = error.localizedDescription
            }
        }

        static func statusText(for state: Model.State) -> String? {
            guard case .ready(let tree) = state else { return nil }
            if tree.truncated {
                return "\(tree.rootName) · showing \(tree.files.count.formatted()) of \(tree.totalFileCount.formatted()) files"
            }
            return "\(tree.rootName) · \(tree.files.count.formatted()) files"
        }

        static func centerMessage(for state: Model.State) -> String? {
            switch state {
            case .idle, .ready: nil
            case .scanning: "Mapping project…"
            case .noProject: "This terminal hasn't reported a working directory."
            case .empty(let name): "\(name) has no files to map."
            case .failed(let message): message
            }
        }
    }
}
```

(`formatted()` uses the current locale; the test expects `12,345`, which matches en_US — the test host's default. If the test machine's locale differs, pin the test to `tree.totalFileCount.formatted(.number.locale(Locale(identifier: "en_US")))` in both places and ledger it.)

- [ ] **Step 4: Run panel tests**

Run: `cd macos && ./skins-test.sh ModelTests; cd ..`
Expected: 6 tests PASS.

- [ ] **Step 5: Create `macos/Sources/Features/MindControl/MindControlDrawer.swift`**

```swift
import SwiftUI

extension MindControl {
    /// A slim tab on the terminal's right edge; clicking it slides the MindControl panel over the
    /// whole terminal. Placement lives only here so other drawer styles can be tried later.
    struct Drawer: View {
        /// The focused terminal's working directory, read when the drawer opens.
        let pwd: () -> URL?
        /// Hands keyboard focus back to the terminal after closing.
        let onClose: () -> Void

        @StateObject private var model = Model()
        @State private var isOpen = false

        var body: some View {
            HStack(spacing: 0) {
                DrawerTab(isOpen: isOpen, action: toggle)

                if isOpen {
                    Panel(model: model, onClose: toggle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }

        private func toggle() {
            let opening = !isOpen
            if opening { model.load(pwd: pwd()) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                isOpen = opening
            }
            if !opening { onClose() }
        }
    }

    private struct DrawerTab: View {
        static let width: CGFloat = 22
        static let height: CGFloat = 64
        private static let glow = Color(red: 0.45, green: 0.80, blue: 1.0)

        let isOpen: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: isOpen ? "chevron.right" : "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Self.glow)
                    .shadow(color: Self.glow.opacity(0.8), radius: 4)
                    .frame(width: Self.width, height: Self.height)
                    .background(
                        // Round only the leading corners: draw a wider rounded rect and clip its trailing edge.
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                            .padding(.trailing, -8)
                    )
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("MindControl")
        }
    }
}
```

- [ ] **Step 6: Add the drawer to `TerminalView`**

In `macos/Sources/Features/Terminal/TerminalView.swift`, insert directly above the line `// Show update information above all else.`:

```swift
                // MindControl: a tab on the right edge that expands into a project map.
                MindControl.Drawer(
                    pwd: {
                        guard let pwd = lastFocusedSurface?.value?.pwd, !pwd.isEmpty else { return nil }
                        return URL(fileURLWithPath: pwd)
                    },
                    onClose: {
                        if let surface = lastFocusedSurface?.value {
                            Ghostty.moveFocus(to: surface)
                        }
                    })

```

- [ ] **Step 7: Full MindControl suites + Lostty suites still green**

```bash
cd macos && ./skins-test.sh; cd ..
```
Expected: `** TEST SUCCEEDED **` for the whole `GhosttyTests` target (existing Skins/Splits/Terminal suites plus all MindControl suites).

- [ ] **Step 8: Build and run the app; manual check**

```bash
cd macos
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/build" build > build/last-build.log 2>&1; grep -E "error:|\*\* BUILD" build/last-build.log
open build/Debug/*.app
cd ..
```
Expected: `** BUILD SUCCEEDED **`; the debug app opens. Check, in order:
1. Tab visible on the right edge, vertically centred; typing in the terminal works without clicking anything.
2. `cd ~/projectrepos/arca`, click the tab → panel slides in over the whole terminal; status reads `arca · N files`; the map breathes and signals travel.
3. Drag orbits, scroll zooms, pinch zooms.
4. Esc closes; typing goes straight to the terminal (Review Focus 3).
5. Reopen → instant (cached). Click the tab (now a chevron on the panel's left edge) → closes.
6. `cd ~` in a split, focus it, open → truncated status (`showing 10,000 of …`) without a beachball (Review Focus 1).
7. Open a new window whose shell hasn't reported a pwd (if shell integration is off) → message, no crash.

Note any visual issue for Task 6 rather than tuning here.

- [ ] **Step 9: Commit**

```bash
command -v swiftlint >/dev/null && (cd macos && swiftlint lint --strict --fix Sources/Features/MindControl Tests/MindControl)
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl macos/Sources/Features/Terminal/TerminalView.swift
git commit -m "mindcontrol: right-edge drawer that expands into the project map

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Tuning, docs, spec refresh

**Files:**
- Create: `MINDCONTROL.md`
- Modify: `docs/superpowers/specs/2026-10-06-lostty-mindcontrol-design.md`
- Possibly modify (constants only): `Renderer/Renderer.swift` (`bloomStrength`, `exposure`, fog), `Renderer/BloomPass.swift` (`threshold`), shader intensity constants, `Data/TreeLayout.swift` (radius coefficients)

- [ ] **Step 1: Tune on real projects (only if Task 5's check showed a problem)**

- Dense clusters blow out → lower edge intensity in `Edges.metal` (`core * 0.30 + glow * 0.10` → `0.20 / 0.06`), then `bloomStrength`.
- Branches overlap into a blob → raise the TreeLayout child radius coefficient `0.45` → `0.6` and the subfolder multiplier `1.6` → `2.0`.
- Frame rate below refresh at 10k → `kHaloScale` 4.0 → 3.2 in `Nodes.metal`.

After any change: `cd macos && ./skins-test.sh; cd ..` → `** TEST SUCCEEDED **`.

- [ ] **Step 2: Create `MINDCONTROL.md`**

```markdown
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
```

- [ ] **Step 3: Fold the plan refinements into the spec**

In the spec: §5 replace the `isPaused` sentence with "On close the panel and its Metal view are removed (no GPU work); the per-window model keeps the scan cache."; §6.3 replace "or when the focused surface's resolved root changes while open" with "(focus cannot move to another split while the panel covers the terminal)" and add "pwd is read from the last focused surface at open time"; §4 tree: add `MindControl.swift (namespace)`, `Tests/MindControl/ModelTests.swift`; set `Status: Implemented`.

- [ ] **Step 4: Full suite and commit**

```bash
cd macos && ./skins-test.sh; cd ..
git add -A MINDCONTROL.md docs macos/Sources/Features/MindControl
git commit -m "mindcontrol: docs, spec refresh, and tuning from real projects

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected: `** TEST SUCCEEDED **` before the commit.
