/*
 * Copyright (c) 2026 Penterakt LLC and contributors.
 * Swift port of Sky Map v2 (https://github.com/sky-map-team/stardroid).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// The camera's gesture math (v2's MapViewModel gesture section), free of any UI framework.
/// Drag/rotate/fling/slew act only in manual mode; zoom works in both. Call `step(dt:)` once
/// per frame to advance fling, slew and horizon leveling.
public struct CameraController: Sendable {
    public private(set) var camera: SkyCamera
    public var manual = true
    public var autoLevelHorizon = true

    private var flingVelocity: (Double, Double)? = nil
    private var flingShortSide = 1.0
    private var slew: Slew? = nil
    private var leveling = false

    struct Slew {
        let start: SkyCamera
        let axis: Vector3
        let angleDeg: Double
        let targetFov: Double
        var t: Double
    }

    static let flingDecayPerSecond = 1.9062036
    static let flingStopSpeedSq = 10.0
    static let levelDecayPerSecond = 4.4628710
    static let slewSeconds = 1.0

    public init(camera: SkyCamera = SkyCamera(lineOfSight: Vector3.unitX, up: Vector3.unitZ, fovDeg: SkyCamera.initialFovDeg)) {
        self.camera = camera
    }

    public var isAnimating: Bool { flingVelocity != nil || slew != nil || leveling }

    /// Sensor mode: the orientation pipeline owns the view direction; FOV stays the user's.
    public mutating func setSensorPointing(lineOfSight: Vector3, up: Vector3) {
        guard !manual else { return }
        camera = SkyCamera(lineOfSight: lineOfSight, up: up, fovDeg: camera.fovDeg)
    }

    public mutating func setCamera(_ c: SkyCamera) { camera = c }

    /// One-finger drag in points: the sky tracks the finger ~1:1 at any zoom.
    public mutating func drag(dx: Double, dy: Double, shortSide: Double) {
        guard manual, shortSide > 0 else { return }
        leveling = false
        let k = camera.fovDeg * degreesToRadians / shortSide
        let pitch = -dy * k, yaw = -dx * k
        let pitchedLos = (camera.lineOfSight - camera.up * pitch).normalized()
        let pitchedUp = (camera.up + camera.lineOfSight * pitch).normalized()
        let horizontal = pitchedLos.cross(pitchedUp)
        let los = (pitchedLos + horizontal * yaw).normalized()
        // Re-orthogonalize up against the new line of sight.
        let up = (pitchedUp - los * pitchedUp.dot(los)).normalized()
        camera = SkyCamera(lineOfSight: los, up: up, fovDeg: camera.fovDeg)
    }

    /// Two-finger stretch: `ratio` > 1 zooms in.
    public mutating func stretch(_ ratio: Double) {
        guard ratio > 0, ratio.isFinite else { return }
        camera.fovDeg = (camera.fovDeg / ratio).clamped(SkyCamera.minFovDeg, SkyCamera.maxFovDeg)
    }

    public mutating func setFov(_ fov: Double) {
        camera.fovDeg = fov.clamped(SkyCamera.minFovDeg, SkyCamera.maxFovDeg)
    }

    /// Two-finger rotate; screen-clockwise degrees rotate the sky with the fingers.
    public mutating func rotate(degrees: Double) {
        guard manual, degrees.isFinite else { return }
        camera.up = (rotationMatrix(degrees, camera.lineOfSight) * camera.up).normalized()
    }

    public mutating func fling(vx: Double, vy: Double, shortSide: Double) {
        guard manual else { return }
        stop()
        flingVelocity = (vx, vy)
        flingShortSide = shortSide
    }

    /// Stops fling, slew and leveling (a new touch always wins).
    public mutating func stop() {
        flingVelocity = nil
        slew = nil
        leveling = false
    }

    /// Smoothstep-eased great-circle slew to `direction`, easing the FOV too. Manual mode only.
    public mutating func aim(at direction: Vector3, fovDeg: Double? = nil) {
        guard manual else { return }
        stop()
        let target = direction.normalized()
        guard target != .zero else { return }
        let angle = acos(camera.lineOfSight.dot(target).clamped(-1, 1)) * radiansToDegrees
        let cross = target.cross(camera.lineOfSight)
        let axis = cross.length2 < 1e-12 ? camera.up : cross.normalized()
        slew = Slew(start: camera, axis: axis, angleDeg: angle,
                    targetFov: (fovDeg ?? camera.fovDeg).clamped(SkyCamera.minFovDeg, SkyCamera.maxFovDeg), t: 0)
    }

    /// A manual gesture ended: spring the horizon back to level if enabled.
    public mutating func gestureEnded(zenith: Vector3) {
        if manual && autoLevelHorizon && slew == nil { leveling = true }
        levelZenith = zenith
    }

    private var levelZenith: Vector3 = .unitZ

    public mutating func updateZenith(_ zenith: Vector3) { levelZenith = zenith }

    /// Advances animations by `dt` seconds (clamped to 0.1 s so a stall never teleports).
    public mutating func step(dt rawDt: Double) {
        let dt = rawDt.clamped(0, 0.1)
        if var (vx, vy) = flingVelocity {
            drag(dx: vx * dt, dy: vy * dt, shortSide: flingShortSide)
            let decay = exp(-Self.flingDecayPerSecond * dt)
            vx *= decay
            vy *= decay
            flingVelocity = vx * vx + vy * vy >= Self.flingStopSpeedSq ? (vx, vy) : nil
            if flingVelocity == nil && autoLevelHorizon && manual { leveling = true }
        }
        if var s = slew {
            s.t = min(1, s.t + dt / Self.slewSeconds)
            let eased = s.t * s.t * (3 - 2 * s.t)
            let r = rotationMatrix(s.angleDeg * eased, s.axis)
            camera = SkyCamera(lineOfSight: (r * s.start.lineOfSight).normalized(), up: (r * s.start.up).normalized(),
                               fovDeg: s.start.fovDeg + (s.targetFov - s.start.fovDeg) * eased)
            slew = s.t >= 1 ? nil : s
            if slew == nil && autoLevelHorizon && manual { leveling = true }
        }
        if leveling && flingVelocity == nil && slew == nil {
            let los = camera.lineOfSight
            let target = levelZenith - los * levelZenith.dot(los)
            if target.length2 < 1e-6 {
                leveling = false
                return
            }
            let targetUp = target.normalized()
            let angle = atan2(camera.up.cross(targetUp).dot(los), camera.up.dot(targetUp)) * radiansToDegrees
            if abs(angle) < 0.1 {
                camera.up = targetUp
                leveling = false
            } else {
                let fraction = 1 - exp(-Self.levelDecayPerSecond * dt)
                camera.up = (rotationMatrix(-angle * fraction, los) * camera.up).normalized()
            }
        }
    }
}

/// Tap-to-identify: the nearest candidate to a tapped direction within a screen tolerance.
public enum Identify {
    public struct Candidate: Sendable {
        public let id: String
        public let position: Vector3
        /// Angular radius of a drawn disc, if any — taps anywhere on the disc hit it.
        public let radiusDeg: Double

        public init(id: String, position: Vector3, radiusDeg: Double = 0) {
            self.id = id
            self.position = position
            self.radiusDeg = radiusDeg
        }
    }

    /// Returns the best candidate id, or nil if nothing is within `tolerancePt` of the tap.
    public static func pick(tap: Vector3, candidates: [Candidate], projection: SkyProjection,
                            tolerancePt: Double = 30) -> String? {
        let toleranceDeg = tolerancePt / projection.pointsPerDegree
        var best: (String, Double)? = nil
        for c in candidates {
            let sep = acos(tap.dot(c.position).clamped(-1, 1)) * radiansToDegrees
            let effective = max(0, sep - c.radiusDeg)
            guard effective <= toleranceDeg else { continue }
            if best == nil || effective < best!.1 { best = (c.id, effective) }
        }
        return best?.0
    }
}
