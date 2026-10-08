#if os(macOS)
import CoreGraphics
import Foundation
import Testing
@testable import Ghostty

private typealias LayoutStore = MindControl.LayoutStore

struct LayoutStoreTests {
    @Test func roundTrips() {
        let positions = ["audio": CGPoint(x: 12.5, y: -40), "ble": CGPoint(x: 0, y: 300)]
        #expect(LayoutStore.decode(LayoutStore.encode(positions)) == positions)
    }

    @Test func unreadableIsEmpty() {
        #expect(LayoutStore.decode(nil) == [:])
        #expect(LayoutStore.decode(Data("not json".utf8)) == [:])
        #expect(LayoutStore.decode(Data(#"{ "version": 1, "positions": { "a": { "x": "no" } } }"#.utf8)) == [:])
    }

    @Test func writeCreatesTheFolder() throws {
        let project = try TempProject()
        try LayoutStore.write(["a": CGPoint(x: 1, y: 2)], root: project.url)
        let data = try Data(contentsOf: project.url.appendingPathComponent(".mindcontrol/layout.json"))
        #expect(LayoutStore.decode(data) == ["a": CGPoint(x: 1, y: 2)])
    }
}
#endif
