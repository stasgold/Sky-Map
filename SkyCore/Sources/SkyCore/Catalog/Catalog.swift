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

/// The renderable layer a catalog object belongs to.
public enum LayerKind: String, Sendable {
    case stars, deepSky = "deep_sky", constellations, meteorShowers = "meteor_showers"
}

/// One render-ready catalog object, with its name resolved for the requested locale.
public struct CatalogObject: Equatable, Sendable {
    public let id: String
    public let layerKind: LayerKind
    public let type: String
    /// J2000.
    public let position: RaDec
    public let magnitude: Double?
    public let colorIndex: Double?
    public let name: String
    /// Whether `name` is a primary name (map labels use primary names only).
    public let nameIsPrimary: Bool
    public let searchFovDeg: Double?
}

/// A constellation stick figure: independent J2000 polylines owned by a catalog object.
public struct Figure: Equatable, Sendable {
    public let owner: String
    public let strokes: [[RaDec]]
}

/// A year-agnostic calendar day, the unit of a meteor shower's activity window.
public struct MonthDay: Comparable, Hashable, Sendable {
    public let month: Int
    public let day: Int

    public init(month: Int, day: Int) {
        self.month = month
        self.day = day
    }

    /// Parses `"MM-DD"`.
    public init?(parsing text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else { return nil }
        self.init(month: parts[0], day: parts[1])
    }

    /// The UTC calendar day of `date`.
    public init(utc date: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.month, .day], from: date)
        self.init(month: c.month!, day: c.day!)
    }

    public static func < (a: MonthDay, b: MonthDay) -> Bool { (a.month, a.day) < (b.month, b.day) }

    /// Day of year in a leap reference year, so Feb 29 is always valid.
    var dayOfYear: Int {
        let cumulative = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]
        return cumulative[month - 1] + day
    }
}

/// One meteor shower: radiant plus annual activity window (which never crosses a year boundary).
public struct MeteorShower: Equatable, Sendable {
    public let id: String
    public let name: String
    public let radiant: RaDec
    public let activeFrom: MonthDay
    public let peak: MonthDay
    public let activeTo: MonthDay
    public let peakZhr: Int

    public func isActive(on date: MonthDay) -> Bool { date >= activeFrom && date <= activeTo }

    /// Linear interpolation of the rate: 0 at the window edges, `peakZhr` at the peak.
    public func zenithalHourlyRate(on date: MonthDay) -> Double {
        let now = date.dayOfYear, start = activeFrom.dayOfYear, p = peak.dayOfYear, end = activeTo.dayOfYear
        if now < start || now > end { return 0 }
        let toPeak: Double
        if now <= p {
            toPeak = p == start ? 1.0 : Double(now - start) / Double(p - start)
        } else {
            toPeak = end == p ? 1.0 : Double(end - now) / Double(end - p)
        }
        return Double(peakZhr) * toPeak
    }
}

/// One search result / "see also" chip.
public struct SearchHit: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let subtext: String?
    /// Resolved position: own, else parent's, else nil (card-only).
    public let position: RaDec?
    public let searchFovDeg: Double?

    public init(id: String, name: String, subtext: String?, position: RaDec?, searchFovDeg: Double?) {
        self.id = id
        self.name = name
        self.subtext = subtext
        self.position = position
        self.searchFovDeg = searchFovDeg
    }
}

/// The localized info-card content for one object.
public struct ObjectInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public let otherNames: [String]
    public let type: String
    public let typeName: String?
    public let layerKind: LayerKind?
    public let position: RaDec?
    public let parent: String?
    public let parentName: String?
    public let magnitude: Double?
    public let description: String?
    public let funFact: String?
    public let distance: String?
    public let size: String?
    public let mass: String?
    public let spectralClass: String?
    public let imageRef: String?
    public let imageCredit: String?
    public let searchSubtext: String?
    public let searchFovDeg: Double?
    public let links: [SearchHit]
}

/// One gallery thumbnail.
public struct GalleryItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let imageRef: String
}

/// A locale request with its name-resolution fallback chain: exact tag → parents → English →
/// the universal locale `""`. Chinese region tags imply their script (zh-TW → zh-hant).
public struct LocaleSpec: Hashable, Sendable {
    public let tag: String
    public let fallbackChain: [String]

    public static let english = LocaleSpec("en")

    public init(_ requestedTag: String) {
        let tag = requestedTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "-").lowercased()
        self.tag = tag
        var chain: [String] = []
        var current = tag
        while !current.isEmpty {
            chain.append(current)
            if let dash = current.lastIndex(of: "-") {
                current = String(current[..<dash])
            } else {
                current = ""
            }
        }
        chain.append("en")
        chain.append("")
        if let zhIndex = chain.firstIndex(of: "zh") {
            let subtags = tag.split(separator: "-").map(String.init)
            if !subtags.contains("hans") && !subtags.contains("hant") {
                let script = subtags.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-hant" : "zh-hans"
                chain.insert(script, at: zhIndex)
            }
        }
        var seen = Set<String>()
        fallbackChain = chain.filter { seen.insert($0).inserted }
    }

    func rank(_ locale: String) -> Int { fallbackChain.firstIndex(of: locale) ?? Int.max }
}

/// The single definition of "normalized name": diacritics stripped, every run of characters
/// other than letters, marks and digits collapsed to one space, lowercased.
public enum NameNormalizer {
    public static func normalize(_ name: String) -> String {
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in name.decomposedStringWithCanonicalMapping.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category == .nonspacingMark { continue }
            let isWordChar: Bool
            switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber:
                isWordChar = true
            default:
                isWordChar = false
            }
            if isWordChar {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return String(out).lowercased()
    }
}
