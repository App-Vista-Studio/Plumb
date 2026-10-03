//
//  MotionService.swift
//  Plumb
//
//  Core Motion wrapper. Views read small slices of this; they never touch raw sensor maths.
//  Filtering per tokens.json: low-pass on processed gravity (not raw accelerometer), 60 Hz,
//  factor 0.15, adaptive so real movement is never hidden, and a 0.05° settling threshold on
//  the published pitch and roll so the last digit doesn't flicker while the phone is still.
//
//  Sensors pause while the app is in the background and resume (re-seeded) on return.
//  In Debug builds without device motion (Simulator) it publishes the design's preview values so
//  every screen still renders as drawn on the boards. Release builds never show fake values:
//  pitch and roll stay at zero and `isAvailable` is false, so screens show the unavailable state.
//

import CoreMotion
import Foundation
import Observation
import UIKit

@Observable
final class MotionService {
    static let shared = MotionService()

    /// Calibrated tilt in degrees. Positive roll = right edge low ("RIGHT"); positive pitch = top edge high ("UP").
    private(set) var pitch: Double
    private(set) var roll: Double
    /// Smoothed gravity in device coordinates (unit g).
    private(set) var gravity: SIMD3<Double> = SIMD3(0, 0, -1)
    /// Degrees from horizontal of the device's long edge when standing on it (Angle Finder, Slope).
    private(set) var edgeAngle: Double = 37.2
    /// 0...1 stability estimate from recent motion.
    private(set) var stability: Double = 0.98
    private(set) var isAvailable: Bool
    private(set) var isRunning = false

    /// Uncalibrated tilt in degrees (what the sensors read before the user's zero is applied).
    private(set) var rawPitch: Double = 0
    private(set) var rawRoll: Double = 0
    /// Heading change in degrees around the vertical axis from an arbitrary start (gyro, no compass).
    /// Used to detect the 180° turn in two-position calibration.
    private(set) var yaw: Double = 0
    /// True while updates are paused because the app is in the background.
    private(set) var isSuspended = false
    /// Number of samples received since the last start or resume. 0 means no live data yet.
    private(set) var sampleCount = 0

    /// Debug-only: no sensor, so the screens show the boards' preview values.
    var isPreview: Bool {
        #if DEBUG
        return !isAvailable
        #else
        return false
        #endif
    }

    /// Phone lying roughly flat (screen up or down), where a bubble level is meaningful.
    var isFlat: Bool { abs(gravity.z) >= 0.7 }

    var zeroPitch: Double {
        didSet { UserDefaults.standard.set(zeroPitch, forKey: "calib.zeroPitch") }
    }
    var zeroRoll: Double {
        didSet { UserDefaults.standard.set(zeroRoll, forKey: "calib.zeroRoll") }
    }
    var calibratedAt: Date? {
        didSet { UserDefaults.standard.set(calibratedAt, forKey: "calib.date") }
    }

    var smoothing: Double = 0.15
    var updateInterval: TimeInterval = 1.0 / 60.0
    /// Published pitch and roll only move once the filtered value has changed by this much (degrees).
    var settlingThreshold: Double = 0.05

    /// Tilt magnitude, the big readout on the level.
    var magnitude: Double { (pitch * pitch + roll * roll).squareRoot() }

    private let manager = CMMotionManager()
    private var users = 0
    private var needsSeed = true
    private var lastRawGravity: SIMD3<Double>?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let available = manager.isDeviceMotionAvailable
        isAvailable = available
        let d = UserDefaults.standard
        let zp = d.double(forKey: "calib.zeroPitch")
        let zr = d.double(forKey: "calib.zeroRoll")
        // Never apply a corrupt or implausible stored zero.
        zeroPitch = zp.isFinite && abs(zp) <= Self.maxZero ? zp : 0
        zeroRoll = zr.isFinite && abs(zr) <= Self.maxZero ? zr : 0
        calibratedAt = d.object(forKey: "calib.date") as? Date
        #if DEBUG
        let preview = !available
        #else
        let preview = false
        #endif
        pitch = preview ? -0.4 : 0
        roll = preview ? 1.2 : 0
        if !preview { edgeAngle = 0; stability = 0 }

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.suspend()
        })
        observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        })
    }

    /// Largest zero offset accepted (degrees). Real sensor bias is well under this.
    static let maxZero: Double = 5

    /// Reference counted: every screen that shows live values calls start on appear and stop on disappear.
    func start() {
        users += 1
        guard users == 1 else { return }
        startUpdates()
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        stopUpdates()
    }

    /// Sets the current attitude as zero (single position). Prefer `applyCalibration` with a two-position average.
    func calibrate() {
        applyCalibration(zeroPitch: rawPitch, zeroRoll: rawRoll)
    }

    /// Stores a new zero reference (raw degrees) and applies it immediately. Out-of-range values are clamped.
    func applyCalibration(zeroPitch zp: Double, zeroRoll zr: Double) {
        guard zp.isFinite, zr.isFinite else { return }
        zeroPitch = max(-Self.maxZero, min(Self.maxZero, zp))
        zeroRoll = max(-Self.maxZero, min(Self.maxZero, zr))
        calibratedAt = Date()
        publish(force: true)
    }

    func resetCalibration() {
        zeroPitch = 0
        zeroRoll = 0
        calibratedAt = nil
        publish(force: true)
    }

    // MARK: Updates

    private func startUpdates() {
        guard isAvailable, !isRunning, !isSuspended else { return }
        needsSeed = true
        sampleCount = 0
        lastRawGravity = nil
        manager.deviceMotionUpdateInterval = updateInterval
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.ingest(motion)
        }
        isRunning = true
    }

    private func stopUpdates() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    private func suspend() {
        isSuspended = true
        stopUpdates()
    }

    private func resume() {
        isSuspended = false
        if users > 0 { startUpdates() }
    }

    private func ingest(_ motion: CMDeviceMotion) {
        let g = motion.gravity
        var new = SIMD3(g.x, g.y, g.z)
        guard new.x.isFinite, new.y.isFinite, new.z.isFinite else { return }
        let len = (new * new).sum().squareRoot()
        guard len > 0.5 else { return }
        new /= len

        let deg = 180.0 / .pi
        // Stability from frame-to-frame change of the unfiltered gravity direction plus user acceleration.
        if let last = lastRawGravity {
            let moved = acos(max(-1, min(1, (last * new).sum()))) * deg
            let ua = motion.userAcceleration
            let shake = (ua.x * ua.x + ua.y * ua.y + ua.z * ua.z).squareRoot()
            let still = moved < settlingThreshold && shake < 0.02
            let target = still ? 1 : max(0, 1 - moved / 0.5 - shake * 5)
            stability += (target - stability) * 0.05
        }
        lastRawGravity = new

        if needsSeed {
            gravity = new
            needsSeed = false
        } else {
            // Adaptive smoothing: less when moving fast so real movement is never hidden.
            let delta = abs(new.x - gravity.x) + abs(new.y - gravity.y) + abs(new.z - gravity.z)
            let k = min(1, smoothing + delta * 2)
            gravity += (new - gravity) * k
            let gl = (gravity * gravity).sum().squareRoot()
            if gl > 0 { gravity /= gl }
        }
        sampleCount += 1

        // Angle of each screen axis from horizontal.
        let horiz = { (a: Double, b: Double) in (a * a + b * b).squareRoot() }
        rawRoll = atan2(gravity.x, horiz(gravity.y, gravity.z)) * deg
        rawPitch = atan2(-gravity.y, horiz(gravity.x, gravity.z)) * deg

        let y = motion.attitude.yaw * deg
        if y.isFinite { yaw = y }

        // Long edge on a surface: angle of gravity within the screen plane.
        var e = abs(atan2(gravity.y, gravity.x) * deg)
        if e > 90 { e = 180 - e }
        edgeAngle = e
        publish(force: sampleCount == 1)
    }

    private func publish(force: Bool = false) {
        guard isAvailable else { return }
        let p = rawPitch - zeroPitch
        let r = rawRoll - zeroRoll
        // Settling threshold: hold the published value until the filtered value really moves.
        if force || abs(p - pitch) >= settlingThreshold || abs(r - roll) >= settlingThreshold {
            pitch = p
            roll = r
        }
    }
}

// MARK: - Level status

enum LevelStatus: Equatable {
    case perfect, nearly, off

    init(magnitude: Double, perfect: Double = PM.Level.perfect, nearly: Double = PM.Level.nearly) {
        guard magnitude.isFinite else { self = .off; return }
        if magnitude <= perfect { self = .perfect }
        else if magnitude <= nearly { self = .nearly }
        else { self = .off }
    }
}
