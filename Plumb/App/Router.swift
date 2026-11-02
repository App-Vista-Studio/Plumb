//
//  Router.swift
//  Plumb
//

import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Hashable {
    case home, tools, projects, history

    var title: String {
        switch self {
        case .home: "Home"
        case .tools: "Tools"
        case .projects: "Projects"
        case .history: "History"
        }
    }

    var icon: PMIconName {
        switch self {
        case .home: .home
        case .tools: .tools
        case .projects: .project
        case .history: .history
        }
    }
}

/// Every pushed screen. Tool screens hide the system navigation bar and draw `PMTopBar`.
enum Route: Hashable {
    case liveMeasure
    case level
    case calibration
    case surface
    case angle
    case protractor
    case compass
    case ruler
    case ar
    case room
    case photo
    case slope
    case calculators
    case converter
    case convert(UnitCategory)
    case shapes
    case shape(ShapeKind)
    case settings
    case paywall
    case report(projectID: UUID)
    case project(projectID: UUID)
    case unavailable(UnavailableKind)
}

/// The honest "can't measure" states from the States board.
enum UnavailableKind: String, Hashable, CaseIterable {
    case motionUnavailable
    case cameraPermission
    case arUnsupported
    case arTrackingLimited
    case compassInterference
}

@Observable
final class Router {
    var tab: AppTab = .home
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }

    /// Jump to a tab from anywhere (e.g. a tool's "Projects" link), clearing the stack.
    func select(_ tab: AppTab) {
        path.removeAll()
        self.tab = tab
    }
}

extension Route {
    @ViewBuilder var destination: some View {
        switch self {
        case .liveMeasure: LiveMeasurementView()
        case .level: LevelView()
        case .calibration: CalibrationView()
        case .surface: SurfaceLevelView()
        case .angle: AngleFinderView()
        case .protractor: ProtractorView()
        case .compass: CompassView()
        case .ruler: RulerView()
        case .ar: ARMeasureView()
        case .room: RoomMeasureView()
        case .photo: PhotoMeasureView()
        case .slope: SlopeView()
        case .calculators: CalculatorsView()
        case .converter: UnitConverterHome()
        case .convert(let category): UnitConvertView(category: category)
        case .shapes: ShapesView()
        case .shape(let kind): ShapeCalculatorView(kind: kind)
        case .settings: SettingsView()
        case .paywall: PaywallView()
        case .report(let id): ReportView(projectID: id)
        case .project(let id): ProjectDetailView(projectID: id)
        case .unavailable(let kind): UnavailableStateView(kind: kind)
        }
    }
}

// Keep the edge-swipe back gesture working while the system navigation bar is hidden.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
