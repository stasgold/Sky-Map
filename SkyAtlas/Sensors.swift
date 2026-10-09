/*
 * Copyright (c) 2026 Penterakt LLC and contributors.
 * Swift port of Sky Map v2 (https://github.com/sky-map-team/stardroid).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CoreLocation
import CoreMotion
import Foundation
import SkyCore

/// Device orientation from CoreMotion's fused attitude, converted to the Android-style
/// orientation matrix `SkyModel.pointing` expects (rows: world East, North, Up in phone
/// coordinates). iOS and Android share the phone frame: x right, y up the screen, z out of it.
final class OrientationProvider {
    private let manager = CMMotionManager()

    /// Whether `attitude.rotationMatrix` stores the reference axes as its columns (v_device =
    /// R · v_reference) or its rows. Decided at runtime by checking which candidate "up" agrees
    /// with the independently reported gravity vector, so a wrong guess can never ship silently.
    private enum Layout { case columns, rows }
    private var layout: Layout = .columns
    private var layoutConfirmed = false

    /// True when the attitude is referenced to true north (needs location services);
    /// otherwise it is magnetic north and the map should apply magnetic declination.
    private(set) var usesTrueNorth = false

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start(_ handler: @escaping (Matrix3) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame
        if frames.contains(.xTrueNorthZVertical) {
            frame = .xTrueNorthZVertical
            usesTrueNorth = true
        } else if frames.contains(.xMagneticNorthZVertical) {
            frame = .xMagneticNorthZVertical
            usesTrueNorth = false
        } else {
            frame = .xArbitraryCorrectedZVertical
            usesTrueNorth = false
        }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.showsDeviceMovementDisplay = true
        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            if let m = self.orientation(from: motion) { handler(m) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func orientation(from motion: CMDeviceMotion) -> Matrix3? {
        let r = motion.attitude.rotationMatrix
        let cols = (x: Vector3(r.m11, r.m21, r.m31), y: Vector3(r.m12, r.m22, r.m32), z: Vector3(r.m13, r.m23, r.m33))
        let rows = (x: Vector3(r.m11, r.m12, r.m13), y: Vector3(r.m21, r.m22, r.m23), z: Vector3(r.m31, r.m32, r.m33))
        let g = motion.gravity
        let upFromGravity = Vector3(-g.x, -g.y, -g.z).normalized()
        if !layoutConfirmed && upFromGravity != .zero {
            let colScore = upFromGravity.dot(cols.z)
            let rowScore = upFromGravity.dot(rows.z)
            if abs(colScore - rowScore) > 0.3 {
                layout = colScore > rowScore ? .columns : .rows
                layoutConfirmed = true
            }
        }
        // Reference frame: X = north, Y = west, Z = up.
        let axes = layout == .columns ? cols : rows
        let north = axes.x, west = axes.y, up = axes.z
        return Matrix3.fromVectors(-west, north, up, columnVectors: false)
    }
}

/// Device location via CoreLocation, coarse accuracy (the sky barely changes over kilometres).
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((LatLong, String?) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 2000
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(manager.authorizationStatus)
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let latLong = LatLong(loc.coordinate.latitude, loc.coordinate.longitude)
        onLocation?(latLong, nil)
        CLGeocoder().reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            let p = placemarks?.first
            let name = [p?.locality, p?.country].compactMap { $0 }.joined(separator: ", ")
            if !name.isEmpty { self?.onLocation?(latLong, name) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
