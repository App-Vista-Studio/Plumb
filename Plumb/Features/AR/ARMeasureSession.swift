//
//  ARMeasureSession.swift
//  Plumb
//
//  Real ARKit point-to-point measuring: world tracking, a centre raycast for the reticle,
//  placed points in world space, and their per-frame screen projections for the SwiftUI overlay.
//  Distances are straight-line metres between raycast hits, shown at 1 cm precision.
//

import ARKit
import AVFoundation
import Observation
import SceneKit
import SwiftUI

/// A measured or in-progress segment in world space.
struct ARWorldSegment: Identifiable, Equatable {
    let id = UUID()
    var a: simd_float3
    var b: simd_float3?
    var saved = false

    var metres: Double? {
        guard let b else { return nil }
        let d = Double(simd_distance(a, b))
        return d.isFinite ? d : nil
    }
}

/// Where a segment is on screen this frame. nil points are behind the camera or off the view.
struct ARScreenSegment: Identifiable {
    var id: UUID
    var a: CGPoint?
    var b: CGPoint?
    var metres: Double?
    var complete: Bool
}

@Observable
final class ARMeasureSession: NSObject, ARSessionDelegate, ARSCNViewDelegate {
    enum Availability: Equatable { case checking, ready, unsupported, cameraDenied, failed(String) }

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private(set) var availability: Availability = .checking
    private(set) var tracking: ARTrackingQuality = .starting
    /// Coaching hint for the current tracking problem; nil when tracking is fine.
    private(set) var coaching: String?
    /// Screen point of the centre raycast hit; nil when nothing is under the reticle.
    private(set) var reticle: CGPoint?
    private(set) var hasSurface = false
    private(set) var segments: [ARWorldSegment] = []
    private(set) var screenSegments: [ARScreenSegment] = []
    /// Live distance from the open segment's start to the reticle hit.
    private(set) var liveMetres: Double?

    private weak var view: ARSCNView?
    private var hit: simd_float3?
    private var isRunning = false

    // MARK: Lifecycle

    func attach(_ view: ARSCNView) {
        self.view = view
        view.delegate = self
        view.session.delegate = self
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
        view.antialiasingMode = .multisampling4X
        view.scene = SCNScene()
    }

    /// Checks support and camera permission, then runs world tracking.
    func start() {
        guard Self.isSupported else { availability = .unsupported; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            availability = .cameraDenied
            return
        default: break
        }
        guard let view, !isRunning else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .none
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.run(config)
        isRunning = true
        availability = .ready
    }

    func pause() {
        guard isRunning else { return }
        view?.session.pause()
        isRunning = false
    }

    /// Full restart after a failure: tracking is reset and placed points are cleared,
    /// because their world positions are no longer meaningful.
    func restart() {
        pause()
        segments.removeAll()
        screenSegments.removeAll()
        liveMetres = nil
        availability = .checking
        if let view {
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { config.sceneReconstruction = .mesh }
            view.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            isRunning = true
            availability = .ready
        }
    }

    // MARK: Editing

    var openSegment: ARWorldSegment? { segments.last.flatMap { $0.b == nil ? $0 : nil } }
    var completed: [ARWorldSegment] { segments.filter { $0.b != nil } }
    var unsaved: [ARWorldSegment] { segments.filter { $0.b != nil && !$0.saved } }
    var canPlace: Bool { hit != nil && tracking == .good }

    /// Places a start point (no open segment) or an end point (open segment) at the reticle hit.
    @discardableResult
    func placePoint() -> Bool {
        guard let hit, tracking == .good else { return false }
        if let i = segments.indices.last, segments[i].b == nil {
            // Ignore a zero-length segment from a double tap.
            guard simd_distance(segments[i].a, hit) > 0.005 else { return false }
            segments[i].b = hit
        } else {
            segments.append(ARWorldSegment(a: hit))
        }
        Haptics.arEndpointPlaced()
        return true
    }

    /// Undo the last point: an open segment is removed; a finished one is reopened.
    func undo() {
        guard let i = segments.indices.last else { return }
        if segments[i].b == nil { segments.removeLast() } else { segments[i].b = nil; segments[i].saved = false }
        Haptics.selection()
    }

    func clear() {
        segments.removeAll()
        screenSegments.removeAll()
        liveMetres = nil
    }

    func markSaved() {
        for i in segments.indices where segments[i].b != nil { segments[i].saved = true }
    }

    // MARK: ARSessionDelegate (main queue)

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // The delegate queue is the main queue (ARSession's default).
        MainActor.assumeIsolated { ingest(frame, session: session) }
    }

    private func ingest(_ frame: ARFrame, session: ARSession) {
        updateTracking(frame.camera.trackingState)
        guard let view else { return }
        let bounds = view.bounds
        guard bounds.width > 0 else { return }
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)

        // Centre raycast: prefer real planes, fall back to estimated surfaces.
        var result: ARRaycastResult?
        if let q = view.raycastQuery(from: centre, allowing: .existingPlaneGeometry, alignment: .any) {
            result = session.raycast(q).first
        }
        if result == nil, let q = view.raycastQuery(from: centre, allowing: .estimatedPlane, alignment: .any) {
            result = session.raycast(q).first
        }
        if let r = result {
            let t = r.worldTransform.columns.3
            let p = simd_float3(t.x, t.y, t.z)
            hit = p
            reticle = project(p, in: view, bounds: bounds) ?? centre
            hasSurface = true
        } else {
            hit = nil
            reticle = nil
        }

        if let open = openSegment, let hit {
            let d = Double(simd_distance(open.a, hit))
            liveMetres = d.isFinite ? d : nil
        } else {
            liveMetres = nil
        }

        screenSegments = segments.map { s in
            ARScreenSegment(id: s.id,
                            a: project(s.a, in: view, bounds: bounds),
                            b: s.b.flatMap { project($0, in: view, bounds: bounds) } ?? (s.b == nil ? reticle : nil),
                            metres: s.metres ?? (s.b == nil ? liveMetres : nil),
                            complete: s.b != nil)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated { fail(error) }
    }

    private func fail(_ error: Error) {
        isRunning = false
        if let e = error as? ARError, e.code == .cameraUnauthorized {
            availability = .cameraDenied
        } else if let e = error as? ARError, e.code == .unsupportedConfiguration {
            availability = .unsupported
        } else {
            availability = .failed(error.localizedDescription)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            tracking = .limited
            coaching = "AR paused"
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated { coaching = "Hold still while AR recovers" }
    }

    /// Try to relocalise rather than reset, so placed points survive a short interruption.
    nonisolated func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }

    // MARK: ARSCNViewDelegate (render thread): detected planes drawn in faint mint.

    nonisolated func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let plane = anchor as? ARPlaneAnchor, let device = renderer.device,
              let geometry = ARSCNPlaneGeometry(device: device) else { return nil }
        geometry.update(from: plane.geometry)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 82 / 255, green: 242 / 255, blue: 184 / 255, alpha: 0.18)
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    nonisolated func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let plane = anchor as? ARPlaneAnchor, let geometry = node.geometry as? ARSCNPlaneGeometry else { return }
        geometry.update(from: plane.geometry)
    }

    // MARK: Helpers

    private func project(_ p: simd_float3, in view: ARSCNView, bounds: CGRect) -> CGPoint? {
        let v = view.projectPoint(SCNVector3(p.x, p.y, p.z))
        // z outside 0...1 is behind the camera or beyond the far plane.
        guard v.z > 0, v.z < 1, v.x.isFinite, v.y.isFinite else { return nil }
        let pt = CGPoint(x: CGFloat(v.x), y: CGFloat(v.y))
        return bounds.insetBy(dx: -bounds.width, dy: -bounds.height).contains(pt) ? pt : nil
    }

    private func updateTracking(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal:
            tracking = .good
            coaching = nil
        case .notAvailable:
            tracking = .limited
            coaching = "AR isn't available right now"
        case .limited(let reason):
            switch reason {
            case .initializing:
                tracking = .starting
                coaching = "Move your iPhone slowly"
            case .excessiveMotion:
                tracking = .limited
                coaching = "Slow down"
            case .insufficientFeatures:
                tracking = .limited
                coaching = "Aim at a surface with more detail or light"
            case .relocalizing:
                tracking = .limited
                coaching = "Hold still while AR recovers"
            @unknown default:
                tracking = .limited
                coaching = "Move your iPhone slowly"
            }
        }
    }
}

/// Camera feed with ARKit tracking. The SwiftUI overlay draws everything else.
struct ARCameraView: UIViewRepresentable {
    var session: ARMeasureSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        session.attach(view)
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) {
        uiView.session.pause()
    }
}
