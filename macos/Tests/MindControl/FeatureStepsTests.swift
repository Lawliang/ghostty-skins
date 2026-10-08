#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

private typealias FeatureSteps = MindControl.FeatureSteps

struct FeatureStepsTests {
    @Test func speechStepsGroupByCondition() throws {
        let map = FlowFixtures.arca
        let feature = try #require(map.feature("speech"))
        let result = FeatureSteps.groups(for: feature, map: map, report: MindControl.HealthReport())
        #expect(result.unknown == [])
        #expect(result.groups.map(\.when) == [nil, "words heard", "nothing heard", nil])
        #expect(result.groups.map { $0.steps.map(\.flowID) } == [["press", "event", "begin", "pcm", "check"], ["commit"], ["discard"], ["send", "reply"]])
        #expect(result.groups.flatMap(\.steps).map(\.number) == Array(1...9))
        let first = try #require(result.groups.first?.steps.first)
        #expect(first.from == "Ring")
        #expect(first.to == "BLE link › ArcaLink")
        #expect(first.carries == "press DOWN / UP")
        #expect(first.kind == .control)
    }

    @Test func statusComesFromTheReport() throws {
        let map = FlowFixtures.arca
        var report = MindControl.HealthReport()
        report.staleFlows = ["pcm"]
        report.unverifiedFlows = ["press"]
        let steps = FeatureSteps.groups(for: try #require(map.feature("speech")), map: map, report: report).groups.flatMap(\.steps)
        #expect(steps.first { $0.flowID == "pcm" }?.status == .stale)
        #expect(steps.first { $0.flowID == "press" }?.status == .unverified)
        #expect(steps.first { $0.flowID == "event" }?.status == .ok)
    }

    @Test func unknownAndBrokenFlowsAreListedNotNumbered() {
        let map = FlowFixtures.arca
        var report = MindControl.HealthReport()
        report.brokenFlows = ["event"]
        let feature = MindControl.FlowMap.Feature(id: "f", name: "F", route: ["press", "ghost", "event", "begin"])
        let result = FeatureSteps.groups(for: feature, map: map, report: report)
        #expect(result.unknown == ["ghost", "event"])
        #expect(result.groups.flatMap(\.steps).map(\.number) == [1, 2])
    }
}
#endif
