# MindControl Flow Map — notes for a rebuild

Written 2026-10-07, during the first build of
`2026-10-07-mindcontrol-flow-map.md` (plan) against
`../specs/2026-10-07-mindcontrol-flow-map-design.md` (spec). Both are unchanged
from the versions approved before implementation.

The first build reached Task 10. Its code is saved on branch
`mindcontrol-flowmap-build-1`. The plan and spec as approved are the starting
point of branch `mindcontrol-flowmap-plan`.

These are the corrections the first build found. Apply them when rebuilding, so
the same bugs aren't rediscovered. Each one changes the plan's code or tests.
The spec stays the binding authority.

## Run every subagent on Opus

Builders, task reviewers, re-reviewers and the final reviewer all use Opus.

## Task 1 — wrong-folder investigation

Already done. Lostty's OSC 7 → `surfaceView.pwd` path reports a `cd` correctly.
The stale folder came from the old MindControl, which loaded only when the panel
opened and cached by root. The Task 16 model removes the cache. Re-check it live
during Task 20's Arca acceptance. Task 1 can be skipped in a rebuild.

## Task 2 — remove the 3D map

- `BloomPassTests.swift` has typealiases to deleted types; remove them.
- `RendererTests.renderAverage` uses a private typealias. Make the typealias
  `fileprivate`, or the static helper won't compile.
- The sidebar test that checked `mindControl.state == .noProject` should inject
  a working directory and check `mindControl.pwd`.

## Task 3 — flow file parsing

- **Trailing commas.** macOS `JSONSerialization` accepts trailing commas
  silently. Add a strict pre-scan that reports "Not valid JSON: trailing comma"
  at the comma's line. It skips commas inside strings, including after `\"`.
  Pin `trailingCommaReportsLine` to `line == 4`.
- **Error lines.** The plan finds an item's line by the first `"id": "<id>"`
  in the whole file. That is wrong when ids repeat across lists (the fixture
  has zone `ring` and system `ring`) or within a list. Instead, record where
  each list element starts, and where each system's parts start, with a
  byte-level locator. Count UTF-8 `\n` bytes so CRLF files work. A missing
  `id` points at its item, not the list key.
- **Test.** Test a non-comma syntax error with a line, and a valid file whose
  strings contain `,]`, `,}` and `\"`.
- **Compiler.** `private typealias FlowMap` in the `Parser` extension doesn't
  compile; put the alias inside `Parser`.

## Task 5 — FlowSource

When `root` is a subfolder of a git repo (Change… can pick one), make both
modes relative to `root`:

- **Working tree.** Strip `git -C root rev-parse --show-prefix` from the
  scanner's files, keeping only those under the prefix.
- **Revision.** Read with `"\(revision):./\(path)"`.
- **Test.** Add one with the fixture under `sub/` and unrelated files outside it.

## Task 6 — FlowCheck

- **Test bug.** `missingViaIsStaleAndNoViaIsUnverified` wrongly expects flow
  `check` to be stale. `SpeechGate.swift`, in the same system, still declares
  `append`. Expect `pcm`, `commit` and `discard` stale, and `check` not.
- **CRLF lines.** Via line numbers must count `\n` UTF-16 code units in the
  `NSString` prefix (`.utf16.filter { $0 == 0x0A }`), not `Character`s. CRLF
  files otherwise always report line 1. Add a CRLF test.
- **Kept as planned.** Density warnings count in `issueCount`. All unmapped
  files together count as one issue.

## Task 10 — main map layout: zone ordering

The plan's code puts Cloud left of Phone in the Arca fixture. The ring zone
has only control flows, and the phone↔cloud data 2-cycle is broken by id.
Replace the zone ordering with:

1. **Classify zones** by flows of any kind that cross zones.
   - **Leftmost:** every system in the zone is external, and the zone
     receives no flows. This includes a zone with no flows at all.
   - **Rightmost:** every system is external, and the zone receives flows but
     sends none.
   - **Middle:** everything else.
2. **Lay out middle zones** with `Layering` on data edges between middle
   zones.
   - When A→B and B→A both exist, drop the edge from the later-declared zone
     (`map.zones` order; the unzoned block counts as last).
   - Pass keys that sort in declaration order (for example `"0003|cloud"`) so
     ties follow declaration order. Map them back afterwards.
3. **Columns:** leftmost zones stacked, then the middle layers, then rightmost
   zones stacked.
4. **Tests.**
   - A pass-through outside zone, r → x → p, gives r | x | p.
   - A mixed zone in a 2-cycle follows declaration order.
   - An outside zone with no flows sits leftmost.

Do not use a pin that drops transit edges.

## Deferred minor findings worth fixing while rebuilding

- **Glob.** A trailing-slash folder pattern (`relay/src/`) matches nothing.
  Strip a trailing `/`.
- **FlowAge.** A `rev-list` failure, or a map with no `paths`, shows
  `.commits(0)` ("Map up to date"). Return `.hidden` instead.
- **Git.isRepository.** Compare the output to `"true"`; inside `.git` it exits
  0 and prints `false`.
- **LayoutStore.encode.** Filter non-finite positions, and don't overwrite a
  good file with empty data when encoding fails.
- **Empty layouts.** `MapLayout.bounds` of an empty layout is `.null`. Camera
  fitting must guard against it. The plan's `PanZoomCamera.fitting` (Task 13)
  does.
- **ArrowRouter.** Self-flows, part→own-system flows and boxes that overlap
  after a drag route through the box centre. Skip them or draw a loop.
- **Tests.**
  - Several are vacuous or weak: `pathTie` message contains "a", the
    `pinFirst` test, and the single-permutation shuffle test.
  - Add boundary tests for density at exactly 20, 8 and 60.
