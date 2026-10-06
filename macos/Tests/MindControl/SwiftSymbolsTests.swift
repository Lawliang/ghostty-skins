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
