//
//  CompassHeadingService.swift
//  Plumb
//
//  Core Location heading for the Compass. True North needs location, so it's only
//  requested once the user picks True North. Interference is judged from both the
//  reported heading accuracy and the raw magnetic field strength.
//

import CoreLocation
import Observation
import UIKit

@Observable
final class CompassHeadingService: NSObject, CLLocationManagerDelegate {
    enum LocationAccess { case notDetermined, denied, granted }

    /// Degrees clockwise from north, 0..<360.
    private(set) var magneticHeading: Double = 42
    /// Negative when unavailable (no location fix yet).
    private(set) var trueHeading: Double = -1
    /// ± degrees; negative means invalid.
    private(set) var accuracy: Double = 5
    /// Raw geomagnetic field strength in µT; nil until the first reading.
    private(set) var fieldStrength: Double?
    private(set) var hasReading = false
    private(set) var locationAccess: LocationAccess = .notDetermined
    let isAvailable: Bool

    private let manager = CLLocationManager()
    private var wantsTrueNorth = false
    private var running = false
    private var orientationObserver: NSObjectProtocol?

    override init() {
        isAvailable = CLLocationManager.headingAvailable()
        super.init()
        manager.delegate = self
        manager.headingFilter = 1
        manager.headingOrientation = .portrait
        locationAccess = Self.access(manager.authorizationStatus)
    }

    func start(trueNorth: Bool) {
        guard isAvailable, !running else { return }
        running = true
        setTrueNorth(trueNorth)
        updateOrientation()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateOrientation() }
        }
        manager.startUpdatingHeading()
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
        if let orientationObserver { NotificationCenter.default.removeObserver(orientationObserver) }
        orientationObserver = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func setTrueNorth(_ on: Bool) {
        wantsTrueNorth = on
        guard isAvailable else { return }
        if on {
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: return
            default: break
            }
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    /// Keep headings right when the phone is turned to landscape or face down.
    private func updateOrientation() {
        let o = UIDevice.current.orientation
        guard o != .unknown, let mapped = CLDeviceOrientation(rawValue: Int32(o.rawValue)) else { return }
        manager.headingOrientation = mapped
    }

    private static func access(_ s: CLAuthorizationStatus) -> LocationAccess {
        switch s {
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        default: .granted
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let mag = newHeading.magneticHeading
        let tru = newHeading.trueHeading
        let acc = newHeading.headingAccuracy
        let field = (newHeading.x * newHeading.x + newHeading.y * newHeading.y + newHeading.z * newHeading.z).squareRoot()
        MainActor.assumeIsolated {
            guard mag.isFinite else { return }
            magneticHeading = mag
            trueHeading = tru.isFinite ? tru : -1
            accuracy = acc.isFinite ? acc : -1
            fieldStrength = field.isFinite && field > 0 ? field : nil
            hasReading = true
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Heading keeps working without a fix; True North just stays unavailable.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            locationAccess = Self.access(status)
            if wantsTrueNorth, running { setTrueNorth(true) }
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
