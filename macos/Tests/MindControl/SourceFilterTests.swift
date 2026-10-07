#if os(macOS)
import Testing
@testable import Ghostty

private typealias SourceFilter = MindControl.SourceFilter

struct SourceFilterTests {
    @Test(arguments: [
        "app/Sources/App.swift", "src/terminal/Terminal.zig", "relay/server.ts", "web/App.tsx",
        "lib/util.py", "core/engine.rs", "cmd/main.go", "Renderer/Shaders/Nodes.metal", "include/api.h",
        "ui/Button.vue", "main.c", "Sources/Bridge.mm", "firmware/arcaPrototype/arcaPrototype.ino",
    ])
    func keepsFeatureSource(path: String) {
        #expect(SourceFilter.isFeatureSource(path), "\(path) should be kept")
    }

    @Test(arguments: [
        // docs and notes
        "README.md", "docs/plan.swift", "Documentation/api.py", "notes.txt",
        // scripts, tooling, harness, plugins, CI and agent config
        "scripts/release.py", "tools/motion.py", "harness/worktree.py", "plugins/x/index.ts", "bin/run.js",
        ".github/workflows/ci.yml", ".claude/hooks/check.py", "build.sh",
        // tests
        "app/Tests/AppTests.swift", "GhosttyTests/Model.swift", "AppUITests/Flow.swift", "test/core.zig",
        "spec/models/user.rb", "__tests__/a.ts", "src/fixtures/data.ts", "pkg/server_test.go",
        "pkg/test_server.py", "pkg/server_test.py", "web/app.test.ts", "web/app.spec.js",
        "Sources/ModelTests.swift", "Sources/ModelTest.swift",
        // samples
        "examples/demo.swift", "benchmarks/speed.zig",
        // assets and config
        "assets/logo.png", "Resources/font.ttf", "config.json", "app.yaml", "Info.plist",
        "Package.resolved", "Cargo.lock",
    ])
    func dropsEverythingElse(path: String) {
        #expect(!SourceFilter.isFeatureSource(path), "\(path) should be left out")
    }
}
#endif
