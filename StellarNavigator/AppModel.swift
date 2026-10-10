/*
 * Copyright (c) 2026 Penterakt LLC and contributors.
 * Swift port of Sky Map v2 (https://github.com/sky-map-team/stardroid).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Combine
import CoreLocation
import Foundation
import SkyCore
import UIKit

/// The pointing readout (RA/Dec, Alt/Az, field of view).
struct HudState: Equatable {
    var raDeg = 0.0
    var decDeg = 0.0
    var altDeg = 0.0
    var azDeg = 0.0
    var fovDeg = SkyCamera.initialFovDeg
}

/// Time travel: the simulated clock runs from `anchorSim` at `rate` × real time.
struct TimeTravel: Equatable {
    var anchorSim: Date
    var anchorReal: Date
    var rate: Double

    func now(_ real: Date = Date()) -> Date { anchorSim.addingTimeInterval(real.timeIntervalSince(anchorReal) * rate) }
}

/// App state and orchestration: the iOS stand-in for v2's MapViewModel, settings store, clock
/// bus and layer registry. The renderer pulls `frame()` from here once per display refresh.
@MainActor
final class AppModel: ObservableObject {
    // MARK: Catalog and astronomy

    let catalog: CatalogStore?
    let catalogError: String?
    let ephemeris: Ephemeris = MeeusEphemeris()
    @Published private(set) var locale: LocaleSpec

    // MARK: Settings (persisted)

    private let defaults = UserDefaults.standard

    @Published var enabledLayers: Set<LayerId> { didSet { saveLayers(); invalidateScenes() } }
    @Published var nightMode: Bool { didSet { defaults.set(nightMode, forKey: "nightMode") } }
    @Published var showSkyGradient: Bool { didSet { defaults.set(showSkyGradient, forKey: "showSkyGradient") } }
    @Published var labelScale: Double { didSet { defaults.set(labelScale, forKey: "labelScale") } }
    @Published var discSize: DiscSize { didSet { defaults.set(discSize.rawValue, forKey: "discSize"); invalidateScenes() } }
    @Published var gridDensity: GridDensity { didSet { defaults.set(gridDensity.rawValue, forKey: "gridDensity"); invalidateScenes() } }
    @Published var altAzDensity: GridDensity { didSet { defaults.set(altAzDensity.rawValue, forKey: "altAzDensity"); invalidateScenes() } }
    @Published var viewDirection: ViewDirectionMode { didSet { defaults.set(viewDirection.rawValue, forKey: "viewDirection") } }
    @Published var autoLevelHorizon: Bool {
        didSet { defaults.set(autoLevelHorizon, forKey: "autoLevel"); controller.autoLevelHorizon = autoLevelHorizon }
    }
    @Published var useDeviceLocation: Bool {
        didSet { defaults.set(useDeviceLocation, forKey: "useDeviceLocation"); applyLocationPreference() }
    }
    @Published var manualLocation: LatLong {
        didSet {
            defaults.set(manualLocation.latitudeDeg, forKey: "manualLat")
            defaults.set(manualLocation.longitudeDeg, forKey: "manualLon")
            applyLocationPreference()
        }
    }

    // MARK: Live state

    @Published private(set) var location: LatLong
    @Published private(set) var locationName: String?
    @Published private(set) var locationDenied = false
    @Published var sensorMode: Bool { didSet { applySensorMode() } }
    @Published private(set) var sensorsAvailable = true
    @Published var timeTravel: TimeTravel? { didSet { invalidateTimeDependent() } }
    @Published private(set) var hud = HudState()
    @Published var selectedInfo: ObjectInfo?
    @Published var searchTarget: SearchHit?

    private(set) var controller = CameraController()
    private let orientation = OrientationProvider()
    private let locationProvider = LocationProvider()
    private var smoothedLos: Vector3?
    private var smoothedUp: Vector3?
    private var lastHudUpdate = Date.distantPast

    static let defaultLocation = LatLong(51.48, 0.0)

    init() {
        do {
            catalog = try CatalogStore.bundled()
            catalogError = nil
        } catch {
            catalog = nil
            catalogError = String(describing: error)
        }
        locale = LocaleSpec(Locale.preferredLanguages.first ?? "en")

        let d = UserDefaults.standard
        if let saved = d.stringArray(forKey: "enabledLayers") {
            enabledLayers = Set(saved.compactMap(LayerId.init(rawValue:)))
        } else {
            enabledLayers = Set(LayerId.allCases.filter(\.enabledByDefault))
        }
        nightMode = d.bool(forKey: "nightMode")
        showSkyGradient = d.object(forKey: "showSkyGradient") as? Bool ?? true
        labelScale = d.object(forKey: "labelScale") as? Double ?? 1.0
        discSize = DiscSize(rawValue: d.string(forKey: "discSize") ?? "") ?? .glyphs
        gridDensity = GridDensity(rawValue: d.string(forKey: "gridDensity") ?? "") ?? .fine
        altAzDensity = GridDensity(rawValue: d.string(forKey: "altAzDensity") ?? "") ?? .medium
        viewDirection = ViewDirectionMode(rawValue: d.string(forKey: "viewDirection") ?? "") ?? .standard
        autoLevelHorizon = d.object(forKey: "autoLevel") as? Bool ?? true
        useDeviceLocation = d.object(forKey: "useDeviceLocation") as? Bool ?? true
        let manual = LatLong(d.object(forKey: "manualLat") as? Double ?? Self.defaultLocation.latitudeDeg,
                             d.object(forKey: "manualLon") as? Double ?? Self.defaultLocation.longitudeDeg)
        manualLocation = manual
        if let lat = d.object(forKey: "lastLat") as? Double, let lon = d.object(forKey: "lastLon") as? Double {
            location = LatLong(lat, lon)
        } else {
            location = manual
        }
        sensorMode = false
        controller.autoLevelHorizon = autoLevelHorizon

        locationProvider.onLocation = { [weak self] loc, name in
            Task { @MainActor in self?.deviceLocationUpdated(loc, name) }
        }
        locationProvider.onAuthorizationChange = { [weak self] status in
            Task { @MainActor in self?.locationDenied = status == .denied || status == .restricted }
        }
        sensorsAvailable = orientation.isAvailable
        // Open looking at the southern (northern-hemisphere) or northern sky, a little up.
        let frame = SkyModel.localFrame(Date(), location)
        let az = location.latitudeDeg >= 0 ? 180.0 : 0.0
        let los = frame.direction(azimuthDeg: az, altitudeDeg: 30)
        let up = (frame.up - los * frame.up.dot(los)).normalized()
        controller.setCamera(SkyCamera(lineOfSight: los, up: up, fovDeg: 60))
        applyLocationPreference()
        sensorMode = sensorsAvailable
        applySensorMode()
    }

    // MARK: Clock

    func now() -> Date { timeTravel?.now() ?? Date() }

    func travel(to date: Date, rate: Double = 1) {
        timeTravel = TimeTravel(anchorSim: date, anchorReal: Date(), rate: rate)
    }

    func setTimeRate(_ rate: Double) {
        let current = now()
        timeTravel = TimeTravel(anchorSim: current, anchorReal: Date(), rate: rate)
    }

    func returnToRealTime() { timeTravel = nil }

    // MARK: Location

    private func applyLocationPreference() {
        if useDeviceLocation {
            locationProvider.start()
        } else {
            locationProvider.stop()
            location = manualLocation
            locationName = nil
            invalidateTimeDependent()
        }
    }

    private func deviceLocationUpdated(_ loc: LatLong, _ name: String?) {
        guard useDeviceLocation else { return }
        location = loc
        if let name { locationName = name }
        defaults.set(loc.latitudeDeg, forKey: "lastLat")
        defaults.set(loc.longitudeDeg, forKey: "lastLon")
        invalidateTimeDependent()
    }

    // MARK: Sensors and gestures

    private func applySensorMode() {
        controller.manual = !sensorMode
        if sensorMode {
            controller.stop()
            smoothedLos = nil
            smoothedUp = nil
            orientation.start { [weak self] m in
                MainActor.assumeIsolated { self?.orientationSample(m) }
            }
        } else {
            orientation.stop()
        }
    }

    private func orientationSample(_ m: Matrix3) {
        guard sensorMode else { return }
        let frame = SkyModel.localFrame(now(), location)
        let p = SkyModel.pointing(frame, m, mode: viewDirection)
        // Light exponential smoothing on top of CoreMotion's own fusion.
        let a = 0.35
        let los = smoothedLos.map { ($0 * (1 - a) + p.lineOfSight * a).normalized() } ?? p.lineOfSight
        var up = smoothedUp.map { ($0 * (1 - a) + p.perpendicular * a) } ?? p.perpendicular
        up = (up - los * up.dot(los)).normalized()
        smoothedLos = los
        smoothedUp = up
        controller.setSensorPointing(lineOfSight: los, up: up)
    }

    func drag(dx: Double, dy: Double, shortSide: Double) { controller.drag(dx: dx, dy: dy, shortSide: shortSide) }
    func pinch(_ ratio: Double) { controller.stretch(ratio) }
    func rotate(_ degrees: Double) { controller.rotate(degrees: degrees) }
    func touchDown() { controller.stop() }

    func gestureEnded(flingVx: Double = 0, flingVy: Double = 0, shortSide: Double) {
        let zenith = SkyModel.localFrame(now(), location).up
        if abs(flingVx) + abs(flingVy) > 100 {
            controller.fling(vx: flingVx, vy: flingVy, shortSide: shortSide)
        }
        controller.gestureEnded(zenith: zenith)
    }

    func zoom(by factor: Double) { controller.stretch(factor) }

    /// Per display-refresh step.
    func tick(dt: Double) {
        controller.updateZenith(SkyModel.localFrame(now(), location).up)
        controller.step(dt: dt)
        let real = Date()
        if real.timeIntervalSince(lastHudUpdate) > 0.15 {
            lastHudUpdate = real
            updateHud()
        }
    }

    var needsContinuousRedraw: Bool { sensorMode || controller.isAnimating || timeTravel != nil }

    private func updateHud() {
        let cam = controller.camera
        let rd = RaDec.fromGeocentricVector(cam.lineOfSight)
        let azAlt = SkyModel.localFrame(now(), location).azAlt(cam.lineOfSight)
        let next = HudState(raDeg: rd.raDeg, decDeg: rd.decDeg, altDeg: azAlt.altitudeDeg, azDeg: azAlt.azimuthDeg, fovDeg: cam.fovDeg)
        if next != hud { hud = next }
    }

    // MARK: Scenes

    private var staticScenes: [LayerId: LayerScene] = [:]
    private var dynamicScenes: [LayerId: (key: String, scene: LayerScene)] = [:]
    private var solarSystemTime: Date?
    private var layerStrings = LayerStrings()

    private func invalidateScenes() {
        staticScenes.removeAll()
        dynamicScenes.removeAll()
        solarSystemTime = nil
    }

    private func invalidateTimeDependent() {
        dynamicScenes.removeAll()
        solarSystemTime = nil
    }

    /// Positions for ephemeris-driven catalog objects (`planet/…`).
    func dynamicPosition(_ id: String) -> RaDec? {
        guard let body = SolarSystemBody(objectId: id), body != .earth else { return nil }
        return ephemeris.topocentricPosition(body, now(), location)
    }

    func frame() -> FrameInput {
        let time = now()
        var scenes: [LayerScene] = []
        for layer in LayerId.allCases where enabledLayers.contains(layer) {
            if let s = scene(layer, time) { scenes.append(s) }
        }
        let sun = showSkyGradient ? ephemeris.geocentricPosition(.sun, time).toGeocentricVector() : nil
        let state = RenderState(nightMode: nightMode, magnitudeLimit: nil, labelScale: labelScale, sunDirection: sun)
        return FrameInput(scenes: scenes, camera: controller.camera, state: state,
                          searchTarget: searchTarget.flatMap { hit in
                              (dynamicPosition(hit.id) ?? hit.position)?.toGeocentricVector()
                          })
    }

    private func scene(_ layer: LayerId, _ time: Date) -> LayerScene? {
        if let s = staticScenes[layer] { return s }
        guard let catalog else { return nil }
        let built: LayerScene
        switch layer {
        case .stars:
            built = CatalogLayers.stars(catalog.layerObjects(.stars, locale))
        case .deepSky:
            built = CatalogLayers.deepSky(catalog.layerObjects(.deepSky, locale))
        case .constellations:
            built = CatalogLayers.constellations(catalog.layerObjects(.constellations, locale), catalog.figures())
        case .grid:
            built = GridLayer.scene(layerStrings, density: gridDensity)
        case .ecliptic:
            built = EclipticLayer.scene(layerStrings)
        case .horizon, .altAzGrid:
            // The local frame drifts ~0.25°/min; rebuild every 10 s of simulated time.
            let key = "\(Int(time.timeIntervalSince1970 / 10))|\(location.latitudeDeg)|\(location.longitudeDeg)"
            if let cached = dynamicScenes[layer], cached.key == key { return cached.scene }
            let frame = SkyModel.localFrame(time, location)
            let s = (layer == .horizon ? HorizonLayer.scene(frame, layerStrings)
                : AltAzGridLayer.scene(frame, layerStrings, density: altAzDensity)).subdividedForDrawing()
            dynamicScenes[layer] = (key, s)
            return s
        case .meteorShowers:
            let day = MonthDay(utc: time)
            let key = "\(day.month)-\(day.day)"
            if let cached = dynamicScenes[layer], cached.key == key { return cached.scene }
            let s = MeteorShowerLayer.scene(catalog.meteorShowers(locale), date: day)
            dynamicScenes[layer] = (key, s)
            return s
        case .solarSystem:
            if let cached = dynamicScenes[layer], !SolarSystemLayer.isDue(last: solarSystemTime, now: time, ephemeris: ephemeris) {
                return cached.scene
            }
            solarSystemTime = time
            let s = SolarSystemLayer.scene(ephemeris: ephemeris, time: time, observer: location, strings: layerStrings, discSize: discSize)
            dynamicScenes[layer] = ("", s)
            return s
        }
        let prepared = built.subdividedForDrawing()
        staticScenes[layer] = prepared
        return prepared
    }

    private func saveLayers() {
        defaults.set(enabledLayers.map(\.rawValue).sorted(), forKey: "enabledLayers")
    }

    func toggle(_ layer: LayerId) {
        if enabledLayers.contains(layer) { enabledLayers.remove(layer) } else { enabledLayers.insert(layer) }
    }

    // MARK: Search and identify

    func search(_ query: String) -> [SearchHit] {
        catalog?.search(query, locale, limit: 30, dynamicPosition: { [unowned self] in dynamicPosition($0) }) ?? []
    }

    func info(_ id: String) -> ObjectInfo? {
        catalog?.objectInfo(id, locale, dynamicPosition: { [unowned self] in dynamicPosition($0) })
    }

    /// Opens an info card. When another sheet is closing, wait for it: SwiftUI drops a sheet
    /// presented while a different one is still animating away.
    func showInfo(_ id: String, afterSheetDismissal: Bool = false) {
        guard afterSheetDismissal else {
            selectedInfo = info(id)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.selectedInfo = self.info(id)
        }
    }

    /// Navigates to a search hit: slews in manual mode; shows the guidance arrow either way.
    func go(to hit: SearchHit) {
        let position = dynamicPosition(hit.id) ?? hit.position
        guard let position else {
            showInfo(hit.id, afterSheetDismissal: true)
            return
        }
        searchTarget = hit
        if !sensorMode {
            controller.aim(at: position.toGeocentricVector(), fovDeg: hit.searchFovDeg)
        }
    }

    private lazy var identifiableIds: Set<String> = catalog?.infoCardObjectIds() ?? []

    func identify(atX x: Double, y: Double, size: CGSize) {
        guard let catalog else { return }
        let projection = SkyProjection(camera: controller.camera, width: Double(size.width), height: Double(size.height))
        let tap = projection.unproject(x: x, y: y)
        var candidates: [Identify.Candidate] = []
        let layerFor: [LayerKind: LayerId] = [.stars: .stars, .deepSky: .deepSky, .constellations: .constellations]
        for (kind, layer) in layerFor where enabledLayers.contains(layer) {
            for obj in catalog.layerObjects(kind, locale) where identifiableIds.contains(obj.id) {
                candidates.append(.init(id: obj.id, position: obj.position.toGeocentricVector()))
            }
        }
        if enabledLayers.contains(.meteorShowers) {
            let day = MonthDay(utc: now())
            for shower in catalog.meteorShowers(locale) where shower.isActive(on: day) {
                candidates.append(.init(id: shower.id, position: shower.radiant.toGeocentricVector()))
            }
        }
        if enabledLayers.contains(.solarSystem) {
            for body in SolarSystemBody.viewable {
                guard let p = dynamicPosition(body.objectId) else { continue }
                candidates.append(.init(id: body.objectId, position: p.toGeocentricVector(),
                                        radiusDeg: ephemeris.angularDiameterDeg(body, now()) / 2))
            }
        }
        if let id = Identify.pick(tap: tap, candidates: candidates, projection: projection) {
            selectedInfo = info(id)
        }
    }

    // MARK: Rise and set

    struct RiseSet {
        var rise: Date?
        var set: Date?
        var alwaysUp = false
        var neverUp = false
    }

    func riseSet(for info: ObjectInfo) -> RiseSet? {
        let time = now()
        let loc = location
        if let body = SolarSystemBody(objectId: info.id), body != .earth {
            let rise = nextRiseSetTime(body, after: time, location: loc, indicator: .rise, ephemeris: ephemeris)
            let set = nextRiseSetTime(body, after: time, location: loc, indicator: .set, ephemeris: ephemeris)
            return classify(rise, set, ephemeris.topocentricPosition(body, time, loc), time, loc, horizonAltitudeDeg(body))
        }
        guard let pos = info.position, info.layerKind != .constellations else { return nil }
        let rise = nextRiseSetTime(position: { _ in pos }, after: time, location: loc, indicator: .rise)
        let set = nextRiseSetTime(position: { _ in pos }, after: time, location: loc, indicator: .set)
        return classify(rise, set, pos, time, loc, 0)
    }

    private func classify(_ rise: Date?, _ set: Date?, _ pos: RaDec, _ time: Date, _ loc: LatLong, _ horizon: Double) -> RiseSet {
        var r = RiseSet(rise: rise, set: set)
        if rise == nil && set == nil {
            if altitudeDeg(pos, time, loc) > horizon { r.alwaysUp = true } else { r.neverUp = true }
        }
        return r
    }
}
