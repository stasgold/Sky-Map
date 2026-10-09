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

/// Computes apparent positions and appearance of solar-system bodies. Implementations are
/// pure and stateless.
public protocol Ephemeris: Sendable {
    /// Geocentric (Earth-centred, equatorial J2000) apparent position.
    func geocentricPosition(_ body: SolarSystemBody, _ time: Date) -> RaDec
    /// Topocentric (observer-centred) position — what the sky shows at `observer`.
    func topocentricPosition(_ body: SolarSystemBody, _ time: Date, _ observer: LatLong) -> RaDec
    /// Phase angle in degrees (0 = fully lit as seen from Earth, 180 = unlit).
    func phaseAngleDeg(_ body: SolarSystemBody, _ time: Date) -> Double
    /// Apparent visual magnitude.
    func magnitude(_ body: SolarSystemBody, _ time: Date) -> Double
    /// Maximum apparent angular speed in degrees/day, for re-submission thresholds.
    func maxAngularVelocityDegPerDay(_ body: SolarSystemBody) -> Double
    /// Distance from Earth's centre in AU (good to ~1%).
    func earthDistanceAu(_ body: SolarSystemBody, _ time: Date) -> Double
}

public extension Ephemeris {
    /// Fraction of the disc illuminated as seen from Earth, in `[0, 1]`.
    func illuminatedFraction(_ body: SolarSystemBody, _ time: Date) -> Double {
        0.5 * (1.0 + cos(phaseAngleDeg(body, time) * degreesToRadians))
    }

    /// True apparent equatorial diameter in degrees.
    func angularDiameterDeg(_ body: SolarSystemBody, _ time: Date) -> Double {
        let distanceKm = earthDistanceAu(body, time) * kmPerAu
        return 2.0 * atan(equatorialRadiusKm(body) / distanceKm) * radiansToDegrees
    }
}

/// The low-precision ephemeris ported from v1: JPL two-term elements, an iterative Kepler
/// solver, the Astronomical Almanac (2008, p. D22) lunar approximation, and Van Flandern-style
/// magnitude polynomials. The Moon's topocentric query applies the full diurnal parallax.
public struct KeplerianEphemeris: Ephemeris {
    public init() {}

    public func geocentricPosition(_ body: SolarSystemBody, _ time: Date) -> RaDec {
        switch body {
        case .moon: return RaDec.fromGeocentricVector(lunarGeocentricDirection(time))
        case .sun: return sunOrbitingPosition(.zero, time)
        case .earth: preconditionFailure("Earth has no geocentric position")
        default: return sunOrbitingPosition(heliocentricCoordinates(orbitalElements(body, time)), time)
        }
    }

    public func topocentricPosition(_ body: SolarSystemBody, _ time: Date, _ observer: LatLong) -> RaDec {
        guard body == .moon else { return geocentricPosition(body, time) }
        let distanceEarthRadii = 1.0 / sin(lunarHorizontalParallaxDeg(time) * degreesToRadians)
        let lmst = meanSiderealTimeDeg(time, observer.longitudeDeg) * degreesToRadians
        let lat = observer.latitudeDeg * degreesToRadians
        let observerFromGeocentre = Vector3(cos(lat) * cos(lmst), cos(lat) * sin(lmst), sin(lat))
        return RaDec.fromGeocentricVector(lunarGeocentricDirection(time) * distanceEarthRadii - observerFromGeocentre)
    }

    public func phaseAngleDeg(_ body: SolarSystemBody, _ time: Date) -> Double {
        switch body {
        case .sun: return 0.0
        case .moon:
            let moon = lunarGeocentricDirection(time)
            // Ecliptic anti-solar direction dotted with the equatorial Moon vector: v1's
            // deliberate ~1% elongation approximation (with v1's inverted sign corrected).
            let antiSolar = heliocentricCoordinates(orbitalElements(.earth, time)).normalized()
            return acos(antiSolar.dot(moon).clamped(-1, 1)) * radiansToDegrees
        case .earth: preconditionFailure("Earth has no phase angle")
        default:
            let (planet, earth) = heliocentricPair(body, time)
            return planetPhaseAngleDeg(planet, earth)
        }
    }

    public func magnitude(_ body: SolarSystemBody, _ time: Date) -> Double {
        switch body {
        case .sun: return -27.0
        case .moon: return -10.0
        case .earth: preconditionFailure("Earth has no magnitude")
        default:
            let (planet, earth) = heliocentricPair(body, time)
            let earthDistance = planet.distance(to: earth)
            let p = planetPhaseAngleDeg(planet, earth) / 100.0
            let base: Double
            switch body {
            case .mercury: base = -0.42 + (3.80 - (2.73 - 2.00 * p) * p) * p
            case .venus: base = -4.40 + (0.09 + (2.39 - 0.65 * p) * p) * p
            case .mars: base = -1.52 + 1.6 * p
            case .jupiter: base = -9.40 + 0.5 * p
            case .saturn: base = -8.75
            case .uranus: base = -7.19
            case .neptune: base = -6.87
            default: base = -1.0 // Pluto
            }
            return base + 5.0 * log10(planet.length * earthDistance)
        }
    }

    public func maxAngularVelocityDegPerDay(_ body: SolarSystemBody) -> Double {
        switch body {
        case .moon: return 15.0
        case .mercury: return 7.0
        case .venus: return 4.0
        case .sun: return 1.1
        case .mars: return 1.5
        case .jupiter: return 0.25
        case .saturn: return 0.13
        case .uranus: return 0.06
        case .neptune, .pluto: return 0.04
        case .earth: return 0.0
        }
    }

    public func earthDistanceAu(_ body: SolarSystemBody, _ time: Date) -> Double {
        switch body {
        case .moon: return 0.00257
        case .sun: return heliocentricCoordinates(orbitalElements(.earth, time)).length
        case .earth: return 0.0
        default:
            let (planet, earth) = heliocentricPair(body, time)
            return planet.distance(to: earth)
        }
    }

    // MARK: internals

    private func heliocentricPair(_ body: SolarSystemBody, _ time: Date) -> (Vector3, Vector3) {
        (heliocentricCoordinates(orbitalElements(body, time)), heliocentricCoordinates(orbitalElements(.earth, time)))
    }

    private func sunOrbitingPosition(_ helio: Vector3, _ time: Date) -> RaDec {
        let earth = heliocentricCoordinates(orbitalElements(.earth, time))
        return RaDec.fromGeocentricVector(toEquatorialCoordinates(helio - earth))
    }

    private func planetPhaseAngleDeg(_ planet: Vector3, _ earth: Vector3) -> Double {
        let d = planet.distance(to: earth)
        let cosPhase = (d * d + planet.length2 - earth.length2) / (2.0 * d * planet.length)
        return acos(cosPhase.clamped(-1, 1)) * radiansToDegrees
    }

    private func lunarHorizontalParallaxDeg(_ time: Date) -> Double {
        let t = time.julianCenturiesJ2000
        return 0.9508
            + 0.0518 * cos((134.9 + 477198.85 * t) * degreesToRadians)
            + 0.0095 * cos((259.2 - 413335.38 * t) * degreesToRadians)
            + 0.0078 * cos((235.7 + 890534.23 * t) * degreesToRadians)
            + 0.0028 * cos((269.9 + 954397.70 * t) * degreesToRadians)
    }

    private func lunarGeocentricDirection(_ time: Date) -> Vector3 {
        let t = time.julianCenturiesJ2000
        func s(_ a: Double) -> Double { sin(a * degreesToRadians) }
        let lambda = 218.32 + 481267.881 * t
            + 6.29 * s(135.0 + 477198.87 * t)
            - 1.27 * s(259.3 - 413335.36 * t)
            + 0.66 * s(235.7 + 890534.22 * t)
            + 0.21 * s(269.9 + 954397.74 * t)
            - 0.19 * s(357.5 + 35999.05 * t)
            - 0.11 * s(186.5 + 966404.03 * t)
        let beta = 5.13 * s(93.3 + 483202.02 * t)
            + 0.28 * s(228.2 + 960400.89 * t)
            - 0.28 * s(318.3 + 6003.15 * t)
            - 0.17 * s(217.6 - 407332.21 * t)
        let l = lambda * degreesToRadians
        let b = beta * degreesToRadians
        return Vector3(
            cos(b) * cos(l),
            0.9175 * cos(b) * sin(l) - 0.3978 * sin(b),
            0.3978 * cos(b) * sin(l) + 0.9175 * sin(b)
        )
    }
}

// MARK: - Precession

/// Precession between the J2000 mean equatorial frame (the frame the app draws in) and the
/// mean equator and equinox of another date. IAU 1976 (Lieske) polynomials.
public enum Precession {
    /// Rotation taking a J2000 vector to the mean equator and equinox of `time`.
    public static func dateFromJ2000(_ time: Date) -> Matrix3 {
        let t = time.julianCenturiesTerrestrialJ2000
        func arcsec(_ v: Double) -> Double { v / 3600.0 * degreesToRadians }
        let zeta = arcsec(2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t)
        let z = arcsec(2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t)
        let theta = arcsec(2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t)
        let cZeta = cos(zeta), sZeta = sin(zeta), cZ = cos(z), sZ = sin(z), cT = cos(theta), sT = sin(theta)
        return Matrix3(
            cZeta * cT * cZ - sZeta * sZ, -sZeta * cT * cZ - cZeta * sZ, -sT * cZ,
            cZeta * cT * sZ + sZeta * cZ, -sZeta * cT * sZ + cZeta * cZ, -sT * sZ,
            cZeta * sT, -sZeta * sT, cT
        )
    }

    /// Rotation taking an of-date vector back to J2000 (the transpose).
    public static func j2000FromDate(_ time: Date) -> Matrix3 { dateFromJ2000(time).transposed() }
}

// MARK: - Meeus

/// The higher-precision ephemeris: the Sun from Meeus ch. 25 and the Moon from the truncated
/// ELP-2000/82 series (Meeus ch. 47), both rotated from equinox-of-date into J2000. Everything
/// else delegates to `KeplerianEphemeris`.
public struct MeeusEphemeris: Ephemeris {
    private let baseline = KeplerianEphemeris()
    public init() {}

    public func geocentricPosition(_ body: SolarSystemBody, _ time: Date) -> RaDec {
        switch body {
        case .sun: return sunApparentPosition(time)
        case .moon:
            return RaDec.fromGeocentricVector(Precession.j2000FromDate(time) * moonPosition(time).directionCosines())
        default: return baseline.geocentricPosition(body, time)
        }
    }

    public func topocentricPosition(_ body: SolarSystemBody, _ time: Date, _ observer: LatLong) -> RaDec {
        switch body {
        case .moon:
            let moon = moonPosition(time)
            let distanceEarthRadii = moon.distanceKm / 6378.14
            let lmst = meanSiderealTimeDeg(time, observer.longitudeDeg) * degreesToRadians
            let lat = observer.latitudeDeg * degreesToRadians
            let obs = Vector3(cos(lat) * cos(lmst), cos(lat) * sin(lmst), sin(lat))
            let topo = moon.directionCosines() * distanceEarthRadii - obs
            return RaDec.fromGeocentricVector(Precession.j2000FromDate(time) * topo)
        case .sun: return sunApparentPosition(time)
        default: return baseline.topocentricPosition(body, time, observer)
        }
    }

    public func phaseAngleDeg(_ body: SolarSystemBody, _ time: Date) -> Double { baseline.phaseAngleDeg(body, time) }
    public func magnitude(_ body: SolarSystemBody, _ time: Date) -> Double { baseline.magnitude(body, time) }
    public func maxAngularVelocityDegPerDay(_ body: SolarSystemBody) -> Double { baseline.maxAngularVelocityDegPerDay(body) }

    public func earthDistanceAu(_ body: SolarSystemBody, _ time: Date) -> Double {
        body == .moon ? moonPosition(time).distanceKm / kmPerAu : baseline.earthDistanceAu(body, time)
    }

    private func sunApparentPosition(_ time: Date) -> RaDec {
        let t = time.julianCenturiesTerrestrialJ2000
        let l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let m = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) * degreesToRadians
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m) + 0.000289 * sin(3 * m)
        let omega = (125.04 - 1934.136 * t) * degreesToRadians
        let lambda = (l0 + c - 0.00569 - 0.00478 * sin(omega)) * degreesToRadians
        let eps = (23.439291 - 0.0130042 * t + 0.00256 * cos(omega)) * degreesToRadians
        let ofDate = Vector3(cos(lambda), cos(eps) * sin(lambda), sin(eps) * sin(lambda))
        return RaDec.fromGeocentricVector(Precession.j2000FromDate(time) * ofDate)
    }

    private struct MoonState {
        let lambdaDeg: Double
        let betaDeg: Double
        let distanceKm: Double
        let obliquityRad: Double

        func directionCosines() -> Vector3 {
            let l = lambdaDeg * degreesToRadians
            let b = betaDeg * degreesToRadians
            return Vector3(
                cos(b) * cos(l),
                cos(obliquityRad) * cos(b) * sin(l) - sin(obliquityRad) * sin(b),
                sin(obliquityRad) * cos(b) * sin(l) + cos(obliquityRad) * sin(b)
            )
        }
    }

    private func moonPosition(_ time: Date) -> MoonState {
        let t = time.julianCenturiesTerrestrialJ2000
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t
        let lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 + t3 / 538841.0 - t4 / 65194000.0
        let d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545868.0 - t4 / 113065000.0
        let m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24490000.0
        let mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69699.0 - t4 / 14712000.0
        let f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t2 - t3 / 3526000.0 + t4 / 863310000.0
        let a1 = 119.75 + 131.849 * t
        let a2 = 53.09 + 479264.290 * t
        let a3 = 313.45 + 481266.484 * t
        let e = 1.0 - 0.002516 * t - 0.0000074 * t2
        func ef(_ mult: Int) -> Double {
            switch abs(mult) {
            case 1: return e
            case 2: return e * e
            default: return 1.0
            }
        }
        func s(_ deg: Double) -> Double { sin(deg * degreesToRadians) }
        var sumL = 0.0, sumR = 0.0, sumB = 0.0
        for row in MeeusEphemeris.table47A {
            let arg = (Double(row[0]) * d + Double(row[1]) * m + Double(row[2]) * mp + Double(row[3]) * f) * degreesToRadians
            let factor = ef(row[1])
            sumL += Double(row[4]) * factor * sin(arg)
            sumR += Double(row[5]) * factor * cos(arg)
        }
        for row in MeeusEphemeris.table47B {
            let arg = (Double(row[0]) * d + Double(row[1]) * m + Double(row[2]) * mp + Double(row[3]) * f) * degreesToRadians
            sumB += Double(row[4]) * ef(row[1]) * sin(arg)
        }
        sumL += 3958.0 * s(a1) + 1962.0 * s(lp - f) + 318.0 * s(a2)
        sumB += -2235.0 * s(lp) + 382.0 * s(a3) + 175.0 * s(a1 - f) + 175.0 * s(a1 + f)
            + 127.0 * s(lp - mp) - 115.0 * s(lp + mp)
        var lambda = lp + sumL / 1_000_000.0
        let beta = sumB / 1_000_000.0
        let distanceKm = 385000.56 + sumR / 1000.0
        let omega = 125.04452 - 1934.136261 * t
        let lSun = 280.4665 + 36000.7698 * t
        let lMoon = 218.3165 + 481267.8813 * t
        func c(_ deg: Double) -> Double { cos(deg * degreesToRadians) }
        let dPsi = -17.20 * s(omega) - 1.32 * s(2 * lSun) - 0.23 * s(2 * lMoon) + 0.21 * s(2 * omega)
        let dEps = 9.20 * c(omega) + 0.57 * c(2 * lSun) + 0.10 * c(2 * lMoon) - 0.09 * c(2 * omega)
        lambda += dPsi / 3600.0
        let eps0 = 23.4392911 - 0.0130042 * t - 1.64e-7 * t2 + 5.04e-7 * t3
        return MoonState(
            lambdaDeg: lambda, betaDeg: beta, distanceKm: distanceKm,
            obliquityRad: (eps0 + dEps / 3600.0) * degreesToRadians
        )
    }

    /// Meeus table 47.A: (D, M, M′, F), longitude coeff (1e-6°), distance coeff (1e-3 km).
    static let table47A: [[Int]] = [
        [0, 0, 1, 0, 6288774, -20905355],
        [2, 0, -1, 0, 1274027, -3699111],
        [2, 0, 0, 0, 658314, -2955968],
        [0, 0, 2, 0, 213618, -569925],
        [0, 1, 0, 0, -185116, 48888],
        [0, 0, 0, 2, -114332, -3149],
        [2, 0, -2, 0, 58793, 246158],
        [2, -1, -1, 0, 57066, -152138],
        [2, 0, 1, 0, 53322, -170733],
        [2, -1, 0, 0, 45758, -204586],
        [0, 1, -1, 0, -40923, -129620],
        [1, 0, 0, 0, -34720, 108743],
        [0, 1, 1, 0, -30383, 104755],
        [2, 0, 0, -2, 15327, 10321],
        [0, 0, 1, 2, -12528, 0],
        [0, 0, 1, -2, 10980, 79661],
        [4, 0, -1, 0, 10675, -34782],
        [0, 0, 3, 0, 10034, -23210],
        [4, 0, -2, 0, 8548, -21636],
        [2, 1, -1, 0, -7888, 24208],
        [2, 1, 0, 0, -6766, 30824],
        [1, 0, -1, 0, -5163, -8379],
        [1, 1, 0, 0, 4987, -16675],
        [2, -1, 1, 0, 4036, -12831],
        [2, 0, 2, 0, 3994, -10445],
        [4, 0, 0, 0, 3861, -11650],
        [2, 0, -3, 0, 3665, 14403],
        [0, 1, -2, 0, -2689, -7003],
        [2, 0, -1, 2, -2602, 0],
        [2, -1, -2, 0, 2390, 10056],
        [1, 0, 1, 0, -2348, 6322],
        [2, -2, 0, 0, 2236, -9884],
        [0, 1, 2, 0, -2120, 5751],
        [0, 2, 0, 0, -2069, 0],
        [2, -2, -1, 0, 2048, -4950],
        [2, 0, 1, -2, -1773, 4130],
        [2, 0, 0, 2, -1595, 0],
        [4, -1, -1, 0, 1215, -3958],
        [0, 0, 2, 2, -1110, 0],
        [3, 0, -1, 0, -892, 3258],
        [2, 1, 1, 0, -810, 2616],
        [4, -1, -2, 0, 759, -1897],
        [0, 2, -1, 0, -713, -2117],
        [2, 2, -1, 0, -700, 2354],
        [2, 1, -2, 0, 691, 0],
        [2, -1, 0, -2, 596, 0],
        [4, 0, 1, 0, 549, -1423],
        [0, 0, 4, 0, 537, -1117],
        [4, -1, 0, 0, 520, -1571],
        [1, 0, -2, 0, -487, -1739],
        [2, 1, 0, -2, -399, 0],
        [0, 0, 2, -2, -381, -4421],
        [1, 1, 1, 0, 351, 0],
        [3, 0, -2, 0, -340, 0],
        [4, 0, -3, 0, 330, 0],
        [2, -1, 2, 0, 327, 0],
        [0, 2, 1, 0, -323, 1165],
        [1, 1, -1, 0, 299, 0],
        [2, 0, 3, 0, 294, 0],
        [2, 0, -1, -2, 0, 8752],
    ]

    /// Meeus table 47.B: (D, M, M′, F), latitude coeff (1e-6°).
    static let table47B: [[Int]] = [
        [0, 0, 0, 1, 5128122],
        [0, 0, 1, 1, 280602],
        [0, 0, 1, -1, 277693],
        [2, 0, 0, -1, 173237],
        [2, 0, -1, 1, 55413],
        [2, 0, -1, -1, 46271],
        [2, 0, 0, 1, 32573],
        [0, 0, 2, 1, 17198],
        [2, 0, 1, -1, 9266],
        [0, 0, 2, -1, 8822],
        [2, -1, 0, -1, 8216],
        [2, 0, -2, -1, 4324],
        [2, 0, 1, 1, 4200],
        [2, 1, 0, -1, -3359],
        [2, -1, -1, 1, 2463],
        [2, -1, 0, 1, 2211],
        [2, -1, -1, -1, 2065],
        [0, 1, -1, -1, -1870],
        [4, 0, -1, -1, 1828],
        [0, 1, 0, 1, -1794],
        [0, 0, 0, 3, -1749],
        [0, 1, -1, 1, -1565],
        [1, 0, 0, 1, -1491],
        [0, 1, 1, 1, -1475],
        [0, 1, 1, -1, -1410],
        [0, 1, 0, -1, -1344],
        [1, 0, 0, -1, -1335],
        [0, 0, 3, 1, 1107],
        [4, 0, 0, -1, 1021],
        [4, 0, -1, 1, 833],
        [0, 0, 1, -3, 777],
        [4, 0, -2, 1, 671],
        [2, 0, 0, -3, 607],
        [2, 0, 2, -1, 596],
        [2, -1, 1, -1, 491],
        [2, 0, -2, 1, -451],
        [0, 0, 3, -1, 439],
        [2, 0, 2, 1, 422],
        [2, 0, -3, -1, 421],
        [2, 1, -1, 1, -366],
        [2, 1, 0, 1, -351],
        [4, 0, 0, 1, 331],
        [2, -1, 1, 1, 315],
        [2, -2, 0, -1, 302],
        [0, 0, 1, 3, -283],
        [2, 1, 1, -1, -229],
        [1, 1, 0, -1, 223],
        [1, 1, 0, 1, 223],
        [0, 1, -2, -1, -220],
        [2, 1, -1, -1, -220],
        [1, 0, 1, 1, -185],
        [2, -1, -2, -1, 181],
        [0, 1, 2, 1, -177],
        [4, 0, -2, -1, 176],
        [4, -1, -1, -1, 166],
        [1, 0, 1, -1, -164],
        [4, 0, 1, -1, 132],
        [1, 0, -1, -1, -119],
        [4, -1, 0, -1, 115],
        [2, -2, 0, 1, 107],
    ]
}
