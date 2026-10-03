//
//  PMIcon.swift
//  Plumb
//
//  Custom stroke icons from icons.json plus the extra glyphs used inline on the boards.
//  24 x 24 grid, round caps and joins. Default stroke 1.7.
//

import SwiftUI

enum PMIconName: String, CaseIterable {
    // icons.json
    case level, surface, calibrate, ruler, photo, ar, room, angle, protractor, slope, compass
    case calculator, converter, history, project, home, tools, lock, settings, info, warning
    case check, back, close, plus, chevronRight

    // Inline glyphs from the boards
    case levelPlain      // level without the end ticks (Start Measuring button)
    case nearly          // circle with a dash (NEARLY LEVEL)
    case arrowRight
    case arrowUp
    case search
    case share           // tray with an up arrow
    case copy
    case trash
    case pencil
    case camera
    case document
    case documentLines
    case pulse           // MEASURING
    case rotate          // CALIBRATING / refresh
    case slashCircle     // UNAVAILABLE
    case idle            // small circle (IDLE)
    case undo
    case redo
    case swapVertical
    case phoneSides      // phone with side arrows (edge detection)
    case photoMarkers    // photo with two endpoints
    case minus
    case more            // three dots
    case lockSmall       // lock drawn on 24 grid, the 14 x 10 body variant used in pills

    var d: String {
        switch self {
        case .level: return "M6.5 8h11a4 4 0 0 1 0 8h-11a4 4 0 0 1 0-8z M10 12a2 2 0 1 0 4 0a2 2 0 1 0-4 0 M8 8v8M16 8v8"
        case .levelPlain: return "M6.5 8h11a4 4 0 0 1 0 8h-11a4 4 0 0 1 0-8z M10 12a2 2 0 1 0 4 0a2 2 0 1 0-4 0"
        case .surface: return "M3 15l8-6 10 3-8 6z M12 11V4 M10 6l2-2 2 2"
        case .calibrate: return "M4 12a8 8 0 1 0 16 0a8 8 0 1 0-16 0 M12 2v4M12 18v4M2 12h4M18 12h4 M10.5 12a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0"
        case .ruler: return "M4 7h16a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z M6 7v4M10 7v3M14 7v4M18 7v3"
        case .photo: return "M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z M7 15l10-6"
        case .ar: return "M12 3l8 4.5v9L12 21l-8-4.5v-9z M12 12l8-4.5M12 12v9M12 12L4 7.5"
        case .room: return "M4 4h16v16H4z M4 12h7v8M15 4v5"
        case .angle: return "M4 20h16 M4 20L17 6 M11 20a7 7 0 0 0-2.1-5"
        case .protractor: return "M3 17a9 9 0 0 1 18 0z M12 17l4-6 M7 17v-1M17 17v-1M12 9v1"
        case .slope: return "M3 19h18L3 9z M7 19v-2"
        case .compass: return "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0 M15.5 8.5l-2 5-5 2 2-5z"
        case .calculator: return "M7 3h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z M8 7h8M8 11h2M14 11h2M8 15h2M14 15h2M8 18h2M14 18h2"
        case .converter: return "M4 8h13l-3-3M20 16H7l3 3"
        case .history: return "M3 12a9 9 0 1 0 3-6.7 M3 4v4h4 M12 8v4l3 2"
        case .project: return "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"
        case .home: return "M4 11l8-7 8 7v9H4z"
        case .tools: return "M6 4h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M15 4h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2h-3a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M6 13h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2z M15 13h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2h-3a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2z"
        case .lock, .lockSmall: return "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z M8 11V8a4 4 0 0 1 8 0v3"
        case .settings: return "M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0 M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"
        case .info: return "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0 M12 11v6M12 7.5v.5"
        case .warning: return "M12 3l10 18H2z M12 10v5M12 18v.5"
        case .check: return "M5 12l5 5 9-10"
        case .back: return "M15 5l-7 7 7 7"
        case .close: return "M6 6l12 12M18 6L6 18"
        case .plus: return "M12 5v14M5 12h14"
        case .chevronRight: return "M9 6l6 6-6 6"
        case .nearly: return SVG.circle(12, 12, 8) + " M8 12h8"
        case .arrowRight: return "M5 12h14M13 6l6 6-6 6"
        case .arrowUp: return "M12 19V5M6 11l6-6 6 6"
        case .search: return SVG.circle(11, 11, 7) + " M20 20l-3.5-3.5"
        case .share: return "M12 3v12M7 8l5-5 5 5 M5 13v6h14v-6"
        case .copy: return SVG.rect(8, 8, 12, 12, rx: 2) + " M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"
        case .trash: return "M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"
        case .pencil: return "M4 20h4L19 9l-4-4L4 16z"
        case .camera: return "M4 8h3l2-3h6l2 3h3v11H4z " + SVG.circle(12, 13, 3.5)
        case .document: return "M6 3h9l4 4v14H6z M14 3v5h5"
        case .documentLines: return "M6 3h9l4 4v14H6z M14 3v5h5M9 13h7M9 17h5"
        case .pulse: return "M3 12h3l3-7 4 14 3-7h5"
        case .rotate: return "M20 12a8 8 0 1 1-2.3-5.7 M20 4v5h-5"
        case .slashCircle: return SVG.circle(12, 12, 9) + " M5.6 5.6l12.8 12.8"
        case .idle: return SVG.circle(12, 12, 4)
        case .undo: return "M9 14L4 9l5-5 M4 9h10a6 6 0 0 1 0 12h-3"
        case .redo: return "M15 14l5-5-5-5 M20 9H10a6 6 0 0 0 0 12h3"
        case .swapVertical: return "M8 4v16M4 8l4-4 4 4M16 20V4M12 16l4 4 4-4"
        case .phoneSides: return SVG.rect(7, 2.5, 10, 19, rx: 2.5) + " M3 9l-1 3 1 3M21 9l1 3-1 3"
        case .photoMarkers: return SVG.rect(3, 5, 18, 14, rx: 2) + " M7 15l10-6 " + SVG.circle(7, 15, 1.2) + " " + SVG.circle(17, 9, 1.2)
        case .minus: return "M3 12h18"
        case .more: return SVG.circle(5, 12, 1.6) + " " + SVG.circle(12, 12, 1.6) + " " + SVG.circle(19, 12, 1.6)
        }
    }
}

/// `PMIcon(.level)` draws a stroked icon at `size` with `stroke` in 24-grid units (like `stroke-width`).
/// Colour comes from `.foregroundStyle`, like `currentColor`.
struct PMIcon: View {
    var name: PMIconName
    var size: CGFloat = 22
    var stroke: CGFloat = 1.7

    init(_ name: PMIconName, size: CGFloat = 22, stroke: CGFloat = 1.7) {
        self.name = name
        self.size = size
        self.stroke = stroke
    }

    var body: some View {
        SVGStroke(d: name.d, size: size, lineWidth: stroke)
            .accessibilityHidden(true)
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(56)), count: 5), spacing: 16) {
        ForEach(PMIconName.allCases, id: \.self) { n in
            VStack(spacing: 4) {
                PMIcon(n)
                Text(n.rawValue).font(.system(size: 8))
            }
        }
    }
    .foregroundStyle(PM.Colors.accent)
    .padding()
    .background(PM.Colors.background)
}
