//
//  ToolChrome.swift
//  Plumb
//
//  Small pieces shared by the Surface, Angle, Protractor, Compass and Ruler screens.
//

import SwiftUI
import UIKit

/// Glowing 2 pt accent frame shown around the whole screen while a reading is locked.
struct ToolChromeLockedFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: PM.Radius.phone, style: .continuous)
            .strokeBorder(PM.Colors.accent, lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: PM.Radius.phone, style: .continuous)
                    .stroke(PM.Colors.accent.opacity(0.25), lineWidth: 28)
                    .blur(radius: 14)
            )
            .clipShape(RoundedRectangle(cornerRadius: PM.Radius.phone, style: .continuous))
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// "LOCKED · 10:47 AM" pill: 26 tall, accent fill, 12 heavy, tracking 0.8.
struct ToolChromeLockedPill: View {
    var time: Date

    var body: some View {
        HStack(spacing: 6) {
            PMIcon(.lock, size: 12, stroke: 2.4)
            Text("LOCKED · \(time.formatted(date: .omitted, time: .shortened).uppercased())")
        }
        .font(.pm(12, .heavy))
        .tracking(0.8)
        .foregroundStyle(PM.Colors.onAccent)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(PM.Colors.accent))
    }
}

/// Lock / Unlock pill. Filled when unlocked, accent outline when locked.
struct ToolChromeLockButton: View {
    var locked: Bool
    var lockLabel: String = "Lock"
    var fontSize: CGFloat = 17
    var iconSize: CGFloat = 18
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                PMIcon(.lock, size: iconSize, stroke: 2)
                Text(locked ? "Unlock" : lockLabel)
            }
        }
        .buttonStyle(ToolChromeLockStyle(locked: locked, disabled: disabled, fontSize: fontSize))
        .disabled(disabled)
        .accessibilityAddTraits(locked ? .isSelected : [])
    }
}

private struct ToolChromeLockStyle: ButtonStyle {
    var locked: Bool
    var disabled: Bool
    var fontSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pm(fontSize, .bold))
            .foregroundStyle(disabled ? PM.Colors.textSecondary : locked ? PM.Colors.accent : PM.Colors.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(disabled ? PM.Colors.surfaceRaised : locked ? PM.Colors.background : PM.Colors.accent))
            .overlay(Capsule().strokeBorder(locked && !disabled ? PM.Colors.accent : .clear, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PM.Motion.cardPress, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Save / Share / Copy row (44 tall, 14 semibold) shown under a locked reading.
struct ToolChromeLockedActions: View {
    var shareText: String
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Save", action: onSave)
                .buttonStyle(PMSecondaryButtonStyle(height: 44, fontSize: 14, horizontalPadding: 16))
            ShareLink(item: shareText) { Text("Share") }
                .buttonStyle(PMSecondaryButtonStyle(height: 44, fontSize: 14, horizontalPadding: 16))
            Button("Copy") {
                UIPasteboard.general.string = shareText
                Haptics.selection()
            }
            .buttonStyle(PMSecondaryButtonStyle(height: 44, fontSize: 14, horizontalPadding: 16))
        }
    }
}

/// 54 pt round info button used beside the lock button.
struct ToolChromeInfoButton: View {
    var action: () -> Void

    var body: some View {
        IconCircleButton(icon: .info, label: "Measurement info", size: 54, iconSize: 20, stroke: 1.8,
                         fill: PM.Colors.surfaceRaised, border: PM.Colors.borderStrong, action: action)
    }
}

/// Measurement Info panel, as drawn on the Level board.
struct ToolChromeInfoPanel: View {
    var rows: [(String, String)]
    var quality: String = "Good"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MEASUREMENT QUALITY").font(.pm(12, .heavy)).tracking(1.2)
                    .foregroundStyle(PM.Colors.textSecondary)
                Spacer()
                HStack(spacing: 6) {
                    PMIcon(.check, size: 14, stroke: 2.6)
                    Text(quality)
                }
                .font(.pm(14, .bold))
                .foregroundStyle(PM.Colors.accent)
            }
            Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        Text(rows[i].0).foregroundStyle(PM.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(rows[i].1).foregroundStyle(PM.Colors.textPrimary).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .font(.pm(13))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(PM.Colors.surface.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(PM.Colors.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: -10)
        .accessibilityElement(children: .combine)
    }
}

/// Transient "Measurement saved" toast.
struct ToolChromeToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    var text: String = "Measurement saved"

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isShowing {
                ToastView(text: text)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(PM.Motion.normal) { isShowing = false }
                    }
            }
        }
    }
}

extension View {
    func toolChromeToast(_ isShowing: Binding<Bool>, text: String = "Measurement saved") -> some View {
        modifier(ToolChromeToastModifier(isShowing: isShowing, text: text))
    }
}

/// Degrees to one decimal with the degree sign, no sign prefix.
func toolChromeDegrees(_ v: Double, decimals: Int = 1) -> String {
    String(format: "%.\(decimals)f°", v)
}
