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
import UIKit

extension Rgba {
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
}

/// Image lookup for `ImageRef` keys and info-card photos, from the bundled `Imagery` folder.
final class ImageStore {
    static let shared = ImageStore()
    private let cache = NSCache<NSString, UIImage>()
    private let root = Bundle.main.url(forResource: "Imagery", withExtension: nil)

    /// `planet/jupiter` → `Imagery/planets/jupiter.webp`.
    func planetDisc(_ ref: ImageRef) -> UIImage? {
        guard ref.hasPrefix("planet/") else { return nil }
        return load("planets/\(ref.dropFirst("planet/".count)).webp")
    }

    /// An info-card photo, e.g. `deep_sky_objects/kennett_m31.webp`.
    func photo(_ imageRef: String) -> UIImage? { load("celestial_images/\(imageRef)") }

    private func load(_ relative: String) -> UIImage? {
        if let hit = cache.object(forKey: relative as NSString) { return hit }
        guard let url = root?.appendingPathComponent(relative), let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: relative as NSString)
        return image
    }
}

/// Everything one frame needs.
struct FrameInput {
    let scenes: [LayerScene]
    let camera: SkyCamera
    let state: RenderState
    let searchTarget: Vector3?
}

/// Draws layer scenes with CoreGraphics in a gnomonic projection, where great circles are
/// straight lines. Within a scene: glows → lines → images → points; labels from every layer are
/// decluttered together and drawn on top. Colors pass through the night-mode transform here,
/// the single place it is applied (as in v2's backend).
final class SkyRenderer {
    private var textSizes: [String: CGSize] = [:]

    func draw(_ input: FrameInput, in ctx: CGContext, size: CGSize) {
        let projection = SkyProjection(camera: input.camera, width: Double(size.width), height: Double(size.height))
        let night = input.state.nightMode
        drawBackground(ctx, size, projection, input.state)

        var labelCandidates: [(LabelPrimitive, Double)] = []
        let shortSide = Double(min(size.width, size.height))
        let cornerCos = projection.cornerCosine - 0.02
        for scene in input.scenes.sorted(by: { $0.depth < $1.depth }) {
            for glow in scene.glows { drawGlow(glow, ctx, projection, night) }
            drawLines(scene.lines, ctx, projection, night)
            for image in scene.images { drawImage(image, ctx, projection, night, shortSide) }
            drawPoints(scene.points, ctx, projection, input.state, cornerCos)
            let threshold = LabelDeclutterer.magnitudeThreshold(fovDeg: input.camera.fovDeg)
            for label in scene.labels {
                if let m = label.magnitudeForThresholding, m > threshold { continue }
                if projection.forward.dot(label.pos) < cornerCos { continue }
                labelCandidates.append((label, Double(scene.depth)))
            }
        }
        drawLabels(labelCandidates.map(\.0), ctx, projection, input.state, shortSide)
        if let target = input.searchTarget { drawSearchTarget(target, ctx, projection, size, night) }
    }

    // MARK: Background

    private func drawBackground(_ ctx: CGContext, _ size: CGSize, _ p: SkyProjection, _ state: RenderState) {
        guard let sun = state.sunDirection, !state.nightMode else {
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            return
        }
        let top = SkyGradient.color(direction: p.unproject(x: p.width / 2, y: 0), sun: sun)
        let mid = SkyGradient.color(direction: p.forward, sun: sun)
        let bottom = SkyGradient.color(direction: p.unproject(x: p.width / 2, y: p.height), sun: sun)
        let colors = [top.cgColor, mid.cgColor, bottom.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    // MARK: Glows

    private func drawGlow(_ glow: GlowPrimitive, _ ctx: CGContext, _ p: SkyProjection, _ night: Bool) {
        guard glow.rings.count >= 2 else { return }
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let n = glow.rings[0].vertices.count
        let step = 2
        for r in 0..<(glow.rings.count - 1) {
            let outer = glow.rings[r], inner = glow.rings[r + 1]
            let color = Rgba(outer.color.r, outer.color.g, outer.color.b, (outer.color.a + inner.color.a) / 2).nightMode(night)
            if color.a <= 0.001 { continue }
            let path = CGMutablePath()
            var j = 0
            while j < n - 1 {
                let k = min(j + step, n - 1)
                if let a = p.project(outer.vertices[j]), let b = p.project(outer.vertices[k]),
                   let c = p.project(inner.vertices[k]), let d = p.project(inner.vertices[j]) {
                    path.move(to: CGPoint(x: a.x, y: a.y))
                    path.addLine(to: CGPoint(x: b.x, y: b.y))
                    path.addLine(to: CGPoint(x: c.x, y: c.y))
                    path.addLine(to: CGPoint(x: d.x, y: d.y))
                    path.closeSubpath()
                }
                j = k
            }
            ctx.addPath(path)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    // MARK: Lines

    private struct StrokeKey: Hashable {
        let color: Rgba
        let width: Double
    }

    private func drawLines(_ lines: [LinePrimitive], _ ctx: CGContext, _ p: SkyProjection, _ night: Bool) {
        guard !lines.isEmpty else { return }
        var paths: [StrokeKey: CGMutablePath] = [:]
        // Lines arrive pre-subdivided (see `LayerScene.subdividedForDrawing`), so every
        // segment is short and a vertex near or behind the eye plane just lifts the pen.
        for line in lines {
            let verts = line.vertices
            let key = StrokeKey(color: line.color, width: line.widthDp)
            let path = paths[key] ?? CGMutablePath()
            var penDown = false
            for v in verts {
                guard p.forward.dot(v) > 0.05, let s = p.project(v) else {
                    penDown = false
                    continue
                }
                let pt = CGPoint(x: s.x, y: s.y)
                if penDown { path.addLine(to: pt) } else { path.move(to: pt) }
                penDown = true
            }
            paths[key] = path
        }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for (key, path) in paths {
            ctx.addPath(path)
            ctx.setStrokeColor(key.color.nightMode(night).cgColor)
            ctx.setLineWidth(key.width)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: Points

    private func drawPoints(_ points: [PointPrimitive], _ ctx: CGContext, _ p: SkyProjection, _ state: RenderState, _ cornerCos: Double) {
        for point in points {
            guard p.forward.dot(point.pos) >= cornerCos, let s = p.project(point.pos) else { continue }
            switch point.appearance {
            case let .stellar(magnitude, colorIndex):
                let style = StellarStyler.style(magnitude: magnitude, colorIndex: colorIndex, state: state)
                if style.color.a <= 0 { continue }
                ctx.setFillColor(style.color.cgColor)
                let r = style.sizeDp / 2
                ctx.fillEllipse(in: CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r))
            case let .fixed(color, sizeDp):
                ctx.setFillColor(color.nightMode(state.nightMode).cgColor)
                let r = sizeDp / 2
                ctx.fillEllipse(in: CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r))
            case let .icon(image, sizeDp, tint):
                MarkerGlyphs.draw(image, in: ctx, center: CGPoint(x: s.x, y: s.y), size: sizeDp, color: tint.nightMode(state.nightMode))
            }
        }
    }

    // MARK: Images

    private func drawImage(_ image: ImagePrimitive, _ ctx: CGContext, _ p: SkyProjection, _ night: Bool, _ shortSide: Double) {
        guard p.forward.dot(image.center) > 0.1, let c = p.project(image.center),
              let axes = p.northEastAxes(at: image.center) else { return }
        let diameterDeg = SizeFloor.drawnDiameterDeg(trueDiameterDeg: image.angularSizeDeg, minScreenFraction: image.minScreenFraction,
                                                     minSizeDp: image.minSizeDp, fovDeg: p.camera.fovDeg, shortSidePt: shortSide)
        let radius = screenRadius(center: image.center, c: c, angularRadiusDeg: diameterDeg / 2, p: p)
        guard radius > 0.3, c.x > -radius, c.y > -radius, c.x < p.width + radius, c.y < p.height + radius else { return }

        ctx.saveGState()
        // Local unit-disc frame: u to the right of the image (= sky west), v down (= sky south).
        let west = (-axes.east.0, -axes.east.1)
        let north = axes.north
        ctx.concatenate(CGAffineTransform(a: radius * west.0, b: radius * west.1,
                                          c: -radius * north.0, d: -radius * north.1, tx: c.x, ty: c.y))
        let disc = CGRect(x: -1, y: -1, width: 2, height: 2)
        ctx.addEllipse(in: disc)
        ctx.clip()
        if let ui = ImageStore.shared.planetDisc(image.image) {
            ui.draw(in: disc)
        } else {
            ctx.setFillColor(SkyColors.planetBody.withAlpha(1).cgColor)
            ctx.fill(disc)
        }
        if let t = image.terminator, t.illuminatedFraction < 0.995 {
            let chi = t.brightLimbAngleDeg * degreesToRadians
            // The lit direction in (u, v): north is (0, -1), east is (-1, 0).
            let lit = (-sin(chi), -cos(chi))
            let perp = (-lit.1, lit.0)
            let path = CGMutablePath()
            for (i, pt) in PhaseGeometry.shadowPolygon(illuminatedFraction: t.illuminatedFraction).enumerated() {
                let q = CGPoint(x: pt.0 * lit.0 + pt.1 * perp.0, y: pt.0 * lit.1 + pt.1 * perp.1)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            path.closeSubpath()
            ctx.addPath(path)
            // Dark side keeps a faint earthshine rather than going fully black.
            ctx.setFillColor(UIColor(white: 0, alpha: 0.86).cgColor)
            ctx.fillPath()
        }
        if night {
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(UIColor.red.cgColor)
            ctx.fill(disc)
        }
        ctx.restoreGState()
    }

    private func screenRadius(center: Vector3, c: ScreenPoint, angularRadiusDeg: Double, p: SkyProjection) -> Double {
        var perp = center.cross(p.upOrtho)
        if perp.length2 < 1e-12 { perp = center.cross(p.right) }
        perp = perp.normalized()
        let a = angularRadiusDeg * degreesToRadians
        guard let e = p.project(center * cos(a) + perp * sin(a)) else { return angularRadiusDeg * p.pointsPerDegree }
        return ((e.x - c.x) * (e.x - c.x) + (e.y - c.y) * (e.y - c.y)).squareRoot()
    }

    // MARK: Labels

    private func font(_ size: LabelSize, _ scale: Double) -> UIFont {
        UIFont.systemFont(ofSize: size.points * scale, weight: size == .title ? .semibold : .regular)
    }

    private func drawLabels(_ labels: [LabelPrimitive], _ ctx: CGContext, _ p: SkyProjection, _ state: RenderState, _ shortSide: Double) {
        var placed: [(LabelPrimitive, CGRect)] = []
        var candidates: [LabelDeclutterer.Candidate] = []
        for label in labels {
            guard let s = p.project(label.pos) else { continue }
            let f = font(label.style.size, state.labelScale)
            let key = "\(f.pointSize)|\(label.text)"
            let textSize: CGSize
            if let cached = textSizes[key] {
                textSize = cached
            } else {
                textSize = (label.text as NSString).size(withAttributes: [.font: f])
                textSizes[key] = textSize
            }
            var offset = label.style.offsetDp
            if label.style.clearanceDeg > 0 || label.style.clearanceMinSizeDp > 0 {
                let clearanceDeg = SizeFloor.drawnDiameterDeg(
                    trueDiameterDeg: label.style.clearanceDeg, minScreenFraction: label.style.clearanceMinScreenFraction,
                    minSizeDp: label.style.clearanceMinSizeDp, fovDeg: p.camera.fovDeg, shortSidePt: shortSide)
                offset = max(offset, clearanceDeg * p.pointsPerDegree)
            }
            let rect = CGRect(x: s.x - textSize.width / 2, y: s.y + offset, width: textSize.width, height: textSize.height)
            guard rect.maxX > 0, rect.minX < p.width, rect.maxY > 0, rect.minY < p.height else { continue }
            candidates.append(.init(index: placed.count, rect: (rect.minX, rect.minY, rect.width, rect.height), priority: label.priority))
            placed.append((label, rect))
        }
        if textSizes.count > 5000 { textSizes.removeAll() }
        for i in LabelDeclutterer.declutter(candidates) {
            let (label, rect) = placed[i]
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font(label.style.size, state.labelScale),
                .foregroundColor: label.style.color.nightMode(state.nightMode).uiColor,
            ]
            (label.text as NSString).draw(at: rect.origin, withAttributes: attrs)
        }
    }

    // MARK: Search target

    private func drawSearchTarget(_ target: Vector3, _ ctx: CGContext, _ p: SkyProjection, _ size: CGSize, _ night: Bool) {
        let color = (night ? Rgba(1, 0.2, 0.2) : Rgba.bytes(0xff, 0x9f, 0x1c)).cgColor
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(2.5)
        if let s = p.project(target), s.x > 0, s.y > 0, s.x < p.width, s.y < p.height {
            ctx.strokeEllipse(in: CGRect(x: s.x - 22, y: s.y - 22, width: 44, height: 44))
        } else {
            // Off screen: an arrow at the edge pointing the way to turn.
            var dx = p.right.dot(target), dy = -p.upOrtho.dot(target)
            let l = (dx * dx + dy * dy).squareRoot()
            if l < 1e-9 { dx = 0; dy = 1 } else { dx /= l; dy /= l }
            let cx = size.width / 2, cy = size.height / 2
            let reach = min(size.width, size.height) / 2 - 50
            let tip = CGPoint(x: cx + dx * reach, y: cy + dy * reach)
            let back = CGPoint(x: tip.x - dx * 36, y: tip.y - dy * 36)
            let path = CGMutablePath()
            path.move(to: tip)
            path.addLine(to: CGPoint(x: back.x - dy * 14, y: back.y + dx * 14))
            path.addLine(to: CGPoint(x: back.x + dy * 14, y: back.y - dx * 14))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        }
        ctx.restoreGState()
    }
}

/// Original vector marker glyphs for deep-sky types and meteor radiants. (v2's bitmap marker
/// icons are reserved brand assets, so this port draws its own.)
enum MarkerGlyphs {
    static func draw(_ ref: ImageRef, in ctx: CGContext, center c: CGPoint, size: Double, color: Rgba) {
        let r = size / 2 * 0.8
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(1.4)
        let box = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        switch ref {
        case "icon/galaxy":
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: -.pi / 6)
            ctx.strokeEllipse(in: CGRect(x: -r, y: -r * 0.45, width: 2 * r, height: r * 0.9))
        case "icon/open_cluster":
            ctx.setLineDash(phase: 0, lengths: [2, 2.5])
            ctx.strokeEllipse(in: box)
        case "icon/globular_cluster":
            ctx.strokeEllipse(in: box)
            ctx.move(to: CGPoint(x: c.x - r, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + r, y: c.y))
            ctx.move(to: CGPoint(x: c.x, y: c.y - r)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + r))
            ctx.strokePath()
        case "icon/planetary_nebula":
            ctx.strokeEllipse(in: box.insetBy(dx: r * 0.35, dy: r * 0.35))
            for k in 0..<4 {
                let a = Double(k) * .pi / 2
                ctx.move(to: CGPoint(x: c.x + cos(a) * r * 0.65, y: c.y + sin(a) * r * 0.65))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            }
            ctx.strokePath()
        case "icon/diffuse_nebula":
            ctx.stroke(box.insetBy(dx: r * 0.15, dy: r * 0.15))
        case "icon/supernova_remnant":
            for k in 0..<8 {
                let a = Double(k) * .pi / 4
                let inner = k % 2 == 0 ? 0.3 : 0.5
                ctx.move(to: CGPoint(x: c.x + cos(a) * r * inner, y: c.y + sin(a) * r * inner))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            }
            ctx.strokePath()
        case "icon/asterism":
            for k in 0..<3 {
                let a = -Double.pi / 2 + Double(k) * 2 * .pi / 3
                let d = CGPoint(x: c.x + cos(a) * r * 0.7, y: c.y + sin(a) * r * 0.7)
                ctx.fillEllipse(in: CGRect(x: d.x - 1.8, y: d.y - 1.8, width: 3.6, height: 3.6))
            }
        case "icon/meteor_radiant", "icon/meteor_radiant_peak":
            let rays = ref.hasSuffix("peak") ? 12 : 6
            ctx.setLineWidth(1.2)
            for k in 0..<rays {
                let a = Double(k) * 2 * .pi / Double(rays) + 0.2
                ctx.move(to: CGPoint(x: c.x + cos(a) * r * 0.25, y: c.y + sin(a) * r * 0.25))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            }
            ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4))
        default:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: c.x, y: c.y - r))
            path.addLine(to: CGPoint(x: c.x + r, y: c.y))
            path.addLine(to: CGPoint(x: c.x, y: c.y + r))
            path.addLine(to: CGPoint(x: c.x - r, y: c.y))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
