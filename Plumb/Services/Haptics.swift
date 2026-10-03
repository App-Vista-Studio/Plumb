//
//  Haptics.swift
//  Plumb
//
//  Haptic map from tokens.json. Never fire during continuous motion or per frame.
//

import UIKit

enum Haptics {
    private static var enabled: Bool { AppSettings.shared.hapticsEnabled }

    /// Light impact, once on entering tolerance.
    static func levelAchieved() { impact(.light) }
    /// Medium impact.
    static func measurementLocked() { impact(.medium) }
    /// Light impact.
    static func arEndpointPlaced() { impact(.light) }
    static func calibrationComplete() { notify(.success) }
    static func measurementSaved() { notify(.success) }
    static func selection() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

/// Fires `Haptics.levelAchieved()` once on entering tolerance and re-arms after leaving by 0.2°.
struct LevelHapticGate {
    private var armed = true

    mutating func update(magnitude: Double, tolerance: Double) {
        if armed, magnitude <= tolerance {
            armed = false
            Haptics.levelAchieved()
        } else if !armed, magnitude > tolerance + 0.2 {
            armed = true
        }
    }
}
