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

/// The solar-system bodies the ephemeris can compute, in v1's reverse-distance draw order.
/// `earth` exists only as an element source for heliocentric → geocentric conversion.
public enum SolarSystemBody: String, CaseIterable, Sendable {
    case pluto, neptune, uranus, saturn, jupiter, mars, sun, mercury, venus, moon, earth

    /// Everything viewable — Earth is the observer, not a target.
    public static let viewable: [SolarSystemBody] = allCases.filter { $0 != .earth }

    /// The catalog id (`planet/<body>`), the join key between ephemeris and catalog.
    public var objectId: String { "planet/\(rawValue)" }

    public init?(objectId: String) {
        guard objectId.hasPrefix("planet/") else { return nil }
        self.init(rawValue: String(objectId.dropFirst("planet/".count)))
    }
}

/// Kilometres in an astronomical unit (IAU 2012, exact).
public let kmPerAu = 149_597_870.7

/// Mean equatorial radius in kilometres (IAU/NASA fact-sheet values).
public func equatorialRadiusKm(_ body: SolarSystemBody) -> Double {
    switch body {
    case .sun: return 696_000.0
    case .mercury: return 2_439.7
    case .venus: return 6_051.8
    case .earth: return 6_378.1
    case .moon: return 1_737.4
    case .mars: return 3_396.2
    case .jupiter: return 71_492.0
    case .saturn: return 60_268.0
    case .uranus: return 25_559.0
    case .neptune: return 24_764.0
    case .pluto: return 1_188.3
    }
}

/// The six Keplerian elements describing an orbit around the Sun. Angles in radians.
/// Source: JPL's approximations (Van Flandern & Pulkkinen, 1979), good for ~1800–2050.
public struct OrbitalElements: Sendable {
    public let distanceAu: Double
    public let eccentricity: Double
    public let inclinationRad: Double
    public let ascendingNodeRad: Double
    public let perihelionRad: Double
    public let meanLongitudeRad: Double

    /// True anomaly in radians.
    public var anomaly: Double { trueAnomaly(meanLongitudeRad - perihelionRad, eccentricity) }
}

private func trueAnomaly(_ m: Double, _ e: Double) -> Double {
    var ea = m + e * sin(m) * (1.0 + e * cos(m))
    for _ in 0..<100 {
        let delta = (ea - e * sin(ea) - m) / (1.0 - e * cos(ea))
        ea -= delta
        if abs(delta) <= 1.0e-8 { break }
    }
    let v = 2.0 * atan(((1 + e) / (1 - e)).squareRoot() * tan(0.5 * ea))
    return normalizeRadians(v)
}

/// The osculating elements for `body` from JPL's two-term linear fits. Not defined for Sun/Moon.
public func orbitalElements(_ body: SolarSystemBody, _ time: Date) -> OrbitalElements {
    let jc = time.julianCenturiesJ2000
    func el(_ a: Double, _ e: Double, _ i: Double, _ node: Double, _ peri: Double, _ l: Double) -> OrbitalElements {
        OrbitalElements(
            distanceAu: a, eccentricity: e,
            inclinationRad: i * degreesToRadians,
            ascendingNodeRad: node * degreesToRadians,
            perihelionRad: peri * degreesToRadians,
            meanLongitudeRad: normalizeRadians(l * degreesToRadians)
        )
    }
    switch body {
    case .mercury:
        return el(0.38709927 + 0.00000037 * jc, 0.20563593 + 0.00001906 * jc, 7.00497902 - 0.00594749 * jc,
                  48.33076593 - 0.12534081 * jc, 77.45779628 + 0.16047689 * jc, 252.25032350 + 149472.67411175 * jc)
    case .venus:
        return el(0.72333566 + 0.00000390 * jc, 0.00677672 - 0.00004107 * jc, 3.39467605 - 0.00078890 * jc,
                  76.67984255 - 0.27769418 * jc, 131.60246718 + 0.00268329 * jc, 181.97909950 + 58517.81538729 * jc)
    case .earth:
        return el(1.00000261 + 0.00000562 * jc, 0.01671123 - 0.00004392 * jc, -0.00001531 - 0.01294668 * jc,
                  0.0, 102.93768193 + 0.32327364 * jc, 100.46457166 + 35999.37244981 * jc)
    case .mars:
        return el(1.52371034 + 0.00001847 * jc, 0.09339410 + 0.00007882 * jc, 1.84969142 - 0.00813131 * jc,
                  49.55953891 - 0.29257343 * jc, -23.94362959 + 0.44441088 * jc, -4.55343205 + 19140.30268499 * jc)
    case .jupiter:
        return el(5.20288700 - 0.00011607 * jc, 0.04838624 - 0.00013253 * jc, 1.30439695 - 0.00183714 * jc,
                  100.47390909 + 0.20469106 * jc, 14.72847983 + 0.21252668 * jc, 34.39644051 + 3034.74612775 * jc)
    case .saturn:
        return el(9.53667594 - 0.00125060 * jc, 0.05386179 - 0.00050991 * jc, 2.48599187 + 0.00193609 * jc,
                  113.66242448 - 0.28867794 * jc, 92.59887831 - 0.41897216 * jc, 49.95424423 + 1222.49362201 * jc)
    case .uranus:
        return el(19.18916464 - 0.00196176 * jc, 0.04725744 - 0.00004397 * jc, 0.77263783 - 0.00242939 * jc,
                  74.01692503 + 0.04240589 * jc, 170.95427630 + 0.40805281 * jc, 313.23810451 + 428.48202785 * jc)
    case .neptune:
        return el(30.06992276 + 0.00026291 * jc, 0.00859048 + 0.00005105 * jc, 1.77004347 + 0.00035372 * jc,
                  131.78422574 - 0.00508664 * jc, 44.96476227 - 0.32241464 * jc, -55.12002969 + 218.45945325 * jc)
    case .pluto:
        return el(39.48211675 - 0.00031596 * jc, 0.24882730 + 0.00005170 * jc, 17.14001206 + 0.00004818 * jc,
                  110.30393684 - 0.01183482 * jc, 224.06891629 - 0.04062942 * jc, 238.92903833 + 145.20780515 * jc)
    case .sun, .moon:
        preconditionFailure("\(body) has no heliocentric orbital elements")
    }
}

private let obliquityRad = 23.439281 * degreesToRadians
private let cosObliquity = cos(obliquityRad)
private let sinObliquity = sin(obliquityRad)

/// Heliocentric ecliptic rectangular coordinates (AU) for an orbit.
func heliocentricCoordinates(_ elem: OrbitalElements) -> Vector3 {
    let anomaly = elem.anomaly
    let ecc = elem.eccentricity
    let radius = elem.distanceAu * (1 - ecc * ecc) / (1 + ecc * cos(anomaly))
    let asc = elem.ascendingNodeRad
    let inc = elem.inclinationRad
    let arg = anomaly + elem.perihelionRad - asc
    return Vector3(
        radius * (cos(asc) * cos(arg) - sin(asc) * sin(arg) * cos(inc)),
        radius * (sin(asc) * cos(arg) + cos(asc) * sin(arg) * cos(inc)),
        radius * (sin(arg) * sin(inc))
    )
}

/// Rotates an ecliptic-plane vector into the equatorial plane by the J2000 obliquity.
func toEquatorialCoordinates(_ v: Vector3) -> Vector3 {
    Vector3(v.x, v.y * cosObliquity - v.z * sinObliquity, v.y * sinObliquity + v.z * cosObliquity)
}
