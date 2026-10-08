import CoreGraphics
import Foundation

extension MindControl {
    /// `.mindcontrol/layout.json`: positions the user dragged systems to. Unreadable means empty.
    enum LayoutStore {
        static func decode(_ data: Data?) -> [String: CGPoint] {
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let positions = object["positions"] as? [String: Any] else { return [:] }
            var result: [String: CGPoint] = [:]
            for (id, value) in positions {
                guard let point = value as? [String: Any], let x = point["x"] as? Double, let y = point["y"] as? Double else { return [:] }
                result[id] = CGPoint(x: x, y: y)
            }
            return result
        }

        static func encode(_ positions: [String: CGPoint]) -> Data {
            let object: [String: Any] = [
                "version": 1,
                "positions": positions.mapValues { ["x": Double($0.x), "y": Double($0.y)] },
            ]
            return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        }

        static func write(_ positions: [String: CGPoint], root: URL) throws {
            let url = root.appendingPathComponent(FlowFile.layoutRelativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encode(positions).write(to: url, options: .atomic)
        }
    }
}
