//
//  HomeLevelDial.swift
//  Plumb
//
//  The 236 pt Quick Measure instrument shared by Home and Live Measurement Mode,
//  plus the overlay that performs the signature zoom between them.
//

import SwiftUI

// MARK: - Dial

/// Home board dial: 36 ticks (major every 90°), 160 pt ring, crosshair, 44 pt tolerance ring, 34 pt bubble.
struct HomeLevelDial: View {
    static let size: CGFloat = 236
    /// Points per degree of tilt: the Level board's 10 pt/° scaled to this dial.
    static let pointsPerDegree: CGFloat = 10 * 236 / 280
    static let maxTravel: CGFloat = 84

    /// Bubble centre offset from the dial centre.
    var bubbleOffset: CGSize
    var showPulse = false
    var showParticles = false
    /// Gentle idle drift, used when there is no live sensor data.
    var drift = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = Self.size / 2
        ZStack {
            face
            ticksAndLines

            if showPulse && !reduceMotion {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
                    let e = 1 - pow(1 - t, 3) // ease-out
                    Circle()
                        .strokeBorder(PM.Colors.accent, lineWidth: 1)
                        .frame(width: 44, height: 44)
                        .scaleEffect(1 + 0.35 * e)
                        .opacity(0.5 * (1 - e))
                }
                .position(x: c, y: c)
            }

            Circle()
                .strokeBorder(PM.Colors.accent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 44, height: 44)
                .opacity(0.8)
                .position(x: c, y: c)

            TimelineView(.animation(paused: !drift || reduceMotion)) { tl in
                let d = driftOffset(tl.date)
                HomeBubble(diameter: 34)
                    .position(x: c + bubbleOffset.width + d.width, y: c + bubbleOffset.height + d.height)
            }

            if showParticles && !reduceMotion {
                TimelineView(.animation) { tl in
                    ZStack {
                        particle(tl.date, delay: 0, x: 60, y: 170, size: 3, color: PM.Colors.accent)
                        particle(tl.date, delay: 2.4, x: 172, y: 150, size: 2, color: PM.Colors.measuring)
                        particle(tl.date, delay: 4.1, x: 140, y: 190, size: 2, color: PM.Colors.textPrimary)
                    }
                    .frame(width: Self.size, height: Self.size)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .animation(reduceMotion ? .linear(duration: 0.2) : PM.Motion.bubbleSpring, value: bubbleOffset)
    }

    /// Bubble offset for a tilt, following the Level board: bubble moves to the high side, clamped to the dial.
    static func offset(pitch: Double, roll: Double, perfect: Bool) -> CGSize {
        if perfect { return .zero }
        var dx = CGFloat(-roll) * pointsPerDegree
        var dy = CGFloat(-pitch) * pointsPerDegree
        let len = (dx * dx + dy * dy).squareRoot()
        if len > maxTravel { dx *= maxTravel / len; dy *= maxTravel / len }
        return CGSize(width: dx, height: dy)
    }

    private var face: some View {
        Circle()
            .fill(RadialGradient(
                stops: [.init(color: PM.Colors.dialFaceTop, location: 0),
                        .init(color: PM.Colors.dialFaceBottom, location: 0.7)],
                center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 188))
            .overlay(Circle().strokeBorder(PM.Colors.dialRim, lineWidth: 1))
            // inset 0 1px 0 rgba(255,255,255,0.08)
            .overlay(
                Circle()
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.08), .clear],
                                                 startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.08)),
                                  lineWidth: 1)
                    .padding(1)
            )
            .shadow(color: .black.opacity(0.5), radius: 25, y: 20)
    }

    private var ticksAndLines: some View {
        Canvas { ctx, _ in
            for i in 0..<36 {
                let major = i % 9 == 0
                var t = ctx
                t.translateBy(x: 117, y: 118)
                t.rotate(by: .degrees(Double(i) * 10))
                t.fill(Path(CGRect(x: 0, y: -112, width: major ? 2 : 1, height: major ? 12 : 6)),
                       with: .color(major ? PM.Colors.tickMajor : PM.Colors.tickMinor))
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: 38.5, y: 38.5, width: 159, height: 159)),
                       with: .color(PM.Colors.dialLine), lineWidth: 1)
            ctx.fill(Path(CGRect(x: 117, y: 30, width: 1, height: 176)), with: .color(PM.Colors.dialLine))
            ctx.fill(Path(CGRect(x: 30, y: 117, width: 176, height: 1)), with: .color(PM.Colors.dialLine))
        }
        .frame(width: Self.size, height: Self.size)
    }

    /// pmDrift: 0 → (3, −2) → 0 over 4.8 s, ease-in-out.
    private func driftOffset(_ date: Date) -> CGSize {
        guard drift, !reduceMotion else { return .zero }
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.8) / 4.8
        let e = (1 - cos(t * 2 * .pi)) / 2
        return CGSize(width: 3 * e, height: -2 * e)
    }

    /// pmFloat: rise 40 pt over 7 s; opacity 0 → 0.7 at 30% → 0.
    private func particle(_ date: Date, delay: Double, x: CGFloat, y: CGFloat, size: CGFloat, color: Color) -> some View {
        var t = (date.timeIntervalSinceReferenceDate - delay).truncatingRemainder(dividingBy: 7) / 7
        if t < 0 { t += 1 }
        let opacity = t < 0.3 ? 0.7 * t / 0.3 : 0.7 * (1 - (t - 0.3) / 0.7)
        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(opacity)
            .position(x: x + size / 2, y: y + size / 2 - 40 * t)
    }
}

/// Mint bubble: radial highlight at 35% 30%, 22 pt glow.
struct HomeBubble: View {
    var diameter: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(
                stops: [.init(color: .white, location: 0),
                        .init(color: PM.Colors.accent, location: 0.38),
                        .init(color: PM.Colors.accentDeep, location: 1)],
                center: UnitPoint(x: 0.35, y: 0.30), startRadius: 0, endRadius: diameter * 0.956))
            .frame(width: diameter, height: diameter)
            .shadow(color: PM.Colors.accent.opacity(0.45), radius: 11)
    }
}

// MARK: - Level readout helpers

struct HomeLevelReading {
    var pitch: Double
    var roll: Double
    var perfectTolerance: Double
    var nearlyTolerance: Double

    var magnitude: Double { (pitch * pitch + roll * roll).squareRoot() }
    var status: LevelStatus { LevelStatus(magnitude: magnitude, perfect: perfectTolerance, nearly: nearlyTolerance) }
    var magnitudeText: String { String(format: "%.1f°", magnitude) }

    /// Dominant axis, as on the Level board: "1.2° RIGHT", "0.4° UP".
    var directionText: String {
        if abs(roll) >= abs(pitch) {
            return String(format: "%.1f° ", abs(roll)) + (roll > 0 ? "RIGHT" : "LEFT")
        }
        return String(format: "%.1f° ", abs(pitch)) + (pitch > 0 ? "UP" : "DOWN")
    }

    /// Rotation of the up-arrow icon for the dominant direction.
    var arrowRotation: Double {
        if abs(roll) >= abs(pitch) { return roll > 0 ? 90 : -90 }
        return pitch > 0 ? 0 : 180
    }

    var bubbleOffset: CGSize {
        HomeLevelDial.offset(pitch: pitch, roll: roll, perfect: status == .perfect)
    }
}

// MARK: - Signature zoom

/// Hands the dial's on-screen frame from Home to Live Measurement Mode and back.
@Observable
final class HomeZoomCoordinator {
    static let shared = HomeZoomCoordinator()
    /// Home dial frame in window coordinates.
    var originFrame: CGRect = .zero
    /// Set by Live Measurement Mode just before it pops, so Home plays the zoom out.
    var pendingReturn = false
}

enum HomeZoomDirection { case open, close }

/// Full-screen layer presented over Home (and the tab bar) during the zoom.
/// The backdrop fading in is the Home chrome fading out (250 ms); the dial scales for 700 ms.
struct HomeZoomOverlay: View {
    var direction: HomeZoomDirection
    var origin: CGRect
    var bubbleOffset: CGSize
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backdrop: Double = 0
    @State private var progress: CGFloat = 0
    @State private var dialOpacity: Double = 1

    var body: some View {
        GeometryReader { safe in
            let safeTop = safe.safeAreaInsets.top
            GeometryReader { geo in
            let finalCentre = LiveMeasurementView.dialCentre(width: geo.size.width, safeTop: safeTop)
            let startCentre = CGPoint(x: origin.midX, y: origin.midY)
            let startScale = max(origin.width, 1) / HomeLevelDial.size
            let p = reduceMotion ? 1 : progress
            ZStack {
                GridBackdrop()
                    .opacity(backdrop)
                HomeLevelDial(bubbleOffset: bubbleOffset)
                    .scaleEffect(startScale + (LiveMeasurementView.dialScale - startScale) * p)
                    .position(x: startCentre.x + (finalCentre.x - startCentre.x) * p,
                              y: startCentre.y + (finalCentre.y - startCentre.y) * p)
                    .opacity(dialOpacity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(true)
        .onAppear(perform: run)
    }

    private func run() {
        let duration: Double = reduceMotion ? 0.2 : 0.7
        switch direction {
        case .open:
            backdrop = 0
            progress = 0
            dialOpacity = reduceMotion ? 0 : 1
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.2)) { backdrop = 1; dialOpacity = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.25)) { backdrop = 1 }
                withAnimation(PM.Motion.spatial(0.7)) { progress = 1 }
            }
        case .close:
            backdrop = 1
            progress = 1
            dialOpacity = 1
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.2)) { backdrop = 0; dialOpacity = 0 }
            } else {
                withAnimation(PM.Motion.spatial(0.7)) { progress = 0 }
                withAnimation(.easeIn(duration: 0.25).delay(0.45)) { backdrop = 0 }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { onFinish() }
    }
}

/// Runs `body` without any implicit animation (used to swap screens under the zoom overlay).
func homeWithoutAnimation(_ body: () -> Void) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t, body)
}
