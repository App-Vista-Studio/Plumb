//
//  LevelProjection.swift
//  Plumb
//
//  Reproduces CSS `perspective` + `transform` on a view, so the tilted phone, table and
//  AR floor plane in the Calibration and Onboarding boards project exactly as drawn.
//

import SwiftUI
import QuartzCore

enum LevelCSSTransform {
    case rotateX(Double)
    case rotateZ(Double)
    case translateY(CGFloat)
}

extension View {
    /// - Parameters:
    ///   - size: the view's frame size.
    ///   - origin: `transform-origin` in the view's local points.
    ///   - transforms: CSS transform functions in the order written.
    ///   - perspectiveOrigin: the parent's perspective origin, relative to this view's top-left.
    ///   - distance: CSS `perspective` length.
    func levelCSSProjection(size: CGSize, origin: CGPoint, transforms: [LevelCSSTransform],
                            perspectiveOrigin: CGPoint, distance: CGFloat) -> some View {
        projectionEffect(ProjectionTransform(LevelProjection.matrix(
            origin: origin, transforms: transforms, perspectiveOrigin: perspectiveOrigin, distance: distance)))
    }
}

enum LevelProjection {
    /// Row-vector matrices (Core Animation convention): each concat applies left then right.
    static func matrix(origin: CGPoint, transforms: [LevelCSSTransform],
                       perspectiveOrigin: CGPoint, distance: CGFloat) -> CATransform3D {
        var m = CATransform3DMakeTranslation(-origin.x, -origin.y, 0)
        // CSS applies the right-most function first.
        for t in transforms.reversed() {
            let step: CATransform3D
            switch t {
            case .rotateX(let deg): step = CATransform3DMakeRotation(deg * .pi / 180, 1, 0, 0)
            case .rotateZ(let deg): step = CATransform3DMakeRotation(deg * .pi / 180, 0, 0, 1)
            case .translateY(let y): step = CATransform3DMakeTranslation(0, y, 0)
            }
            m = CATransform3DConcat(m, step)
        }
        // Perspective about the parent's perspective origin (expressed relative to transform-origin).
        let px = perspectiveOrigin.x - origin.x
        let py = perspectiveOrigin.y - origin.y
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(-px, -py, 0))
        var p = CATransform3DIdentity
        p.m34 = -1 / distance
        m = CATransform3DConcat(m, p)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(px + origin.x, py + origin.y, 0))
        return m
    }
}
