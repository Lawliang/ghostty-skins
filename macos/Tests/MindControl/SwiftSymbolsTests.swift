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

    @Test func declaredTypesCanIncludePrivateOnes() {
        let source = """
        private struct Foo {}
        fileprivate final class Bar {}
        struct Outer {
            private enum Inner {}
            private(set) var count = 0
        }
        """
        #expect(SwiftSymbols.declaredTypes(in: source, includePrivate: true) == ["Foo", "Bar", "Outer", "Inner"])
        #expect(SwiftSymbols.declaredTypes(in: source) == ["Outer"])
    }

    @Test func packageAndDistributedTypesAreDeclared() {
        let source = """
        package enum Baz {}
        distributed actor Qux {}
        public distributed actor Remote {}
        package final class Shared {}
        """
        #expect(SwiftSymbols.declaredTypes(in: source) == ["Baz", "Qux", "Remote", "Shared"])
    }
}
#endif
