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

/// The observer's local reference directions expressed in celestial (geocentric equatorial)
/// coordinates. The magnetic pair is the true pair rotated about `up` by the magnetic declination.
public struct LocalFrame: Equatable, Sendable {
    public let trueNorth: Vector3
    public let up: Vector3
    public let trueEast: Vector3
    public let magneticNorth: Vector3
    public let magneticEast: Vector3

    /// `[magneticNorth, up, magneticEast]` as column vectors.
    public var axesMagneticCelestial: Matrix3 { Matrix3.fromVectors(magneticNorth, up, magneticEast) }

    /// `lineOfSight` as true azimuth (0–360° clockwise from north) and altitude.
    public func azAlt(_ lineOfSight: Vector3) -> AzAlt {
        let alt = asin(lineOfSight.dot(up).clamped(-1, 1)) * radiansToDegrees
        let az = normalizeDegrees(atan2(lineOfSight.dot(trueEast), lineOfSight.dot(trueNorth)) * radiansToDegrees)
        return AzAlt(azimuthDeg: az, altitudeDeg: alt)
    }

    /// The celestial direction for a true azimuth/altitude.
    public func direction(azimuthDeg: Double, altitudeDeg: Double) -> Vector3 {
        let az = azimuthDeg * degreesToRadians
        let alt = altitudeDeg * degreesToRadians
        return (trueNorth * (cos(alt) * cos(az)) + trueEast * (cos(alt) * sin(az)) + up * sin(alt)).normalized()
    }
}

public struct AzAlt: Equatable, Sendable {
    public let azimuthDeg: Double
    public let altitudeDeg: Double
}

/// Where the phone points: the direction into the screen and the screen-up direction.
public struct Pointing: Equatable, Sendable {
    public let lineOfSight: Vector3
    public let perpendicular: Vector3
}

/// Which phone axis is "into the sky".
public enum ViewDirectionMode: String, CaseIterable, Sendable {
    /// Looking out of the back of the screen, up along the phone's long side.
    case standard
    /// Displays fixed 90° from the sensor frame.
    case rotate90
    /// Sighting along the phone's long edge (phone strapped to a telescope tube).
    case telescope

    var pointingPhone: Vector3 {
        switch self {
        case .standard, .rotate90: return -Vector3.unitZ
        case .telescope: return Vector3.unitY
        }
    }

    var screenUpPhone: Vector3 {
        switch self {
        case .standard: return Vector3.unitY
        case .rotate90: return Vector3.unitX
        case .telescope: return Vector3.unitZ
        }
    }
}

/// v1's three-frame math (celestial / phone / local) as pure functions.
public enum SkyModel {
    /// The point directly overhead.
    public static func zenithRaDec(_ time: Date, _ location: LatLong) -> RaDec {
        RaDec(meanSiderealTimeDeg(time, location.longitudeDeg), location.latitudeDeg)
    }

    /// The observer's local frame in celestial coordinates for this time and place.
    public static func localFrame(_ time: Date, _ location: LatLong, magneticDeclinationDeg: Double = 0) -> LocalFrame {
        // Clamp just shy of the poles, where north is undefined.
        let safe = LatLong(location.latitudeDeg.clamped(-89, 89), location.longitudeDeg)
        let up = zenithRaDec(time, safe).toGeocentricVector()
        let z = Vector3.unitZ
        let trueNorth = (z - up * up.dot(z)).normalized()
        let trueEast = trueNorth.cross(up)
        let magneticNorth = rotationMatrix(magneticDeclinationDeg, up) * trueNorth
        let magneticEast = magneticNorth.cross(up)
        return LocalFrame(trueNorth: trueNorth, up: up, trueEast: trueEast,
                          magneticNorth: magneticNorth, magneticEast: magneticEast)
    }

    /// Resolves a phone→world orientation to a celestial pointing.
    ///
    /// `orientation` follows Android's rotation-matrix convention: its rows are world East,
    /// North and Up (north being the frame's *magnetic* north) expressed in phone coordinates,
    /// where the phone frame is x right, y up the screen, z out of the screen (the same as iOS).
    public static func pointing(_ frame: LocalFrame, _ orientation: Matrix3, mode: ViewDirectionMode = .standard) -> Pointing {
        let eastPhone = Vector3(orientation.xx, orientation.xy, orientation.xz)
        let northPhone = Vector3(orientation.yx, orientation.yy, orientation.yz)
        let upPhone = Vector3(orientation.zx, orientation.zy, orientation.zz)
        let axesPhoneInverse = Matrix3.fromVectors(northPhone, upPhone, eastPhone, columnVectors: false)
        let transform = frame.axesMagneticCelestial * axesPhoneInverse
        return Pointing(lineOfSight: transform * mode.pointingPhone, perpendicular: transform * mode.screenUpPhone)
    }
}

/// Fuses raw "up" (opposite gravity) and magnetic-field vectors in phone coordinates into an
/// orientation matrix in the convention `SkyModel.pointing` expects. Nil when degenerate.
public func orientationFromSensors(acceleration: Vector3, magneticField: Vector3) -> Matrix3? {
    let tol = 0.01
    if acceleration.length2 < tol || magneticField.length2 < tol { return nil }
    let upPhone = acceleration.normalized()
    let fieldDir = magneticField.normalized()
    let northPhone = (fieldDir - upPhone * fieldDir.dot(upPhone)).normalized()
    if northPhone == .zero { return nil }
    let eastPhone = northPhone.cross(upPhone)
    return Matrix3.fromVectors(eastPhone, northPhone, upPhone, columnVectors: false)
}

// MARK: - Bright limb

/// Position angle of the midpoint of a body's bright limb (Meeus 48.5), degrees east of north.
public func brightLimbAngleDeg(body: RaDec, sun: RaDec) -> Double {
    let ra = body.raDeg * degreesToRadians
    let dec = body.decDeg * degreesToRadians
    let sunRa = sun.raDeg * degreesToRadians
    let sunDec = sun.decDeg * degreesToRadians
    let dRa = sunRa - ra
    let num = cos(sunDec) * sin(dRa)
    let den = sin(sunDec) * cos(dec) - cos(sunDec) * sin(dec) * cos(dRa)
    let n = normalizeDegrees(atan2(num, den) * radiansToDegrees)
    return n >= 360.0 ? 0.0 : n
}

// MARK: - Lunar phase

/// The eight conventional lunar phases, with the Moon–Sun elongation at which each occurs.
public enum LunarPhase: Double, CaseIterable, Sendable {
    case new = 0, waxingCrescent = 45, firstQuarter = 90, waxingGibbous = 135
    case full = 180, waningGibbous = 225, lastQuarter = 270, waningCrescent = 315

    public var displayName: String {
        switch self {
        case .new: return "New Moon"
        case .waxingCrescent: return "Waxing Crescent"
        case .firstQuarter: return "First Quarter"
        case .waxingGibbous: return "Waxing Gibbous"
        case .full: return "Full Moon"
        case .waningGibbous: return "Waning Gibbous"
        case .lastQuarter: return "Last Quarter"
        case .waningCrescent: return "Waning Crescent"
        }
    }
}

/// Classifies the Moon's phase at `time` into one of the eight buckets.
public func lunarPhaseBucket(_ time: Date, ephemeris: Ephemeris = KeplerianEphemeris()) -> LunarPhase {
    let phase = ephemeris.phaseAngleDeg(.moon, time)
    if phase < 30.0 { return .full }
    if phase > 157.5 { return .new }
    let waxing = ephemeris.phaseAngleDeg(.moon, time.adding(days: 1)) < phase
    if phase < 67.5 { return waxing ? .waxingGibbous : .waningGibbous }
    if phase < 112.5 { return waxing ? .firstQuarter : .lastQuarter }
    return waxing ? .waxingCrescent : .waningCrescent
}

private let synodicMonthDays = 29.530588853

/// The first instant strictly after `after` at which the Moon reaches `phase`.
public func nextLunarPhaseEvent(_ phase: LunarPhase, after: Date, ephemeris: Ephemeris = KeplerianEphemeris()) -> Date {
    func elongation(_ t: Date) -> Double {
        normalizeDegrees(ephemeris.geocentricPosition(.moon, t).raDeg - ephemeris.geocentricPosition(.sun, t).raDeg)
    }
    let target = phase.rawValue
    var advance = normalizeDegrees(target - elongation(after))
    if advance < 1e-6 { advance += 360.0 }
    var time = after.adding(days: advance / 360.0 * synodicMonthDays)
    for _ in 0..<8 {
        let err = normalizeDegrees(target - elongation(time) + 180.0) - 180.0
        time = time.adding(days: err / 360.0 * synodicMonthDays)
    }
    return time
}

// MARK: - Rise / set

public enum RiseSetIndicator: Sendable { case rise, set }

public let civilTwilightSunAltDeg: Double = -6.0
public let nauticalTwilightSunAltDeg: Double = -12.0

/// -0.83° for the Sun and Moon (refraction plus semidiameter); 0 for point-like bodies.
public func horizonAltitudeDeg(_ body: SolarSystemBody) -> Double {
    body == .sun || body == .moon ? -0.83 : 0.0
}

/// The next rise/set of `body` at `location` after `after`, or nil within the next few days.
public func nextRiseSetTime(
    _ body: SolarSystemBody, after: Date, location: LatLong, indicator: RiseSetIndicator,
    ephemeris: Ephemeris = KeplerianEphemeris()
) -> Date? {
    nextRiseSetTime(
        position: { ephemeris.topocentricPosition(body, $0, location) },
        after: after, location: location, indicator: indicator,
        horizonAltitudeDeg: horizonAltitudeDeg(body)
    )
}

/// The generalized solver: the next crossing of `horizonAltitudeDeg` by an object at `position`.
public func nextRiseSetTime(
    position: (Date) -> RaDec, after: Date, location: LatLong, indicator: RiseSetIndicator,
    horizonAltitudeDeg: Double = 0.0
) -> Date? {
    for dayOffset in 0...2 {
        if let c = riseSetOnDayOf(position, after.adding(days: Double(dayOffset)), location, indicator, horizonAltitudeDeg),
           c >= after {
            return c
        }
    }
    return nil
}

private func utDayStart(_ date: Date) -> Date {
    let s = date.timeIntervalSince1970
    return Date(timeIntervalSince1970: (s / 86_400.0).rounded(.down) * 86_400.0)
}

private func riseSetOnDayOf(
    _ position: (Date) -> RaDec, _ date: Date, _ location: LatLong, _ indicator: RiseSetIndicator, _ horizonAlt: Double
) -> Date? {
    let dayStart = utDayStart(date)
    let sign = indicator == .rise ? 1.0 : -1.0
    var delta = 5.0
    var ut = 12.0
    var iterations = 0
    while abs(delta) > 0.008 && iterations < 25 {
        let trial = dayStart.adding(hours: ut)
        let p = position(trial)
        let gha = meanSiderealTimeDeg(trial, 0.0) - p.raDeg
        guard let ha = riseSetHourAngleDeg(horizonAlt, location.latitudeDeg, p.decDeg) else { return nil }
        delta = (gha + location.longitudeDeg + sign * ha) / 15.0
        if !delta.isFinite { return nil }
        delta = delta.truncatingRemainder(dividingBy: 24.0)
        if delta > 12.0 { delta -= 24.0 }
        if delta < -12.0 { delta += 24.0 }
        ut = (ut - delta).truncatingRemainder(dividingBy: 24.0)
        if ut < 0.0 { ut += 24.0 }
        iterations += 1
    }
    return iterations == 25 ? nil : dayStart.adding(hours: ut)
}

private func riseSetHourAngleDeg(_ altDeg: Double, _ latDeg: Double, _ decDeg: Double) -> Double? {
    let alt = altDeg * degreesToRadians, lat = latDeg * degreesToRadians, dec = decDeg * degreesToRadians
    let cosHa = (sin(alt) - sin(lat) * sin(dec)) / (cos(lat) * cos(dec))
    if cosHa.isNaN || abs(cosHa) > 1.0 { return nil }
    return acos(cosHa) * radiansToDegrees
}

/// Altitude of `position` above the horizon at `time` and `location`, degrees.
public func altitudeDeg(_ position: RaDec, _ time: Date, _ location: LatLong) -> Double {
    let ha = (meanSiderealTimeDeg(time, location.longitudeDeg) - position.raDeg) * degreesToRadians
    let lat = location.latitudeDeg * degreesToRadians, dec = position.decDeg * degreesToRadians
    let sinAlt = sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha)
    return asin(sinAlt.clamped(-1, 1)) * radiansToDegrees
}
