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

public let degreesToRadians: Double = .pi / 180.0
public let radiansToDegrees: Double = 180.0 / .pi
public let hoursToDegrees: Double = 15.0
public let twoPi: Double = 2.0 * .pi

/// `a` modulo `n`, always in `[0, n)` even for negative `a`.
@inlinable
public func floorMod(_ a: Double, _ n: Double) -> Double {
    let r = a.truncatingRemainder(dividingBy: n)
    return r < 0 ? r + n : r
}

/// Reduces an angle in radians to `[0, 2π)`.
@inlinable
public func normalizeRadians(_ radians: Double) -> Double { floorMod(radians, twoPi) }

/// Reduces an angle in degrees to `[0, 360)`.
@inlinable
public func normalizeDegrees(_ degrees: Double) -> Double { floorMod(degrees, 360.0) }

extension Comparable {
    @inlinable
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

// MARK: - Vector3

/// An immutable 3-vector in `Double` precision.
public struct Vector3: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    @inlinable
    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(0, 0, 0)
    public static let unitX = Vector3(1, 0, 0)
    public static let unitY = Vector3(0, 1, 0)
    public static let unitZ = Vector3(0, 0, 1)

    @inlinable public var length2: Double { x * x + y * y + z * z }
    @inlinable public var length: Double { length2.squareRoot() }

    @inlinable public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    @inlinable public static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    @inlinable public static func * (a: Vector3, s: Double) -> Vector3 { Vector3(a.x * s, a.y * s, a.z * s) }
    @inlinable public static func / (a: Vector3, s: Double) -> Vector3 { a * (1.0 / s) }
    @inlinable public static prefix func - (a: Vector3) -> Vector3 { Vector3(-a.x, -a.y, -a.z) }

    @inlinable public func dot(_ o: Vector3) -> Double { x * o.x + y * o.y + z * o.z }

    @inlinable public func cross(_ o: Vector3) -> Vector3 {
        Vector3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    @inlinable public func distance(to o: Vector3) -> Double { (self - o).length }

    /// The unit vector, or `.zero` for a vector too short to normalize reliably.
    @inlinable public func normalized() -> Vector3 {
        let l = length
        return l < 1e-6 ? .zero : self / l
    }

    public func cosineSimilarity(_ o: Vector3) -> Double { dot(o) / (dot(self) * o.dot(o)).squareRoot() }
}

// MARK: - Matrix3

/// An immutable 3x3 matrix; elements are named `[row][col]`.
public struct Matrix3: Equatable, Sendable {
    public var xx, xy, xz, yx, yy, yz, zx, zy, zz: Double

    public init(
        _ xx: Double, _ xy: Double, _ xz: Double,
        _ yx: Double, _ yy: Double, _ yz: Double,
        _ zx: Double, _ zy: Double, _ zz: Double
    ) {
        self.xx = xx; self.xy = xy; self.xz = xz
        self.yx = yx; self.yy = yy; self.yz = yz
        self.zx = zx; self.zy = zy; self.zz = zz
    }

    public static let identity = Matrix3(1, 0, 0, 0, 1, 0, 0, 0, 1)

    public var determinant: Double {
        xx * yy * zz + xy * yz * zx + xz * yx * zy - xx * yz * zy - yy * zx * xz - zz * xy * yx
    }

    public var inverse: Matrix3? {
        let det = determinant
        if abs(det) < 1e-8 { return nil }
        return Matrix3(
            (yy * zz - yz * zy) / det, (xz * zy - xy * zz) / det, (xy * yz - xz * yy) / det,
            (yz * zx - yx * zz) / det, (xx * zz - xz * zx) / det, (xz * yx - xx * yz) / det,
            (yx * zy - yy * zx) / det, (xy * zx - xx * zy) / det, (xx * yy - xy * yx) / det
        )
    }

    public func transposed() -> Matrix3 { Matrix3(xx, yx, zx, xy, yy, zy, xz, yz, zz) }

    public static func * (a: Matrix3, m: Matrix3) -> Matrix3 {
        Matrix3(
            a.xx * m.xx + a.xy * m.yx + a.xz * m.zx,
            a.xx * m.xy + a.xy * m.yy + a.xz * m.zy,
            a.xx * m.xz + a.xy * m.yz + a.xz * m.zz,
            a.yx * m.xx + a.yy * m.yx + a.yz * m.zx,
            a.yx * m.xy + a.yy * m.yy + a.yz * m.zy,
            a.yx * m.xz + a.yy * m.yz + a.yz * m.zz,
            a.zx * m.xx + a.zy * m.yx + a.zz * m.zx,
            a.zx * m.xy + a.zy * m.yy + a.zz * m.zy,
            a.zx * m.xz + a.zy * m.yz + a.zz * m.zz
        )
    }

    public static func * (a: Matrix3, v: Vector3) -> Vector3 {
        Vector3(
            a.xx * v.x + a.xy * v.y + a.xz * v.z,
            a.yx * v.x + a.yy * v.y + a.yz * v.z,
            a.zx * v.x + a.zy * v.y + a.zz * v.z
        )
    }

    /// Builds a matrix from three vectors, as columns (default) or rows.
    public static func fromVectors(_ v1: Vector3, _ v2: Vector3, _ v3: Vector3, columnVectors: Bool = true) -> Matrix3 {
        columnVectors
            ? Matrix3(v1.x, v2.x, v3.x, v1.y, v2.y, v3.y, v1.z, v2.z, v3.z)
            : Matrix3(v1.x, v1.y, v1.z, v2.x, v2.y, v2.z, v3.x, v3.y, v3.z)
    }
}

/// The rotation matrix for `degrees` about the unit vector `axis`.
public func rotationMatrix(_ degrees: Double, _ axis: Vector3) -> Matrix3 {
    let cosD = cos(degrees * degreesToRadians)
    let sinD = sin(degrees * degreesToRadians)
    let omc = 1.0 - cosD
    let x = axis.x, y = axis.y, z = axis.z
    let xs = x * sinD, ys = y * sinD, zs = z * sinD
    let xm = x * omc, ym = y * omc, zm = z * omc
    let xym = x * ym, yzm = y * zm, zxm = z * xm
    return Matrix3(
        x * xm + cosD, xym + zs, zxm - ys,
        xym - zs, y * ym + cosD, yzm + xs,
        zxm + ys, yzm - xs, z * zm + cosD
    )
}

// MARK: - RaDec

/// Right ascension / declination in degrees. The z axis is dec +90°, the x axis ra 0°/dec 0°.
public struct RaDec: Equatable, Hashable, Sendable {
    public var raDeg: Double
    public var decDeg: Double

    public init(_ raDeg: Double, _ decDeg: Double) {
        self.raDeg = raDeg
        self.decDeg = decDeg
    }

    public func toGeocentricVector() -> Vector3 {
        let ra = raDeg * degreesToRadians
        let dec = decDeg * degreesToRadians
        return Vector3(cos(ra) * cos(dec), sin(ra) * cos(dec), sin(dec))
    }

    public static func raDegreesFromHms(_ h: Double, _ m: Double, _ s: Double) -> Double {
        hoursToDegrees * (h + m / 60.0 + s / 3600.0)
    }

    /// The sign lives in the degrees field (including -0.0); minutes and seconds are magnitudes.
    public static func decDegreesFromDms(_ d: Double, _ m: Double, _ s: Double) -> Double {
        let mag = abs(d) + m / 60.0 + s / 3600.0
        return d.sign == .minus ? -mag : mag
    }

    /// Recovers ra/dec from a geocentric vector (need not be a unit vector).
    public static func fromGeocentricVector(_ v: Vector3) -> RaDec {
        let ra = normalizeDegrees(atan2(v.y, v.x) * radiansToDegrees)
        let dec = atan2(v.z, (v.x * v.x + v.y * v.y).squareRoot()) * radiansToDegrees
        return RaDec(ra, dec)
    }
}

/// Angular separation between two directions on the celestial sphere, in degrees.
public func angularSeparationDeg(_ a: RaDec, _ b: RaDec) -> Double {
    let c = a.toGeocentricVector().dot(b.toGeocentricVector())
    return acos(c.clamped(-1, 1)) * radiansToDegrees
}

// MARK: - LatLong

/// A normalized geographic location: latitude clamped to [-90, 90], longitude wrapped to [-180, 180).
public struct LatLong: Equatable, Hashable, Sendable {
    public let latitudeDeg: Double
    public let longitudeDeg: Double

    public init(_ latitudeDeg: Double, _ longitudeDeg: Double) {
        self.latitudeDeg = latitudeDeg.clamped(-90, 90)
        self.longitudeDeg = floorMod(longitudeDeg + 180.0, 360.0) - 180.0
    }

    public func distance(to other: LatLong) -> Double {
        angularSeparationDeg(RaDec(longitudeDeg, latitudeDeg), RaDec(other.longitudeDeg, other.latitudeDeg))
    }
}
