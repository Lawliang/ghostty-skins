import Foundation

extension MindControl {
    struct FeatureStep: Equatable, Sendable {
        enum Status: Equatable, Sendable { case ok, stale, unverified }

        let number: Int
        let flowID: String
        let from: String
        let to: String
        let carries: String
        let kind: FlowMap.Kind
        let when: String?
        let status: Status
    }

    /// Consecutive steps sharing one `when`.
    struct StepGroup: Equatable, Sendable {
        let when: String?
        var steps: [FeatureStep]
    }

    enum FeatureSteps {
        /// The feature's route as numbered steps. Flows that don't exist or can't be drawn are listed in `unknown`.
        static func groups(for feature: FlowMap.Feature, map: FlowMap, report: HealthReport) -> (groups: [StepGroup], unknown: [String]) {
            var groups: [StepGroup] = []
            var unknown: [String] = []
            var number = 0
            for id in feature.route {
                guard let flow = map.flow(id), !report.brokenFlows.contains(id) else {
                    unknown.append(id)
                    continue
                }
                number += 1
                let status: FeatureStep.Status = report.staleFlows.contains(id) ? .stale
                    : report.unverifiedFlows.contains(id) ? .unverified : .ok
                let step = FeatureStep(number: number, flowID: id, from: name(of: flow.from, in: map), to: name(of: flow.to, in: map),
                                       carries: flow.carries, kind: flow.kind, when: flow.when, status: status)
                if let last = groups.indices.last, groups[last].when == flow.when {
                    groups[last].steps.append(step)
                } else {
                    groups.append(StepGroup(when: flow.when, steps: [step]))
                }
            }
            return (groups, unknown)
        }

        /// "Audio" for a system, "Audio › AudioCapture" for a part.
        static func name(of endpoint: FlowMap.Endpoint, in map: FlowMap) -> String {
            guard let system = map.system(endpoint.system) else { return endpoint.description }
            guard let partID = endpoint.part else { return system.name }
            return "\(system.name) › \(system.part(partID)?.name ?? partID)"
        }
    }
}
