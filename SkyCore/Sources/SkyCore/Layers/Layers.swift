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

/// The sky-map palette (v2's `SkyColors`, upstream's true-ARGB values). Day-mode colors; the
/// backend applies the night-mode transform.
public enum SkyColors {
    public static let horizonLine = Rgba.bytes(0x59, 0x7c, 0x4a, 0x78)
    public static let horizonLabel = Rgba.bytes(0xb8, 0xde, 0x8e)
    public static let gridLine = Rgba.bytes(0xbc, 0xef, 0xf8, 0x14)
    public static let gridLabel = Rgba.bytes(0xbc, 0xef, 0xf8)
    public static let eclipticLine = Rgba.bytes(0x73, 0x53, 0x14)
    public static let eclipticLabel = Rgba.bytes(0xff, 0x9f, 0x1c)
    public static let skyLabel = Rgba.bytes(0xe0, 0x5c, 0x34)
    public static let planetBody = Rgba.bytes(0xf6, 0x7e, 0x81, 0x14)
    public static let starLabel = Rgba.bytes(0xcf, 0xcc, 0xcf)
    public static let deepSkyIcon = Rgba.bytes(0x7e, 0xc8, 0xe3)
    public static let deepSkyLabel = Rgba.bytes(0x5e, 0x96, 0xaa)
    public static let constellationLine = Rgba.bytes(0xb2, 0x7c, 0xc9, 0x80)
    public static let constellationLabel = Rgba.bytes(0xb2, 0x7c, 0xc9)
    public static let altAzGridLine = Rgba.bytes(0x8f, 0xa0, 0xb3, 0x20)
    public static let altAzGridLabel = Rgba.bytes(0x8f, 0xa0, 0xb3)
}

/// The localized label text the computed layers emit.
public struct LayerStrings: Equatable, Sendable {
    public var northPole = "NP"
    public var southPole = "SP"
    public var zenith = "Zenith"
    public var nadir = "Nadir"
    public var north = "N"
    public var south = "S"
    public var east = "E"
    public var west = "W"
    public var ecliptic = "Ecliptic"
    public var bodyNames: [SolarSystemBody: String] = [:]

    public init() {}

    public func bodyName(_ body: SolarSystemBody) -> String {
        bodyNames[body] ?? body.rawValue.capitalized
    }
}

/// Identifies a layer. Raw values double as settings keys.
public enum LayerId: String, CaseIterable, Identifiable, Sendable {
    case stars, constellations, deepSky = "deep_sky", solarSystem = "solar_system"
    case meteorShowers = "meteor_showers", grid, altAzGrid = "altaz_grid", horizon, ecliptic

    public var id: String { rawValue }

    /// v1's depth table, back to front.
    public var depth: Int {
        switch self {
        case .grid: return 0
        case .altAzGrid: return 1
        case .ecliptic: return 5
        case .constellations: return 10
        case .deepSky: return 20
        case .stars: return 30
        case .solarSystem: return 60
        case .meteorShowers: return 80
        case .horizon: return 90
        }
    }

    public var displayName: String {
        switch self {
        case .stars: return "Stars"
        case .constellations: return "Constellations"
        case .deepSky: return "Messier & Deep Sky"
        case .solarSystem: return "Sun, Moon & Planets"
        case .meteorShowers: return "Meteor Showers"
        case .grid: return "RA/Dec Grid"
        case .altAzGrid: return "Alt/Az Grid"
        case .horizon: return "Horizon"
        case .ecliptic: return "Ecliptic"
        }
    }

    public var enabledByDefault: Bool { self != .altAzGrid }
}

/// Decluttering rank: magnitude −1.5 → ~100, magnitude 10 → ~0; magnitude-less → 50.
public func labelPriority(_ magnitude: Double?) -> Int {
    guard let m = magnitude else { return 50 }
    return Int(((10.0 - m) / 11.5 * 100).rounded()).clamped(0, 100)
}

// MARK: - Catalog layers

public enum CatalogLayers {
    static let constellationLineWidthDp = 1.5
    static let dsoIconSizeDp = 20.0
    static let dsoLabelMagnitudeBonus = 2.0

    public static func stars(_ objects: [CatalogObject]) -> LayerScene {
        LayerScene(
            depth: LayerId.stars.depth,
            points: objects.map {
                PointPrimitive(pos: $0.position.toGeocentricVector(),
                               appearance: .stellar(magnitude: $0.magnitude ?? 6.0, colorIndex: $0.colorIndex))
            },
            labels: objects.compactMap { label($0, .standard, SkyColors.starLabel) }
        )
    }

    public static func deepSky(_ objects: [CatalogObject]) -> LayerScene {
        LayerScene(
            depth: LayerId.deepSky.depth,
            points: objects.map {
                PointPrimitive(pos: $0.position.toGeocentricVector(),
                               appearance: .icon(image: iconFor($0.type), sizeDp: dsoIconSizeDp, tint: SkyColors.deepSkyIcon))
            },
            labels: objects.compactMap {
                label($0, .minor, SkyColors.deepSkyLabel, magnitudeBonus: dsoLabelMagnitudeBonus, offsetDp: dsoIconSizeDp / 2 + 2)
            }
        )
    }

    public static func constellations(_ objects: [CatalogObject], _ figures: [Figure]) -> LayerScene {
        LayerScene(
            depth: LayerId.constellations.depth,
            lines: figures.flatMap { f in
                f.strokes.map {
                    LinePrimitive(vertices: $0.map { $0.toGeocentricVector() }, color: SkyColors.constellationLine,
                                  widthDp: constellationLineWidthDp)
                }
            },
            labels: objects.compactMap { label($0, .standard, SkyColors.constellationLabel) }
        )
    }

    /// Walks up the type hierarchy to the nearest type with a marker icon.
    public static func iconFor(_ type: String) -> ImageRef {
        let icons: [String: ImageRef] = [
            "galaxy": "icon/galaxy", "cluster.open": "icon/open_cluster", "cluster.globular": "icon/globular_cluster",
            "cluster": "icon/open_cluster", "nebula.planetary": "icon/planetary_nebula",
            "nebula.supernova_remnant": "icon/supernova_remnant", "nebula": "icon/diffuse_nebula",
            "asterism": "icon/asterism", "star_cloud": "icon/asterism",
        ]
        var path = type
        while !path.isEmpty {
            if let i = icons[path] { return i }
            if let dot = path.lastIndex(of: ".") { path = String(path[..<dot]) } else { path = "" }
        }
        return "icon/other"
    }

    private static func label(_ obj: CatalogObject, _ size: LabelSize, _ color: Rgba, magnitudeBonus: Double = 0,
                              offsetDp: Double = LabelStyle.defaultOffsetDp) -> LabelPrimitive? {
        guard !obj.name.isEmpty, obj.nameIsPrimary else { return nil }
        return LabelPrimitive(pos: obj.position.toGeocentricVector(), text: obj.name,
                              style: LabelStyle(size: size, color: color, offsetDp: offsetDp),
                              priority: labelPriority(obj.magnitude),
                              magnitudeForThresholding: obj.magnitude.map { $0 - magnitudeBonus })
    }
}

// MARK: - Grid

public enum GridDensity: String, CaseIterable, Identifiable, Sendable {
    case coarse, medium, fine
    public var id: String { rawValue }
}

public enum GridLayer {
    public static func scene(_ strings: LayerStrings, density: GridDensity = .fine) -> LayerScene {
        let numRa: Int, numDec: Int
        switch density {
        case .coarse: (numRa, numDec) = (8, 3)
        case .medium: (numRa, numDec) = (12, 6)
        case .fine: (numRa, numDec) = (24, 9)
        }
        let hourStride = 24 / min(numRa, 12)
        var lines: [LinePrimitive] = []
        for i in 0..<numRa {
            let ra = Double(i) * 360.0 / Double(numRa)
            lines.append(LinePrimitive(vertices: [RaDec(ra, 90), RaDec(ra, 0), RaDec(ra, -90)].map { $0.toGeocentricVector() },
                                       color: SkyColors.gridLine, widthDp: 1.5))
        }
        lines.append(decLine(0))
        for d in 1..<numDec {
            lines.append(decLine(Double(d) * 90.0 / Double(numDec)))
            lines.append(decLine(-Double(d) * 90.0 / Double(numDec)))
        }
        var labels: [LabelPrimitive] = [label(0, 90, strings.northPole), label(0, -90, strings.southPole)]
        for hour in stride(from: 0, to: 24, by: hourStride) {
            labels.append(label(Double(hour) * 15, 0, hour == 0 ? "0" : "\(hour)h"))
        }
        for d in 1..<numDec {
            let dec = d * 90 / numDec
            labels.append(label(0, Double(dec), "\(dec)°"))
            labels.append(label(0, -Double(dec), "-\(dec)°"))
        }
        return LayerScene(depth: LayerId.grid.depth, lines: lines, labels: labels)
    }

    private static func decLine(_ dec: Double) -> LinePrimitive {
        LinePrimitive(vertices: (0...36).map { RaDec(Double($0 % 36) * 10.0, dec).toGeocentricVector() },
                      color: SkyColors.gridLine, widthDp: 1.5)
    }

    private static func label(_ ra: Double, _ dec: Double, _ text: String) -> LabelPrimitive {
        LabelPrimitive(pos: RaDec(ra, dec).toGeocentricVector(), text: text,
                       style: LabelStyle(size: .minor, color: SkyColors.gridLabel), priority: 40)
    }
}

// MARK: - Alt/Az grid

public enum AltAzGridLayer {
    public static func scene(_ frame: LocalFrame, _ strings: LayerStrings, density: GridDensity = .medium) -> LayerScene {
        let azStep: Double, altStep: Double
        switch density {
        case .coarse: (azStep, altStep) = (45, 30)
        case .medium: (azStep, altStep) = (30, 15)
        case .fine: (azStep, altStep) = (15, 10)
        }
        var lines: [LinePrimitive] = []
        var labels: [LabelPrimitive] = []
        var az = 0.0
        while az < 360 {
            lines.append(LinePrimitive(
                vertices: stride(from: -90.0, through: 90.0, by: 10).map { frame.direction(azimuthDeg: az, altitudeDeg: $0) },
                color: SkyColors.altAzGridLine, widthDp: 1.5))
            if Int(az) % 90 != 0 {
                labels.append(label(frame.direction(azimuthDeg: az, altitudeDeg: 2), "\(Int(az))°"))
            }
            az += azStep
        }
        var alt = altStep
        while alt < 90 {
            for a in [alt, -alt] {
                lines.append(LinePrimitive(
                    vertices: (0...36).map { frame.direction(azimuthDeg: Double($0 % 36) * 10, altitudeDeg: a) },
                    color: SkyColors.altAzGridLine, widthDp: 1.5))
            }
            labels.append(label(frame.direction(azimuthDeg: 0, altitudeDeg: alt), "\(Int(alt))°"))
            alt += altStep
        }
        labels.append(label(frame.up, strings.zenith))
        labels.append(label(-frame.up, strings.nadir))
        return LayerScene(depth: LayerId.altAzGrid.depth, lines: lines, labels: labels)
    }

    private static func label(_ pos: Vector3, _ text: String) -> LabelPrimitive {
        LabelPrimitive(pos: pos, text: text, style: LabelStyle(size: .minor, color: SkyColors.altAzGridLabel), priority: 40)
    }
}

// MARK: - Ecliptic

public enum EclipticLayer {
    static let obliquityDeg = 23.439281

    public static func scene(_ strings: LayerStrings) -> LayerScene {
        var lines: [LinePrimitive] = []
        let ras = [0.0, 90, 180, 270, 0], decs = [0.0, obliquityDeg, 0, -obliquityDeg, 0]
        lines.append(LinePrimitive(vertices: ras.indices.map { RaDec(ras[$0], decs[$0]).toGeocentricVector() },
                                   color: SkyColors.eclipticLine, widthDp: 1.8))
        for lon in stride(from: 0, to: 360, by: 10) {
            let major = lon % 30 == 0
            lines.append(LinePrimitive(
                vertices: [geocentric(Double(lon), 0), geocentric(Double(lon), major ? 2 : 1)],
                color: SkyColors.eclipticLine, widthDp: major ? 2.0 : 1.5))
        }
        var labels = [label(geocentric(45, 3), strings.ecliptic), label(geocentric(225, 3), strings.ecliptic)]
        for lon in stride(from: 30, to: 360, by: 30) {
            labels.append(label(geocentric(Double(lon), 3), "\(lon)°"))
        }
        return LayerScene(depth: LayerId.ecliptic.depth, lines: lines, labels: labels)
    }

    /// Geocentric unit vector for ecliptic longitude/latitude (degrees).
    public static func geocentric(_ lonDeg: Double, _ latDeg: Double) -> Vector3 {
        let l = lonDeg * degreesToRadians, b = latDeg * degreesToRadians
        let xe = cos(b) * cos(l), ye = cos(b) * sin(l), ze = sin(b)
        let c = cos(obliquityDeg * degreesToRadians), s = sin(obliquityDeg * degreesToRadians)
        return Vector3(xe, ye * c - ze * s, ye * s + ze * c)
    }

    private static func label(_ pos: Vector3, _ text: String) -> LabelPrimitive {
        LabelPrimitive(pos: pos, text: text, style: LabelStyle(size: .minor, color: SkyColors.eclipticLabel), priority: 40)
    }
}

// MARK: - Horizon

public enum HorizonLayer {
    static let segments = 180
    static let rings = 8

    public static func scene(_ frame: LocalFrame, _ strings: LayerStrings) -> LayerScene {
        let north = frame.trueNorth, east = frame.trueEast, south = -north, west = -east, nadir = -frame.up
        let horizon = LinePrimitive(vertices: [north, east, south, west, north], color: SkyColors.horizonLine, widthDp: 2.5)
        func label(_ p: Vector3, _ t: String) -> LabelPrimitive {
            LabelPrimitive(pos: p, text: t, style: LabelStyle(size: .standard, color: SkyColors.horizonLabel), priority: 70)
        }
        var glowRings: [GlowRing] = []
        for r in 0...rings {
            let tilt = Double(r) * degreesToRadians
            let alpha = r == rings ? 0.0 : 0.7 * exp(-Double(r) * 0.55)
            let verts = (0...segments).map { i -> Vector3 in
                let a = 2.0 * .pi * Double(i % segments) / Double(segments)
                return north * (cos(a) * cos(tilt)) + east * (sin(a) * cos(tilt)) + nadir * sin(tilt)
            }
            glowRings.append(GlowRing(vertices: verts, color: SkyColors.horizonLine.withAlpha(alpha)))
        }
        return LayerScene(
            depth: LayerId.horizon.depth,
            lines: [horizon],
            labels: [label(north, strings.north), label(south, strings.south), label(east, strings.east), label(west, strings.west)],
            glows: [GlowPrimitive(rings: glowRings)]
        )
    }
}

// MARK: - Meteor showers

public enum MeteorShowerLayer {
    static let iconSizeDp = 32.0
    public static let peakThresholdZhr = 10.0

    public static func scene(_ showers: [MeteorShower], date: MonthDay) -> LayerScene {
        let active = showers.filter { $0.isActive(on: date) }
        return LayerScene(
            depth: LayerId.meteorShowers.depth,
            points: active.map {
                PointPrimitive(pos: $0.radiant.toGeocentricVector(),
                               appearance: .icon(image: $0.zenithalHourlyRate(on: date) > peakThresholdZhr
                                   ? "icon/meteor_radiant_peak" : "icon/meteor_radiant",
                                                 sizeDp: iconSizeDp, tint: .white))
            },
            labels: active.map {
                LabelPrimitive(pos: $0.radiant.toGeocentricVector(), text: $0.name,
                               style: LabelStyle(size: .standard, color: SkyColors.skyLabel, offsetDp: iconSizeDp / 2 + 2),
                               priority: labelPriority(nil))
            }
        )
    }
}

// MARK: - Solar system

public enum DiscSize: String, CaseIterable, Identifiable, Sendable {
    /// Fixed physical-size ladder, grows with zoom (v1).
    case glyphs
    /// True size, floored at a constant share of the screen.
    case auto
    /// True size with only a small absolute floor.
    case trueScale = "true_scale"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .glyphs: return "Glyphs"
        case .auto: return "Auto"
        case .trueScale: return "True scale"
        }
    }
}

public enum SolarSystemLayer {
    public static let calibrationFovDeg = 21.1
    static let saturnRingSpan = 2.269
    static let minBodySizeDp = 3.0
    static let labelClearance = 0.6

    public static func scene(ephemeris: Ephemeris, time: Date, observer: LatLong, strings: LayerStrings,
                             discSize: DiscSize = .glyphs) -> LayerScene {
        let bodies = SolarSystemBody.viewable
            .map { ($0, ephemeris.earthDistanceAu($0, time)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let sun = ephemeris.geocentricPosition(.sun, time)
        var images: [ImagePrimitive] = []
        var labels: [LabelPrimitive] = []
        for body in bodies {
            let pos = ephemeris.topocentricPosition(body, time, observer).toGeocentricVector()
            let drawn = drawnSizeDeg(body, time, ephemeris, discSize)
            let fraction = discSize == .auto ? glyphSizeDeg(body) / calibrationFovDeg : 0
            let terminator: Terminator? = body == .sun ? nil : Terminator(
                illuminatedFraction: ephemeris.illuminatedFraction(body, time),
                brightLimbAngleDeg: brightLimbAngleDeg(body: ephemeris.geocentricPosition(body, time), sun: sun)
            )
            images.append(ImagePrimitive(center: pos, angularSizeDeg: drawn, image: "planet/\(body.rawValue)",
                                         terminator: terminator, minScreenFraction: fraction, minSizeDp: minBodySizeDp))
            labels.append(LabelPrimitive(
                pos: pos, text: strings.bodyName(body),
                style: LabelStyle(size: .standard, color: SkyColors.skyLabel, clearanceDeg: drawn * labelClearance,
                                  clearanceMinScreenFraction: fraction * labelClearance,
                                  clearanceMinSizeDp: minBodySizeDp * labelClearance),
                priority: labelPriority(ephemeris.magnitude(body, time)),
                magnitudeForThresholding: nil
            ))
        }
        return LayerScene(depth: LayerId.solarSystem.depth, images: images, labels: labels)
    }

    static func drawnSizeDeg(_ body: SolarSystemBody, _ time: Date, _ e: Ephemeris, _ mode: DiscSize) -> Double {
        if mode == .glyphs { return glyphSizeDeg(body) }
        let disc = e.angularDiameterDeg(body, time)
        return body == .saturn ? disc * saturnRingSpan : disc
    }

    /// Physical size compressed by a 0.3 power law (Pluto = 0.6°); the Moon matches the Sun.
    static func glyphSizeDeg(_ body: SolarSystemBody) -> Double {
        if body == .moon { return glyphSizeDeg(.sun) }
        let globe = 0.6 * pow(2.0 * equatorialRadiusKm(body) / 2376.6, 0.3)
        return body == .saturn ? globe * saturnRingSpan : globe
    }

    /// Recompute threshold: true once any body could have moved ≥ 0.01°.
    public static func isDue(last: Date?, now: Date, ephemeris: Ephemeris) -> Bool {
        guard let last else { return true }
        let days = abs(now.timeIntervalSince(last)) / 86_400
        return SolarSystemBody.viewable.contains { days * ephemeris.maxAngularVelocityDegPerDay($0) >= 0.01 }
    }
}
