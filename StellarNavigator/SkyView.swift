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
import UIKit

/// The sky surface: a display-link-driven view that draws `AppModel.frame()` and turns touches
/// into camera gestures (drag, pinch, two-finger rotate, fling, tap to identify).
final class SkyUIView: UIView, UIGestureRecognizerDelegate {
    weak var model: AppModel?
    private let renderer = SkyRenderer()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var dirty = true
    private var lastPinchScale: CGFloat = 1
    private var lastRotation: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        contentMode = .redraw
        isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(onRotate(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        for g in [pan, pinch, rotate, tap, doubleTap] as [UIGestureRecognizer] {
            g.delegate = self
            addGestureRecognizer(g)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            let link = CADisplayLink(target: self, selector: #selector(onFrame(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    func setNeedsRedraw() { dirty = true }

    @objc private func onFrame(_ link: CADisplayLink) {
        guard let model else { return }
        let dt = lastTimestamp.map { link.timestamp - $0 } ?? 0
        lastTimestamp = link.timestamp
        model.tick(dt: dt)
        if dirty || model.needsContinuousRedraw {
            dirty = false
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let model else { return }
        renderer.draw(model.frame(), in: ctx, size: bounds.size)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dirty = true
    }

    private var shortSide: Double { Double(min(bounds.width, bounds.height)) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        model?.touchDown()
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard let model else { return }
        let t = g.translation(in: self)
        model.drag(dx: Double(t.x), dy: Double(t.y), shortSide: shortSide)
        g.setTranslation(.zero, in: self)
        if g.state == .ended {
            let v = g.velocity(in: self)
            model.gestureEnded(flingVx: Double(v.x), flingVy: Double(v.y), shortSide: shortSide)
        }
        dirty = true
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .began { lastPinchScale = 1 }
        let ratio = g.scale / lastPinchScale
        lastPinchScale = g.scale
        model?.pinch(Double(ratio))
        if g.state == .ended { model?.gestureEnded(shortSide: shortSide) }
        dirty = true
    }

    @objc private func onRotate(_ g: UIRotationGestureRecognizer) {
        if g.state == .began { lastRotation = 0 }
        let delta = g.rotation - lastRotation
        lastRotation = g.rotation
        model?.rotate(Double(delta) * radiansToDegrees)
        if g.state == .ended { model?.gestureEnded(shortSide: shortSide) }
        dirty = true
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self)
        model?.identify(atX: Double(p.x), y: Double(p.y), size: bounds.size)
    }

    @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
        model?.zoom(by: 2)
        dirty = true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (g is UIPinchGestureRecognizer || g is UIRotationGestureRecognizer)
            && (other is UIPinchGestureRecognizer || other is UIRotationGestureRecognizer)
    }
}

struct SkyViewRepresentable: UIViewRepresentable {
    @ObservedObject var model: AppModel

    func makeUIView(context: Context) -> SkyUIView {
        let v = SkyUIView(frame: .zero)
        v.model = model
        return v
    }

    func updateUIView(_ view: SkyUIView, context: Context) {
        // Any published change (layers, night mode, location, …) may change the picture.
        view.setNeedsRedraw()
    }
}
