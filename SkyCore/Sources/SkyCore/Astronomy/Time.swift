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

/// Julian Day at the J2000.0 epoch.
public let jdJ2000: Double = 2451545.0
private let jdUnixEpoch: Double = 2440587.5
private let secondsPerDay: Double = 86_400.0

public extension Date {
    /// Exact identity `JD = unixSeconds / 86400 + 2440587.5`.
    var julianDay: Double { timeIntervalSince1970 / secondsPerDay + jdUnixEpoch }

    /// Julian centuries since J2000.0 (UT, approximating TT).
    var julianCenturiesJ2000: Double { (julianDay - jdJ2000) / 36525.0 }

    /// Delta-T (TT − UT) in seconds, Espenak–Meeus polynomial for 2005–2050.
    var deltaTSeconds: Double {
        let u = (julianDay - jdJ2000) / 365.25
        return 62.92 + 0.32217 * u + 0.005589 * u * u
    }

    /// Julian centuries of Terrestrial Time since J2000.0.
    var julianCenturiesTerrestrialJ2000: Double {
        (julianDay + deltaTSeconds / secondsPerDay - jdJ2000) / 36525.0
    }

    func adding(days: Double) -> Date { addingTimeInterval(days * secondsPerDay) }
    func adding(hours: Double) -> Date { addingTimeInterval(hours * 3600.0) }
}

/// Local mean sidereal time in degrees for the given longitude (negative for west).
public func meanSiderealTimeDeg(_ time: Date, _ longitudeDeg: Double) -> Double {
    let delta = time.julianDay - jdJ2000
    return normalizeDegrees(280.461 + 360.98564737 * delta + longitudeDeg)
}
