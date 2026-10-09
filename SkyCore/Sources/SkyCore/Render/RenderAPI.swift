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

/// A backend-independent straight-alpha color with channels in `[0, 1]`.
public struct Rgba: Equatable, Hashable, Sendable {
    public var r, g, b, a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// From 0–255 channel bytes.
    public static func bytes(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> Rgba {
        Rgba(Double(r) / 255, Double(g) / 255, Double(b) / 255, Double(a) / 255)
    }

    public static let white = Rgba(1, 1, 1)
    public static let black = Rgba(0, 0, 0)

    public func withAlpha(_ a: Double) -> Rgba { Rgba(r, g, b, a) }

    /// The night-mode red transform, applied by the backend to every color.
    public func nightMode(_ on: Bool) -> Rgba {
        guard on else { return self }
        return Rgba(0.299 * r + 0.587 * g + 0.114 * b, 0, 0, a)
    }
}

/// An opaque image key (e.g. `"planet/jupiter"`, `"icon/galaxy"`) the backend resolves.
public typealias ImageRef = String

// MARK: - Primitives

/// How a point is styled.
public enum PointAppearance: Equatable, Sendable {
    /// A catalog star: the backend maps magnitude (and B−V) to size/intensity.
    case stellar(magnitude: Double, colorIndex: Double?)
    /// A fixed-appearance dot.
    case fixed(color: Rgba, sizeDp: Double)
    /// A screen-space icon of `sizeDp` square, tinted.
    case icon(image: ImageRef, sizeDp: Double, tint: Rgba)
}

public struct PointPrimitive: Equatable, Sendable {
    public let pos: Vector3
    public let appearance: PointAppearance
}

/// A polyline on the celestial sphere; the backend subdivides long arcs into great circles.
public struct LinePrimitive: Equatable, Sendable {
    public let vertices: [Vector3]
    public let color: Rgba
    public let widthDp: Double
}

/// One loop of a glow mesh.
public struct GlowRing: Equatable, Sendable {
    public let vertices: [Vector3]
    public let color: Rgba
}

/// A filled, additively blended gradient mesh of concentric rings (the horizon glow).
public struct GlowPrimitive: Equatable, Sendable {
    public let rings: [GlowRing]
}

/// The Moon's position relative to Earth's shadow, in Moon radii.
public struct EclipseShadow: Equatable, Sendable {
    public let umbraRadius: Double
    public let penumbraRadius: Double
    public let offset: Double
    public let directionDeg: Double
}

/// How much of a body is lit and which way the lit limb faces (degrees east of north).
public struct Terminator: Equatable, Sendable {
    public let illuminatedFraction: Double
    public let brightLimbAngleDeg: Double
    public var eclipse: EclipseShadow? = nil
}

/// A world-anchored image whose drawn size is its true angular size, floored (see `SizeFloor`).
/// Images are drawn north-pole-up on the sky.
public struct ImagePrimitive: Equatable, Sendable {
    public let center: Vector3
    public let angularSizeDeg: Double
    public let image: ImageRef
    public var terminator: Terminator? = nil
    public var minScreenFraction: Double = 0
    public var minSizeDp: Double = 0
}

public enum LabelSize: Sendable {
    case title, standard, minor

    /// Point sizes at label scale 1 (v2's 15/10/8 sp, nudged up for iOS legibility).
    public var points: Double {
        switch self {
        case .title: return 16
        case .standard: return 12
        case .minor: return 10
        }
    }
}

/// Visual style of a label; it hangs `offsetDp` below its anchor, or clears an angular disc.
public struct LabelStyle: Equatable, Sendable {
    public static let defaultOffsetDp = 4.0

    public let size: LabelSize
    public let color: Rgba
    public var offsetDp: Double = LabelStyle.defaultOffsetDp
    public var clearanceDeg: Double = 0
    public var clearanceMinScreenFraction: Double = 0
    public var clearanceMinSizeDp: Double = 0
}

/// A localized text label. `priority` ranks screen-space conflicts (higher wins);
/// `magnitudeForThresholding` (if set) gates the label by field of view.
public struct LabelPrimitive: Equatable, Sendable {
    public let pos: Vector3
    public let text: String
    public let style: LabelStyle
    public let priority: Int
    public var magnitudeForThresholding: Double? = nil
}

/// The complete content of one layer. Within a scene, types draw glows → lines → images →
/// points → labels; layers draw back to front by `depth`.
public struct LayerScene: Equatable, Sendable {
    public var depth: Int
    public var points: [PointPrimitive] = []
    public var lines: [LinePrimitive] = []
    public var images: [ImagePrimitive] = []
    public var labels: [LabelPrimitive] = []
    public var glows: [GlowPrimitive] = []

    public init(depth: Int, points: [PointPrimitive] = [], lines: [LinePrimitive] = [],
                images: [ImagePrimitive] = [], labels: [LabelPrimitive] = [], glows: [GlowPrimitive] = []) {
        self.depth = depth
        self.points = points
        self.lines = lines
        self.images = images
        self.labels = labels
        self.glows = glows
    }
}

/// Global per-frame render settings.
public struct RenderState: Equatable, Sendable {
    public var nightMode = false
    public var magnitudeLimit: Double? = nil
    public var labelScale = 1.0
    /// Sun direction (celestial unit vector) for the daylight sky gradient, or nil for none.
    public var sunDirection: Vector3? = nil

    public init(nightMode: Bool = false, magnitudeLimit: Double? = nil, labelScale: Double = 1.0, sunDirection: Vector3? = nil) {
        self.nightMode = nightMode
        self.magnitudeLimit = magnitudeLimit
        self.labelScale = labelScale
        self.sunDirection = sunDirection
    }
}

// MARK: - Camera and projection

/// The per-frame view onto the celestial sphere. `fovDeg` spans the **shorter** viewport side.
public struct SkyCamera: Equatable, Sendable {
    public var lineOfSight: Vector3
    public var up: Vector3
    public var fovDeg: Double

    public init(lineOfSight: Vector3, up: Vector3, fovDeg: Double) {
        self.lineOfSight = lineOfSight
        self.up = up
        self.fovDeg = fovDeg
    }

    public static let minFovDeg = 0.03
    public static let maxFovDeg = 90.0
    public static let initialFovDeg = 21.1
}

public struct ScreenPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    @inlinable
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The shared, pure projection (perspective about the eye at the sphere's centre). Screen
/// coordinates are top-left origin, y down, in points.
public struct SkyProjection: Sendable {
    public let camera: SkyCamera
    public let width: Double
    public let height: Double
    public let forward: Vector3
    public let right: Vector3
    public let upOrtho: Vector3
    /// Points per unit of tangent-plane distance.
    public let scale: Double

    public init(camera: SkyCamera, width: Double, height: Double) {
        self.camera = camera
        self.width = max(width, 1)
        self.height = max(height, 1)
        let f = camera.lineOfSight.normalized()
        var r = f.cross(camera.up)
        if r.length2 < 1e-12 { r = f.cross(abs(f.z) < 0.9 ? Vector3.unitZ : Vector3.unitX) }
        r = r.normalized()
        forward = f
        right = r
        upOrtho = r.cross(f)
        let cot = 1.0 / tan(camera.fovDeg * degreesToRadians / 2.0)
        scale = cot * min(self.width, self.height) / 2.0
    }

    /// Projects a direction to screen, or nil if it is at/behind the eye plane.
    @inlinable
    public func project(_ p: Vector3) -> ScreenPoint? {
        let w = forward.dot(p)
        if w <= 1e-9 { return nil }
        return ScreenPoint(x: width / 2 + scale * right.dot(p) / w, y: height / 2 - scale * upOrtho.dot(p) / w)
    }

    /// The world direction under a screen point.
    public func unproject(x: Double, y: Double) -> Vector3 {
        (forward + right * ((x - width / 2) / scale) + upOrtho * ((height / 2 - y) / scale)).normalized()
    }

    /// Cosine of the angle from the view centre to the screen corner — anything with a smaller
    /// dot product against `forward` is off screen.
    public var cornerCosine: Double {
        let dx = width / 2 / scale, dy = height / 2 / scale
        return 1.0 / (1.0 + dx * dx + dy * dy).squareRoot()
    }

    /// Screen-space unit vectors pointing toward celestial north and east at `p`
    /// (for orienting images and terminators). Nil near the poles or off screen.
    public func northEastAxes(at p: Vector3) -> (north: (Double, Double), east: (Double, Double))? {
        let pole = Vector3.unitZ
        var east = pole.cross(p)
        if east.length2 < 1e-10 { east = Vector3.unitY.cross(p) }
        east = east.normalized()
        let north = p.cross(east).normalized()
        let eps = 1e-4
        guard let c = project(p), let n = project((p + north * eps).normalized()),
              let e = project((p + east * eps).normalized()) else { return nil }
        func unit(_ dx: Double, _ dy: Double) -> (Double, Double) {
            let l = (dx * dx + dy * dy).squareRoot()
            return l < 1e-12 ? (0, -1) : (dx / l, dy / l)
        }
        return (unit(n.x - c.x, n.y - c.y), unit(e.x - c.x, e.y - c.y))
    }

    /// Points per degree at the view centre.
    public var pointsPerDegree: Double { scale * degreesToRadians }
}

// MARK: - Backend policy helpers

/// How big to draw a body whose true apparent size would be too small to see (D86).
public enum SizeFloor {
    public static func drawnDiameterDeg(trueDiameterDeg: Double, minScreenFraction: Double, minSizeDp: Double,
                                        fovDeg: Double, shortSidePt: Double) -> Double {
        guard shortSidePt > 0 else { return trueDiameterDeg }
        let fractionFloor = minScreenFraction * fovDeg
        let dpFloor = minSizeDp * fovDeg / shortSidePt
        return max(trueDiameterDeg, max(fractionFloor, dpFloor))
    }
}

/// The lit/dark geometry of a phase: positive inside the lit region (lit limb faces +x).
public enum PhaseGeometry {
    public static func litOffset(x: Double, y: Double, illuminatedFraction: Double) -> Double {
        let s = 2.0 * illuminatedFraction.clamped(0, 1) - 1.0
        let yy = y.clamped(-1, 1)
        return x + s * (1.0 - yy * yy).squareRoot()
    }

    /// The shadowed region of the unit disc as a closed polygon, lit limb facing +x:
    /// the terminator (`x = −s√(1−y²)`) up, then the dark limb back down.
    public static func shadowPolygon(illuminatedFraction: Double, segments: Int = 48) -> [(Double, Double)] {
        let s = 2.0 * illuminatedFraction.clamped(0, 1) - 1.0
        var pts: [(Double, Double)] = []
        for i in 0...segments {
            let y = -1.0 + 2.0 * Double(i) / Double(segments)
            pts.append((-s * (1 - y * y).squareRoot(), y))
        }
        for i in stride(from: segments, through: 0, by: -1) {
            let y = -1.0 + 2.0 * Double(i) / Double(segments)
            pts.append((-(1 - y * y).squareRoot(), y))
        }
        return pts
    }
}

/// Size and color for catalog stars (v2's `StellarStyler`).
public enum StellarStyler {
    public struct Style: Equatable {
        public let color: Rgba
        public let sizeDp: Double
    }

    public static func style(magnitude: Double, colorIndex: Double?, state: RenderState) -> Style {
        let sizeDp = magnitude <= 1.0 ? 5.0 : 3.0
        var alpha = 1.0
        if let limit = state.magnitudeLimit {
            let overshoot = magnitude - limit
            if overshoot >= 0.5 { alpha = 0 } else if overshoot > 0 { alpha = 0.15 + 0.85 * (1 - overshoot / 0.5) }
        }
        let m = magnitude.clamped(0, 5.6)
        let shade = 1.0 - m / (5.6 + 3.0)
        let tint = colorFor(colorIndex)
        return Style(color: Rgba(tint.r * shade, tint.g * shade, tint.b * shade, alpha).nightMode(state.nightMode), sizeDp: sizeDp)
    }

    private static func colorFor(_ bv: Double?) -> Rgba {
        guard let bv else { return .white }
        let t = ((bv + 0.4) / 2.4).clamped(0, 1)
        func lerp(_ a: Rgba, _ b: Rgba, _ t: Double) -> Rgba {
            Rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
        }
        return t < 0.5 ? lerp(Rgba(0.65, 0.75, 1), .white, t / 0.5) : lerp(.white, Rgba(1, 0.7, 0.4), (t - 0.5) / 0.5)
    }
}

/// FOV-dependent label gating and greedy screen-space decluttering (v2's `LabelDeclutterer`).
public enum LabelDeclutterer {
    /// Faintest magnitude whose label shows at `fovDeg`: 4.0 at 45°, +1 per 10° zoomed in,
    /// −1 per 45° zoomed out.
    public static func magnitudeThreshold(fovDeg: Double) -> Double {
        let delta = 45.0 - fovDeg
        return 4.0 + delta / (delta >= 0 ? 10.0 : 45.0)
    }

    public struct Candidate {
        public let index: Int
        public let rect: (x: Double, y: Double, w: Double, h: Double)
        public let priority: Int

        public init(index: Int, rect: (x: Double, y: Double, w: Double, h: Double), priority: Int) {
            self.index = index
            self.rect = rect
            self.priority = priority
        }
    }

    /// Returns the indices of candidates that survive, highest priority first (stable).
    public static func declutter(_ candidates: [Candidate]) -> [Int] {
        let ordered = candidates.enumerated().sorted { a, b in
            a.element.priority != b.element.priority ? a.element.priority > b.element.priority : a.offset < b.offset
        }.map(\.element)
        var kept: [(Double, Double, Double, Double)] = []
        var result: [Int] = []
        for c in ordered {
            let l = c.rect.x, t = c.rect.y, r = c.rect.x + c.rect.w, b = c.rect.y + c.rect.h
            if kept.contains(where: { l < $0.2 && r > $0.0 && t < $0.3 && b > $0.1 }) { continue }
            kept.append((l, t, r, b))
            result.append(c.index)
        }
        return result
    }
}

/// Subdivides polylines into great-circle segments no longer than `maxStepDeg`.
public enum GreatCircle {
    public static func subdivide(_ vertices: [Vector3], maxStepDeg: Double = 2.0) -> [Vector3] {
        guard vertices.count >= 2 else { return vertices }
        var out: [Vector3] = [vertices[0]]
        out.reserveCapacity(vertices.count * 2)
        for i in 1..<vertices.count {
            let a = vertices[i - 1], b = vertices[i]
            let angle = acos(a.dot(b).clamped(-1, 1)) * radiansToDegrees
            let n = Int((angle / maxStepDeg).rounded(.up))
            if n > 1 && angle < 179.999 {
                let theta = angle * degreesToRadians
                let sinT = sin(theta)
                for k in 1..<n {
                    let t = Double(k) / Double(n)
                    let wa = sin((1 - t) * theta) / sinT, wb = sin(t * theta) / sinT
                    out.append(a * wa + b * wb)
                }
            }
            out.append(b)
        }
        return out
    }
}

public extension LayerScene {
    /// This scene with every line subdivided into short great-circle steps, done once per
    /// scene so a CPU backend can project vertices directly every frame.
    func subdividedForDrawing(maxStepDeg: Double = 2.0) -> LayerScene {
        var copy = self
        copy.lines = lines.map {
            LinePrimitive(vertices: GreatCircle.subdivide($0.vertices, maxStepDeg: maxStepDeg), color: $0.color, widthDp: $0.widthDp)
        }
        return copy
    }
}

/// The daylight sky dome color in a direction, given the sun direction (v1's banded gradient):
/// blue above the sun's "equator" brightening toward the sun, grey fading to black opposite it.
public enum SkyGradient {
    public static func color(direction: Vector3, sun: Vector3) -> Rgba {
        let band = direction.dot(sun).clamped(-1, 1)
        if band > 0 { return Rgba(0, 0, (band * 20 + 50) / 255) }
        let i = max(0, (band * 40 + 40) / 255)
        return Rgba(i, i, i)
    }
}
