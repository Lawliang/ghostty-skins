import Foundation

extension MindControl {
    /// The instructions Draft and Refresh with Claude hand to `claude`. Every rule here must match what
    /// FlowFile, Glob, PathOwnership and FlowCheck accept, or Claude writes a map MindControl rejects.
    enum ClaudePrompts {
        enum Kind { case draft, refresh }

        static let upkeepRule = "When you change how data or control moves between systems, update `.mindcontrol/flow.json`."

        static func draft(projectName: String) -> String {
            """
            You are drafting a MindControl flow map for the project "\(projectName)" in this folder.

            MindControl draws how a project's systems pass data and control to each other. Write `.mindcontrol/flow.json` \
            describing this project. Read the code and any architecture docs (docs/, README, CLAUDE.md, AGENTS.md) first.

            \(formatAndRules)

            ## Steps

            1. Read the code and the docs.
            2. Write `.mindcontrol/flow.json`. Find the hand-off for every flow in the code and record it in "via". \
            Use "when" for branches.
            3. Add this line to the project's CLAUDE.md (create the file if it's missing), under a "MindControl" heading if there's no better place:
               \(upkeepRule)
            4. Check the file is valid JSON, for example with `python3 -m json.tool .mindcontrol/flow.json`.

            MindControl reloads the map as soon as the file is saved.
            """
        }

        static func refresh(projectName: String) -> String {
            """
            You are refreshing the MindControl flow map for the project "\(projectName)" in this folder.

            `.mindcontrol/flow.json` describes how this project's systems pass data and control to each other. \
            The code has moved on since it was written; bring the map up to date.

            1. Read `.mindcontrol/flow.json`.
            2. Find the commit that last changed it: `git log -1 --format=%H -- .mindcontrol/flow.json`. If that prints \
            nothing (the file was never committed) or this folder isn't in git, read the whole project instead and skip to step 4.
            3. Read what changed since: `git log -p <that commit>..HEAD -- ':(glob)<pattern>' …`, with one `':(glob)<pattern>'` \
            for each pattern in the systems' "paths", and read the files those commits touched. Also look at \
            `git diff --stat <that commit>..HEAD` for new source folders no system's "paths" cover yet, and at `git diff HEAD` \
            for changes not committed yet.
            4. Update systems, parts, flows, feature routes and every "via" and "anchor" so they match the code, checking \
            each one where the rules below say MindControl looks. Keep each id that still means the same thing; feature \
            routes, saved positions and the user's habits depend on them. Change a name rather than its id.
            5. Don't touch `.mindcontrol/layout.json`. It holds where the user dragged the boxes; leave positions alone.
            6. Stay within the limits below, merging systems rather than adding more.
            7. Check the file is valid JSON, for example with `python3 -m json.tool .mindcontrol/flow.json`.

            MindControl reloads the map as soon as the file is saved.

            \(formatAndRules)
            """
        }

        static let formatAndRules = """
        ## Format

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
            { "id": "pcm", "from": "audio.capture", "to": "openai", "kind": "data", "carries": "PCM16 24 kHz", "via": "sendAudio" },
            { "id": "commit", "from": "audio.capture", "to": "openai", "kind": "control", "carries": "commit turn",
              "via": "commitTurn", "when": "words heard" }
          ],
          "features": [ { "id": "speech", "name": "A press becomes speech", "route": ["pcm", "commit"] } ]
        }
        ```

        The file is strict JSON: no comments and no trailing commas.

        ## Rules

        - "version" is 1.
        - ids use only lowercase letters, digits and "-" (no capitals, dots, spaces or "_"), and are unique within their \
        list. A part is addressed as "system.part".
        - Required fields: a zone has "id" and "name"; a system has "id" and "name"; a part has "id" and "name"; a flow \
        has "id", "from", "to", "kind" and "carries"; a feature has "id", "name" and "route". The "systems" list is \
        required; "zones", "flows" and "features" are optional. Text values are never empty.
        - Zones are where systems run: a device, the phone, a server, the cloud. Give every system a "zone" naming one \
        of the zones' ids.
        - A system is one real unit of the codebase with one job. "summary" is one sentence.
        - "paths" are glob patterns, relative to this folder, for the source files a system owns:
          - "*" matches within one folder or file name, "**" across folders (including none), "?" one character.
          - A pattern with no wildcard names a file, or a folder and everything inside it.
          - Never end a pattern with "/": "relay/src/" matches nothing. Write "relay/src" or "relay/src/**".
          - When a file matches patterns from more than one system, the pattern with the longest fixed text before its \
        first wildcard wins: "app/Sources/Coordination/Journal*.swift" beats "app/Sources/Coordination/**". Patterns from \
        two systems with equally long fixed text matching the same file are an error, so when one folder holds several \
        systems, give each a pattern with more fixed text than the folder's catch-all.
          - Every source file should belong to a system: MindControl lists source files no system owns as unmapped. \
        It only counts the files it reads (below), so don't cover the others.
        - MindControl reads only source files whose names end in \(codeList(SourceFilter.sourceExtensions, prefix: ".")). \
        It skips everything inside a folder named \(codeList(SourceFilter.excludedDirectories)) (ignoring case) or whose \
        name ends in "Tests", "-tests" or "_tests", and test files: names that, before the extension, end in "Test", \
        "Tests", "Spec", "_test", ".test" or ".spec" or start with "test_" (ModelTests.swift, server_test.go, \
        test_core.py, app.test.ts, app.spec.js). Every "via" and every Swift type "anchor" must be in a file it reads, \
        or the arrow or part is marked stale.
        - "external": true marks things outside this codebase: services, hardware, the OS. Leave "paths" and "parts" out \
        of an external system entirely (even an empty "parts" list is an error).
        - "parts" are a system's main pieces, at most \(FlowCheck.maxPartsPerSystem) parts per system. A part's optional \
        "anchor" ties it to the code, and an anchor that matches nothing marks the part stale:
          - In Swift, a capitalised type name declared with class, struct, enum, protocol, actor or typealias in one of that system's \
        own files (the files its "paths" own). Private types count; extensions don't. Use the bare name ("Inner", not \
        "Outer.Inner"): a name with a dot or a "/" is read as a file path.
          - In any other language, the file's path relative to this folder, such as "relay/src/pipe.ts".
        - A flow is one arrow "from" a system or "system.part" "to" another, both declared in this file. Use "kind": \
        "data" when something is carried (audio, a transcript, JSON, a reply), and "kind": "control" when one side \
        triggers the other (a callback, begin and end, a command) and little or nothing is carried.
        - "carries" is a short phrase for what travels or what is triggered.
        - "via" is where the hand-off happens: the name of the function, method or symbol, spelled exactly as in the \
        code, without parentheses, arguments or a receiver ("sendAudio", not "session.sendAudio(pcm)"). MindControl looks \
        for it as a whole word in the files the "from" system owns (the files the "to" system owns when "from" is \
        external) and marks the arrow stale if it isn't there. Find it in the code; never guess. A "via" starts and ends \
        with a letter, digit or "_" (the whole-word search can't find "+=" or "->"). Give every flow a "via" unless both \
        ends are external; a flow without one is drawn as unverified.
        - "when" is a short condition for flows that only happen sometimes ("words heard"). Give each outcome of a \
        decision its own condition ("words heard", "nothing heard"). Flows of the same outcome use exactly the same \
        text, and together form one branch of a feature's route. Flows with the same "when" sit next to each other in a \
        route: MindControl groups a route's steps by condition only where they follow one another.
        - "features" are the main things the product does, each a "route" listing flow ids from this file in the order \
        they happen.
        - Keep the map small: at most \(FlowCheck.maxSystems) systems, at most \(FlowCheck.maxPartsPerSystem) parts in a \
        system, at most \(FlowCheck.maxFlows) flows. Merge systems rather than add more.
        - Don't make systems, parts or flows for docs, scripts, tests, tooling or anything that doesn't move data or \
        control. Fold helpers into the system that uses them; its "paths" can cover them.
        """

        /// "`a`, `b`, `c`", sorted so the prompt is the same every time.
        private static func codeList(_ items: Set<String>, prefix: String = "") -> String {
            items.sorted().map { "`\(prefix)\($0)`" }.joined(separator: ", ")
        }
    }
}
