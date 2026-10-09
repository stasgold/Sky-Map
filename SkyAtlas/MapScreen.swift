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

enum Sheet: String, Identifiable {
    case search, layers, timeTravel, settings, gallery, about
    var id: String { rawValue }
}

/// UI accent: red in night mode so nothing on screen spoils dark adaptation.
extension AppModel {
    var accent: Color { nightMode ? Color(red: 0.85, green: 0.1, blue: 0.1) : Color(red: 1, green: 0.62, blue: 0.11) }
    var chromeText: Color { nightMode ? Color(red: 0.8, green: 0.1, blue: 0.1) : .white }
}

struct MapScreen: View {
    @StateObject private var model = AppModel()
    @State private var sheet: Sheet?

    var body: some View {
        ZStack {
            SkyViewRepresentable(model: model)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if model.timeTravel != nil { TimeTravelBanner(model: model) }
                if let target = model.searchTarget { targetBanner(target) }
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 12)
            if let error = model.catalogError {
                Text("Catalog failed to load: \(error)").padding().background(.red.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .preferredColorScheme(.dark)
        .tint(model.accent)
        .statusBarHidden(false)
        .sheet(item: $sheet) { which in
            Group {
                switch which {
                case .search: SearchSheet(model: model) { sheet = nil }
                case .layers: LayersSheet(model: model)
                case .timeTravel: TimeTravelSheet(model: model)
                case .settings: SettingsSheet(model: model)
                case .gallery: GallerySheet(model: model)
                case .about: AboutSheet(model: model)
                }
            }
            .preferredColorScheme(.dark)
            .tint(model.accent)
        }
        .sheet(item: Binding(get: { model.selectedInfo.map(InfoWrapper.init) }, set: { model.selectedInfo = $0?.info })) { w in
            ObjectInfoSheet(model: model, info: w.info)
                .preferredColorScheme(.dark)
                .tint(model.accent)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            chromeButton("magnifyingglass", "Search") { sheet = .search }
            chromeButton("square.3.layers.3d", "Layers") { sheet = .layers }
            chromeButton("clock.arrow.circlepath", "Time travel") { sheet = .timeTravel }
            Spacer()
            chromeButton(model.nightMode ? "moon.fill" : "moon", "Night mode") { model.nightMode.toggle() }
            Menu {
                Button { sheet = .gallery } label: { Label("Gallery", systemImage: "photo.on.rectangle") }
                Button { sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
                Button { sheet = .about } label: { Label("About & Credits", systemImage: "info.circle") }
            } label: {
                chromeIcon("ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack(alignment: .bottom) {
            HudView(model: model)
            Spacer()
            VStack(spacing: 10) {
                chromeButton("plus.magnifyingglass", "Zoom in") { model.zoom(by: 1.5) }
                chromeButton("minus.magnifyingglass", "Zoom out") { model.zoom(by: 1 / 1.5) }
                if model.sensorsAvailable {
                    chromeButton(model.sensorMode ? "location.north.circle.fill" : "hand.draw", model.sensorMode ? "Auto mode" : "Manual mode") {
                        model.sensorMode.toggle()
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func targetBanner(_ target: SearchHit) -> some View {
        HStack {
            Image(systemName: "scope")
            Text(model.sensorMode ? "Follow the arrow to \(target.name)" : target.name).lineLimit(1)
            Spacer()
            Button { model.searchTarget = nil } label: { Image(systemName: "xmark.circle.fill") }
                .accessibilityLabel("Clear search target")
        }
        .font(.footnote)
        .foregroundStyle(model.chromeText)
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 6)
    }

    private func chromeButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chromeIcon(icon) }.accessibilityLabel(label)
    }

    private func chromeIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(model.chromeText)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.45), in: Circle())
    }
}

private struct InfoWrapper: Identifiable {
    let info: ObjectInfo
    var id: String { info.id }
}

/// The live pointing readout.
struct HudView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let h = model.hud
        VStack(alignment: .leading, spacing: 2) {
            Text("RA \(Format.ra(h.raDeg))  Dec \(Format.dec(h.decDeg))")
            Text("Alt \(Format.signedDegrees(h.altDeg))  Az \(Int(h.azDeg.rounded()) % 360)° \(Format.compassPoint(h.azDeg))")
            Text("FOV \(Format.fov(h.fovDeg))")
            Text(model.locationName ?? Format.latLong(model.location)).lineLimit(1)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(model.chromeText.opacity(0.85))
        .padding(8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct TimeTravelBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                VStack(alignment: .leading) {
                    Text(model.now().formatted(date: .abbreviated, time: .shortened))
                    if let rate = model.timeTravel?.rate, rate != 1 {
                        Text(Format.rate(rate)).font(.caption2)
                    }
                }
                Spacer()
                Button("Now") { model.returnToRealTime() }
                    .buttonStyle(.borderedProminent)
            }
            .font(.footnote)
            .foregroundStyle(model.chromeText)
            .padding(10)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 6)
        }
    }
}

enum Format {
    static func ra(_ deg: Double) -> String {
        let hours = normalizeDegrees(deg) / 15
        let h = Int(hours), m = Int((hours - Double(h)) * 60)
        return String(format: "%02dh%02dm", h, m)
    }

    static func dec(_ deg: Double) -> String {
        let sign = deg < 0 ? "-" : "+"
        let a = abs(deg)
        return String(format: "%@%02d°%02d′", sign, Int(a), Int((a - Double(Int(a))) * 60))
    }

    static func signedDegrees(_ deg: Double) -> String { String(format: "%+.0f°", deg) }

    static func fov(_ deg: Double) -> String { deg >= 1 ? String(format: "%.1f°", deg) : String(format: "%.0f′", deg * 60) }

    static func compassPoint(_ az: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return points[Int((normalizeDegrees(az) / 22.5).rounded()) % 16]
    }

    static func latLong(_ l: LatLong) -> String {
        String(format: "%.2f°%@ %.2f°%@", abs(l.latitudeDeg), l.latitudeDeg >= 0 ? "N" : "S",
               abs(l.longitudeDeg), l.longitudeDeg >= 0 ? "E" : "W")
    }

    static func rate(_ r: Double) -> String {
        switch abs(r) {
        case 0: return "Paused"
        case 1: return r < 0 ? "Real time, backwards" : "Real time"
        default:
            let per: String
            if abs(r) >= 86_400 { per = "\(Int(abs(r) / 86_400)) day/s" } else if abs(r) >= 3600 { per = "\(Int(abs(r) / 3600)) hr/s" } else { per = "\(Int(abs(r) / 60)) min/s" }
            return (r < 0 ? "◀︎ " : "▶︎ ") + per
        }
    }
}
