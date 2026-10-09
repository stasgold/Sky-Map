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

public enum CatalogError: Error, CustomStringConvertible {
    case missingFile(String)
    case malformed(String)

    public var description: String {
        switch self {
        case .missingFile(let f): return "missing catalog file: \(f)"
        case .malformed(let m): return "malformed catalog data: \(m)"
        }
    }
}

/// The bundled catalog, loaded straight from the human-readable `source-data` tree that the
/// Android build compiles into SQLite. At ~3k stars it is small enough to hold in memory, so the
/// queries the Android app runs against Room are plain Swift here.
public final class CatalogStore: @unchecked Sendable {
    /// Stars at or above this magnitude are excluded, matching what v1/v2 ship.
    public static let bundledStarMaxMagnitude = 5.6

    struct ObjectRow {
        let id: String
        var layerKind: LayerKind?
        let type: String
        var ra: Double?
        var dec: Double?
        var magnitude: Double?
        var searchFov: Double?
        var parentId: String?
        var imageRef: String?
    }

    struct NameRow {
        let locale: String
        let name: String
        let normalized: String
        let isPrimary: Bool
    }

    struct CardRow {
        let description, funFact, distance, size, mass, spectralClass, imageCredit, searchSubtext: String?
    }

    struct ShowerRow {
        let from: MonthDay, peak: MonthDay, to: MonthDay, peakZhr: Int
    }

    private let directory: URL
    private(set) var objects: [String: ObjectRow] = [:]
    private var objectOrder: [String] = []
    private var figureList: [Figure] = []
    private var showerRows: [(String, ShowerRow)] = []
    private var links: [String: [String]] = [:]
    private var names: [String: [NameRow]] = [:]
    private var typeParents: [String: String] = [:]
    private var typeNames: [String: [String: String]] = [:]
    private var cardsByLocale: [String: [String: CardRow]] = [:]
    private var availableCardLocales: Set<String> = []
    private let lock = NSLock()

    /// The catalog bundled with SkyCore.
    public static func bundled() throws -> CatalogStore {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: nil) else {
            throw CatalogError.missingFile("catalog resource directory")
        }
        return try CatalogStore(directory: url)
    }

    public init(directory: URL) throws {
        self.directory = directory
        try load()
    }

    // MARK: Loading

    private func load() throws {
        var filteredStars = Set<String>()
        for row in try readCsv("stars.csv") {
            let id = row["id"] ?? ""
            guard let mag = Double(row["magnitude"] ?? "") else { continue }
            if mag >= Self.bundledStarMaxMagnitude {
                filteredStars.insert(id)
                continue
            }
            put(ObjectRow(id: id, layerKind: .stars, type: "star", ra: Double(row["ra_deg"] ?? ""),
                          dec: Double(row["dec_deg"] ?? ""), magnitude: mag))
        }
        for row in try readCsv("dso.csv") {
            let id = row["id"] ?? ""
            let type = row["type"] ?? "other"
            put(ObjectRow(id: id, layerKind: type == "black_hole" ? nil : .deepSky, type: type,
                          ra: Double(row["ra_deg"] ?? ""), dec: Double(row["dec_deg"] ?? ""),
                          magnitude: Double(row["magnitude"] ?? "")))
        }
        let iau = try readJson("constellations/iau.json")
        for case let c as [String: Any] in iau["constellations"] as? [Any] ?? [] {
            guard let id = c["id"] as? String else { continue }
            put(ObjectRow(id: id, layerKind: .constellations, type: "constellation",
                          ra: c["ra"] as? Double, dec: c["dec"] as? Double))
            var strokes: [[RaDec]] = []
            for case let stroke as [Any] in c["strokes"] as? [Any] ?? [] {
                strokes.append(stroke.compactMap { p in
                    guard let pair = p as? [Double], pair.count == 2 else { return nil }
                    return RaDec(pair[0], pair[1])
                })
            }
            figureList.append(Figure(owner: id, strokes: strokes))
        }
        let registry = try readJson("objects.json")["objects"] as? [String: Any] ?? [:]
        for id in registry.keys.sorted() {
            guard let meta = registry[id] as? [String: Any], !filteredStars.contains(id) else { continue }
            let activity = meta["activity"] as? [String: Any]
            if let activity,
               let from = MonthDay(parsing: activity["from"] as? String ?? ""),
               let peak = MonthDay(parsing: activity["peak"] as? String ?? ""),
               let to = MonthDay(parsing: activity["to"] as? String ?? "") {
                showerRows.append((id, ShowerRow(from: from, peak: peak, to: to, peakZhr: activity["peak_zhr"] as? Int ?? 0)))
            }
            if var existing = objects[id] {
                existing.parentId = meta["parent"] as? String ?? existing.parentId
                existing.imageRef = meta["image_ref"] as? String ?? existing.imageRef
                existing.magnitude = existing.magnitude ?? (meta["magnitude"] as? Double)
                existing.searchFov = meta["search_fov"] as? Double ?? existing.searchFov
                objects[id] = existing
            } else {
                guard let type = meta["type"] as? String else {
                    throw CatalogError.malformed("objects.json entry \(id) needs a type")
                }
                put(ObjectRow(id: id, layerKind: activity != nil ? .meteorShowers : nil, type: type,
                              ra: meta["ra"] as? Double, dec: meta["dec"] as? Double,
                              magnitude: meta["magnitude"] as? Double, searchFov: meta["search_fov"] as? Double,
                              parentId: meta["parent"] as? String, imageRef: meta["image_ref"] as? String))
            }
            if let seeAlso = meta["see_also"] as? [String] { links[id] = seeAlso }
        }
        let namesDir = directory.appendingPathComponent("names")
        let nameFiles = (try? FileManager.default.contentsOfDirectory(atPath: namesDir.path)) ?? []
        for file in nameFiles.sorted() where file.hasSuffix(".csv") {
            let tag = String(file.dropLast(4)).lowercased()
            let locale = tag == "universal" ? "" : tag
            for row in try readCsv("names/\(file)") {
                let id = row["object_id"] ?? ""
                if filteredStars.contains(id) { continue }
                let name = row["name"] ?? ""
                names[id, default: []].append(
                    NameRow(locale: locale, name: name, normalized: NameNormalizer.normalize(name), isPrimary: row["is_primary"] == "1")
                )
            }
        }
        let cardDir = directory.appendingPathComponent("info_cards")
        let cardFiles = (try? FileManager.default.contentsOfDirectory(atPath: cardDir.path)) ?? []
        availableCardLocales = Set(cardFiles.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)).lowercased() })
        for case let t as [String: Any] in try readJson("types.json")["types"] as? [Any] ?? [] {
            guard let code = t["code"] as? String else { continue }
            if let parent = t["parent"] as? String { typeParents[code] = parent }
            typeNames[code] = t["names"] as? [String: String] ?? [:]
        }
    }

    private func put(_ row: ObjectRow) {
        if objects[row.id] == nil { objectOrder.append(row.id) }
        objects[row.id] = row
    }

    private func readJson(_ path: String) throws -> [String: Any] {
        let url = directory.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { throw CatalogError.missingFile(path) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogError.malformed(path)
        }
        return obj
    }

    private func readCsv(_ path: String) throws -> [[String: String]] {
        let url = directory.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            throw CatalogError.missingFile(path)
        }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return [] }
        let header = Self.splitCsvLine(headerLine)
        return try lines.dropFirst().map { line in
            let fields = Self.splitCsvLine(line)
            guard fields.count == header.count else { throw CatalogError.malformed("\(path): \(line)") }
            return Dictionary(uniqueKeysWithValues: zip(header, fields))
        }
    }

    /// Minimal RFC-4180 reader: quoted fields, doubled-quote escapes, no embedded newlines.
    static func splitCsvLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var chars = Array(line)
        if chars.last == "\r" { chars.removeLast() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes && c == "\"" && i + 1 < chars.count && chars[i + 1] == "\"" {
                current.append("\"")
                i += 1
            } else if c == "\"" {
                inQuotes.toggle()
            } else if c == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i += 1
        }
        fields.append(current)
        return fields
    }

    private func cards(for locale: String) -> [String: CardRow] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cardsByLocale[locale] { return cached }
        var result: [String: CardRow] = [:]
        if availableCardLocales.contains(locale), let json = try? readJson("info_cards/\(locale).json"),
           let cards = json["cards"] as? [String: Any] {
            for (id, value) in cards {
                guard let c = value as? [String: Any] else { continue }
                result[id] = CardRow(
                    description: c["description"] as? String, funFact: c["fun_fact"] as? String,
                    distance: c["distance"] as? String, size: c["size"] as? String, mass: c["mass"] as? String,
                    spectralClass: c["spectral_class"] as? String, imageCredit: c["image_credit"] as? String,
                    searchSubtext: c["search_subtext"] as? String
                )
            }
        }
        cardsByLocale[locale] = result
        return result
    }

    /// The best card in the chain, whole-row (fields never mix across locales).
    private func card(_ id: String, _ locale: LocaleSpec) -> CardRow? {
        for l in locale.fallbackChain where !l.isEmpty {
            if let c = cards(for: l)[id] { return c }
        }
        return nil
    }

    // MARK: Name resolution

    /// Primary-first then alphabetical, then the chain's best locale.
    private func bestNameRow(_ id: String, _ locale: LocaleSpec) -> NameRow? {
        (names[id] ?? [])
            .filter { locale.rank($0.locale) != Int.max }
            .min { a, b in
                let ra = locale.rank(a.locale), rb = locale.rank(b.locale)
                if ra != rb { return ra < rb }
                if a.isPrimary != b.isPrimary { return a.isPrimary }
                return a.name < b.name
            }
    }

    /// Display name for any object id (falls back to the id's tail).
    public func displayName(_ id: String, _ locale: LocaleSpec) -> String {
        bestNameRow(id, locale)?.name ?? String(id.split(separator: "/").last ?? "")
    }

    /// The most specific non-universal chain locale with any name rows for this object.
    private func winningLocale(_ rows: [NameRow], _ locale: LocaleSpec) -> String? {
        rows.map(\.locale).filter { !$0.isEmpty && locale.rank($0) != Int.max }.min { locale.rank($0) < locale.rank($1) }
    }

    public func typeDisplayName(_ code: String, _ locale: LocaleSpec) -> String? {
        var current: String? = code
        while let c = current {
            if let n = typeNames[c] {
                for l in locale.fallbackChain where !l.isEmpty {
                    if let v = n[l] { return v }
                }
            }
            current = typeParents[c]
        }
        return nil
    }

    // MARK: Queries

    public func layerObjects(_ kind: LayerKind, _ locale: LocaleSpec) -> [CatalogObject] {
        objectOrder.compactMap { id in
            guard let row = objects[id], row.layerKind == kind, let ra = row.ra, let dec = row.dec else { return nil }
            let nameRow = bestNameRow(id, locale)
            return CatalogObject(id: id, layerKind: kind, type: row.type, position: RaDec(ra, dec),
                                 magnitude: row.magnitude, colorIndex: nil, name: nameRow?.name ?? "",
                                 nameIsPrimary: nameRow?.isPrimary ?? false, searchFovDeg: row.searchFov)
        }
    }

    public func figures() -> [Figure] { figureList }

    public func meteorShowers(_ locale: LocaleSpec) -> [MeteorShower] {
        showerRows.compactMap { id, s in
            guard let row = objects[id], let ra = row.ra, let dec = row.dec else { return nil }
            return MeteorShower(id: id, name: displayName(id, locale), radiant: RaDec(ra, dec),
                                activeFrom: s.from, peak: s.peak, activeTo: s.to, peakZhr: s.peakZhr)
        }
    }

    /// Resolves an object's position: its own, else its parent's; `dynamicPosition` supplies
    /// ephemeris-positioned bodies (`planet/…`) whose catalog rows carry no coordinates.
    public func resolvedPosition(_ id: String, dynamicPosition: (String) -> RaDec? = { _ in nil }) -> RaDec? {
        guard let row = objects[id] else { return nil }
        if let ra = row.ra, let dec = row.dec { return RaDec(ra, dec) }
        if let p = dynamicPosition(id) { return p }
        if let parent = row.parentId {
            if let pr = objects[parent], let ra = pr.ra, let dec = pr.dec { return RaDec(ra, dec) }
            return dynamicPosition(parent)
        }
        return nil
    }

    private func resolvedFov(_ id: String) -> Double? {
        guard let row = objects[id] else { return nil }
        if row.ra != nil && row.dec != nil { return row.searchFov }
        return row.searchFov ?? row.parentId.flatMap { objects[$0]?.searchFov }
    }

    private func hit(_ id: String, name: String, _ locale: LocaleSpec, _ dyn: (String) -> RaDec?) -> SearchHit {
        SearchHit(id: id, name: name, subtext: card(id, locale)?.searchSubtext,
                  position: resolvedPosition(id, dynamicPosition: dyn), searchFovDeg: resolvedFov(id))
    }

    /// Word-prefix name search ranked whole-name-prefix first, then primary names, unlayered
    /// objects (planets, moons), brightness, and name; filtered by whole-object locale fallback.
    public func search(_ prefix: String, _ locale: LocaleSpec, limit: Int = 20,
                       dynamicPosition: (String) -> RaDec? = { _ in nil }) -> [SearchHit] {
        let normalizedPrefix = NameNormalizer.normalize(prefix)
        let terms = normalizedPrefix.split(separator: " ").map(String.init)
        guard !terms.isEmpty, limit > 0 else { return [] }

        struct Candidate {
            let id: String
            let row: NameRow
            let wholePrefix: Bool
        }
        var best: [String: Candidate] = [:]
        for (id, rows) in names {
            guard objects[id] != nil else { continue }
            let winner = winningLocale(rows, locale)
            for row in rows where row.locale.isEmpty || row.locale == winner {
                let words = row.normalized.split(separator: " ")
                // Every query term must prefix some word of the name.
                guard terms.allSatisfy({ t in words.contains { $0.hasPrefix(t) } }) else { continue }
                let c = Candidate(id: id, row: row, wholePrefix: row.normalized.hasPrefix(normalizedPrefix))
                if let existing = best[id] {
                    if Self.betterName(c.wholePrefix, c.row, than: existing.wholePrefix, existing.row, locale) {
                        best[id] = c
                    }
                } else {
                    best[id] = c
                }
            }
        }
        let ranked = best.values.sorted { a, b in
            if a.wholePrefix != b.wholePrefix { return a.wholePrefix }
            if a.row.isPrimary != b.row.isPrimary { return a.row.isPrimary }
            let au = objects[a.id]?.layerKind == nil, bu = objects[b.id]?.layerKind == nil
            if au != bu { return au }
            let am = objects[a.id]?.magnitude ?? .greatestFiniteMagnitude
            let bm = objects[b.id]?.magnitude ?? .greatestFiniteMagnitude
            if am != bm { return am < bm }
            return a.row.name < b.row.name
        }
        return ranked.prefix(limit).map { hit($0.id, name: $0.row.name, locale, dynamicPosition) }
    }

    private static func betterName(_ aWhole: Bool, _ a: NameRow, than bWhole: Bool, _ b: NameRow, _ locale: LocaleSpec) -> Bool {
        if aWhole != bWhole { return aWhole }
        if a.isPrimary != b.isPrimary { return a.isPrimary }
        let ra = locale.rank(a.locale), rb = locale.rank(b.locale)
        if ra != rb { return ra < rb }
        return a.name < b.name
    }

    /// The info card for `id`, or nil if the object is unknown.
    public func objectInfo(_ id: String, _ locale: LocaleSpec, dynamicPosition: (String) -> RaDec? = { _ in nil }) -> ObjectInfo? {
        guard let row = objects[id] else { return nil }
        let rows = names[id] ?? []
        let title = bestNameRow(id, locale)
        let winner = winningLocale(rows, locale)
        var seen = Set([title?.name ?? ""])
        let others = rows
            .filter { ($0.locale.isEmpty || $0.locale == winner) }
            .sorted { a, b in a.isPrimary != b.isPrimary ? a.isPrimary : a.name < b.name }
            .map(\.name)
            .filter { seen.insert($0).inserted }
        let c = card(id, locale)
        return ObjectInfo(
            id: id, name: title?.name ?? displayName(id, locale), otherNames: others, type: row.type,
            typeName: typeDisplayName(row.type, locale), layerKind: row.layerKind,
            position: resolvedPosition(id, dynamicPosition: dynamicPosition), parent: row.parentId,
            parentName: row.parentId.map { displayName($0, locale) }, magnitude: row.magnitude,
            description: c?.description, funFact: c?.funFact, distance: c?.distance, size: c?.size, mass: c?.mass,
            spectralClass: c?.spectralClass, imageRef: row.imageRef, imageCredit: c?.imageCredit,
            searchSubtext: c?.searchSubtext, searchFovDeg: resolvedFov(id),
            links: (links[id] ?? []).filter { objects[$0] != nil }.map {
                hit($0, name: displayName($0, locale), locale, dynamicPosition)
            }
        )
    }

    /// Every id with curated info-card content — the tap-to-identify candidate set.
    public func infoCardObjectIds() -> Set<String> {
        Set(cards(for: "en").keys).intersection(objects.keys)
    }

    /// Every object with a photo, sorted by display name.
    public func galleryItems(_ locale: LocaleSpec) -> [GalleryItem] {
        objects.values.compactMap { row in
            row.imageRef.map { GalleryItem(id: row.id, name: displayName(row.id, locale), imageRef: $0) }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public var objectCount: Int { objects.count }
}
