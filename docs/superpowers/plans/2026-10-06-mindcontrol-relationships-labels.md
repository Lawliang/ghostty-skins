# MindControl Relationships, Layout, Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MindControl explain a project: file-to-file "uses" relationships drawn distinctly from folder "contains" lines, a layout that separates clusters, and labels with hover/pin inspection.

**Architecture:** The background pipeline becomes `ProjectScanner` → `DependencyScanner` (per-language parsers) → `ConeTreeLayout` → `Relaxation` → `Graph` (edges tagged `.contains`/`.uses`). The renderer splits edges into two buffers: straight neutral hairlines for contains, amber Bézier curves for uses, with signals only on uses. Per-node highlight values drive focus/dim. A CPU projection each frame feeds `Picking` (hover/click) and `LabelPlanner`, whose output a `CATextLayer` overlay draws above the Metal view. `Inspector` holds hover/pin state; the panel shows an info card and a legend.

**Tech Stack:** Swift 5 mode (Ghostty target), SwiftUI + AppKit + QuartzCore, MetalKit, Metal Shading Language, NSRegularExpression, Swift Testing, macOS 13+.

**Spec:** `docs/superpowers/specs/2026-10-06-mindcontrol-relationships-labels-design.md`

## Global Constraints

- Work only in worktree `~/projectrepos/lostty/.claude/worktrees/mindcontrol`, branch `mindcontrol`.
- Swift 5 language mode, `MACOSX_DEPLOYMENT_TARGET = 13.0` — no macOS 14+ APIs.
- Swift types nested in `enum MindControl`; C structs/macros prefixed `MC`/`MC_`; Metal entry points prefixed `mc`.
- `MCNodeInstance` must stay 64 bytes; shared structs live only in `Renderer/ShaderTypes.h`.
- Dependency limits: files > 512 KB skipped; ≤ 40 uses-edges per file; ≤ 30,000 total; Swift names declared in > 3 files skipped.
- Labels: ≤ 150 on screen, never overlapping.
- Tests: `.superpowers/mc-test.sh <Suite> …` (per-suite pass/fail counts; wraps `macos/skins-test.sh`). Full suite: `cd macos && ./skins-test.sh`.
- Test files follow repo style: `#if os(macOS)`, `import Testing`, `@testable import Ghostty`, file-private typealiases for `MindControl.X`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Plan-level refinements to the spec

Task 13 folds these into the spec.

1. **Subfolder distance** is `fileBallRadius(parent files) + 2 + 1.2·√w` (spec: `3 + 1.2·√w`), so a folder's own file ball can't swallow its subfolders.
2. **Relaxation budget** for 10k nodes is < 1.5 s in the Debug test build (spec said 500 ms); Debug is unoptimised, release is several times faster.
3. **Python** also resolves absolute imports beside the importing file (scripts in a folder import siblings that way).
4. **Edges render from two buffers** (contains, uses); `MCEdgeInstance.kind` is still stored.
5. **"Sibling clusters don't overlap"** is tested on sibling folders' file balls.
6. `GraphNode` gains `descendantFiles` (label priority, info card); `GraphBuffers` gains `sourceNodes` (deduped nodes in buffer order).
7. The hover "tooltip" is the focus node's label showing its relative path.

## Review Focus

1. **Swift projects full of common type names** (`View`, `Model`, `Coordinator` in many files) — ambiguity cutoff and caps keep the edge count sane. Pinned by `DependencyScannerTests.ambiguousSwiftNamesAreSkipped` and `capsPerFileAndTotal`.
2. **Binary, non-UTF-8, or huge files with source extensions** — skipped, never crash. Pinned by `DependencyScannerTests.unreadableAndHugeFilesAreSkipped`.
3. **Mouse leaves the view / hovers empty space** — focus clears. Pinned by `InspectorTests.hoverEmptyClearsFocus`; `mouseExited` wiring checked manually.
4. **Project changes while a node is pinned** — inspector resets, no stale index into a new graph. Pinned by `InspectorTests.resetClearsEverything`; Panel wiring checked manually.
5. **Label/projection cost at 10k nodes** every frame on the main thread — budget enforced by `LabelPlannerTests.budgetIsRespected`; frame rate checked manually on Lostty.

## File Map

```
macos/Sources/Features/MindControl/
  Data/Graph.swift                 modify: EdgeKind, GraphEdge.kind, GraphNode.descendantFiles, sample uses-edges
  Data/Graph+Stress.swift          modify: cross-links are .uses
  Data/Parsers/ParserSupport.swift create: regex helpers, path join
  Data/Parsers/ZigImports.swift    create
  Data/Parsers/ScriptImports.swift create
  Data/Parsers/PythonImports.swift create
  Data/Parsers/MarkdownLinks.swift create
  Data/Parsers/SwiftSymbols.swift  create
  Data/DependencyScanner.swift     create
  Data/TreeLayout.swift            modify (T5), delete (T7)
  Data/ConeTreeLayout.swift        create (T7)
  Data/Relaxation.swift            create (T8)
  MindControlModel.swift           modify: dependencies + layout + relaxation in the pipeline
  MindControlPanel.swift           modify: legend, inspector, info card
  MindControlLegend.swift          create (T6)
  Inspection/Inspector.swift       create (T12)
  Inspection/NodeDetails.swift     create (T12)
  Inspection/InfoCard.swift        create (T12)
  Labels/LabelPlanner.swift        create (T11)
  Labels/LabelOverlayView.swift    create (T12)
  Renderer/ShaderTypes.h           modify: MCEdgeInstance.kind, MC_EDGE_*, MC_USES_SEGMENTS, MCNodeInstance.highlight
  Renderer/GraphBuffers.swift      modify: kinds, split buffers, sourceNodes, highlight
  Renderer/Pipelines.swift         modify: containsEdges, usesEdges
  Renderer/Renderer.swift          modify: two edge buffers, focus, camera snapshot, onFrame, node data
  Renderer/Picking.swift           create (T10)
  Renderer/MetalGraphView.swift    modify: tracking, hover/click, label overlay, Esc unpin
  Renderer/Shaders/ShaderCommon.h  modify: usesCurve helper
  Renderer/Shaders/Edges.metal     rewrite: contains + uses
  Renderer/Shaders/Signals.metal   rewrite: curved, uses-only
  Renderer/Shaders/Nodes.metal     modify: highlight
macos/Tests/MindControl/
  GraphBuffersTests, StressGraphTests, RendererTests, ModelTests, DensityTests   modify
  ParserTests, SwiftSymbolsTests, DependencyScannerTests                          create
  TreeLayoutTests → ConeTreeLayoutTests (T7); RelaxationTests (T8)
  PickingTests (T10), LabelPlannerTests (T11), InspectorTests (T12)
MINDCONTROL.md                                                                    modify (T13)
```

Helper used throughout: `.superpowers/mc-test.sh` prints `<Suite>: N passed, M failed` per suite and exits non-zero on any failure. Compile errors show with `grep -E "error:" macos/build/last-test.log | sort -u | head`.

---

# Phase 1 — Relationships

### Task 1: Edge kinds through the model and buffers

**Files:**
- Modify: `Data/Graph.swift`, `Data/Graph+Stress.swift`, `Renderer/ShaderTypes.h`, `Renderer/GraphBuffers.swift`
- Test: `macos/Tests/MindControl/GraphBuffersTests.swift`, `StressGraphTests.swift`

**Interfaces:**
- Produces: `MindControl.EdgeKind { case contains, uses }`; `GraphEdge(from:to:kind: = .contains)`; C `MCEdgeInstance.kind: UInt32`, macros `MC_EDGE_CONTAINS 0`, `MC_EDGE_USES 1`; `GraphBuffers.containsEdges`, `GraphBuffers.usesEdges: [MCEdgeInstance]`. `Graph.sample` cross-links and `Graph.stress` cross-links are `.uses`.

- [ ] **Step 1: Write the failing tests.** Append inside `struct GraphBuffersTests`:

```swift
    @Test func edgesSplitByKind() {
        let graph = Graph(nodes: [node("a"), node("b"), node("c")],
                          edges: [GraphEdge(from: "a", to: "b"), GraphEdge(from: "b", to: "c", kind: .uses)])
        let buffers = GraphBuffers(graph: graph)
        #expect(buffers.edges.count == 2)
        #expect(buffers.containsEdges.count == 1)
        #expect(buffers.usesEdges.count == 1)
        #expect(buffers.usesEdges[0].a == 1 && buffers.usesEdges[0].b == 2)
        #expect(buffers.usesEdges[0].kind == 1)
        #expect(buffers.containsEdges[0].kind == 0)
    }

    @Test func sampleGraphHasUsesEdges() {
        #expect(GraphBuffers(graph: .sample).usesEdges.count == 3)
    }
```

Append inside `struct StressGraphTests`:

```swift
    @Test func crossLinksAreUsesEdges() {
        let g = Graph.stress(nodeCount: 2_000)
        let uses = g.edges.filter { $0.kind == .uses }
        #expect(!uses.isEmpty)
        #expect(uses.allSatisfy { $0.from.hasPrefix("l") && $0.to.hasPrefix("l") })
        #expect(g.edges.filter { $0.kind == .contains }.count == g.nodes.count - 1)
    }
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh GraphBuffersTests StressGraphTests` → compile FAIL (`GraphEdge` has no `kind`).

- [ ] **Step 3: Implement.**

`Data/Graph.swift` — add before `struct GraphEdge` and replace `GraphEdge`:

```swift
    /// What a line between two nodes means.
    enum EdgeKind: Sendable {
        /// A folder contains a file or subfolder.
        case contains
        /// A file uses something defined in another file (import, type reference, link).
        case uses
    }

    struct GraphEdge: Sendable {
        let from: String
        let to: String
        var kind: EdgeKind = .contains
    }
```

In `Graph.sample` (same file) change the three cross-link lines to pass `kind: .uses`:

```swift
        edges.append(MindControl.GraphEdge(from: "Views/0", to: "Graph/1", kind: .uses))
        edges.append(MindControl.GraphEdge(from: "Parsing/2", to: "Graph/0", kind: .uses))
        edges.append(MindControl.GraphEdge(from: "Docs/1", to: "Views/2", kind: .uses))
```

`Data/Graph+Stress.swift` — the cross-link append becomes:

```swift
                    edges.append(MindControl.GraphEdge(from: "l\(a)", to: "l\(b)", kind: .uses))
```

`Renderer/ShaderTypes.h` — add after the `MC_BUFFER_FRAME` define, and extend `MCEdgeInstance`:

```c
#define MC_EDGE_CONTAINS 0
#define MC_EDGE_USES 1
```

```c
typedef struct {
    unsigned int a;
    unsigned int b;
    float signalSeed;      // [0, 1), decides whether and how this edge carries a signal
    unsigned int kind;     // MC_EDGE_CONTAINS or MC_EDGE_USES
} MCEdgeInstance;
```

`Renderer/GraphBuffers.swift` — add properties after `let edges: [MCEdgeInstance]`:

```swift
        /// Folder→child edges, drawn as straight hairlines.
        let containsEdges: [MCEdgeInstance]
        /// File→file dependencies, drawn as curves that carry signals.
        let usesEdges: [MCEdgeInstance]
```

replace the `self.edges = graph.edges.compactMap { … }` statement with:

```swift
            let edges: [MCEdgeInstance] = graph.edges.compactMap { edge in
                guard let a = index[edge.from], let b = index[edge.to], a != b else { return nil }
                let kind = edge.kind == .uses ? UInt32(MC_EDGE_USES) : UInt32(MC_EDGE_CONTAINS)
                return MCEdgeInstance(a: a, b: b, signalSeed: StableHash.unit(edge.from + "\u{1F}" + edge.to), kind: kind)
            }
            self.edges = edges
            self.containsEdges = edges.filter { $0.kind == UInt32(MC_EDGE_CONTAINS) }
            self.usesEdges = edges.filter { $0.kind == UInt32(MC_EDGE_USES) }
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh GraphBuffersTests StressGraphTests RendererTests` → all pass (renderer still draws `buffers.edges`, unchanged).

- [ ] **Step 5: Commit.**

```bash
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl
git commit -m "mindcontrol: tag edges as contains or uses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Import parsers (Zig, TS/JS, Python, Markdown)

**Files:**
- Create: `Data/Parsers/ParserSupport.swift`, `ZigImports.swift`, `ScriptImports.swift`, `PythonImports.swift`, `MarkdownLinks.swift`
- Test: `macos/Tests/MindControl/ParserTests.swift`

**Interfaces:**
- Produces (in `MindControl`): `ParserSupport.regex(_:)`, `.captures(_:in:) -> [String]`, `.join(_ dir: String, _ relative: String) -> String?`, `.directory(of:) -> String`; `ZigImports.specifiers(in:) -> [String]`; `ScriptImports.specifiers(in:) -> [String]` (relative only), `ScriptImports.extensions`; `PythonImports.Import { module: String; names: [String] }`, `PythonImports.imports(in:) -> [Import]`; `MarkdownLinks.targets(in:) -> [String]`.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/ParserTests.swift`

```swift
#if os(macOS)
import Testing
@testable import Ghostty

private typealias ParserSupport = MindControl.ParserSupport
private typealias ZigImports = MindControl.ZigImports
private typealias ScriptImports = MindControl.ScriptImports
private typealias PythonImports = MindControl.PythonImports
private typealias MarkdownLinks = MindControl.MarkdownLinks

struct ParserTests {
    @Test func joinResolvesDotsAndRejectsEscapes() {
        #expect(ParserSupport.join("src/app", "../core/x.zig") == "src/core/x.zig")
        #expect(ParserSupport.join("src", "./a/./b.ts") == "src/a/b.ts")
        #expect(ParserSupport.join("", "a.md") == "a.md")
        #expect(ParserSupport.join("src", "../../outside.zig") == nil)
        #expect(ParserSupport.directory(of: "a/b/c.zig") == "a/b")
        #expect(ParserSupport.directory(of: "c.zig").isEmpty)
    }

    @Test func zigImportsOnlyZigFiles() {
        let source = """
        const std = @import("std");
        const term = @import("terminal/main.zig");
        const x = @import( "../x.zig" );
        // const y = @import("ignored-but-harmless.zig");
        """
        #expect(ZigImports.specifiers(in: source) == ["terminal/main.zig", "../x.zig", "ignored-but-harmless.zig"])
    }

    @Test func scriptImportForms() {
        let source = """
        import React from 'react';
        import { a, b } from "./ab";
        import type { T } from '../types';
        import './side-effect';
        export * from './reexport';
        export { c } from "./c";
        const d = require('./d');
        const e = await import("./lazy");
        import {
          multi,
          line,
        } from './multi';
        """
        #expect(ScriptImports.specifiers(in: source) ==
                ["./ab", "../types", "./side-effect", "./reexport", "./c", "./d", "./lazy", "./multi"])
    }

    @Test func pythonImportForms() {
        let source = """
        import os, sys
        import pkg.sub.mod as m
        from pkg.util import helper, other as o
        from . import sibling
        from ..parent import thing
        from .local.mod import (x, y)
        """
        let imports = PythonImports.imports(in: source)
        #expect(imports.contains(.init(module: "os", names: [])))
        #expect(imports.contains(.init(module: "sys", names: [])))
        #expect(imports.contains(.init(module: "pkg.sub.mod", names: [])))
        #expect(imports.contains(.init(module: "pkg.util", names: ["helper", "other"])))
        #expect(imports.contains(.init(module: ".", names: ["sibling"])))
        #expect(imports.contains(.init(module: "..parent", names: ["thing"])))
        #expect(imports.contains(.init(module: ".local.mod", names: ["x", "y"])))
    }

    @Test func markdownLinkTargets() {
        let source = """
        See [the guide](docs/guide.md#setup) and ![diagram](img/arch.png "Arch").
        External [site](https://example.com), [anchor](#top), [mail](mailto:a@b.c).
        Spaces: [x](<my%20file.md>) and [y](../up.md?raw=1).
        """
        #expect(MarkdownLinks.targets(in: source) == ["docs/guide.md", "img/arch.png", "my file.md", "../up.md"])
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh ParserTests` → compile FAIL (`ParserSupport` not found).

- [ ] **Step 3: Implement.**

`Data/Parsers/ParserSupport.swift`:

```swift
import Foundation

extension MindControl {
    /// Shared helpers for the line/regex based import parsers.
    enum ParserSupport {
        /// Compiles a constant pattern. A bad pattern is a programming error caught by the parser tests.
        static func regex(_ pattern: String) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }

        /// The first participating capture group of every match, in order.
        static func captures(_ regex: NSRegularExpression, in source: String) -> [String] {
            let text = source as NSString
            return regex.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
                for group in 1..<match.numberOfRanges {
                    let range = match.range(at: group)
                    if range.location != NSNotFound { return text.substring(with: range) }
                }
                return nil
            }
        }

        /// Joins a relative path onto a directory, resolving `.` and `..`. Nil if it climbs above the root.
        static func join(_ directory: String, _ relative: String) -> String? {
            var parts = directory.split(separator: "/").map(String.init)
            for part in relative.split(separator: "/") {
                switch part {
                case ".":
                    continue
                case "..":
                    guard !parts.isEmpty else { return nil }
                    parts.removeLast()
                default:
                    parts.append(String(part))
                }
            }
            return parts.joined(separator: "/")
        }

        /// The directory part of a relative path ("" at the root).
        static func directory(of path: String) -> String {
            guard let slash = path.lastIndex(of: "/") else { return "" }
            return String(path[..<slash])
        }
    }
}
```

`Data/Parsers/ZigImports.swift`:

```swift
import Foundation

extension MindControl {
    /// `@import("…zig")` paths. Package imports like `@import("std")` don't end in `.zig` and are ignored.
    enum ZigImports {
        private static let pattern = ParserSupport.regex(#"@import\(\s*"([^"]+\.zig)"\s*\)"#)

        static func specifiers(in source: String) -> [String] {
            ParserSupport.captures(pattern, in: source)
        }
    }
}
```

`Data/Parsers/ScriptImports.swift`:

```swift
import Foundation

extension MindControl {
    /// Relative module specifiers from TypeScript/JavaScript import, export-from, require and dynamic import.
    enum ScriptImports {
        static let extensions = ["ts", "tsx", "js", "jsx", "mjs", "cjs"]

        private static let pattern = ParserSupport.regex(
            #"(?:import|export)\s[^'"`;]*?\sfrom\s*['"]([^'"]+)['"]"# + "|" +
            #"\bimport\s*['"]([^'"]+)['"]"# + "|" +
            #"\brequire\(\s*['"]([^'"]+)['"]\s*\)"# + "|" +
            #"\bimport\(\s*['"]([^'"]+)['"]\s*\)"#)

        static func specifiers(in source: String) -> [String] {
            ParserSupport.captures(pattern, in: source).filter { $0.hasPrefix("./") || $0.hasPrefix("../") }
        }
    }
}
```

`Data/Parsers/PythonImports.swift`:

```swift
import Foundation

extension MindControl {
    /// `import a.b` and `from x import y` statements (single-line forms).
    enum PythonImports {
        struct Import: Equatable {
            /// Dotted module, with leading dots for relative imports ("." alone for `from . import x`).
            let module: String
            /// Names after `import` in a `from` statement; empty for plain `import`.
            let names: [String]
        }

        private static let plain = ParserSupport.regex(#"^[ \t]*import[ \t]+([^\n#]+)"#)
        private static let from = ParserSupport.regex(#"^[ \t]*from[ \t]+(\.*[\w.]*)[ \t]+import[ \t]+\(?([^\n#)]+)"#)

        static func imports(in source: String) -> [Import] {
            let text = source as NSString
            let range = NSRange(location: 0, length: text.length)
            var result: [Import] = []
            for match in plain.matches(in: source, range: range) {
                for part in text.substring(with: match.range(at: 1)).split(separator: ",") {
                    if let module = firstWord(part) { result.append(Import(module: module, names: [])) }
                }
            }
            for match in from.matches(in: source, range: range) {
                let module = text.substring(with: match.range(at: 1))
                let names = text.substring(with: match.range(at: 2)).split(separator: ",").compactMap(firstWord)
                result.append(Import(module: module, names: names))
            }
            return result
        }

        /// "pkg.mod as m" → "pkg.mod".
        private static func firstWord(_ part: Substring) -> String? {
            part.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
        }
    }
}
```

`Data/Parsers/MarkdownLinks.swift`:

```swift
import Foundation

extension MindControl {
    /// Local targets of Markdown links and images (no URLs, anchors-only or mail links).
    enum MarkdownLinks {
        private static let pattern = ParserSupport.regex(#"!?\[[^\]\n]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)"#)

        static func targets(in source: String) -> [String] {
            ParserSupport.captures(pattern, in: source).compactMap { raw in
                guard !raw.contains("://"), !raw.hasPrefix("#"), !raw.hasPrefix("mailto:") else { return nil }
                var target = raw
                if let cut = target.firstIndex(where: { $0 == "#" || $0 == "?" }) {
                    target = String(target[..<cut])
                }
                target = target.removingPercentEncoding ?? target
                return target.isEmpty ? nil : target
            }
        }
    }
}
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh ParserTests` → 5 passed.

- [ ] **Step 5: Commit.**

```bash
git add -A macos/Sources/Features/MindControl/Data/Parsers macos/Tests/MindControl/ParserTests.swift
git commit -m "mindcontrol: import parsers for Zig, TS/JS, Python and Markdown

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Swift symbol parser

**Files:**
- Create: `Data/Parsers/SwiftSymbols.swift`
- Test: `macos/Tests/MindControl/SwiftSymbolsTests.swift`

**Interfaces:**
- Produces: `MindControl.SwiftSymbols.declaredTypes(in:) -> [String]` (non-private `class|struct|enum|protocol|actor|typealias` names, capitalised), `SwiftSymbols.typeLikeIdentifiers(in:) -> Set<String>` (capitalised identifiers outside comments and string literals).

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/SwiftSymbolsTests.swift`

```swift
#if os(macOS)
import Testing
@testable import Ghostty

private typealias SwiftSymbols = MindControl.SwiftSymbols

struct SwiftSymbolsTests {
    @Test func declaredTypesSkipPrivateOnes() {
        let source = """
        import SwiftUI

        public final class Renderer: NSObject {}
        struct GraphBuffers {
            enum Nested { case a }
            private struct Hidden {}
            fileprivate enum AlsoHidden {}
            class func make() {}
        }
        @MainActor
        protocol Drawable {}
        actor Worker {}
        typealias Callback = () -> Void
        extension Renderer {}
        """
        #expect(SwiftSymbols.declaredTypes(in: source) ==
                ["Renderer", "GraphBuffers", "Nested", "Drawable", "Worker", "Callback"])
    }

    @Test func identifiersSkipCommentsAndStrings() {
        let source = """
        let a = GraphBuffers(graph: g) // Renderer in a comment
        /* Block Comment mentions Pipelines /* nested Inner */ still comment */
        let s = "Camera in a string \\" Escaped"
        let multi = \"""
        MultiLine Text
        \"""
        let b: OrbitCamera = .init()
        """
        let ids = SwiftSymbols.typeLikeIdentifiers(in: source)
        #expect(ids.contains("GraphBuffers"))
        #expect(ids.contains("OrbitCamera"))
        #expect(!ids.contains("Renderer"))
        #expect(!ids.contains("Pipelines"))
        #expect(!ids.contains("Inner"))
        #expect(!ids.contains("Camera"))
        #expect(!ids.contains("MultiLine"))
        #expect(!ids.contains("graph"))          // lowercase identifiers aren't type-like
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh SwiftSymbolsTests` → compile FAIL.

- [ ] **Step 3: Implement `Data/Parsers/SwiftSymbols.swift`.**

```swift
import Foundation

extension MindControl {
    /// Swift files don't import each other, so relationships come from type names:
    /// which types a file declares, and which declared types it mentions.
    enum SwiftSymbols {
        private static let declaration = ParserSupport.regex(
            #"^[ \t]*(?:@\w+(?:\([^)\n]*\))?[ \t]+)*"# +
            #"((?:(?:public|internal|open|private|fileprivate|final|indirect|nonisolated)(?:\([^)\n]*\))?[ \t]+)*)"# +
            #"(?:class|struct|enum|protocol|actor|typealias)[ \t]+([A-Z]\w*)"#)

        /// Capitalised type names declared in the file, excluding `private`/`fileprivate` ones.
        static func declaredTypes(in source: String) -> [String] {
            let text = source as NSString
            return declaration.matches(in: source, range: NSRange(location: 0, length: text.length)).compactMap { match in
                let modifiersRange = match.range(at: 1)
                let modifiers = modifiersRange.location == NSNotFound ? "" : text.substring(with: modifiersRange)
                if modifiers.contains("private") { return nil }
                return text.substring(with: match.range(at: 2))
            }
        }

        /// Capitalised identifiers outside comments and string literals.
        static func typeLikeIdentifiers(in source: String) -> Set<String> {
            let bytes = Array(source.utf8)
            let count = bytes.count
            let slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), quote = UInt8(ascii: "\"")
            let backslash = UInt8(ascii: "\\"), newline = UInt8(ascii: "\n")
            var result = Set<String>()
            var i = 0

            func isIdentifierStart(_ b: UInt8) -> Bool { (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 }
            func isIdentifier(_ b: UInt8) -> Bool { isIdentifierStart(b) || (b >= 48 && b <= 57) }

            while i < count {
                let b = bytes[i]
                if b == slash, i + 1 < count, bytes[i + 1] == slash {
                    while i < count, bytes[i] != newline { i += 1 }
                    continue
                }
                if b == slash, i + 1 < count, bytes[i + 1] == star {
                    var depth = 1
                    i += 2
                    while i < count, depth > 0 {
                        if bytes[i] == slash, i + 1 < count, bytes[i + 1] == star {
                            depth += 1; i += 2
                        } else if bytes[i] == star, i + 1 < count, bytes[i + 1] == slash {
                            depth -= 1; i += 2
                        } else {
                            i += 1
                        }
                    }
                    continue
                }
                if b == quote {
                    if i + 2 < count, bytes[i + 1] == quote, bytes[i + 2] == quote {
                        i += 3
                        while i + 2 < count, !(bytes[i] == quote && bytes[i + 1] == quote && bytes[i + 2] == quote) { i += 1 }
                        i += 3
                        continue
                    }
                    i += 1
                    while i < count, bytes[i] != quote, bytes[i] != newline {
                        if bytes[i] == backslash { i += 1 }
                        i += 1
                    }
                    i += 1
                    continue
                }
                if isIdentifierStart(b) {
                    let start = i
                    while i < count, isIdentifier(bytes[i]) { i += 1 }
                    if b >= 65, b <= 90 { result.insert(String(decoding: bytes[start..<i], as: UTF8.self)) }
                    continue
                }
                i += 1
            }
            return result
        }
    }
}
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh SwiftSymbolsTests` → 2 passed.

- [ ] **Step 5: Commit.**

```bash
git add macos/Sources/Features/MindControl/Data/Parsers/SwiftSymbols.swift macos/Tests/MindControl/SwiftSymbolsTests.swift
git commit -m "mindcontrol: Swift type declarations and references

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 4: DependencyScanner

**Files:**
- Create: `Data/DependencyScanner.swift`
- Test: `macos/Tests/MindControl/DependencyScannerTests.swift`

**Interfaces:**
- Consumes: parsers (Tasks 2–3), `FileTree` (existing).
- Produces: `MindControl.Dependency { from: String; to: String }` (`Hashable, Sendable`); `MindControl.DependencyScanner.scan(tree: FileTree, shouldStop: () -> Bool = { Task.isCancelled }) throws -> [Dependency]`; statics `maxFileBytes = 512 * 1024`, `maxPerFile = 40`, `maxTotal = 30_000`, `maxDeclarers = 3`.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/DependencyScannerTests.swift`

```swift
#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias DependencyScanner = MindControl.DependencyScanner
private typealias Dependency = MindControl.Dependency
private typealias FileTree = MindControl.FileTree

struct DependencyScannerTests {
    /// A temporary project; `tree` lists every file written.
    private final class Project {
        let url: URL
        private(set) var files: [String] = []

        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("mc-deps-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }

        func write(_ path: String, _ contents: String) throws {
            try write(path, Data(contents.utf8))
        }

        func write(_ path: String, _ data: Data) throws {
            let target = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
            files.append(path)
        }

        var tree: FileTree {
            FileTree(rootName: url.lastPathComponent, rootPath: url.path, files: files.sorted(), totalFileCount: files.count)
        }
    }

    private func scan(_ project: Project) throws -> Set<Dependency> {
        Set(try DependencyScanner.scan(tree: project.tree))
    }

    @Test func zigRelativeImports() throws {
        let p = try Project()
        try p.write("src/main.zig", #"const t = @import("terminal/Terminal.zig"); const std = @import("std");"#)
        try p.write("src/terminal/Terminal.zig", #"const page = @import("../page.zig");"#)
        try p.write("src/page.zig", "")
        #expect(try scan(p) == [Dependency(from: "src/main.zig", to: "src/terminal/Terminal.zig"),
                                Dependency(from: "src/terminal/Terminal.zig", to: "src/page.zig")])
    }

    @Test func scriptImportsResolveExtensionsAndIndex() throws {
        let p = try Project()
        try p.write("web/app.ts", "import { a } from './lib/a';\nimport b from './lib';\nimport x from 'react';")
        try p.write("web/lib/a.tsx", "")
        try p.write("web/lib/index.js", "")
        #expect(try scan(p) == [Dependency(from: "web/app.ts", to: "web/lib/a.tsx"),
                                Dependency(from: "web/app.ts", to: "web/lib/index.js")])
    }

    @Test func pythonImportsResolveModulesAndPackages() throws {
        let p = try Project()
        try p.write("pkg/__init__.py", "")
        try p.write("pkg/util.py", "")
        try p.write("pkg/sub/__init__.py", "")
        try p.write("pkg/sub/mod.py", "from .. import util\nfrom . import helper\nimport os")
        try p.write("pkg/sub/helper.py", "")
        try p.write("main.py", "import pkg.util\nfrom pkg.sub import mod")
        // A `from X import name` statement depends on package X (its __init__.py) as well as `name`.
        #expect(try scan(p) == [
            Dependency(from: "pkg/sub/mod.py", to: "pkg/__init__.py"),
            Dependency(from: "pkg/sub/mod.py", to: "pkg/util.py"),
            Dependency(from: "pkg/sub/mod.py", to: "pkg/sub/__init__.py"),
            Dependency(from: "pkg/sub/mod.py", to: "pkg/sub/helper.py"),
            Dependency(from: "main.py", to: "pkg/util.py"),
            Dependency(from: "main.py", to: "pkg/sub/__init__.py"),
            Dependency(from: "main.py", to: "pkg/sub/mod.py"),
        ])
    }

    @Test func pythonResolvesSiblingsOfTheImportingFile() throws {
        let p = try Project()
        try p.write("scripts/run.py", "import helpers")
        try p.write("scripts/helpers.py", "")
        #expect(try scan(p) == [Dependency(from: "scripts/run.py", to: "scripts/helpers.py")])
    }

    @Test func markdownLinksToProjectFiles() throws {
        let p = try Project()
        try p.write("README.md", "[guide](docs/guide.md#start) [web](https://x.y) [missing](nope.md)")
        try p.write("docs/guide.md", "[back](../README.md) [code](/src/main.zig)")
        try p.write("src/main.zig", "")
        #expect(try scan(p) == [Dependency(from: "README.md", to: "docs/guide.md"),
                                Dependency(from: "docs/guide.md", to: "README.md"),
                                Dependency(from: "docs/guide.md", to: "src/main.zig")])
    }

    @Test func swiftTypeReferences() throws {
        let p = try Project()
        try p.write("A.swift", "struct Alpha {}\nlet b = Beta()")
        try p.write("B.swift", "final class Beta { let a: Alpha? = nil }\n// Gamma in a comment")
        try p.write("C.swift", "enum Gamma {}\nprivate struct Secret {}")
        try p.write("D.swift", "let s: Secret? = nil")
        #expect(try scan(p) == [Dependency(from: "A.swift", to: "B.swift"),
                                Dependency(from: "B.swift", to: "A.swift")])
    }

    @Test func ambiguousSwiftNamesAreSkipped() throws {
        let p = try Project()
        for i in 0..<4 { try p.write("M\(i).swift", "struct Model {}") }
        try p.write("Use.swift", "let m = Model()")
        #expect(try scan(p).isEmpty)
    }

    @Test func capsPerFileAndTotal() throws {
        let p = try Project()
        let imports = (0..<60).map { "@import(\"t\($0).zig\");" }.joined(separator: "\n")
        try p.write("hub.zig", imports)
        for i in 0..<60 { try p.write("t\(i).zig", "") }
        let deps = try DependencyScanner.scan(tree: p.tree)
        #expect(deps.count == DependencyScanner.maxPerFile)
        #expect(Set(deps).count == deps.count)
    }

    @Test func unreadableAndHugeFilesAreSkipped() throws {
        let p = try Project()
        try p.write("binary.ts", Data([0xFF, 0xFE, 0x00, 0x80, 0x27]))
        try p.write("huge.zig", String(repeating: "// x\n", count: 120_000) + #"@import("t.zig");"#)
        try p.write("t.zig", "")
        try p.write("ok.zig", #"@import("t.zig");"#)
        #expect(try scan(p) == [Dependency(from: "ok.zig", to: "t.zig")])
    }

    @Test func selfReferencesAreDropped() throws {
        let p = try Project()
        try p.write("Loop.swift", "struct Loop { var next: Loop? }")
        #expect(try scan(p).isEmpty)
    }

    @Test func stopRequestCancels() throws {
        let p = try Project()
        try p.write("a.zig", "")
        #expect(throws: CancellationError.self) {
            try DependencyScanner.scan(tree: p.tree, shouldStop: { true })
        }
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh DependencyScannerTests` → compile FAIL.

- [ ] **Step 3: Implement `Data/DependencyScanner.swift`.**

```swift
import Foundation

extension MindControl {
    /// `from` uses something defined in `to`; both are paths relative to the project root.
    struct Dependency: Hashable, Sendable {
        let from: String
        let to: String
    }

    /// Finds file-to-file relationships: imports, Swift type references and Markdown links.
    enum DependencyScanner {
        static let maxFileBytes = 512 * 1024
        static let maxPerFile = 40
        static let maxTotal = 30_000
        /// A Swift type name declared in more files than this is too ambiguous to link.
        static let maxDeclarers = 3

        static func scan(tree: FileTree, shouldStop: () -> Bool = { Task.isCancelled }) throws -> [Dependency] {
            let root = URL(fileURLWithPath: tree.rootPath)
            let files = Set(tree.files)

            // Swift needs a project-wide index of which file declares which type.
            var swiftSources: [String: String] = [:]
            var declarers: [String: Set<String>] = [:]
            for path in tree.files where path.hasSuffix(".swift") {
                if shouldStop() { throw CancellationError() }
                guard let source = read(path, root: root) else { continue }
                swiftSources[path] = source
                for name in SwiftSymbols.declaredTypes(in: source) {
                    declarers[name, default: []].insert(path)
                }
            }
            declarers = declarers.filter { $0.value.count <= maxDeclarers }

            var result: [Dependency] = []
            for path in tree.files {
                if shouldStop() { throw CancellationError() }
                guard let targets = targets(of: path, root: root, files: files,
                                            swiftSources: swiftSources, declarers: declarers) else { continue }
                for target in targets.subtracting([path]).sorted().prefix(maxPerFile) {
                    result.append(Dependency(from: path, to: target))
                    if result.count >= maxTotal { return result }
                }
            }
            return result
        }

        private static func targets(of path: String, root: URL, files: Set<String>,
                                    swiftSources: [String: String], declarers: [String: Set<String>]) -> Set<String>? {
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "swift" {
                guard let source = swiftSources[path] else { return nil }
                return Set(SwiftSymbols.typeLikeIdentifiers(in: source).flatMap { declarers[$0] ?? [] })
            }
            let isScript = ScriptImports.extensions.contains(ext)
            guard ["zig", "py", "md", "markdown"].contains(ext) || isScript,
                  let source = read(path, root: root) else { return nil }
            switch ext {
            case "zig":
                return Set(ZigImports.specifiers(in: source).compactMap { resolveRelative($0, from: path, in: files) })
            case "py":
                return Set(PythonImports.imports(in: source).flatMap { resolvePython($0, from: path, in: files) })
            case "md", "markdown":
                return Set(MarkdownLinks.targets(in: source).compactMap { resolveMarkdown($0, from: path, in: files) })
            default:
                return Set(ScriptImports.specifiers(in: source).compactMap { resolveScript($0, from: path, in: files) })
            }
        }

        /// UTF-8 contents, or nil for missing, oversized or non-UTF-8 files.
        private static func read(_ path: String, root: URL) -> String? {
            let url = root.appendingPathComponent(path)
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxFileBytes,
                  let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private static func child(_ directory: String, _ name: String) -> String {
            directory.isEmpty ? name : (name.isEmpty ? directory : directory + "/" + name)
        }

        static func resolveRelative(_ spec: String, from path: String, in files: Set<String>) -> String? {
            guard let joined = ParserSupport.join(ParserSupport.directory(of: path), spec), files.contains(joined) else { return nil }
            return joined
        }

        static func resolveScript(_ spec: String, from path: String, in files: Set<String>) -> String? {
            guard let base = ParserSupport.join(ParserSupport.directory(of: path), spec) else { return nil }
            let candidates = [base]
                + ScriptImports.extensions.map { "\(base).\($0)" }
                + ScriptImports.extensions.map { "\(base)/index.\($0)" }
            return candidates.first { files.contains($0) }
        }

        static func resolveMarkdown(_ target: String, from path: String, in files: Set<String>) -> String? {
            let directory = target.hasPrefix("/") ? "" : ParserSupport.directory(of: path)
            guard let joined = ParserSupport.join(directory, target), files.contains(joined) else { return nil }
            return joined
        }

        static func resolvePython(_ statement: PythonImports.Import, from path: String, in files: Set<String>) -> [String] {
            let dots = statement.module.prefix { $0 == "." }.count
            let modulePath = statement.module.dropFirst(dots).split(separator: ".").joined(separator: "/")

            var bases: [String] = []
            if dots > 0 {
                // One dot is the importing file's package; each extra dot climbs a level.
                var directory = ParserSupport.directory(of: path)
                for _ in 0..<(dots - 1) {
                    guard !directory.isEmpty else { return [] }
                    directory = ParserSupport.directory(of: directory)
                }
                bases.append(child(directory, modulePath))
            } else {
                bases.append(modulePath)
                let directory = ParserSupport.directory(of: path)
                if !directory.isEmpty { bases.append(child(directory, modulePath)) }
            }

            func moduleFile(_ base: String) -> String? {
                guard !base.isEmpty else { return nil }
                return [base + ".py", base + "/__init__.py"].first { files.contains($0) }
            }

            for base in bases {
                var found: [String] = []
                if let file = moduleFile(base) { found.append(file) }
                for name in statement.names where name != "*" {
                    if let file = moduleFile(child(base, name)) { found.append(file) }
                }
                if !found.isEmpty { return found }
            }
            return []
        }
    }
}
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh DependencyScannerTests` → 11 passed.

- [ ] **Step 5: Commit.**

```bash
git add macos/Sources/Features/MindControl/Data/DependencyScanner.swift macos/Tests/MindControl/DependencyScannerTests.swift
git commit -m "mindcontrol: scan file-to-file dependencies

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Dependencies in the pipeline

**Files:**
- Modify: `Data/TreeLayout.swift`, `MindControlModel.swift`
- Test: `macos/Tests/MindControl/TreeLayoutTests.swift`, `ModelTests.swift`

**Interfaces:**
- Consumes: `Dependency`, `DependencyScanner` (Task 4).
- Produces: `TreeLayout.graph(for: FileTree, dependencies: [Dependency] = []) -> Graph` (appends `.uses` edges between existing file nodes); `Model.init(scan:dependencies:)` where `dependencies: @escaping @Sendable (FileTree) throws -> [Dependency] = { try DependencyScanner.scan(tree: $0) }`.

- [ ] **Step 1: Write the failing tests.** Append inside `struct TreeLayoutTests`:

```swift
    @Test func dependenciesBecomeUsesEdges() {
        let deps = [MindControl.Dependency(from: "src/a.swift", to: "src/b.swift"),
                    MindControl.Dependency(from: "src/a.swift", to: "gone.swift")]
        let graph = TreeLayout.graph(for: tree(["src/a.swift", "src/b.swift"]), dependencies: deps)
        let uses = graph.edges.filter { $0.kind == .uses }
        #expect(uses.count == 1)
        #expect(uses.first?.from == "src/a.swift" && uses.first?.to == "src/b.swift")
    }
```

Append inside `struct ModelTests`:

```swift
    @Test func dependenciesReachTheGraph() async {
        let model = Model(
            scan: { _ in FileTree(rootName: "proj", rootPath: "/tmp/mc-model-test", files: ["a.swift", "b.swift"], totalFileCount: 2) },
            dependencies: { _ in [MindControl.Dependency(from: "a.swift", to: "b.swift")] })
        model.load(pwd: pwd)
        await model.loadingTask?.value
        #expect(model.graph?.edges.filter { $0.kind == .uses }.count == 1)
    }
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh TreeLayoutTests ModelTests` → compile FAIL (extra argument `dependencies`).

- [ ] **Step 3: Implement.**

`Data/TreeLayout.swift`: change the signature to `static func graph(for tree: FileTree, dependencies: [Dependency] = []) -> Graph` and, immediately before `return Graph(nodes: nodes, edges: edges)`, add:

```swift
            let ids = Set(nodes.map(\.id))
            for dependency in dependencies where dependency.from != dependency.to
                && ids.contains(dependency.from) && ids.contains(dependency.to) {
                edges.append(GraphEdge(from: dependency.from, to: dependency.to, kind: .uses))
            }
```

`MindControlModel.swift`: add a stored property and extend the initializer:

```swift
        private let dependencies: @Sendable (FileTree) throws -> [Dependency]

        init(scan: @escaping @Sendable (URL) throws -> FileTree = { try ProjectScanner().scan(pwd: $0) },
             dependencies: @escaping @Sendable (FileTree) throws -> [Dependency] = { try DependencyScanner.scan(tree: $0) }) {
            self.scan = scan
            self.dependencies = dependencies
        }
```

and in `load(pwd:)` capture it next to `let scan = self.scan` (`let dependencies = self.dependencies`) and replace the body of the detached `Result { … }` with:

```swift
                    let tree = try scan(pwd)
                    try Task.checkCancellation()
                    let found = try dependencies(tree)
                    try Task.checkCancellation()
                    return (tree, TreeLayout.graph(for: tree, dependencies: found))
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh TreeLayoutTests ModelTests DensityTests` → all pass.

- [ ] **Step 5: Commit.**

```bash
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl
git commit -m "mindcontrol: dependencies flow into the graph as uses-edges

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Draw contains vs uses, signals on uses, legend

**Files:**
- Modify: `Renderer/ShaderTypes.h`, `Renderer/Shaders/ShaderCommon.h`, `Renderer/Pipelines.swift`, `Renderer/Renderer.swift`, `MindControlPanel.swift`
- Rewrite: `Renderer/Shaders/Edges.metal`, `Renderer/Shaders/Signals.metal`
- Create: `MindControlLegend.swift`
- Test: `macos/Tests/MindControl/RendererTests.swift`

**Interfaces:**
- Consumes: `GraphBuffers.containsEdges/usesEdges` (Task 1).
- Produces: `MC_USES_SEGMENTS 12` (ShaderTypes.h); Metal `usesCurve(pa, pb, t) -> CurveSample`; pipelines `containsEdges` (`mcContainsEdgeVertex/Fragment`), `usesEdges` (`mcUsesEdgeVertex/Fragment`), `signals` (`mcSignalVertex/Fragment`, now over the uses buffer); `MindControl.Legend` view.

- [ ] **Step 1: Write the failing test.** In `RendererTests`, add a channel-sum helper next to `renderAverage(using:)` and a test:

```swift
    /// Sum of each colour channel over one offscreen frame, as (red, green, blue).
    private func renderChannelSums(using renderer: Renderer, width: Int = 160, height: Int = 100) throws -> SIMD3<Double> {
        let device = renderer.device
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        let texture = try #require(device.makeTexture(descriptor: desc))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].storeAction = .store
        let cmd = try #require(device.makeCommandQueue()?.makeCommandBuffer())
        renderer.encodeFrame(into: cmd, output: pass, width: width, height: height, pixelScale: 1, time: 1.5)
        let blit = try #require(cmd.makeBlitCommandEncoder())
        blit.synchronize(resource: texture)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        var sums = SIMD3<Double>(repeating: 0)
        for p in stride(from: 0, to: bytes.count, by: 4) {       // BGRA
            sums += SIMD3(Double(bytes[p + 2]), Double(bytes[p + 1]), Double(bytes[p]))
        }
        return sums
    }

    @Test func usesEdgesAreWarmerThanContainsEdges() throws {
        let nodes = [GraphNode(id: "a", label: "a", kind: .source, position: SIMD3(-4, 0, 0)),
                     GraphNode(id: "b", label: "b", kind: .source, position: SIMD3(4, 0, 0))]
        let renderer = try Renderer()
        renderer.signalsEnabled = false
        renderer.setGraph(Graph(nodes: nodes, edges: [GraphEdge(from: "a", to: "b")]))
        let contains = try renderChannelSums(using: renderer)
        renderer.setGraph(Graph(nodes: nodes, edges: [GraphEdge(from: "a", to: "b", kind: .uses)]))
        let uses = try renderChannelSums(using: renderer)
        #expect(uses.x / uses.z > contains.x / contains.z)   // red relative to blue
    }
```

(`RendererTests` already imports `Metal`; the typealiases at the top cover `GraphNode`, `GraphEdge`, `Graph`.)

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh RendererTests` → `usesEdgesAreWarmerThanContainsEdges` FAILS (both edges are coloured by their endpoints today, so the ratios are equal).

- [ ] **Step 3: Shared definitions.**

`Renderer/ShaderTypes.h` — add after the `MC_EDGE_USES` define:

```c
#define MC_USES_SEGMENTS 12   // uses-edges are curves tessellated into this many segments
```

`Renderer/Shaders/ShaderCommon.h` — add before the closing `#endif`:

```metal
#define MC_USES_BOW 0.18   // control-point offset as a fraction of the screen-space chord

struct CurveSample {
    float2 point;
    float2 normal;
};

/// Point and unit normal at t on the quadratic Bézier that bows a uses-edge from pa to pb (pixels).
inline CurveSample usesCurve(float2 pa, float2 pb, float t) {
    float2 delta = pb - pa;
    float len = length(delta);
    float2 dir = len > 1e-3 ? delta / len : float2(1.0, 0.0);
    float2 control = (pa + pb) * 0.5 + float2(-dir.y, dir.x) * (MC_USES_BOW * len);
    float s = 1.0 - t;
    CurveSample sample;
    sample.point = s * s * pa + 2.0 * s * t * control + t * t * pb;
    float2 tangent = 2.0 * s * (control - pa) + 2.0 * t * (pb - control);
    float tangentLength = length(tangent);
    float2 along = tangentLength > 1e-3 ? tangent / tangentLength : dir;
    sample.normal = float2(-along.y, along.x);
    return sample;
}
```

- [ ] **Step 4: Rewrite `Renderer/Shaders/Edges.metal`.**

```metal
#include "ShaderCommon.h"

// Contains-edges: straight hairlines in a neutral blue-grey — the folder skeleton.
// Uses-edges: amber quadratic Bézier curves — one file depends on another.

constant float kContainsHalfWidth = 0.25;   // core half-width, points
constant float kUsesHalfWidth = 0.45;       // core half-width, points
constant float kFeather = 1.6;              // extra quad half-width for AA and glow, points
constant float3 kContainsColor = float3(0.42, 0.52, 0.78);
constant float3 kUsesColor = float3(1.0, 0.68, 0.30);

struct EdgeOut {
    float4 position [[position]];
    float3 color;
    float across [[center_no_perspective]];   // pixels from the centreline
    float fog;
};

vertex EdgeOut mcContainsEdgeVertex(uint vid [[vertex_id]],
                                    uint iid [[instance_id]],
                                    const device MCEdgeInstance* edges [[buffer(MC_BUFFER_INSTANCES)]],
                                    const device MCNodeInstance* nodes [[buffer(MC_BUFFER_NODES)]],
                                    constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    EdgeOut out = {};
    MCEdgeInstance e = edges[iid];
    MCNodeInstance na = nodes[e.a];
    MCNodeInstance nb = nodes[e.b];

    float4 ca = u.viewProjection * float4(na.position, 1.0);
    float4 cb = u.viewProjection * float4(nb.position, 1.0);
    if (ca.w < 0.01 || cb.w < 0.01) { out.position = culledPosition(); return out; }

    float2 pa = toPixels(ca, u.viewportSize);
    float2 pb = toPixels(cb, u.viewportSize);
    float2 delta = pb - pa;
    float len = length(delta);
    float2 dir = len > 1e-3 ? delta / len : float2(1.0, 0.0);
    float2 normal = float2(-dir.y, dir.x);

    bool atB = vid >= 2;
    float side = (vid & 1) ? 1.0 : -1.0;
    float halfQuad = (kContainsHalfWidth + kFeather) * u.pixelScale;

    float4 clip = atB ? cb : ca;
    out.position = fromPixels((atB ? pb : pa) + normal * side * halfQuad, clip, u.viewportSize);
    out.color = kContainsColor * min(na.intensity, nb.intensity);
    out.across = side * halfQuad;
    out.fog = fogFactor(u, atB ? nb.position : na.position);
    return out;
}

fragment float4 mcContainsEdgeFragment(EdgeOut in [[stage_in]],
                                       constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    float d = abs(in.across) / u.pixelScale;
    float core = 1.0 - smoothstep(kContainsHalfWidth - 0.5, kContainsHalfWidth + 0.5, d);
    float glow = exp(-d * d * 0.7);
    float intensity = (core * 0.15 + glow * 0.05) * u.glowScale;
    return float4(in.color * intensity * in.fog, 0.0);
}

/// Uses-edges are triangle strips of (MC_USES_SEGMENTS + 1) * 2 vertices following usesCurve.
vertex EdgeOut mcUsesEdgeVertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device MCEdgeInstance* edges [[buffer(MC_BUFFER_INSTANCES)]],
                                const device MCNodeInstance* nodes [[buffer(MC_BUFFER_NODES)]],
                                constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    EdgeOut out = {};
    MCEdgeInstance e = edges[iid];
    MCNodeInstance na = nodes[e.a];
    MCNodeInstance nb = nodes[e.b];

    float4 ca = u.viewProjection * float4(na.position, 1.0);
    float4 cb = u.viewProjection * float4(nb.position, 1.0);
    if (ca.w < 0.01 || cb.w < 0.01) { out.position = culledPosition(); return out; }

    float t = float(vid / 2) / float(MC_USES_SEGMENTS);
    float side = (vid & 1) ? 1.0 : -1.0;
    CurveSample c = usesCurve(toPixels(ca, u.viewportSize), toPixels(cb, u.viewportSize), t);
    float halfQuad = (kUsesHalfWidth + kFeather) * u.pixelScale;

    out.position = fromPixels(c.point + c.normal * side * halfQuad, mix(ca, cb, t), u.viewportSize);
    out.color = kUsesColor * min(na.intensity, nb.intensity);
    out.across = side * halfQuad;
    out.fog = mix(fogFactor(u, na.position), fogFactor(u, nb.position), t);
    return out;
}

fragment float4 mcUsesEdgeFragment(EdgeOut in [[stage_in]],
                                   constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    float d = abs(in.across) / u.pixelScale;
    float core = 1.0 - smoothstep(kUsesHalfWidth - 0.5, kUsesHalfWidth + 0.5, d);
    float glow = exp(-d * d * 0.5);
    float intensity = (core * 0.45 + glow * 0.15) * u.glowScale;
    return float4(in.color * intensity * in.fog, 0.0);
}
```

- [ ] **Step 5: Rewrite `Renderer/Shaders/Signals.metal`.**

```metal
#include "ShaderCommon.h"

// Signals travel along uses-edges from the file that uses something toward its definition,
// following the same curve. Derived from the edge seed and time: no per-frame CPU work.

constant float kCarryChance = 0.4;       // fraction of uses-edges that carry a signal
constant float kSignalHalfWidth = 5.0;   // quad half-width, points
constant float kTailPoints = 60.0;       // tail length scale, points
constant float3 kSignalColor = float3(1.0, 0.86, 0.62);

struct SignalOut {
    float4 position [[position]];
    float3 color;
    float along [[center_no_perspective]];    // 0 at the user, 1 at the definition
    float across [[center_no_perspective]];   // points from the centreline
    float lengthPoints;
    float head;
    float fog;
};

vertex SignalOut mcSignalVertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device MCEdgeInstance* edges [[buffer(MC_BUFFER_INSTANCES)]],
                                const device MCNodeInstance* nodes [[buffer(MC_BUFFER_NODES)]],
                                constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    SignalOut out = {};
    MCEdgeInstance e = edges[iid];
    if (hash11(e.signalSeed * 13.7 + 0.5) > kCarryChance) { out.position = culledPosition(); return out; }

    MCNodeInstance na = nodes[e.a];
    MCNodeInstance nb = nodes[e.b];
    float4 ca = u.viewProjection * float4(na.position, 1.0);
    float4 cb = u.viewProjection * float4(nb.position, 1.0);
    if (ca.w < 0.01 || cb.w < 0.01) { out.position = culledPosition(); return out; }

    float2 pa = toPixels(ca, u.viewportSize);
    float2 pb = toPixels(cb, u.viewportSize);
    float chord = length(pb - pa);
    if (chord < 1.0) { out.position = culledPosition(); return out; }

    float t = float(vid / 2) / float(MC_USES_SEGMENTS);
    float side = (vid & 1) ? 1.0 : -1.0;
    CurveSample c = usesCurve(pa, pb, t);
    float halfQuad = kSignalHalfWidth * u.pixelScale;

    out.position = fromPixels(c.point + c.normal * side * halfQuad, mix(ca, cb, t), u.viewportSize);
    out.along = t;
    out.across = side * kSignalHalfWidth;
    out.lengthPoints = chord * 1.05 / u.pixelScale;   // the bow adds a few percent of length

    float period = mix(2.5, 6.0, hash11(e.signalSeed * 3.1 + 2.3));
    out.head = fract(u.time / period + e.signalSeed) * 1.8 - 0.2;
    out.color = kSignalColor * min(na.intensity, nb.intensity);
    out.fog = mix(fogFactor(u, na.position), fogFactor(u, nb.position), t);
    return out;
}

fragment float4 mcSignalFragment(SignalOut in [[stage_in]],
                                 constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    float behind = (in.head - in.along) * in.lengthPoints;
    float trail = behind >= 0.0 ? exp(-behind / kTailPoints * 3.0) : exp(behind * 0.9);
    float profile = exp(-in.across * in.across * 0.45);
    float spark = exp(-(behind * behind + in.across * in.across) * 0.2);
    float onEdge = smoothstep(0.0, 0.03, in.along) * (1.0 - smoothstep(0.97, 1.0, in.along));
    float intensity = (trail * profile * 1.4 + spark * 3.5) * onEdge * mix(0.5, 1.0, u.glowScale);
    return float4(in.color * intensity * in.fog, 0.0);
}
```

- [ ] **Step 6: Pipelines and renderer.**

`Renderer/Pipelines.swift`: replace `let edges: MTLRenderPipelineState` with

```swift
        let containsEdges: MTLRenderPipelineState
        let usesEdges: MTLRenderPipelineState
```

and the `edges = try make("mcEdgeVertex", "mcEdgeFragment", …)` line with

```swift
            containsEdges = try make("mcContainsEdgeVertex", "mcContainsEdgeFragment", format: hdr, additive: true)
            usesEdges = try make("mcUsesEdgeVertex", "mcUsesEdgeFragment", format: hdr, additive: true)
```

`Renderer/Renderer.swift`:
- Replace `private var edgeBuffer: MTLBuffer?` with `private var containsBuffer: MTLBuffer?` and `private var usesBuffer: MTLBuffer?`; replace `private var edgeCount = 0` with `private var containsCount = 0` and `private var usesCount = 0`; add `private static let usesVertexCount = (Int(MC_USES_SEGMENTS) + 1) * 2`.
- In `setGraph`, replace the two `edgeCount`/`edgeBuffer` lines with:

```swift
            containsCount = buffers.containsEdges.count
            usesCount = buffers.usesEdges.count
            containsBuffer = makeBuffer(buffers.containsEdges)
            usesBuffer = makeBuffer(buffers.usesEdges)
```

- In `encodeScene`, replace the whole `if let nodeBuffer, let edgeBuffer { … }` block with:

```swift
            if let nodeBuffer {
                encoder.setVertexBuffer(nodeBuffer, offset: 0, index: Int(MC_BUFFER_NODES))
                if let containsBuffer {
                    encoder.setRenderPipelineState(pipelines.containsEdges)
                    encoder.setVertexBuffer(containsBuffer, offset: 0, index: Int(MC_BUFFER_INSTANCES))
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: containsCount)
                }
                if let usesBuffer {
                    encoder.setRenderPipelineState(pipelines.usesEdges)
                    encoder.setVertexBuffer(usesBuffer, offset: 0, index: Int(MC_BUFFER_INSTANCES))
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: Self.usesVertexCount, instanceCount: usesCount)
                    if signalsEnabled {
                        encoder.setRenderPipelineState(pipelines.signals)
                        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: Self.usesVertexCount, instanceCount: usesCount)
                    }
                }
            }
```

- [ ] **Step 7: Legend.** Create `MindControlLegend.swift`:

```swift
import SwiftUI

extension MindControl {
    /// Explains what lines and node colours mean. Colours are sRGB approximations of the shader values.
    struct Legend: View {
        private static let contains = Color(red: 0.68, green: 0.75, blue: 0.89)
        private static let uses = Color(red: 1.0, green: 0.85, blue: 0.58)
        private static let folder = Color(red: 0.54, green: 0.74, blue: 1.0)
        private static let source = Color(red: 0.48, green: 0.93, blue: 1.0)
        private static let document = Color(red: 0.83, green: 0.63, blue: 1.0)

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                line(Self.contains, width: 1, label: "contains — folder holds file")
                line(Self.uses, width: 2, label: "uses — file depends on file")
                HStack(spacing: 10) {
                    dot(Self.folder, "folder")
                    dot(Self.source, "source")
                    dot(Self.document, "document")
                }
            }
            .font(.system(size: 10.5))
            .foregroundColor(.white.opacity(0.75))
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.35)))
            .padding(14)
            .allowsHitTesting(false)
        }

        private func line(_ color: Color, width: CGFloat, label: String) -> some View {
            HStack(spacing: 8) {
                Capsule().fill(color).frame(width: 22, height: width)
                Text(label)
            }
        }

        private func dot(_ color: Color, _ label: String) -> some View {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
            }
        }
    }
}
```

In `MindControlPanel.swift`, inside the `ZStack`, after the status-text block, add:

```swift
                if renderer != nil {
                    Legend()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
```

- [ ] **Step 8: Run tests.** `.superpowers/mc-test.sh RendererTests DensityTests GraphBuffersTests` → all pass (`signalsAddLight` uses the stress graph, whose cross-links are now uses-edges).

- [ ] **Step 9: Commit.**

```bash
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl
git commit -m "mindcontrol: contains hairlines, curved uses-edges with signals, legend

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
# Phase 2 — Layout

### Task 7: ConeTreeLayout replaces TreeLayout

**Files:**
- Create: `Data/ConeTreeLayout.swift`, `macos/Tests/MindControl/ConeTreeLayoutTests.swift`
- Delete: `Data/TreeLayout.swift`, `macos/Tests/MindControl/TreeLayoutTests.swift`
- Modify: `Data/Graph.swift` (`GraphNode.descendantFiles`), `MindControlModel.swift`, `macos/Tests/MindControl/DensityTests.swift`

**Interfaces:**
- Consumes: `FileTree`, `Dependency`, `GraphNode/GraphEdge/Graph`.
- Produces: `MindControl.ConeTreeLayout` with `rootID = "."`, `documentExtensions`, `crowdThreshold`, `minimumFileWeight`, `fileWeight(siblings:)`, `fileBallRadius(fileCount:) -> Float`, `subfolderDistance(parentFiles:childTotalFiles:) -> Float`, `capDirection(index:count:axis:halfAngle:) -> SIMD3<Float>`, `graph(for: FileTree, dependencies: [Dependency] = []) -> Graph`. `GraphNode.descendantFiles: Int = 0` (set for folders and root).

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/ConeTreeLayoutTests.swift` (ports every TreeLayout test, plus cluster separation and folder sizes):

```swift
#if os(macOS)
import Foundation
import Testing
import simd
@testable import Ghostty

private typealias ConeTreeLayout = MindControl.ConeTreeLayout
private typealias FileTree = MindControl.FileTree
private typealias Dependency = MindControl.Dependency

struct ConeTreeLayoutTests {
    private func tree(_ files: [String]) -> FileTree {
        FileTree(rootName: "proj", rootPath: "/tmp/proj", files: files.sorted(), totalFileCount: files.count)
    }

    private let sample = [
        "README.md", "Package.swift", "docs/guide.MD", "docs/notes.txt",
        "src/app/main.swift", "src/app/view.swift", "src/core/model.swift", "src/core/store.swift",
        "src/core/net/client.swift", "tests/model_tests.swift", "assets/logo.pdf",
    ]

    @Test func createsFolderNodes() {
        let graph = ConeTreeLayout.graph(for: tree(["a/b/c.swift"]))
        #expect(Set(graph.nodes.map(\.id)) == [ConeTreeLayout.rootID, "a", "a/b", "a/b/c.swift"])
        #expect(graph.nodes.first { $0.id == "a/b" }?.label == "b")
    }

    @Test func kindsByExtension() {
        let graph = ConeTreeLayout.graph(for: tree(sample))
        let kind = { (id: String) in graph.nodes.first { $0.id == id }?.kind }
        #expect(kind(ConeTreeLayout.rootID) == .root)
        #expect(kind("src") == .folder)
        #expect(kind("README.md") == .document)
        #expect(kind("docs/guide.MD") == .document)
        #expect(kind("assets/logo.pdf") == .document)
        #expect(kind("src/app/main.swift") == .source)
    }

    @Test func oneContainsEdgePerNode() {
        let graph = ConeTreeLayout.graph(for: tree(sample))
        let contains = graph.edges.filter { $0.kind == .contains }
        #expect(contains.count == graph.nodes.count - 1)
        let targets = contains.map(\.to)
        #expect(Set(targets).count == targets.count)
        #expect(!targets.contains(ConeTreeLayout.rootID))
        #expect(contains.contains { $0.from == "src/core" && $0.to == "src/core/net" })
    }

    @Test func emptyTreeIsJustTheRoot() {
        let graph = ConeTreeLayout.graph(for: tree([]))
        #expect(graph.nodes.map(\.id) == [ConeTreeLayout.rootID])
        #expect(graph.edges.isEmpty)
    }

    @Test func isDeterministic() {
        let a = ConeTreeLayout.graph(for: tree(sample))
        let b = ConeTreeLayout.graph(for: tree(sample))
        #expect(a.nodes.map(\.id) == b.nodes.map(\.id))
        #expect(a.nodes.map(\.position) == b.nodes.map(\.position))
    }

    @Test func positionsAreFiniteAndDistinct() {
        let files = (0..<300).map { "m\($0 % 6)/s\($0 % 4)/f\($0).swift" }
        let positions = ConeTreeLayout.graph(for: tree(files)).nodes.map(\.position)
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
        let graph = ConeTreeLayout.graph(for: tree(sample))
        #expect(graph.nodes.first { $0.id == ConeTreeLayout.rootID }?.position == .zero)
    }

    @Test func tenThousandFilesLayOutQuickly() {
        let files = (0..<10_000).map { "d\($0 % 50)/e\($0 % 7)/f\($0).swift" }
        let input = tree(files)
        let clock = ContinuousClock()
        var graph: MindControl.Graph?
        let elapsed = clock.measure { graph = ConeTreeLayout.graph(for: input) }
        let expectedNodes: Int = 10_000 + 50 + 350 + 1   // files + top folders + nested folders + root
        #expect(graph?.nodes.count == expectedNodes)
        #expect(elapsed < .milliseconds(200))
    }

    @Test func crowdedFilesAreDimmed() {
        let crowded = (0..<1_000).map { "big/f\($0).txt" }
        let graph = ConeTreeLayout.graph(for: tree(crowded + ["small/a.swift", "small/b.swift"]))
        let weight = { (id: String) in graph.nodes.first { $0.id == id }?.weight }
        #expect(weight("small/a.swift") == 1)
        #expect(weight("big") == 1)
        #expect((weight("big/f0.txt") ?? 1) < 0.3)
        #expect((weight("big/f0.txt") ?? 0) >= ConeTreeLayout.minimumFileWeight)
    }

    @Test func dependenciesBecomeUsesEdges() {
        let deps = [Dependency(from: "src/a.swift", to: "src/b.swift"), Dependency(from: "src/a.swift", to: "gone.swift")]
        let graph = ConeTreeLayout.graph(for: tree(["src/a.swift", "src/b.swift"]), dependencies: deps)
        let uses = graph.edges.filter { $0.kind == .uses }
        #expect(uses.count == 1)
        #expect(uses.first?.from == "src/a.swift" && uses.first?.to == "src/b.swift")
    }

    @Test func folderSizesAreRecorded() {
        let graph = ConeTreeLayout.graph(for: tree(sample))
        let size = { (id: String) in graph.nodes.first { $0.id == id }?.descendantFiles }
        #expect(size(ConeTreeLayout.rootID) == sample.count)
        #expect(size("src") == 5)
        #expect(size("src/core") == 3)
        #expect(size("README.md") == 0)
    }

    @Test func siblingClustersDoNotOverlap() {
        var files: [String] = []
        for f in 0..<6 { for i in 0..<(20 + f * 15) { files.append("top\(f)/file\(i).swift") } }
        for f in 0..<5 { for i in 0..<30 { files.append("top0/sub\(f)/file\(i).swift") } }
        let graph = ConeTreeLayout.graph(for: tree(files))
        let position = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.position) })
        func directFiles(_ folder: String) -> Int {
            files.filter { ($0 as NSString).deletingLastPathComponent == folder }.count
        }
        func expectSeparated(_ folders: [String]) {
            for i in folders.indices {
                for j in folders.indices where j > i {
                    let (a, b) = (folders[i], folders[j])
                    let gap = simd_distance(position[a]!, position[b]!)
                    let reach = ConeTreeLayout.fileBallRadius(fileCount: directFiles(a))
                        + ConeTreeLayout.fileBallRadius(fileCount: directFiles(b))
                    #expect(gap > reach, "\(a) and \(b) overlap")
                }
            }
        }
        expectSeparated((0..<6).map { "top\($0)" })
        expectSeparated((0..<5).map { "top0/sub\($0)" })
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh ConeTreeLayoutTests` → compile FAIL (`ConeTreeLayout` not found).

- [ ] **Step 3: Implement.**

`Data/Graph.swift` — add to `GraphNode` after `weight`:

```swift
        /// For folders and the root: files anywhere beneath them. 0 for files.
        var descendantFiles: Int = 0
```

`Data/ConeTreeLayout.swift`:

```swift
import Foundation
import simd

extension MindControl {
    /// Places the folder tree so sibling clusters don't overlap: every folder owns a cone of space
    /// sized by how many files it holds, subfolders sit along their cone's axis, and a folder's own
    /// files form a small ball around it.
    enum ConeTreeLayout {
        static let rootID = "."
        static let documentExtensions: Set<String> = ["md", "markdown", "txt", "rst", "adoc", "org", "pdf"]
        /// Files in folders with more siblings than this start to dim.
        static let crowdThreshold: Float = 30
        static let minimumFileWeight: Float = 0.12

        /// Brightness for a file with `siblings` files beside it (itself included).
        static func fileWeight(siblings: Int) -> Float {
            min(1, max(minimumFileWeight, pow(crowdThreshold / Float(max(siblings, 1)), 0.75)))
        }

        /// Radius of the ball a folder's own files sit in.
        static func fileBallRadius(fileCount: Int) -> Float {
            0.8 + 0.35 * Float(fileCount).squareRoot()
        }

        /// How far a subfolder sits from its parent: clear of the parent's file ball, further for bigger subtrees.
        static func subfolderDistance(parentFiles: Int, childTotalFiles: Int) -> Float {
            fileBallRadius(fileCount: parentFiles) + 2 + 1.2 * Float(1 + childTotalFiles).squareRoot()
        }

        private final class Folder {
            let id: String
            var folders: [String: Folder] = [:]
            var files: [String] = []
            /// Files anywhere beneath this folder.
            var totalFiles = 0

            init(id: String) { self.id = id }
        }

        static func graph(for tree: FileTree, dependencies: [Dependency] = []) -> Graph {
            let root = Folder(id: rootID)
            for path in tree.files {
                var folder = root
                let parts = path.split(separator: "/").map(String.init)
                for depth in 0..<max(0, parts.count - 1) {
                    if let existing = folder.folders[parts[depth]] {
                        folder = existing
                    } else {
                        let created = Folder(id: parts[0...depth].joined(separator: "/"))
                        folder.folders[parts[depth]] = created
                        folder = created
                    }
                }
                folder.files.append(path)
            }
            countFiles(root)

            var nodes = [GraphNode(id: rootID, label: tree.rootName, kind: .root, position: .zero,
                                   descendantFiles: root.totalFiles)]
            var edges: [GraphEdge] = []
            nodes.reserveCapacity(tree.files.count * 2)
            place(root, at: .zero, axis: SIMD3(0, 1, 0), halfAngle: .pi, nodes: &nodes, edges: &edges)

            let ids = Set(nodes.map(\.id))
            for dependency in dependencies where dependency.from != dependency.to
                && ids.contains(dependency.from) && ids.contains(dependency.to) {
                edges.append(GraphEdge(from: dependency.from, to: dependency.to, kind: .uses))
            }
            return Graph(nodes: nodes, edges: edges)
        }

        @discardableResult
        private static func countFiles(_ folder: Folder) -> Int {
            folder.totalFiles = folder.files.count + folder.folders.values.reduce(0) { $0 + countFiles($1) }
            return folder.totalFiles
        }

        private static func place(_ folder: Folder, at position: SIMD3<Float>, axis: SIMD3<Float>, halfAngle: Float,
                                  nodes: inout [GraphNode], edges: inout [GraphEdge]) {
            let files = folder.files.sorted()
            let ball = fileBallRadius(fileCount: files.count)
            let weight = fileWeight(siblings: files.count)
            for (i, path) in files.enumerated() {
                let direction = fibonacciSphere(index: i, count: files.count)
                // Spread through a thick shell so big folders read as volumes, not a crust.
                let distance = ball * (0.55 + 0.45 * fract(Float(i) * 0.618034))
                nodes.append(GraphNode(id: path, label: (path as NSString).lastPathComponent, kind: kind(for: path),
                                       position: position + direction * distance, weight: weight))
                edges.append(GraphEdge(from: folder.id, to: path))
            }

            // Heaviest subfolders take the centre of the cap; ties keep name order.
            let byName = folder.folders.keys.sorted().compactMap { folder.folders[$0] }
            let subfolders = byName.enumerated().sorted { a, b in
                a.element.totalFiles != b.element.totalFiles ? a.element.totalFiles > b.element.totalFiles : a.offset < b.offset
            }.map(\.element)
            let totalWeight = Float(subfolders.reduce(0) { $0 + $1.totalFiles + 1 })

            for (i, child) in subfolders.enumerated() {
                let childAxis = capDirection(index: i, count: subfolders.count, axis: axis, halfAngle: halfAngle)
                let share = Float(child.totalFiles + 1) / totalWeight
                let childHalfAngle = max(0.05, halfAngle * share.squareRoot() * 0.85)
                let childPosition = position
                    + childAxis * subfolderDistance(parentFiles: files.count, childTotalFiles: child.totalFiles)
                nodes.append(GraphNode(id: child.id, label: (child.id as NSString).lastPathComponent, kind: .folder,
                                       position: childPosition, descendantFiles: child.totalFiles))
                edges.append(GraphEdge(from: folder.id, to: child.id))
                place(child, at: childPosition, axis: childAxis, halfAngle: childHalfAngle, nodes: &nodes, edges: &edges)
            }
        }

        private static func kind(for path: String) -> NodeKind {
            documentExtensions.contains((path as NSString).pathExtension.lowercased()) ? .document : .source
        }

        private static func fract(_ x: Float) -> Float { x - x.rounded(.down) }

        private static let goldenAngle = Float.pi * (3 - Float(5).squareRoot())

        private static func fibonacciSphere(index: Int, count: Int) -> SIMD3<Float> {
            let y = count == 1 ? 0 : 1 - (Float(index) / Float(count - 1)) * 2
            let r = max(0, 1 - y * y).squareRoot()
            let theta = goldenAngle * Float(index)
            return SIMD3(cos(theta) * r, y, sin(theta) * r)
        }

        /// Directions spread evenly (equal area) over the spherical cap around `axis`; index 0 is the axis.
        static func capDirection(index: Int, count: Int, axis: SIMD3<Float>, halfAngle: Float) -> SIMD3<Float> {
            let up = simd_normalize(axis)
            guard count > 1 else { return up }
            let rimZ = cos(min(halfAngle, .pi))
            let z = 1 - (1 - rimZ) * Float(index) / Float(count - 1)
            let r = max(0, 1 - z * z).squareRoot()
            let phi = goldenAngle * Float(index)
            let reference: SIMD3<Float> = abs(up.y) < 0.99 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
            let tangent = simd_normalize(simd_cross(up, reference))
            let bitangent = simd_cross(up, tangent)
            return simd_normalize(tangent * (r * cos(phi)) + bitangent * (r * sin(phi)) + up * z)
        }
    }
}
```

Then: in `MindControlModel.swift` replace `TreeLayout.graph(for: tree, dependencies: found)` with `ConeTreeLayout.graph(for: tree, dependencies: found)`; in `DensityTests.swift` replace `MindControl.TreeLayout.graph` with `MindControl.ConeTreeLayout.graph`; delete the old layout:

```bash
git rm macos/Sources/Features/MindControl/Data/TreeLayout.swift macos/Tests/MindControl/TreeLayoutTests.swift
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh ConeTreeLayoutTests DensityTests ModelTests GraphBuffersTests` → all pass. If only `DensityTests.lopsidedProjectDoesNotBlowOut` fails (the new layout packs the Lostty-shaped fixture differently), tune `fileBallRadius`'s coefficient (0.35 → 0.45) first, then the shell (0.55 → 0.45); re-run both suites; ledger the change.

- [ ] **Step 5: Commit.**

```bash
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl
git commit -m "mindcontrol: cone tree layout gives each folder its own space

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Relaxation

**Files:**
- Create: `Data/Relaxation.swift`, `macos/Tests/MindControl/RelaxationTests.swift`
- Modify: `MindControlModel.swift`

**Interfaces:**
- Consumes: `Graph`, `SplitMix64` (tests), `ConeTreeLayout` (tests).
- Produces: `MindControl.Relaxation.relax(_ graph: Graph, shouldStop: () -> Bool = { Task.isCancelled }) throws -> Graph` (same nodes/edges, new positions); statics `iterations = 60`, `minSpacing = 0.45`, `springRestLength = 2.5`, `springStrength = 0.02`, `folderMobility = 0.2`, `maxMovePerStep = 1.0`.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/RelaxationTests.swift`

```swift
#if os(macOS)
import Foundation
import Testing
import simd
@testable import Ghostty

private typealias Relaxation = MindControl.Relaxation
private typealias Graph = MindControl.Graph
private typealias GraphNode = MindControl.GraphNode
private typealias GraphEdge = MindControl.GraphEdge

struct RelaxationTests {
    /// `count` files packed into a cube of half-size `radius` around `center`, plus a root at the origin.
    private func crowd(count: Int, radius: Float, center: SIMD3<Float> = SIMD3(5, 0, 0)) -> Graph {
        var rng = MindControl.SplitMix64(seed: 1)
        var nodes = [GraphNode(id: ".", label: "root", kind: .root, position: .zero)]
        for i in 0..<count {
            let offset = SIMD3<Float>(Float.random(in: -radius...radius, using: &rng),
                                      Float.random(in: -radius...radius, using: &rng),
                                      Float.random(in: -radius...radius, using: &rng))
            nodes.append(GraphNode(id: "f\(i)", label: "f\(i)", kind: .source, position: center + offset))
        }
        return Graph(nodes: nodes, edges: [])
    }

    private func minimumDistance(_ graph: Graph) -> Float {
        let p = graph.nodes.map(\.position)
        var best = Float.infinity
        for i in p.indices { for j in p.indices where j > i { best = min(best, simd_distance(p[i], p[j])) } }
        return best
    }

    @Test func separatesCrowdedNodes() throws {
        let relaxed = try Relaxation.relax(crowd(count: 150, radius: 0.5))
        #expect(minimumDistance(relaxed) >= 0.9 * Relaxation.minSpacing)
    }

    @Test func rootNeverMoves() throws {
        let relaxed = try Relaxation.relax(crowd(count: 60, radius: 0.3, center: .zero))
        #expect(relaxed.nodes[0].position == .zero)
    }

    @Test func foldersMoveLessThanFiles() throws {
        let graph = Graph(nodes: [
            GraphNode(id: ".", label: "root", kind: .root, position: SIMD3(20, 20, 20)),
            GraphNode(id: "d", label: "d", kind: .folder, position: .zero),
            GraphNode(id: "d/f", label: "f", kind: .source, position: SIMD3(0.1, 0, 0)),
        ], edges: [])
        let relaxed = try Relaxation.relax(graph)
        let folderMove = simd_length(relaxed.nodes[1].position - graph.nodes[1].position)
        let fileMove = simd_length(relaxed.nodes[2].position - graph.nodes[2].position)
        #expect(folderMove < fileMove)
    }

    @Test func usesEdgesPullFilesTogether() throws {
        let nodes = [
            GraphNode(id: ".", label: "root", kind: .root, position: SIMD3(0, 30, 0)),
            GraphNode(id: "a", label: "a", kind: .source, position: SIMD3(-6, 0, 0)),
            GraphNode(id: "b", label: "b", kind: .source, position: SIMD3(6, 0, 0)),
        ]
        let apart = try Relaxation.relax(Graph(nodes: nodes, edges: []))
        let linked = try Relaxation.relax(Graph(nodes: nodes, edges: [GraphEdge(from: "a", to: "b", kind: .uses)]))
        let gap = { (g: Graph) in simd_distance(g.nodes[1].position, g.nodes[2].position) }
        #expect(gap(apart) == 12)
        #expect(gap(linked) < 12)
    }

    @Test func isDeterministic() throws {
        let graph = crowd(count: 120, radius: 0.5)
        #expect(try Relaxation.relax(graph).nodes.map(\.position) == Relaxation.relax(graph).nodes.map(\.position))
    }

    @Test func keepsNodesAndEdges() throws {
        let graph = MindControl.Graph.sample
        let relaxed = try Relaxation.relax(graph)
        #expect(relaxed.nodes.map(\.id) == graph.nodes.map(\.id))
        #expect(relaxed.edges.count == graph.edges.count)
    }

    @Test func tenThousandNodesRelaxQuickly() throws {
        let files = (0..<10_000).map { "d\($0 % 50)/e\($0 % 7)/f\($0).swift" }
        let tree = MindControl.FileTree(rootName: "p", rootPath: "/tmp/p", files: files.sorted(), totalFileCount: files.count)
        let graph = MindControl.ConeTreeLayout.graph(for: tree)
        let clock = ContinuousClock()
        let elapsed = try clock.measure { _ = try Relaxation.relax(graph) }
        #expect(elapsed < .milliseconds(1_500))
    }

    @Test func stopRequestCancels() {
        #expect(throws: CancellationError.self) {
            try Relaxation.relax(.sample, shouldStop: { true })
        }
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh RelaxationTests` → compile FAIL.

- [ ] **Step 3: Implement `Data/Relaxation.swift`.**

```swift
import Foundation
import simd

extension MindControl {
    /// A short, bounded force pass over a laid-out graph: pushes apart nodes closer than `minSpacing`
    /// and gently pulls files that use each other together. Folders are anchors; the root never moves.
    enum Relaxation {
        static let iterations = 60
        static let minSpacing: Float = 0.45
        static let springRestLength: Float = 2.5
        static let springStrength: Float = 0.02
        static let folderMobility: Float = 0.2
        static let maxMovePerStep: Float = 1.0

        /// The 13 neighbour-cell offsets "after" (0,0,0), so each pair of adjacent cells is visited once.
        private static let forwardOffsets: [(Int32, Int32, Int32)] = {
            var offsets: [(Int32, Int32, Int32)] = []
            for dx: Int32 in -1...1 { for dy: Int32 in -1...1 { for dz: Int32 in -1...1 {
                if (dx, dy, dz) > (0, 0, 0) { offsets.append((dx, dy, dz)) }
            } } }
            return offsets
        }()

        static func relax(_ graph: Graph, shouldStop: () -> Bool = { Task.isCancelled }) throws -> Graph {
            let count = graph.nodes.count
            guard count > 1 else { return graph }

            var positions = graph.nodes.map(\.position)
            let mobility: [Float] = graph.nodes.map { node in
                switch node.kind {
                case .root: 0
                case .folder: folderMobility
                case .source, .document: 1
                }
            }
            var index: [String: Int] = [:]
            for (i, node) in graph.nodes.enumerated() { index[node.id] = i }
            let springs: [(Int, Int)] = graph.edges.compactMap { edge in
                guard edge.kind == .uses, let a = index[edge.from], let b = index[edge.to] else { return nil }
                return (a, b)
            }

            var delta = [SIMD3<Float>](repeating: .zero, count: count)
            var grid: [Int64: [Int32]] = [:]

            func push(_ i: Int, _ j: Int) {
                var offset = positions[i] - positions[j]
                var distance = simd_length(offset)
                guard distance < minSpacing else { return }
                if distance < 1e-5 {
                    // Coincident nodes: separate along a direction that depends only on the pair.
                    offset = SIMD3(sin(Float(i * 7 + j)), cos(Float(i * 13 + j)), sin(Float(i + j * 3)))
                    distance = 1e-5
                }
                let shove = offset / max(simd_length(offset), 1e-5) * ((minSpacing - distance) * 0.5)
                delta[i] += shove
                delta[j] -= shove
            }

            for iteration in 0..<iterations {
                if shouldStop() { throw CancellationError() }
                let step = 0.5 + (0.05 - 0.5) * Float(iteration) / Float(iterations - 1)
                for i in 0..<count { delta[i] = .zero }

                grid.removeAll(keepingCapacity: true)
                for i in 0..<count { grid[key(cell(positions[i])), default: []].append(Int32(i)) }

                // Sorted keys keep the summation order, and so the result, deterministic.
                for cellKey in grid.keys.sorted() {
                    let members = grid[cellKey]!
                    for a in 0..<members.count {
                        for b in (a + 1)..<members.count { push(Int(members[a]), Int(members[b])) }
                    }
                    let (cx, cy, cz) = unpack(cellKey)
                    for (dx, dy, dz) in forwardOffsets {
                        guard let others = grid[key((cx + dx, cy + dy, cz + dz))] else { continue }
                        for a in members { for b in others { push(Int(a), Int(b)) } }
                    }
                }

                for (a, b) in springs {
                    let offset = positions[b] - positions[a]
                    let distance = simd_length(offset)
                    guard distance > 1e-5 else { continue }
                    let pull = offset / distance * ((distance - springRestLength) * springStrength)
                    delta[a] += pull
                    delta[b] -= pull
                }

                for i in 0..<count where mobility[i] > 0 {
                    let move = delta[i] * (2 * step * mobility[i])
                    let length = simd_length(move)
                    positions[i] += length > maxMovePerStep ? move / length * maxMovePerStep : move
                }
            }

            var relaxed = graph
            for i in 0..<count { relaxed.nodes[i].position = positions[i] }
            return relaxed
        }

        private static func cell(_ p: SIMD3<Float>) -> (Int32, Int32, Int32) {
            (Int32((p.x / minSpacing).rounded(.down)), Int32((p.y / minSpacing).rounded(.down)), Int32((p.z / minSpacing).rounded(.down)))
        }

        private static let bias: Int64 = 1 << 20
        private static let mask: Int64 = (1 << 21) - 1

        private static func key(_ c: (Int32, Int32, Int32)) -> Int64 {
            ((Int64(c.0) + bias) & mask) << 42 | ((Int64(c.1) + bias) & mask) << 21 | ((Int64(c.2) + bias) & mask)
        }

        private static func unpack(_ k: Int64) -> (Int32, Int32, Int32) {
            (Int32((k >> 42) & mask - bias), Int32((k >> 21) & mask - bias), Int32(k & mask - bias))
        }
    }
}
```

(Note on `unpack`: Swift's `&` binds tighter than `-` only in some languages — in Swift `&` is a multiplication-precedence operator, so `(k >> 42) & mask - bias` parses as `((k >> 42) & mask) - bias`. Keep the expression as written.)

`MindControlModel.swift`: replace `return (tree, ConeTreeLayout.graph(for: tree, dependencies: found))` with

```swift
                    let laidOut = ConeTreeLayout.graph(for: tree, dependencies: found)
                    return (tree, try Relaxation.relax(laidOut))
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh RelaxationTests ModelTests DensityTests` → all pass. If `separatesCrowdedNodes` falls short of 0.9 × minSpacing, raise the final step (0.05 → 0.15) before touching `iterations`; if `tenThousandNodesRelaxQuickly` misses its budget, profile before changing constants. Ledger either change.

- [ ] **Step 5: Commit.**

```bash
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl
git commit -m "mindcontrol: relax the layout so nodes keep their distance

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
# Phase 3 — Inspection

### Task 9: Highlight (focus and dim)

**Files:**
- Modify: `Renderer/ShaderTypes.h`, `Renderer/GraphBuffers.swift`, `Renderer/Renderer.swift`, `Renderer/Shaders/Nodes.metal`, `Edges.metal`, `Signals.metal`
- Test: `macos/Tests/MindControl/GraphBuffersTests.swift`, `RendererTests.swift`

**Interfaces:**
- Produces: `MCNodeInstance.highlight: Float`; `GraphBuffers.sourceNodes: [GraphNode]` (deduped, buffer order); on `Renderer`: `private(set) var nodes: [GraphNode]`, `nodePositions: [SIMD3<Float>]`, `nodeRadii: [Float]`, `func neighbours(of index: Int) -> [Int]`, `func setFocus(_ index: Int?)`, `private(set) var focusedIndex: Int?`, statics `focusHighlight = 1.6`, `neighbourHighlight = 1.25`, `dimmedHighlight = 0.12`.

- [ ] **Step 1: Write the failing tests.** Append inside `struct GraphBuffersTests`:

```swift
    @Test func highlightStartsAtOneAndSourceNodesMatchBufferOrder() {
        let graph = Graph(nodes: [node("a"), node("a"), node("b")], edges: [])
        let buffers = GraphBuffers(graph: graph)
        #expect(buffers.nodes.allSatisfy { $0.highlight == 1 })
        #expect(buffers.sourceNodes.map(\.id) == ["a", "b"])
    }
```

Append inside `struct RendererTests`:

```swift
    @Test func focusDimsEverythingElse() throws {
        let renderer = try Renderer()
        renderer.setGraph(.sample)
        let normal = try renderAverage(using: renderer)
        let docs = try #require(renderer.nodes.firstIndex { $0.id == "Docs/0" })
        renderer.setFocus(docs)
        #expect(renderer.focusedIndex == docs)
        #expect(try renderAverage(using: renderer) < normal)
        renderer.setFocus(nil)
        #expect(abs(try renderAverage(using: renderer) - normal) < 1e-9)
    }

    @Test func neighboursFollowEdges() throws {
        let renderer = try Renderer()
        renderer.setGraph(.sample)
        let views0 = try #require(renderer.nodes.firstIndex { $0.id == "Views/0" })
        let neighbourIDs = Set(renderer.neighbours(of: views0).map { renderer.nodes[$0].id })
        #expect(neighbourIDs == ["Views", "Graph/1"])     // its folder, and the file it uses
    }
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh GraphBuffersTests RendererTests` → compile FAIL.

- [ ] **Step 3: Implement.**

`Renderer/ShaderTypes.h` — `MCNodeInstance` gains a final field (still 64 bytes):

```c
    float highlight;       // 1 normal; >1 focused or neighbour; <1 dimmed
```

`Renderer/GraphBuffers.swift` — add `let sourceNodes: [GraphNode]`; collect them in the node loop and pass `highlight: 1`:

```swift
            var sourceNodes: [GraphNode] = []
            for node in graph.nodes where index[node.id] == nil {
                index[node.id] = UInt32(nodes.count)
                sourceNodes.append(node)
                nodes.append(MCNodeInstance(
                    position: node.position,
                    radius: NodeStyle.radius(for: node.kind),
                    color: NodeStyle.color(for: node.kind),
                    phase: StableHash.unit(node.id) * 2 * .pi,
                    intensity: node.weight,
                    highlight: 1
                ))
            }
            self.sourceNodes = sourceNodes
```

`Renderer/Renderer.swift` — add state and API:

```swift
        static let focusHighlight: Float = 1.6
        static let neighbourHighlight: Float = 1.25
        static let dimmedHighlight: Float = 0.12

        /// Graph nodes in GPU buffer order (index i here is instance i in the node buffer).
        private(set) var nodes: [GraphNode] = []
        private(set) var nodePositions: [SIMD3<Float>] = []
        private(set) var nodeRadii: [Float] = []
        private(set) var focusedIndex: Int?
        private var adjacency: [[Int]] = []

        func neighbours(of index: Int) -> [Int] {
            adjacency.indices.contains(index) ? adjacency[index] : []
        }

        /// Brightens `index` and its direct neighbours and dims everything else; nil restores everything.
        func setFocus(_ index: Int?) {
            guard let nodeBuffer, nodeCount > 0 else { focusedIndex = nil; return }
            let instances = nodeBuffer.contents().bindMemory(to: MCNodeInstance.self, capacity: nodeCount)
            guard let index, index >= 0, index < nodeCount else {
                for i in 0..<nodeCount { instances[i].highlight = 1 }
                focusedIndex = nil
                return
            }
            for i in 0..<nodeCount { instances[i].highlight = Self.dimmedHighlight }
            for neighbour in adjacency[index] { instances[neighbour].highlight = Self.neighbourHighlight }
            instances[index].highlight = Self.focusHighlight
            focusedIndex = index
        }
```

and at the end of `setGraph`:

```swift
            nodes = buffers.sourceNodes
            nodePositions = buffers.nodes.map(\.position)
            nodeRadii = buffers.nodes.map(\.radius)
            adjacency = Array(repeating: [], count: nodeCount)
            for edge in buffers.edges {
                adjacency[Int(edge.a)].append(Int(edge.b))
                adjacency[Int(edge.b)].append(Int(edge.a))
            }
            focusedIndex = nil
```

Shaders:
- `Nodes.metal`: add `float highlight;` to `NodeOut`, set `out.highlight = n.highlight;` in the vertex shader, and make the fragment's return `return float4(rgb * in.intensity * in.highlight * in.fog, 0.0);`.
- `Edges.metal`: in both vertex shaders multiply the colour by `min(na.highlight, nb.highlight)`:
  `out.color = kContainsColor * min(na.intensity, nb.intensity) * min(na.highlight, nb.highlight);` and
  `out.color = kUsesColor * min(na.intensity, nb.intensity) * min(na.highlight, nb.highlight);`
- `Signals.metal`: `out.color = kSignalColor * min(na.intensity, nb.intensity) * min(na.highlight, nb.highlight);`

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh GraphBuffersTests RendererTests DensityTests` → all pass.

- [ ] **Step 5: Commit.**

```bash
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl
git commit -m "mindcontrol: focus highlights a node and its neighbours

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Picking and the camera snapshot

**Files:**
- Create: `Renderer/Picking.swift`, `macos/Tests/MindControl/PickingTests.swift`
- Modify: `Renderer/Renderer.swift`

**Interfaces:**
- Consumes: `Renderer.nodePositions/nodeRadii` (Task 9), `Matrix` (tests).
- Produces: `MindControl.CameraSnapshot { viewProjection: simd_float4x4; viewportPoints: SIMD2<Float>; projScaleY: Float }` (`Equatable`); `MindControl.ScreenNode { index: Int; point: CGPoint; radius: CGFloat; depth: Float }`; `MindControl.Picking.project(positions:radii:camera:) -> [ScreenNode]`, `Picking.nearest(to: CGPoint, in: [ScreenNode]) -> Int?`; on `Renderer`: `private(set) var lastCamera: CameraSnapshot?`, `var onFrame: (() -> Void)?` (called after each on-screen frame).

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/PickingTests.swift`

```swift
#if os(macOS)
import CoreGraphics
import Testing
import simd
@testable import Ghostty

private typealias Picking = MindControl.Picking
private typealias CameraSnapshot = MindControl.CameraSnapshot

struct PickingTests {
    /// Identity transform: world x/y in [-1, 1] map straight onto a 200 × 100 pt view.
    private let flat = CameraSnapshot(viewProjection: matrix_identity_float4x4, viewportPoints: SIMD2(200, 100), projScaleY: 1)

    private var perspective: CameraSnapshot {
        let projection = MindControl.Matrix.perspective(fovY: 1, aspect: 2, near: 0.1, far: 100)
        let view = MindControl.Matrix.lookAt(eye: SIMD3(0, 0, 10), target: .zero, up: SIMD3(0, 1, 0))
        return CameraSnapshot(viewProjection: projection * view, viewportPoints: SIMD2(200, 100), projScaleY: projection.columns.1.y)
    }

    @Test func projectsToBottomLeftOriginPoints() {
        let nodes = Picking.project(positions: [SIMD3(0, 0, 0.5), SIMD3(-1, -1, 0.5), SIMD3(1, 1, 0.5)],
                                    radii: [0.1, 0.1, 0.1], camera: flat)
        #expect(nodes.map(\.point) == [CGPoint(x: 100, y: 50), CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 100)])
        #expect(nodes[0].radius == 5)                         // 0.1 × 1 / 1 × 100 / 2
    }

    @Test func tinyNodesKeepAMinimumRadius() {
        let nodes = Picking.project(positions: [.zero], radii: [0.0001], camera: flat)
        #expect(nodes[0].radius == Picking.minimumCorePoints)
    }

    @Test func nearestWithinHitRadius() {
        let nodes = Picking.project(positions: [SIMD3(0, 0, 0.5), SIMD3(0.5, 0, 0.5)], radii: [0.01, 0.01], camera: flat)
        #expect(Picking.nearest(to: CGPoint(x: 103, y: 52), in: nodes) == 0)
        #expect(Picking.nearest(to: CGPoint(x: 148, y: 50), in: nodes) == 1)
        #expect(Picking.nearest(to: CGPoint(x: 125, y: 50), in: nodes) == nil)   // 25 pt from both
    }

    @Test func nearerNodeWinsWhenOverlapping() {
        let nodes = Picking.project(positions: [SIMD3(0, 0, -5), SIMD3(0, 0, 0)], radii: [0.2, 0.2], camera: perspective)
        #expect(Picking.nearest(to: CGPoint(x: 100, y: 50), in: nodes) == 1)
    }

    @Test func nodesBehindTheCameraAreSkipped() {
        let nodes = Picking.project(positions: [SIMD3(0, 0, 20), .zero], radii: [0.2, 0.2], camera: perspective)
        #expect(nodes.map(\.index) == [1])
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh PickingTests` → compile FAIL.

- [ ] **Step 3: Implement `Renderer/Picking.swift`.**

```swift
import CoreGraphics
import simd

extension MindControl {
    /// The camera as of the last rendered frame, in view points.
    struct CameraSnapshot: Equatable {
        let viewProjection: simd_float4x4
        let viewportPoints: SIMD2<Float>
        /// projection[1][1]; converts a world radius at depth w into points.
        let projScaleY: Float
    }

    /// A node on screen, in view points with AppKit's bottom-left origin.
    struct ScreenNode: Equatable {
        let index: Int
        let point: CGPoint
        /// Projected core radius in points.
        let radius: CGFloat
        /// Clip-space w; smaller is nearer the camera.
        let depth: Float
    }

    /// Finds nodes under the pointer by projecting their centres on the CPU.
    enum Picking {
        static let minimumHitRadius: CGFloat = 8
        static let hitSlop: CGFloat = 3
        /// Matches `kMinCorePoints` in Nodes.metal.
        static let minimumCorePoints: CGFloat = 1.4

        static func project(positions: [SIMD3<Float>], radii: [Float], camera: CameraSnapshot) -> [ScreenNode] {
            let size = camera.viewportPoints
            var result: [ScreenNode] = []
            result.reserveCapacity(positions.count)
            for i in positions.indices {
                let clip = camera.viewProjection * SIMD4(positions[i], 1)
                guard clip.w > 0.01 else { continue }
                let ndc = SIMD2(clip.x, clip.y) / clip.w
                // A little past the edges, so labels can slide in as their node approaches.
                guard abs(ndc.x) <= 1.2, abs(ndc.y) <= 1.2 else { continue }
                let point = CGPoint(x: CGFloat((ndc.x * 0.5 + 0.5) * size.x), y: CGFloat((ndc.y * 0.5 + 0.5) * size.y))
                let radius = CGFloat(radii[i] * camera.projScaleY / clip.w * size.y * 0.5)
                result.append(ScreenNode(index: i, point: point, radius: max(minimumCorePoints, radius), depth: clip.w))
            }
            return result
        }

        /// The node nearest `point` within its hit radius; on a near-tie the one closer to the camera wins.
        static func nearest(to point: CGPoint, in nodes: [ScreenNode]) -> Int? {
            var best: ScreenNode?
            var bestDistance = CGFloat.infinity
            for node in nodes {
                let distance = hypot(node.point.x - point.x, node.point.y - point.y)
                guard distance <= max(minimumHitRadius, node.radius + hitSlop) else { continue }
                let tie = abs(distance - bestDistance) <= 0.5
                if distance < bestDistance - 0.5 || (tie && node.depth < (best?.depth ?? .infinity)) {
                    best = node
                    bestDistance = min(bestDistance, distance)
                }
            }
            return best?.index
        }
    }
}
```

`Renderer/Renderer.swift` — add

```swift
        /// The camera of the last encoded frame, for picking and labels.
        private(set) var lastCamera: CameraSnapshot?
        /// Called after each on-screen frame (not for offscreen renders).
        var onFrame: (() -> Void)?
```

In `encodeFrame`, after building `frame`, record the snapshot:

```swift
            lastCamera = CameraSnapshot(viewProjection: frame.viewProjection,
                                        viewportPoints: SIMD2(Float(width), Float(height)) / pixelScale,
                                        projScaleY: frame.projScaleY)
```

and at the end of `draw(in:)`, after `commandBuffer.commit()`:

```swift
            onFrame?()
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh PickingTests RendererTests` → all pass.

- [ ] **Step 5: Commit.**

```bash
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl
git commit -m "mindcontrol: project nodes to screen and pick the one under the pointer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: LabelPlanner

**Files:**
- Create: `Labels/LabelPlanner.swift`, `macos/Tests/MindControl/LabelPlannerTests.swift`

**Interfaces:**
- Consumes: `ScreenNode` (Task 10), `GraphNode`, `ConeTreeLayout.rootID`.
- Produces: `MindControl.PlacedLabel { index; text; frame: CGRect; fontSize: CGFloat; isBold: Bool; opacity: CGFloat }`; `MindControl.LabelPlanner.Input { screen; nodes; focus: Int?; neighbours: Set<Int>; viewport: CGSize; measure: (String, CGFloat, Bool) -> CGSize }`; `LabelPlanner.plan(_:) -> [PlacedLabel]`; statics `budget = 150`, `fileShowRadius = 2.5`, `fileFullRadius = 5`, `gap = 4`; `MindControl.RectGrid`.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/LabelPlannerTests.swift`

```swift
#if os(macOS)
import CoreGraphics
import Testing
@testable import Ghostty

private typealias LabelPlanner = MindControl.LabelPlanner
private typealias ScreenNode = MindControl.ScreenNode
private typealias GraphNode = MindControl.GraphNode

struct LabelPlannerTests {
    private let measure: (String, CGFloat, Bool) -> CGSize = { text, size, _ in
        CGSize(width: CGFloat(text.count) * size * 0.6, height: size * 1.3)
    }

    private func folder(_ id: String, files: Int = 10) -> GraphNode {
        GraphNode(id: id, label: id.split(separator: "/").last.map(String.init) ?? id, kind: .folder,
                  position: .zero, descendantFiles: files)
    }

    private func file(_ id: String) -> GraphNode {
        GraphNode(id: id, label: id.split(separator: "/").last.map(String.init) ?? id, kind: .source, position: .zero)
    }

    private func screen(_ index: Int, _ x: CGFloat, _ y: CGFloat, radius: CGFloat = 4) -> ScreenNode {
        ScreenNode(index: index, point: CGPoint(x: x, y: y), radius: radius, depth: 1)
    }

    private func plan(_ nodes: [GraphNode], _ screen: [ScreenNode], focus: Int? = nil, neighbours: Set<Int> = [],
                      viewport: CGSize = CGSize(width: 800, height: 600)) -> [MindControl.PlacedLabel] {
        LabelPlanner.plan(.init(screen: screen, nodes: nodes, focus: focus, neighbours: neighbours,
                                viewport: viewport, measure: measure))
    }

    @Test func budgetIsRespected() {
        let nodes = (0..<400).map { folder("f\($0)") }
        let screen = (0..<400).map { self.screen($0, CGFloat($0 % 20) * 200, CGFloat($0 / 20) * 40) }
        #expect(plan(nodes, screen, viewport: CGSize(width: 4_000, height: 4_000)).count == LabelPlanner.budget)
    }

    @Test func labelsNeverOverlap() {
        var rng = MindControl.SplitMix64(seed: 3)
        let nodes = (0..<300).map { folder("folder\($0)") }
        let screen = (0..<300).map { self.screen($0, CGFloat.random(in: 0...800, using: &rng), CGFloat.random(in: 0...600, using: &rng)) }
        let labels = plan(nodes, screen)
        #expect(!labels.isEmpty)
        for i in labels.indices {
            for j in labels.indices where j > i {
                #expect(!labels[i].frame.intersects(labels[j].frame))
            }
        }
    }

    @Test func farFilesHiddenCloseFilesShown() {
        let nodes = [file("a/far.swift"), file("a/near.swift")]
        let labels = plan(nodes, [screen(0, 100, 100, radius: 1.4), screen(1, 300, 300, radius: 6)])
        #expect(labels.map(\.text) == ["near.swift"])
        #expect(labels.first?.opacity == 0.85)
        #expect(labels.first?.isBold == false)
    }

    @Test func foldersBeatFilesAndBiggerFoldersWin() {
        let nodes = [file("x/a.swift"), folder("small", files: 2), folder("big", files: 500)]
        // All three at the same spot: only the first placed label fits.
        let labels = plan(nodes, [screen(0, 100, 100, radius: 6), screen(1, 100, 100), screen(2, 100, 100)])
        #expect(labels.map(\.text) == ["big"])
        #expect(labels.first?.isBold == true)
    }

    @Test func focusAndNeighboursAlwaysShownAndFocusShowsItsPath() {
        let nodes = [folder("crowd", files: 900), file("src/deep/focus.swift"), file("src/other.swift")]
        let labels = plan(nodes, [screen(0, 100, 100), screen(1, 100, 100, radius: 1.4), screen(2, 400, 100, radius: 1.4)],
                          focus: 1, neighbours: [2])
        #expect(labels.map(\.text) == ["src/deep/focus.swift", "other.swift"])
        #expect(labels.allSatisfy { $0.opacity >= 0.9 })
    }

    @Test func othersDimWhileSomethingIsFocused() {
        let nodes = [folder("a"), folder("b")]
        let labels = plan(nodes, [screen(0, 100, 100), screen(1, 100, 400)], focus: 0)
        let b = labels.first { $0.text == "b" }
        #expect(abs((b?.opacity ?? 0) - 0.9 * 0.35) < 1e-6)
    }

    @Test func offscreenLabelsAreSkipped() {
        let labels = plan([folder("gone")], [screen(0, -500, 100)])
        #expect(labels.isEmpty)
    }

    @Test func labelSitsRightOfItsNode() {
        let labels = plan([folder("src")], [screen(0, 100, 100, radius: 4)])
        #expect(labels.first?.frame.minX == 100 + 4 + LabelPlanner.gap)
        #expect(abs((labels.first?.frame.midY ?? 0) - 100) < 1e-9)
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh LabelPlannerTests` → compile FAIL.

- [ ] **Step 3: Implement `Labels/LabelPlanner.swift`.**

```swift
import CoreGraphics
import Foundation

extension MindControl {
    struct PlacedLabel: Equatable {
        let index: Int
        let text: String
        /// View points, AppKit bottom-left origin.
        let frame: CGRect
        let fontSize: CGFloat
        let isBold: Bool
        let opacity: CGFloat
    }

    /// Chooses which labels show and where: focus first, then its neighbours, folders by size, then
    /// files that are close enough to read. Never overlaps two labels and never exceeds the budget.
    enum LabelPlanner {
        static let budget = 150
        static let fileShowRadius: CGFloat = 2.5
        static let fileFullRadius: CGFloat = 5
        static let gap: CGFloat = 4

        struct Input {
            let screen: [ScreenNode]
            /// Indexed by `ScreenNode.index`.
            let nodes: [GraphNode]
            let focus: Int?
            let neighbours: Set<Int>
            let viewport: CGSize
            /// Measures text (string, font size, bold); injected so tests don't depend on fonts.
            let measure: (String, CGFloat, Bool) -> CGSize
        }

        private struct Candidate {
            let screen: ScreenNode
            let tier: Int        // 0 focus, 1 neighbour, 2 folder, 3 file
            let key: CGFloat     // lower first within a tier
        }

        static func plan(_ input: Input) -> [PlacedLabel] {
            var candidates: [Candidate] = []
            for s in input.screen {
                let node = input.nodes[s.index]
                if s.index == input.focus {
                    candidates.append(Candidate(screen: s, tier: 0, key: 0))
                } else if input.neighbours.contains(s.index) {
                    candidates.append(Candidate(screen: s, tier: 1, key: -s.radius))
                } else if node.kind == .folder || node.kind == .root {
                    candidates.append(Candidate(screen: s, tier: 2, key: -CGFloat(node.descendantFiles)))
                } else if s.radius >= fileShowRadius {
                    candidates.append(Candidate(screen: s, tier: 3, key: -s.radius))
                }
            }
            candidates.sort { a, b in
                if a.tier != b.tier { return a.tier < b.tier }
                if a.key != b.key { return a.key < b.key }
                return a.screen.index < b.screen.index
            }

            let highlighting = input.focus != nil
            var placed: [PlacedLabel] = []
            var occupied = RectGrid(cell: 64)
            for candidate in candidates {
                if placed.count >= budget { break }
                let s = candidate.screen
                let node = input.nodes[s.index]
                let isFolder = node.kind == .folder || node.kind == .root
                let text = candidate.tier == 0 && node.id != ConeTreeLayout.rootID ? node.id : node.label
                let fontSize: CGFloat = isFolder ? 12 + min(2, CGFloat(log10(Double(max(1, node.descendantFiles))))) : 10.5
                let size = input.measure(text, fontSize, isFolder)
                let frame = CGRect(x: s.point.x + s.radius + gap, y: s.point.y - size.height / 2,
                                   width: size.width, height: size.height)
                guard frame.maxX > 0, frame.minX < input.viewport.width,
                      frame.maxY > 0, frame.minY < input.viewport.height,
                      !occupied.intersects(frame) else { continue }

                var opacity: CGFloat = isFolder
                    ? 0.9
                    : min(1, max(0, (s.radius - fileShowRadius) / (fileFullRadius - fileShowRadius))) * 0.85
                if candidate.tier <= 1 {
                    opacity = max(opacity, 0.9)
                } else if highlighting {
                    opacity *= 0.35
                }
                guard opacity > 0.02 else { continue }

                occupied.insert(frame)
                placed.append(PlacedLabel(index: s.index, text: text, frame: frame, fontSize: fontSize,
                                          isBold: isFolder, opacity: opacity))
            }
            return placed
        }
    }

    /// Rectangles bucketed into a coarse grid for quick overlap tests.
    struct RectGrid {
        let cell: CGFloat
        private var buckets: [Int64: [CGRect]] = [:]

        init(cell: CGFloat) { self.cell = cell }

        func intersects(_ rect: CGRect) -> Bool {
            keys(for: rect).contains { key in buckets[key]?.contains { $0.intersects(rect) } ?? false }
        }

        mutating func insert(_ rect: CGRect) {
            for key in keys(for: rect) { buckets[key, default: []].append(rect) }
        }

        private func keys(for rect: CGRect) -> [Int64] {
            let x0 = Int64((rect.minX / cell).rounded(.down)), x1 = Int64((rect.maxX / cell).rounded(.down))
            let y0 = Int64((rect.minY / cell).rounded(.down)), y1 = Int64((rect.maxY / cell).rounded(.down))
            var keys: [Int64] = []
            for x in x0...x1 { for y in y0...y1 { keys.append(x << 32 ^ (y & 0xFFFF_FFFF)) } }
            return keys
        }
    }
}
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh LabelPlannerTests` → 8 passed.

- [ ] **Step 5: Commit.**

```bash
git add -A macos/Sources/Features/MindControl/Labels macos/Tests/MindControl/LabelPlannerTests.swift
git commit -m "mindcontrol: plan which labels show without overlapping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Inspector, labels overlay, hover/click, info card

**Files:**
- Create: `Inspection/Inspector.swift`, `Inspection/NodeDetails.swift`, `Inspection/InfoCard.swift`, `Labels/LabelOverlayView.swift`, `macos/Tests/MindControl/InspectorTests.swift`
- Modify: `Renderer/MetalGraphView.swift`, `MindControlPanel.swift`

**Interfaces:**
- Consumes: `Renderer.setFocus/nodes/nodePositions/nodeRadii/neighbours/lastCamera/onFrame` (Tasks 9–10), `Picking`, `LabelPlanner`.
- Produces: `@MainActor final class MindControl.Inspector: ObservableObject` with `hovered`, `pinned`, `focus`, `onFocusChange`, `hover(_:)`, `click(_:)`, `escape() -> Bool`, `reset()`; `MindControl.NodeDetails.make(graph:nodeID:) -> NodeDetails?` with `name, path, kind, uses, usedBy, files`; `MindControl.InfoCard(details:)`; `MindControl.LabelOverlayView` (`show(_:)`, `static measure(_:_:_:)`); `MetalGraphView(renderer:inspector:onEscape:)`.

- [ ] **Step 1: Write the failing tests** — `macos/Tests/MindControl/InspectorTests.swift`

```swift
#if os(macOS)
import Testing
@testable import Ghostty

private typealias Inspector = MindControl.Inspector
private typealias NodeDetails = MindControl.NodeDetails

@MainActor
struct InspectorTests {
    @Test func hoverSetsFocus() {
        let inspector = Inspector()
        var changes: [Int?] = []
        inspector.onFocusChange = { changes.append($0) }
        inspector.hover(3)
        inspector.hover(3)                 // no change, no callback
        #expect(inspector.focus == 3)
        #expect(changes == [3])
    }

    @Test func hoverEmptyClearsFocus() {
        let inspector = Inspector()
        inspector.hover(3)
        inspector.hover(nil)
        #expect(inspector.focus == nil)
    }

    @Test func clickPinsAndHoverDoesNotMoveAPin() {
        let inspector = Inspector()
        inspector.click(5)
        inspector.hover(2)
        #expect(inspector.pinned == 5)
        #expect(inspector.focus == 5)
        inspector.click(5)                 // clicking the pinned node again unpins
        #expect(inspector.pinned == nil)
        #expect(inspector.focus == 2)
    }

    @Test func clickEmptySpaceUnpins() {
        let inspector = Inspector()
        inspector.click(5)
        inspector.click(nil)
        #expect(inspector.pinned == nil)
    }

    @Test func escapeUnpinsFirstThenReportsNothingToDo() {
        let inspector = Inspector()
        inspector.click(1)
        #expect(inspector.escape())
        #expect(inspector.pinned == nil)
        #expect(!inspector.escape())
    }

    @Test func resetClearsEverything() {
        let inspector = Inspector()
        var last: Int?? = .none
        inspector.onFocusChange = { last = $0 }
        inspector.hover(1)
        inspector.click(2)
        inspector.reset()
        #expect(inspector.hovered == nil && inspector.pinned == nil)
        #expect(last == .some(nil))
    }

    @Test func nodeDetailsCountUses() {
        let graph = MindControl.Graph.sample
        let views0 = NodeDetails.make(graph: graph, nodeID: "Views/0")
        #expect(views0?.name == "Views 1")
        #expect(views0?.path == "Views/0")
        #expect(views0?.uses == 1)          // Views/0 → Graph/1
        #expect(views0?.usedBy == 0)
        let graph1 = NodeDetails.make(graph: graph, nodeID: "Graph/1")
        #expect(graph1?.usedBy == 1)
        let folder = NodeDetails.make(graph: MindControl.ConeTreeLayout.graph(for: MindControl.FileTree(
            rootName: "p", rootPath: "/p", files: ["src/a.swift", "src/b.swift"], totalFileCount: 2)), nodeID: "src")
        #expect(folder?.files == 2)
        #expect(NodeDetails.make(graph: graph, nodeID: "missing") == nil)
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure.** `.superpowers/mc-test.sh InspectorTests` → compile FAIL.

- [ ] **Step 3: Implement the pure pieces.**

`Inspection/Inspector.swift`:

```swift
import Combine

extension MindControl {
    /// Hover and pin state for the map. The focus is the pinned node, else the hovered one.
    @MainActor
    final class Inspector: ObservableObject {
        @Published private(set) var hovered: Int?
        @Published private(set) var pinned: Int?
        /// Called whenever `focus` changes.
        var onFocusChange: ((Int?) -> Void)?

        var focus: Int? { pinned ?? hovered }

        func hover(_ index: Int?) {
            guard hovered != index else { return }
            change { hovered = index }
        }

        /// A click on a node pins it (or unpins it if already pinned); a click on empty space unpins.
        func click(_ index: Int?) {
            change { pinned = (index == nil || pinned == index) ? nil : index }
        }

        /// Esc unpins. Returns false when nothing was pinned, so the caller can close the panel instead.
        func escape() -> Bool {
            guard pinned != nil else { return false }
            change { pinned = nil }
            return true
        }

        func reset() {
            change {
                hovered = nil
                pinned = nil
            }
        }

        private func change(_ update: () -> Void) {
            let before = focus
            update()
            if focus != before { onFocusChange?(focus) }
        }
    }
}
```

`Inspection/NodeDetails.swift`:

```swift
extension MindControl {
    /// What the info card shows for a node.
    struct NodeDetails: Equatable {
        let name: String
        let path: String
        let kind: NodeKind
        /// Files this file uses.
        let uses: Int
        /// Files that use this file.
        let usedBy: Int
        /// For folders: files beneath.
        let files: Int

        static func make(graph: Graph, nodeID: String) -> NodeDetails? {
            guard let node = graph.nodes.first(where: { $0.id == nodeID }) else { return nil }
            var uses = 0, usedBy = 0
            for edge in graph.edges where edge.kind == .uses {
                if edge.from == nodeID { uses += 1 }
                if edge.to == nodeID { usedBy += 1 }
            }
            return NodeDetails(name: node.label, path: node.id == ConeTreeLayout.rootID ? "/" : node.id,
                               kind: node.kind, uses: uses, usedBy: usedBy, files: node.descendantFiles)
        }
    }
}
```

- [ ] **Step 4: Run tests.** `.superpowers/mc-test.sh InspectorTests` → 7 passed.

- [ ] **Step 5: Overlay, info card and wiring.**

`Labels/LabelOverlayView.swift`:

```swift
import AppKit
import QuartzCore

extension MindControl {
    /// Text labels over the Metal view, drawn with a reusable pool of CATextLayers. Never takes the mouse.
    final class LabelOverlayView: NSView {
        private var pool: [CATextLayer] = []
        private static var sizeCache: [String: CGSize] = [:]

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        static func font(size: CGFloat, bold: Bool) -> NSFont {
            .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        }

        /// Text size, cached because labels are re-planned every frame.
        static func measure(_ text: String, _ size: CGFloat, _ bold: Bool) -> CGSize {
            let key = "\(bold ? "b" : "r")\(size)|\(text)"
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
                text.shadowColor = NSColor.black.cgColor
                text.shadowOpacity = 0.8
                text.shadowRadius = 2
                text.shadowOffset = .zero
                text.alignmentMode = .left
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
                text.font = Self.font(size: label.fontSize, bold: label.isBold)
                text.fontSize = label.fontSize
                text.frame = label.frame
                text.opacity = Float(label.opacity)
            }
            CATransaction.commit()
        }
    }
}
```

`Inspection/InfoCard.swift`:

```swift
import SwiftUI

extension MindControl {
    /// Details for the pinned node.
    struct InfoCard: View {
        let details: NodeDetails

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(details.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(details.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
            }
            .foregroundColor(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.45)))
            .padding(14)
            .allowsHitTesting(false)
        }

        private var summary: String {
            switch details.kind {
            case .root, .folder:
                return "Folder · \(details.files.formatted()) files"
            case .source, .document:
                let kind = details.kind == .document ? "Document" : "Source"
                return "\(kind) · uses \(details.uses) · used by \(details.usedBy)"
            }
        }
    }
}
```

`Renderer/MetalGraphView.swift` — replace the whole file:

```swift
import SwiftUI
import MetalKit

extension MindControl {
    /// MTKView that turns mouse and trackpad input into camera moves, hover and pins,
    /// and draws node labels in an overlay.
    final class GraphMTKView: MTKView {
        var renderer: Renderer?
        var inspector: Inspector?
        var onEscape: (() -> Void)?

        private let labels = LabelOverlayView()
        private var screenNodes: [ScreenNode] = []
        private var mouseDownPoint: CGPoint?
        private var trackingArea: NSTrackingArea?

        override init(frame: CGRect, device: MTLDevice?) {
            super.init(frame: frame, device: device)
            labels.frame = bounds
            labels.autoresizingMask = [.width, .height]
            addSubview(labels)
        }

        required init(coder: NSCoder) {
            super.init(coder: coder)
            labels.frame = bounds
            labels.autoresizingMask = [.width, .height]
            addSubview(labels)
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Take keyboard focus so Esc reaches us while the panel is open.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func keyDown(with event: NSEvent) {
            // Esc unpins first, then closes. Other keys are swallowed so the panel doesn't beep;
            // menu shortcuts still arrive via performKeyEquivalent.
            guard event.keyCode == 53 else { return }
            if inspector?.escape() == true { return }
            onEscape?()
        }

        override func mouseMoved(with event: NSEvent) {
            inspector?.hover(pick(event))
        }

        override func mouseExited(with event: NSEvent) {
            inspector?.hover(nil)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            renderer?.camera.beginDrag()
        }

        override func mouseDragged(with event: NSEvent) {
            renderer?.camera.drag(dx: Float(event.deltaX), dy: Float(event.deltaY))
        }

        override func mouseUp(with event: NSEvent) {
            renderer?.camera.endDrag()
            let point = convert(event.locationInWindow, from: nil)
            if let start = mouseDownPoint, hypot(point.x - start.x, point.y - start.y) < 3 {
                inspector?.click(pick(event))
            }
            mouseDownPoint = nil
        }

        override func scrollWheel(with event: NSEvent) {
            let step: Float = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
            renderer?.camera.zoom(by: exp(-Float(event.scrollingDeltaY) * step))
        }

        override func magnify(with event: NSEvent) {
            renderer?.camera.zoom(by: 1 / max(0.1, 1 + Float(event.magnification)))
        }

        private func pick(_ event: NSEvent) -> Int? {
            Picking.nearest(to: convert(event.locationInWindow, from: nil), in: screenNodes)
        }

        /// After each frame: re-project nodes (for picking) and re-plan labels.
        func frameDidRender() {
            guard let renderer, let camera = renderer.lastCamera else { return }
            screenNodes = Picking.project(positions: renderer.nodePositions, radii: renderer.nodeRadii, camera: camera)
            let focus = inspector?.focus
            let neighbours = focus.map { Set(renderer.neighbours(of: $0)) } ?? []
            labels.show(LabelPlanner.plan(.init(screen: screenNodes, nodes: renderer.nodes, focus: focus,
                                                neighbours: neighbours, viewport: bounds.size,
                                                measure: LabelOverlayView.measure)))
        }
    }

    struct MetalGraphView: NSViewRepresentable {
        let renderer: Renderer
        let inspector: Inspector
        var onEscape: (() -> Void)?

        func makeNSView(context: Context) -> GraphMTKView {
            let view = GraphMTKView(frame: .zero, device: renderer.device)
            view.renderer = renderer
            view.inspector = inspector
            view.onEscape = onEscape
            view.delegate = renderer
            view.colorPixelFormat = Renderer.outputFormat
            view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            view.framebufferOnly = true
            view.preferredFramesPerSecond = 120
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderer.onFrame = { [weak view] in view?.frameDidRender() }
            inspector.onFocusChange = { [weak renderer] focus in renderer?.setFocus(focus) }
            return view
        }

        func updateNSView(_ view: GraphMTKView, context: Context) {
            view.onEscape = onEscape
        }
    }
}
```

`MindControlPanel.swift`:
- Add `@StateObject private var inspector = Inspector()`.
- Change the Metal view line to `MetalGraphView(renderer: renderer, inspector: inspector, onEscape: onClose)`.
- After the legend block add the info card:

```swift
                if let pinned = inspector.pinned, let renderer, renderer.nodes.indices.contains(pinned),
                   let graph = model.graph, let details = NodeDetails.make(graph: graph, nodeID: renderer.nodes[pinned].id) {
                    InfoCard(details: details)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
```

- In `.onChange(of: model.graphVersion)`, reset before swapping graphs:

```swift
            .onChange(of: model.graphVersion) { _ in
                inspector.reset()
                renderer?.setGraph(model.graph ?? Self.emptyGraph)
            }
```

- [ ] **Step 6: Full suite, build, manual check.**

```bash
cd macos && ./skins-test.sh > /dev/null 2>&1; echo "exit=$?"
grep -oE "Test case '[^']+' (passed|failed)" build/last-test.log | sort -u | awk '{print $NF}' | sort | uniq -c
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -project Ghostty.xcodeproj -scheme Ghostty -configuration Debug SYMROOT="$PWD/build" build > build/last-build.log 2>&1; grep -E "error:|\*\* BUILD" build/last-build.log
cd ..
```
Expected: `exit=0`, no failures, `** BUILD SUCCEEDED **`. Relaunch only the debug instance this session started (find it with `pgrep -f "worktrees/mindcontrol/macos/build/Debug/Ghostty.app/Contents/MacOS"`; never touch `/Applications/Lostty.app`), then `open -n macos/build/Debug/Ghostty.app`. The interactive check is the user's (this session can't click): folder labels visible; file labels fade in when zooming; hover lights a node and its neighbours and shows its path; click pins and shows the info card; Esc unpins, Esc again closes; moving the mouse off the map clears the hover.

- [ ] **Step 7: Commit.**

```bash
git add -A macos/Sources/Features/MindControl macos/Tests/MindControl
git commit -m "mindcontrol: labels, hover and pin inspection with an info card

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Tuning, docs, spec refresh

**Files:**
- Modify: `MINDCONTROL.md`, `docs/superpowers/specs/2026-10-06-mindcontrol-relationships-labels-design.md`
- Possibly modify (constants only): `ConeTreeLayout.swift`, `Relaxation.swift`, `Edges.metal`, `Signals.metal`, `LabelPlanner.swift`

- [ ] **Step 1: Offscreen renders.** Copy the scratch snapshot test back in, run it, look, then move it out again:

```bash
cp .superpowers/ZZSnapshotTests.swift macos/Tests/MindControl/
(cd macos && ./skins-test.sh ZZSnapshotTests | tail -1)
mv macos/Tests/MindControl/ZZSnapshotTests.swift .superpowers/
```

The snapshot test calls `MindControl.TreeLayout.graph(for:)`; before running, change that call to `try MindControl.Relaxation.relax(MindControl.ConeTreeLayout.graph(for: tree, dependencies: try MindControl.DependencyScanner.scan(tree: tree)))`. Read the PNGs in the scratchpad (`mc-arca.png`, `mc-lostty.png`). Look for: clusters visibly separated; amber curves present and readable against the hairlines; no blown-out regions.

- [ ] **Step 2: Tune only what the renders show.** Separation too weak → raise `subfolderDistance`'s constant (2 → 3); amber curves too loud on Lostty → lower uses intensity (`core * 0.45 + glow * 0.15` → `0.35 / 0.10`); hairlines invisible → contains intensity `0.15 / 0.05` → `0.22 / 0.07`. Re-run the full suite after any change; ledger each.

- [ ] **Step 3: Update `MINDCONTROL.md`.** Replace its bullet list with:

```markdown
- **Lines:** thin blue-grey lines mean a folder contains a file; amber curves mean one file uses
  another (imports in Zig, TypeScript/JavaScript and Python; type references in Swift; links in
  Markdown). Signals travel along amber curves toward the file being used.
- **Labels:** folder names are always shown; file names fade in as you zoom close.
- **Inspect:** hover a node to light it and everything it connects to; click to pin it and see its
  path and how many files it uses and is used by. Esc unpins; Esc again closes.
- **Orbit:** drag. **Zoom:** scroll or pinch.
- Large projects are capped at 10,000 files, keeping the shallowest ones; the status line says when.
- Nothing is drawn while the visualizer is closed.
```

- [ ] **Step 4: Fold the plan refinements into the spec.** Set `Status: Implemented` and add a "Refinements during implementation" section listing items 1–7 from this plan's "Plan-level refinements to the spec", plus any tuning values changed in Step 2.

- [ ] **Step 5: Full suite and commit.**

```bash
(cd macos && ./skins-test.sh > /dev/null 2>&1; echo "exit=$?")
git add -A MINDCONTROL.md docs macos/Sources/Features/MindControl
git commit -m "mindcontrol: tuning, docs and spec refresh for relationships and labels

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected: `exit=0` before the commit.
