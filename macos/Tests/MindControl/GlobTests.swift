#if os(macOS)
import Testing
@testable import Ghostty

private typealias Glob = MindControl.Glob

struct GlobTests {
    @Test(arguments: [
        ("app/Sources/Audio/**", "app/Sources/Audio/A.swift", true),
        ("app/Sources/Audio/**", "app/Sources/Audio/sub/B.swift", true),
        ("app/Sources/Audio/**", "app/Sources/AudioX/A.swift", false),
        ("app/*/A.swift", "app/x/A.swift", true),
        ("app/*/A.swift", "app/x/y/A.swift", false),
        ("**/*.ts", "relay/src/pipe.ts", true),
        ("**/*.ts", "pipe.ts", true),
        ("relay/src/pipe.ts", "relay/src/pipe.ts", true),
        ("relay/src", "relay/src/pipe.ts", true),
        ("relay/src", "relay/srcx/pipe.ts", false),
        ("app/Coordination/Journal*.swift", "app/Coordination/JournalUploader.swift", true),
        ("app/Coordination/Journal*.swift", "app/Coordination/Chat.swift", false),
        ("a.b/*", "aXb/c", false),
        // A trailing "/" on a plain folder names the folder, as in git's `:(glob)`. With a wildcard it can only
        // match folders, and git matches no files with it either.
        ("relay/src/", "relay/src/pipe.ts", true),
        ("relay/src/", "relay/src/deep/pipe.ts", true),
        ("relay/src/", "relay/srcx/pipe.ts", false),
        ("app/*/", "app/x/A.swift", false),
        ("app/**/", "app/x/A.swift", false),
    ])
    func matching(pattern: String, path: String, expected: Bool) {
        #expect(Glob.matches(pattern, path) == expected)
    }

    @Test func literalPrefixCountsUpToFirstStar() {
        #expect(Glob.literalPrefixLength("app/Coordination/Journal*.swift") == "app/Coordination/Journal".count)
        #expect(Glob.literalPrefixLength("app/Coordination/**") == "app/Coordination/".count)
        #expect(Glob.literalPrefixLength("relay/src/pipe.ts") == "relay/src/pipe.ts".count)
        #expect(Glob.literalPrefixLength("**/*.ts") == 0)
        #expect(Glob.literalPrefixLength("relay/src/") == "relay/src".count)
    }
}
#endif
