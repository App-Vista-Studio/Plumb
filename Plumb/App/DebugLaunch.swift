//
//  DebugLaunch.swift
//  Plumb
//
//  Debug-only launch arguments for design review screenshots:
//    -screen <name>   open a tab or pushed route (home, tools, projects, history, level, calibration,
//                     surface, angle, protractor, compass, ruler, ar, room, photo, slope, calculators,
//                     converter, settings, paywall, report, project, live, onboarding,
//                     shapes, shape.<kind> (e.g. shape.square),
//                     convert.<category> (e.g. convert.length, convert.temperature),
//                     unavailable.<kind>)
//    -state <name>    board state for the screen to show (each screen reads DebugLaunch.state)
//    -appearance light|dark   force appearance (defaults to dark when -screen is given)
//  Release builds ignore all of these.
//

import SwiftUI

enum DebugLaunch {
    #if DEBUG
    private static func value(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let screen: String? = value("-screen")
    static let state: String? = value("-state")
    static let appearance: String? = value("-appearance")
    #else
    static let screen: String? = nil
    static let state: String? = nil
    static let appearance: String? = nil
    #endif

    static var isActive: Bool { screen != nil }

    /// `-state` equals `name`.
    static func `is`(_ name: String) -> Bool { state == name }

    static var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: isActive ? .dark : nil
        }
    }

    /// Applies `-screen` to the router. Returns true when onboarding should be shown instead.
    static func apply(to router: Router, store: MeasurementStore) -> Bool {
        guard let screen else { return false }
        let firstProject = store.projects.first?.id ?? UUID()
        switch screen {
        case "onboarding": return true
        case "home": router.tab = .home
        case "tools": router.tab = .tools
        case "projects": router.tab = .projects
        case "history": router.tab = .history
        case "live": router.path = [.liveMeasure]
        case "level": router.path = [.level]
        case "calibration": router.path = [.calibration]
        case "surface": router.path = [.surface]
        case "angle": router.path = [.angle]
        case "protractor": router.path = [.protractor]
        case "compass": router.path = [.compass]
        case "ruler": router.path = [.ruler]
        case "ar": router.path = [.ar]
        case "room": router.path = [.room]
        case "photo": router.path = [.photo]
        case "slope": router.path = [.slope]
        case "calculators": router.path = [.calculators]
        case "converter": router.path = [.converter]
        case "shapes": router.path = [.shapes]
        case "settings": router.path = [.settings]
        case "paywall": router.path = [.paywall]
        case "report": router.path = [.report(projectID: firstProject)]
        case "project": router.path = [.project(projectID: firstProject)]
        default:
            if screen.hasPrefix("convert."),
               let category = UnitCategory(rawValue: String(screen.dropFirst("convert.".count))) {
                router.path = [.converter, .convert(category)]
            } else if screen.hasPrefix("shape."),
               let kind = ShapeKind(rawValue: String(screen.dropFirst("shape.".count))) {
                router.path = [.shape(kind)]
            } else if screen.hasPrefix("unavailable."),
               let kind = UnavailableKind(rawValue: String(screen.dropFirst("unavailable.".count))) {
                router.path = [.unavailable(kind)]
            }
        }
        return false
    }
}
