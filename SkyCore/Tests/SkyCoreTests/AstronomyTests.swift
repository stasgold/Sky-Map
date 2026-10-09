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
import XCTest
@testable import SkyCore

func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)!
}

/// Golden values ported from the upstream Kotlin tests (USNO / Astronomical Almanac references).
final class AstronomyTests: XCTestCase {
    let kepler = KeplerianEphemeris()
    let meeus = MeeusEphemeris()

    private func assertPosition(_ e: Ephemeris, _ body: SolarSystemBody, _ t: Date, _ raH: Double, _ dec: Double,
                                _ tol: Double, precessToDate: Bool = false, line: UInt = #line) {
        var pos = e.geocentricPosition(body, t)
        if precessToDate {
            pos = RaDec.fromGeocentricVector(Precession.dateFromJ2000(t) * pos.toGeocentricVector())
        }
        var dRa = abs(pos.raDeg - raH * 15.0)
        dRa = min(dRa, 360 - dRa)
        XCTAssertLessThan(dRa, tol, "\(body) ra", line: line)
        XCTAssertEqual(pos.decDeg, dec, accuracy: tol, "\(body) dec", line: line)
    }

    func testJulianDay() {
        XCTAssertEqual(utc(2000, 1, 1, 12).julianDay, 2451545.0, accuracy: 1e-9)
    }

    func testKeplerianPlanets2009() {
        let t = utc(2009, 1, 1, 12)
        let tol = 0.30
        assertPosition(kepler, .sun, t, 18.813, -22.97, tol)
        assertPosition(kepler, .mercury, t, 20.177, -21.60, tol)
        assertPosition(kepler, .venus, t, 22.033, -13.60, tol)
        assertPosition(kepler, .mars, t, 18.285, -24.08, tol)
        assertPosition(kepler, .jupiter, t, 20.085, -20.75, tol)
        assertPosition(kepler, .saturn, t, 11.550, 5.15, tol)
        assertPosition(kepler, .uranus, t, 23.362, -4.95, tol)
        assertPosition(kepler, .neptune, t, 21.662, -14.37, tol)
        assertPosition(kepler, .pluto, t, 18.088, -17.75, tol)
    }

    func testKeplerianPlanets2010() {
        let t = utc(2010, 12, 25, 12)
        let tol = 0.30
        assertPosition(kepler, .sun, t, 18.260, -23.38, tol)
        assertPosition(kepler, .mercury, t, 17.403, -20.17, tol)
        assertPosition(kepler, .venus, t, 15.068, -13.83, tol)
        assertPosition(kepler, .mars, t, 18.975, -23.72, tol)
        assertPosition(kepler, .jupiter, t, 23.773, -2.88, tol)
        assertPosition(kepler, .saturn, t, 13.065, -4.23, tol)
    }

    func testKeplerianMoon() {
        assertPosition(kepler, .moon, utc(2009, 1, 1, 12), 22.456, -7.164, 1.6)
        assertPosition(kepler, .moon, utc(2020, 10, 12), 9.0708, 20.0433, 1.6)
    }

    func testMeeusSunAndMoon() {
        assertPosition(meeus, .sun, utc(2009, 1, 1, 12), 18.813, -22.97, 0.05, precessToDate: true)
        assertPosition(meeus, .sun, utc(2009, 9, 20, 12), 11.857, 0.933, 0.05, precessToDate: true)
        assertPosition(meeus, .moon, utc(2009, 1, 1, 12), 22.45567, -7.16387, 0.10, precessToDate: true)
        assertPosition(meeus, .moon, utc(2009, 9, 20, 12), 13.12333, -12.60171, 0.10, precessToDate: true)
        assertPosition(meeus, .moon, utc(2010, 12, 25, 12), 9.91497, 8.05611, 0.10, precessToDate: true)
    }

    func testMeeusSunAgreesWithBaselineFrame() {
        for year in [1800, 1900, 2000, 2026, 2050] {
            let t = utc(year, 3, 21, 12)
            XCTAssertLessThan(angularSeparationDeg(meeus.geocentricPosition(.sun, t), kepler.geocentricPosition(.sun, t)), 0.5)
        }
    }

    private let london = LatLong(51.51, -0.13)
    private let newYork = LatLong(40.71, -74.01)
    private let tromso = LatLong(69.65, 18.96)

    private func assertClose(_ a: Date?, _ b: Date, minutes: Double, line: UInt = #line) {
        guard let a else { return XCTFail("nil", line: line) }
        XCTAssertLessThan(abs(a.timeIntervalSince(b)), minutes * 60, "\(a) vs \(b)", line: line)
    }

    func testSunriseSunset() {
        assertClose(nextRiseSetTime(.sun, after: utc(2026, 7, 8), location: london, indicator: .rise), utc(2026, 7, 8, 3, 53), minutes: 5)
        assertClose(nextRiseSetTime(.sun, after: utc(2026, 7, 8), location: london, indicator: .set), utc(2026, 7, 8, 20, 17), minutes: 5)
        assertClose(nextRiseSetTime(.sun, after: utc(2026, 1, 15), location: newYork, indicator: .rise), utc(2026, 1, 15, 12, 18), minutes: 5)
        assertClose(nextRiseSetTime(.sun, after: utc(2026, 1, 15), location: newYork, indicator: .set), utc(2026, 1, 15, 21, 53), minutes: 5)
        assertClose(nextRiseSetTime(.sun, after: utc(2026, 7, 8, 12), location: london, indicator: .rise), utc(2026, 7, 9, 3, 54), minutes: 5)
    }

    func testMoonriseMoonset() {
        assertClose(nextRiseSetTime(.moon, after: utc(2026, 7, 8), location: london, indicator: .rise), utc(2026, 7, 8, 23, 19), minutes: 15)
        assertClose(nextRiseSetTime(.moon, after: utc(2026, 7, 8), location: london, indicator: .set), utc(2026, 7, 8, 13, 37), minutes: 15)
    }

    func testPolarDay() {
        XCTAssertNil(nextRiseSetTime(.sun, after: utc(2026, 6, 20), location: tromso, indicator: .set))
        XCTAssertNil(nextRiseSetTime(.sun, after: utc(2026, 6, 20), location: tromso, indicator: .rise))
    }

    func testLocalFrameIsOrthonormal() {
        let f = SkyModel.localFrame(utc(2026, 3, 1, 22), london)
        XCTAssertEqual(f.up.length, 1, accuracy: 1e-9)
        XCTAssertEqual(f.trueNorth.dot(f.up), 0, accuracy: 1e-9)
        XCTAssertEqual(f.trueEast.dot(f.up), 0, accuracy: 1e-9)
        // Polaris sits near the north point at altitude ≈ latitude.
        let polaris = RaDec(37.95, 89.26).toGeocentricVector()
        let azAlt = f.azAlt(polaris)
        XCTAssertEqual(azAlt.altitudeDeg, 51.51, accuracy: 1.0)
        XCTAssertLessThan(min(azAlt.azimuthDeg, 360 - azAlt.azimuthDeg), 2.0)
    }

    func testPointingLookingNorthAtHorizon() {
        let f = SkyModel.localFrame(utc(2026, 3, 1, 22), london)
        // Phone held upright, screen facing the user, back of phone facing north:
        // phone -z = north, phone y = up, phone x = east. Rows: east, north, up in phone coords.
        let orientation = Matrix3.fromVectors(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0), columnVectors: false)
        let p = SkyModel.pointing(f, orientation)
        XCTAssertEqual(p.lineOfSight.dot(f.trueNorth), 1, accuracy: 1e-9)
        XCTAssertEqual(p.perpendicular.dot(f.up), 1, accuracy: 1e-9)
    }

    func testLunarPhaseFullMoon() {
        // Full Moon 2026-03-03 11:38 UT.
        XCTAssertEqual(lunarPhaseBucket(utc(2026, 3, 3, 12)), .full)
        let next = nextLunarPhaseEvent(.full, after: utc(2026, 2, 20))
        XCTAssertLessThan(abs(next.timeIntervalSince(utc(2026, 3, 3, 11, 38))), 12 * 3600)
    }

    func testBrightLimbFacesSun() {
        // A body due west of the Sun on the equator has its lit limb facing east (90°).
        XCTAssertEqual(brightLimbAngleDeg(body: RaDec(10, 0), sun: RaDec(20, 0)), 90, accuracy: 1e-6)
    }
}
