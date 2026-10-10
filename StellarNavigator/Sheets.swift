/*
 * Copyright (c) 2026 Penterakt LLC and contributors.
 * Swift port of Sky Map v2 (https://github.com/sky-map-team/stardroid).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SkyCore
import SwiftUI

// MARK: - Search

struct SearchSheet: View {
    @ObservedObject var model: AppModel
    let dismiss: () -> Void
    @State private var query = ""
    @State private var results: [SearchHit] = []
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List(results) { hit in
                Button {
                    model.go(to: hit)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.name).foregroundStyle(.primary)
                        if let sub = hit.subtext { Text(sub).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .swipeActions {
                    Button("Info") { dismiss(); model.showInfo(hit.id, afterSheetDismissal: true) }
                }
            }
            .overlay {
                if !query.isEmpty && results.isEmpty {
                    Text("No matches").foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Stars, planets, M31, α Cyg…")
            .onChange(of: query) { _, q in results = model.search(q) }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: dismiss) } }
        }
    }
}

// MARK: - Layers

struct LayersSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LayerId.allCases) { layer in
                        Toggle(layer.displayName, isOn: Binding(
                            get: { model.enabledLayers.contains(layer) },
                            set: { _ in model.toggle(layer) }
                        ))
                        if model.enabledLayers.contains(layer) { options(for: layer) }
                    }
                }
                Section("Display") {
                    Toggle("Daylight sky gradient", isOn: $model.showSkyGradient)
                    Toggle("Night mode (red)", isOn: $model.nightMode)
                }
            }
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func options(for layer: LayerId) -> some View {
        switch layer {
        case .solarSystem:
            Picker("Disc size", selection: $model.discSize) {
                ForEach(DiscSize.allCases) { Text($0.displayName).tag($0) }
            }.pickerStyle(.segmented)
        case .grid:
            Picker("Grid density", selection: $model.gridDensity) {
                ForEach(GridDensity.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.segmented)
        case .altAzGrid:
            Picker("Grid density", selection: $model.altAzDensity) {
                ForEach(GridDensity.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.segmented)
        default:
            EmptyView()
        }
    }
}

// MARK: - Time travel

struct TimeTravelSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var message: String?

    private let rates: [(String, Double)] = [
        ("−1 day/s", -86_400), ("−1 hr/s", -3600), ("Pause", 0), ("Real", 1), ("1 min/s", 60), ("1 hr/s", 3600), ("1 day/s", 86_400),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Go to") {
                    DatePicker("Date & time", selection: $date, in: dateRange)
                    Button("Travel") { model.travel(to: date); dismiss() }
                }
                Section("Next event") {
                    presetButton("Sunset") { nextRiseSetTime(.sun, after: model.now(), location: model.location, indicator: .set, ephemeris: model.ephemeris) }
                    presetButton("Sunrise") { nextRiseSetTime(.sun, after: model.now(), location: model.location, indicator: .rise, ephemeris: model.ephemeris) }
                    presetButton("Moonrise") { nextRiseSetTime(.moon, after: model.now(), location: model.location, indicator: .rise, ephemeris: model.ephemeris) }
                    presetButton("Full Moon") { nextLunarPhaseEvent(.full, after: model.now(), ephemeris: model.ephemeris) }
                    presetButton("New Moon") { nextLunarPhaseEvent(.new, after: model.now(), ephemeris: model.ephemeris) }
                }
                Section("Speed") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(rates.indices, id: \.self) { i in
                                Button(rates[i].0) { model.setTimeRate(rates[i].1) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                if model.timeTravel != nil {
                    Section { Button("Return to now") { model.returnToRealTime(); dismiss() } }
                }
                if let message { Section { Text(message).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Time Travel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { date = model.now() }
        }
    }

    /// The ephemerides are valid 1800–2050 (Keplerian elements); v2 allows a wider range for
    /// coarse browsing, but this port stays inside the validated window.
    private var dateRange: ClosedRange<Date> {
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: DateComponents(year: 1800, month: 1, day: 2))!...cal.date(from: DateComponents(year: 2049, month: 12, day: 30))!
    }

    private func presetButton(_ title: String, _ compute: @escaping () -> Date?) -> some View {
        Button(title) {
            if let d = compute() {
                model.travel(to: d)
                dismiss()
            } else {
                message = "No \(title.lowercased()) in the next few days at this location."
            }
        }
    }
}

// MARK: - Object info

struct ObjectInfoSheet: View {
    @ObservedObject var model: AppModel
    let info: ObjectInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let ref = info.imageRef, let image = ImageStore.shared.photo(ref) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .colorMultiply(model.nightMode ? .red : .white)
                        if let credit = info.imageCredit {
                            Text("Image: \(credit)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    header
                    if let d = info.description { Text(d) }
                    if let f = info.funFact {
                        Label { Text(f) } icon: { Image(systemName: "sparkles") }
                            .padding(10)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    dataRows
                    if !info.links.isEmpty { links }
                    if info.position != nil || SolarSystemBody(objectId: info.id) != nil {
                        Button {
                            if let hit = findHit { model.go(to: hit) }
                            dismiss()
                        } label: {
                            Label("Show in sky", systemImage: "scope").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle(info.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var findHit: SearchHit? {
        SearchHit(id: info.id, name: info.name, subtext: info.searchSubtext, position: info.position, searchFovDeg: info.searchFovDeg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.name).font(.title2.bold())
            HStack(spacing: 6) {
                if let t = info.typeName { Text(t) }
                if let parent = info.parentName { Text("· orbits \(parent)") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if !info.otherNames.isEmpty {
                Text("Also known as " + info.otherNames.prefix(6).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dataRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Distance", info.distance)
            row("Size", info.size)
            row("Mass", info.mass)
            row("Spectral class", info.spectralClass)
            row("Magnitude", info.magnitude.map { String(format: "%.1f", $0) })
            if let p = info.position {
                row("RA / Dec", "\(Format.ra(p.raDeg))  \(Format.dec(p.decDeg))")
            }
            if let rs = model.riseSet(for: info) {
                if rs.alwaysUp {
                    row("Rise / set", "Always above the horizon")
                } else if rs.neverUp {
                    row("Rise / set", "Never rises here")
                } else {
                    row("Next rise", rs.rise.map { $0.formatted(date: .abbreviated, time: .shortened) })
                    row("Next set", rs.set.map { $0.formatted(date: .abbreviated, time: .shortened) })
                }
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .top) {
                Text(title).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Text(value)
            }
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("See also").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(info.links) { link in
                        Button(link.name) { model.selectedInfo = model.info(link.id) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var latText = ""
    @State private var lonText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    Toggle("Use device location", isOn: $model.useDeviceLocation)
                    if model.useDeviceLocation && model.locationDenied {
                        Text("Location access is off. Enable it in Settings, or enter a location below.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.useDeviceLocation {
                        TextField("Latitude (−90…90)", text: $latText).keyboardType(.numbersAndPunctuation)
                        TextField("Longitude (−180…180)", text: $lonText).keyboardType(.numbersAndPunctuation)
                        Button("Set location") {
                            if let lat = Double(latText), let lon = Double(lonText) {
                                model.manualLocation = LatLong(lat, lon)
                            }
                        }
                    }
                    LabeledContent("Current", value: model.locationName ?? Format.latLong(model.location))
                }
                Section("Pointing") {
                    Picker("Phone direction", selection: $model.viewDirection) {
                        Text("Through the screen").tag(ViewDirectionMode.standard)
                        Text("Rotated display").tag(ViewDirectionMode.rotate90)
                        Text("Along the top edge (telescope)").tag(ViewDirectionMode.telescope)
                    }
                    Toggle("Auto-level horizon (manual mode)", isOn: $model.autoLevelHorizon)
                }
                Section("Labels") {
                    VStack(alignment: .leading) {
                        Text("Label size \(Int(model.labelScale * 100))%")
                        Slider(value: $model.labelScale, in: 0.7...1.8, step: 0.1)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                latText = String(format: "%.4f", model.manualLocation.latitudeDeg)
                lonText = String(format: "%.4f", model.manualLocation.longitudeDeg)
            }
        }
    }
}

// MARK: - Gallery

struct GallerySheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [GalleryItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            dismiss()
                            model.showInfo(item.id, afterSheetDismissal: true)
                        } label: {
                            VStack(spacing: 4) {
                                Thumbnail(ref: item.imageRef, night: model.nightMode)
                                Text(item.name).font(.caption2).lineLimit(1).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { items = model.catalog?.galleryItems(model.locale) ?? [] }
        }
    }
}

private struct Thumbnail: View {
    let ref: String
    let night: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.05)
            if let image {
                Image(uiImage: image).resizable().scaledToFill().colorMultiply(night ? .red : .white)
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            let r = ref
            image = await Task.detached { ImageStore.shared.photo(r)?.preparingThumbnail(of: CGSize(width: 208, height: 208)) }.value
        }
    }
}

// MARK: - About

struct AboutSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Stellar Navigator").font(.title.bold())
                    Text("An iOS port of the open-source Sky Map v2 Android app (github.com/sky-map-team/stardroid). It is not affiliated with or endorsed by the Sky Map team or Penterakt LLC. Free software under the GNU GPL v3 or later; the source code is available on GitHub.")
                    Text("Catalog: \(model.catalog?.objectCount ?? 0) objects, entirely offline.").foregroundStyle(.secondary)
                    Text(Credits.text)
                        .font(.footnote)
                }
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

enum Credits {
    static let text = """
    ORIGINAL APP
    Sky Map was originally developed as "Google Sky Map" by Google Inc. and open-sourced; Sky Map v2 is © 2026 Penterakt LLC and contributors (engineering: John Taylor). Original engineering, design and product management at Google: Brent Bryan, Dominic Widdows, Hector Ouilhet, James Powell, John Taylor, Kevin Serafini, Lior Ron.

    DATA
    • Centre de Données astronomiques de Strasbourg (cdsweb.u-strasbg.fr)
    • The Bright Star Catalogue, 5th Revised Ed. (Hoffleit D., Warren Jr W.H.)
    • Star names: IAU Catalog of Star Names, IAU Working Group on Star Names (iau.org), CC BY 4.0
    • The HYG Database, HYG v1.0 (astronexus.com)
    • History and Accurate Positions for the NGC/IC Objects (Harold G. Corwin Jr)
    • Revised New General Catalogue of Nonstellar Astronomical Objects (Sulentic J.W., Tifft W.G.)
    • SFA Star Charts (observe.phy.sfasu.edu)
    • Solar-system positions from data provided by the USNO; Sun and Moon from Meeus, Astronomical Algorithms (ELP-2000/82 truncated)
    • Catalog text and translations: Sky Map contributors, GPLv3

    IMAGES
    • Hubble Space Telescope images: NASA, ESA, and the Space Telescope Science Institute (hubblesite.org)
    • Planet images: NASA/JPL-Caltech, NASA/Johns Hopkins APL/Carnegie (MESSENGER), NASA/Johns Hopkins APL/SwRI (New Horizons)
    • Sun: NASA/SDO (HMI)
    • Moon image: NASA/GSFC/Arizona State University (Lunar Reconnaissance Orbiter)
    • Star field images: ESO Digitized Sky Survey 2 (archive.eso.org/dss), CC BY 4.0
    • Constellation charts: IAU and Sky & Telescope (Roger Sinnott & Rick Fienberg), CC BY 4.0
    • Additional deep-sky object images: Gemini Observatory/NOIRLab/NSF/AURA (noirlab.edu)
    • M31 image: Peter Kennett (Wikimedia Commons)
    • Sagittarius A* image: EHT Collaboration (eso.org), CC BY 4.0
    • Cygnus X-1 illustration: NASA/CXC/M.Weiss (chandra.harvard.edu)
    """
}
