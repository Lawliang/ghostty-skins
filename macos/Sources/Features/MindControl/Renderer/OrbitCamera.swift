import simd

extension MindControl {
    /// Turntable camera orbiting a target, with fling inertia and a slow idle drift.
    struct OrbitCamera {
        static let pitchLimit: Float = 85 * .pi / 180
        static let idleDelay: Double = 3
        static let driftSpeed: Float = 0.06          // radians per second
        static let dragSensitivity: Float = 0.006    // radians per point
        static let inertiaDecay: Float = 3.5         // per second
        static let fieldOfView: Float = 50 * .pi / 180

        private(set) var target: SIMD3<Float> = .zero
        private(set) var yaw: Float = 0.6
        private(set) var pitch: Float = 0.3
        private(set) var distance: Float = 24
        private(set) var minDistance: Float = 0.5
        private(set) var maxDistance: Float = 500
        private(set) var yawVelocity: Float = 0
        private(set) var pitchVelocity: Float = 0
        private(set) var idleTime: Double = 0
        private(set) var isDragging = false

        mutating func beginDrag() {
            isDragging = true
            yawVelocity = 0
            pitchVelocity = 0
            idleTime = 0
        }

        mutating func drag(dx: Float, dy: Float) {
            guard dx.isFinite, dy.isFinite else { return }
            let dYaw = -dx * Self.dragSensitivity
            let dPitch = dy * Self.dragSensitivity
            yaw += dYaw
            pitch = clampPitch(pitch + dPitch)
            // Mouse events arrive at roughly 60 Hz; turn the latest delta into a fling velocity.
            yawVelocity = dYaw * 60
            pitchVelocity = dPitch * 60
            idleTime = 0
        }

        mutating func endDrag() {
            isDragging = false
            idleTime = 0
        }

        mutating func zoom(by factor: Float) {
            guard factor.isFinite, factor > 0 else { return }
            distance = min(max(distance * factor, minDistance), maxDistance)
            idleTime = 0
        }

        mutating func update(dt: Double) {
            guard dt.isFinite, dt > 0 else { return }
            let t = Float(dt)

            if isDragging {
                // Bleed off velocity while the button is held still, so a pause before release doesn't fling.
                let hold = exp(-t * 20)
                yawVelocity *= hold
                pitchVelocity *= hold
                return
            }

            idleTime += dt
            yaw += yawVelocity * t
            pitch = clampPitch(pitch + pitchVelocity * t)

            let decay = exp(-t * Self.inertiaDecay)
            yawVelocity *= decay
            pitchVelocity *= decay
            if abs(yawVelocity) < 0.01 { yawVelocity = 0 }
            if abs(pitchVelocity) < 0.01 { pitchVelocity = 0 }

            if idleTime > Self.idleDelay {
                yaw += Self.driftSpeed * t
            }
        }

        /// Points the camera at `center` from far enough away that a sphere of `radius` fills the view.
        mutating func frame(center: SIMD3<Float>, radius: Float) {
            let r = max(radius, 1)
            target = center
            distance = r / sin(Self.fieldOfView / 2) * 1.15
            minDistance = max(r * 0.1, 0.5)
            maxDistance = distance * 6
        }

        var position: SIMD3<Float> {
            target + distance * SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        }

        var viewMatrix: simd_float4x4 {
            Matrix.lookAt(eye: position, target: target, up: SIMD3(0, 1, 0))
        }

        func projectionMatrix(aspect: Float) -> simd_float4x4 {
            Matrix.perspective(fovY: Self.fieldOfView, aspect: aspect, near: max(distance * 0.01, 0.01), far: maxDistance * 4)
        }

        private func clampPitch(_ value: Float) -> Float {
            min(max(value, -Self.pitchLimit), Self.pitchLimit)
        }
    }
}
