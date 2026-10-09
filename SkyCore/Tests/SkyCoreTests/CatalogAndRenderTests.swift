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

final class CatalogTests: XCTestCase {
    static let store = try! CatalogStore.bundled()
    var store: CatalogStore { Self.store }

    func testBundledCounts() {
        // README of v2: 3,186 bundled stars, 135 deep-sky objects, 89 figures.
        XCTAssertEqual(store.layerObjects(.stars, .english).count, 3186)
        XCTAssertEqual(store.layerObjects(.deepSky, .english).count, 135)
        XCTAssertEqual(store.figures().count, 89)
        XCTAssertEqual(store.meteorShowers(.english).count, 10)
    }

    func testLocaleChain() {
        XCTAssertEqual(LocaleSpec("pt-BR").fallbackChain, ["pt-br", "pt", "en", ""])
        XCTAssertEqual(LocaleSpec("zh-TW").fallbackChain, ["zh-tw", "zh-hant", "zh", "en", ""])
        XCTAssertEqual(LocaleSpec("zh-Hans-CN").fallbackChain, ["zh-hans-cn", "zh-hans", "zh", "en", ""])
    }

    func testNormalizer() {
        XCTAssertEqual(NameNormalizer.normalize("  Étoile  Polaire!"), "etoile polaire")
        XCTAssertEqual(NameNormalizer.normalize("α-Cyg"), "α cyg")
    }

    func testSearchFindsDesignationsAndNames() {
        XCTAssertEqual(store.search("Sirius", .english).first?.id, "star/sirius")
        XCTAssertEqual(store.search("m31", .english).first?.id, "dso/m31")
        XCTAssertTrue(store.search("deneb", .english).contains { $0.id.hasPrefix("star/deneb") })
        let jup = store.search("jup", .english, dynamicPosition: { _ in RaDec(1, 2) })
        XCTAssertEqual(jup.first?.id, "planet/jupiter")
        XCTAssertEqual(jup.first?.position, RaDec(1, 2))
        XCTAssertFalse(store.search("andromeda gal", .english).isEmpty)
    }

    func testLocalizedNames() {
        let fr = store.search("Grande Ourse", LocaleSpec("fr"))
        XCTAssertFalse(fr.isEmpty)
        let names = store.layerObjects(.constellations, LocaleSpec("de"))
        XCTAssertTrue(names.contains { $0.name == "Großer Bär" || $0.name == "Großer Wagen" })
    }

    func testObjectInfo() throws {
        let info = try XCTUnwrap(store.objectInfo("dso/m31", .english))
        XCTAssertNotNil(info.description)
        XCTAssertEqual(info.imageRef, "deep_sky_objects/kennett_m31.webp")
        let io = try XCTUnwrap(store.objectInfo("moon/io", .english, dynamicPosition: { $0 == "planet/jupiter" ? RaDec(5, 5) : nil }))
        XCTAssertEqual(io.parent, "planet/jupiter")
        XCTAssertEqual(io.position, RaDec(5, 5))
        XCTAssertFalse(io.links.isEmpty)
        XCTAssertGreaterThan(store.infoCardObjectIds().count, 200)
        XCTAssertGreaterThan(store.galleryItems(.english).count, 200)
    }

    func testCsvQuotes() {
        XCTAssertEqual(CatalogStore.splitCsvLine("a,\"b, c\",\"d\"\"e\""), ["a", "b, c", "d\"e"])
    }
}

final class RenderTests: XCTestCase {
    func testProjectionCentreAndEdge() {
        let cam = SkyCamera(lineOfSight: .unitX, up: .unitZ, fovDeg: 90)
        let p = SkyProjection(camera: cam, width: 400, height: 800)
        let c = p.project(.unitX)!
        XCTAssertEqual(c.x, 200, accuracy: 1e-9)
        XCTAssertEqual(c.y, 400, accuracy: 1e-9)
        // 45° to the left edge along the short side; up is screen-up.
        let up = p.project(RaDec(0, 45).toGeocentricVector())!
        XCTAssertEqual(up.y, 200, accuracy: 1e-6)
        XCTAssertNil(p.project(-Vector3.unitX))
        // Looking at RA 0 with north up, east (RA 90) is on the LEFT, as on a real sky.
        let east = p.project(RaDec(30, 0).toGeocentricVector())!
        XCTAssertLessThan(east.x, 200)
        // Round trip.
        let dir = p.unproject(x: 123, y: 456)
        let back = p.project(dir)!
        XCTAssertEqual(back.x, 123, accuracy: 1e-6)
        XCTAssertEqual(back.y, 456, accuracy: 1e-6)
    }

    func testNorthEastAxes() throws {
        let p = SkyProjection(camera: SkyCamera(lineOfSight: .unitX, up: .unitZ, fovDeg: 30), width: 300, height: 300)
        let axes = try XCTUnwrap(p.northEastAxes(at: .unitX))
        XCTAssertEqual(axes.north.1, -1, accuracy: 1e-6) // north is screen-up
        XCTAssertEqual(axes.east.0, -1, accuracy: 1e-6) // east is screen-left
    }

    func testDeclutter() {
        let kept = LabelDeclutterer.declutter([
            .init(index: 0, rect: (0, 0, 10, 10), priority: 10),
            .init(index: 1, rect: (5, 5, 10, 10), priority: 90),
            .init(index: 2, rect: (50, 50, 10, 10), priority: 5),
        ])
        XCTAssertEqual(kept, [1, 2])
        XCTAssertEqual(LabelDeclutterer.magnitudeThreshold(fovDeg: 45), 4.0)
        XCTAssertEqual(LabelDeclutterer.magnitudeThreshold(fovDeg: 25), 6.0)
    }

    func testSubdivision() {
        let out = GreatCircle.subdivide([RaDec(0, 0).toGeocentricVector(), RaDec(90, 0).toGeocentricVector()], maxStepDeg: 10)
        XCTAssertEqual(out.count, 10)
        XCTAssertTrue(out.allSatisfy { abs($0.length - 1) < 1e-9 })
    }

    func testPhaseShadowPolygon() {
        let full = PhaseGeometry.shadowPolygon(illuminatedFraction: 1)
        XCTAssertTrue(full.allSatisfy { abs($0.0 + (1 - $0.1 * $0.1).squareRoot()) < 1e-9 }) // degenerate: no area
        XCTAssertGreaterThan(PhaseGeometry.litOffset(x: 0.5, y: 0, illuminatedFraction: 0.5), 0)
    }

    func testLayersBuild() {
        let store = CatalogTests.store
        let strings = LayerStrings()
        let stars = CatalogLayers.stars(store.layerObjects(.stars, .english))
        XCTAssertEqual(stars.points.count, 3186)
        XCTAssertTrue(stars.labels.contains { $0.text == "Sirius" })
        let cons = CatalogLayers.constellations(store.layerObjects(.constellations, .english), store.figures())
        XCTAssertGreaterThan(cons.lines.count, 89)
        XCTAssertEqual(GridLayer.scene(strings).lines.count, 24 + 1 + 16)
        XCTAssertEqual(EclipticLayer.scene(strings).lines.count, 37)
        let frame = SkyModel.localFrame(utc(2026, 1, 1), LatLong(40, -74))
        XCTAssertEqual(HorizonLayer.scene(frame, strings).labels.count, 4)
        XCTAssertFalse(AltAzGridLayer.scene(frame, strings).lines.isEmpty)
        let solar = SolarSystemLayer.scene(ephemeris: MeeusEphemeris(), time: utc(2026, 1, 1), observer: LatLong(40, -74), strings: strings)
        XCTAssertEqual(solar.images.count, 10)
        // Sorted far to near: the Moon draws last.
        XCTAssertEqual(solar.images.last?.image, "planet/moon")
        let perseidsPeak = MeteorShowerLayer.scene(store.meteorShowers(.english), date: MonthDay(month: 8, day: 12))
        XCTAssertTrue(perseidsPeak.labels.contains { $0.text.lowercased().contains("perseid") })
        XCTAssertEqual(CatalogLayers.iconFor("galaxy.spiral.barred"), "icon/galaxy")
        XCTAssertEqual(CatalogLayers.iconFor("unknown.thing"), "icon/other")
    }
}

final class CameraTests: XCTestCase {
    func testDragMovesViewOppositeFinger() {
        var c = CameraController(camera: SkyCamera(lineOfSight: .unitX, up: .unitZ, fovDeg: 60))
        // Drag the finger left by a third of the screen: the view swings right (toward -y... west on screen right).
        c.drag(dx: -100, dy: 0, shortSide: 300)
        let p = SkyProjection(camera: c.camera, width: 300, height: 300)
        // The point that was at the centre now sits left of centre, following the finger.
        XCTAssertLessThan(p.project(.unitX)!.x, 150)
        XCTAssertEqual(c.camera.lineOfSight.dot(c.camera.up), 0, accuracy: 1e-9)
    }

    func testZoomClamps() {
        var c = CameraController()
        c.stretch(1e9)
        XCTAssertEqual(c.camera.fovDeg, SkyCamera.minFovDeg)
        c.stretch(1e-9)
        XCTAssertEqual(c.camera.fovDeg, SkyCamera.maxFovDeg)
    }

    func testSlewReachesTarget() {
        var c = CameraController(camera: SkyCamera(lineOfSight: .unitX, up: .unitZ, fovDeg: 60))
        c.autoLevelHorizon = false
        let target = RaDec(120, 30).toGeocentricVector()
        c.aim(at: target, fovDeg: 10)
        for _ in 0..<20 { c.step(dt: 0.1) }
        XCTAssertEqual(c.camera.lineOfSight.dot(target), 1, accuracy: 1e-9)
        XCTAssertEqual(c.camera.fovDeg, 10, accuracy: 1e-9)
        XCTAssertFalse(c.isAnimating)
    }

    func testLevelingRestoresZenithUp() {
        var c = CameraController(camera: SkyCamera(lineOfSight: .unitX, up: .unitZ, fovDeg: 60))
        c.rotate(degrees: 40)
        c.gestureEnded(zenith: .unitZ)
        for _ in 0..<100 { c.step(dt: 0.05) }
        XCTAssertEqual(c.camera.up.dot(.unitZ), 1, accuracy: 1e-4)
    }

    func testIdentify() {
        let p = SkyProjection(camera: SkyCamera(lineOfSight: .unitX, up: .unitZ, fovDeg: 30), width: 300, height: 300)
        let cands = [Identify.Candidate(id: "a", position: RaDec(1, 0).toGeocentricVector()),
                     Identify.Candidate(id: "b", position: RaDec(10, 0).toGeocentricVector())]
        XCTAssertEqual(Identify.pick(tap: .unitX, candidates: cands, projection: p), "a")
        XCTAssertNil(Identify.pick(tap: RaDec(-20, 0).toGeocentricVector(), candidates: cands, projection: p))
    }
}
