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
}
#endif
