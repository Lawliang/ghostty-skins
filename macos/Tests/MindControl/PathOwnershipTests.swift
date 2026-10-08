#if os(macOS)
import Testing
@testable import Ghostty

private typealias PathOwnership = MindControl.PathOwnership

struct PathOwnershipTests {
    private func ownership(_ systems: String) -> PathOwnership {
        PathOwnership(map: FlowFixtures.map(#"{ "version": 1, "systems": [\#(systems)] }"#))
    }

    @Test func moreSpecificPatternWins() {
        let owners = ownership(#"""
        { "id": "core", "name": "Core", "paths": ["app/Coordination/**"] },
        { "id": "journal", "name": "Journal", "paths": ["app/Coordination/Journal*.swift"] }
        """#)
        #expect(owners.owner(of: "app/Coordination/Journal.swift") == .system("journal"))
        #expect(owners.owner(of: "app/Coordination/Chat.swift") == .system("core"))
    }

    @Test func equalSpecificityIsATie() {
        let owners = ownership(#"""
        { "id": "b", "name": "B", "paths": ["app/A/*.swift"] },
        { "id": "a", "name": "A", "paths": ["app/A/*.swift"] }
        """#)
        #expect(owners.owner(of: "app/A/x.swift") == .tie(["a", "b"]))
    }

    @Test func twoPatternsOfOneSystemAreNotATie() {
        let owners = ownership(#"{ "id": "a", "name": "A", "paths": ["app/*.swift", "app/*.swift"] }"#)
        #expect(owners.owner(of: "app/x.swift") == .system("a"))
    }

    @Test func unmatchedFileHasNoOwner() {
        let owners = ownership(#"{ "id": "a", "name": "A", "paths": ["app/**"] }"#)
        #expect(owners.owner(of: "relay/src/pipe.ts") == .none)
    }
}
#endif
