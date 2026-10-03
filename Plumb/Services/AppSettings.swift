//
//  AppSettings.swift
//  Plumb
//

import Foundation
import Observation

enum UnitSystem: String, CaseIterable { case metric, imperial }
enum CompassNorth: String, CaseIterable { case magnetic, trueNorth }

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var units: UnitSystem { didSet { save("units", units.rawValue) } }
    /// "Perfectly level within" (degrees).
    var perfectTolerance: Double { didSet { save("perfectTolerance", perfectTolerance) } }
    /// "Nearly level within" (degrees).
    var nearlyTolerance: Double { didSet { save("nearlyTolerance", nearlyTolerance) } }
    var compassNorth: CompassNorth { didSet { save("compassNorth", compassNorth.rawValue) } }
    var hapticsEnabled: Bool { didSet { save("haptics", hapticsEnabled) } }
    var soundEnabled: Bool { didSet { save("sound", soundEnabled) } }
    var isPro: Bool { didSet { save("isPro", isPro) } }
    /// Settings > Reduce Motion. nil follows the iOS setting; true forces reduced motion app-wide.
    var reduceMotionOverride: Bool? {
        didSet {
            if let v = reduceMotionOverride { save("reduceMotion", v) } else { UserDefaults.standard.removeObject(forKey: "reduceMotion") }
        }
    }
    /// Settings > High-contrast readouts: thicker ticks and larger numbers on instruments.
    var highContrastReadouts: Bool { didSet { save("highContrastReadouts", highContrastReadouts) } }

    private init() {
        let d = UserDefaults.standard
        units = UnitSystem(rawValue: d.string(forKey: "units") ?? "") ?? .metric
        perfectTolerance = d.object(forKey: "perfectTolerance") as? Double ?? PM.Level.perfect
        nearlyTolerance = d.object(forKey: "nearlyTolerance") as? Double ?? PM.Level.nearly
        compassNorth = CompassNorth(rawValue: d.string(forKey: "compassNorth") ?? "") ?? .magnetic
        hapticsEnabled = d.object(forKey: "haptics") as? Bool ?? true
        soundEnabled = d.object(forKey: "sound") as? Bool ?? false
        isPro = d.bool(forKey: "isPro")
        reduceMotionOverride = d.object(forKey: "reduceMotion") as? Bool
        highContrastReadouts = d.object(forKey: "highContrastReadouts") as? Bool ?? true
    }

    /// Effective reduce-motion value given the system setting.
    func reducesMotion(system: Bool) -> Bool { reduceMotionOverride ?? system }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
