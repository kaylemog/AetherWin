// FPSGamepadOverlay.swift
// AetherWin - Dual-Stick First-Person Controller Overlay for MiSide & 3D DirectX Games
// Formatted for iPhone 13 Landscape Safe Areas (844x390 pt)

import SwiftUI

struct FPSGamepadOverlay: View {
    @ObservedObject var inputRouter: UniversalInputRouter

    @State private var leftStickOffset: CGSize = .zero
    @State private var lastLookPoint: CGPoint?
    private let stickRadius: CGFloat = 58.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Right-half invisible free-look touch pad (smooth 1:1 camera rotation for MiSide!)
                HStack(spacing: 0) {
                    Color.clear.frame(width: geo.size.width * 0.42)
                    Color.white.opacity(0.001)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    if let prev = lastLookPoint {
                                        let dx = Float(val.location.x - prev.x)
                                        let dy = Float(val.location.y - prev.y)
                                        inputRouter.sendRelativeMouseDelta(dx: dx, dy: dy)
                                    }
                                    lastLookPoint = val.location
                                }
                                .onEnded { _ in
                                    lastLookPoint = nil
                                    inputRouter.sendRelativeMouseDelta(dx: 0, dy: 0)
                                }
                        )
                }

                // Top Triggers (Sprint, Crouch, Phone/Esc)
                VStack {
                    HStack {
                        holdKeyPill(label: "SPRINT", key: .shift, color: .cyan)
                        holdKeyPill(label: "CROUCH", key: .control, color: .teal)
                        Spacer()
                        tapKeyPill(label: "MENU / ESC", key: .escape, color: .orange)
                    }
                    .padding(.horizontal, max(geo.safeAreaInsets.leading, 24))
                    .padding(.top, 52)
                    Spacer()
                }

                // Bottom Left Analog Stick + Bottom Right Action Cluster
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        // Left Movement Thumbstick (WASD + XInput Left Stick)
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.35))
                                .frame(width: stickRadius * 2, height: stickRadius * 2)
                                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1.5))

                            Circle()
                                .fill(.white.opacity(0.75))
                                .frame(width: 48, height: 48)
                                .offset(leftStickOffset)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    let clamped = clampStick(val.translation, maxRadius: stickRadius)
                                    leftStickOffset = clamped
                                    inputRouter.updateLeftStick(
                                        x: Float(clamped.width / stickRadius),
                                        y: Float(-clamped.height / stickRadius),
                                        mapToWASD: true
                                    )
                                }
                                .onEnded { _ in
                                    leftStickOffset = .zero
                                    inputRouter.updateLeftStick(x: 0, y: 0, mapToWASD: true)
                                }
                        )

                        Spacer()

                        // MiSide / 3D Action Cluster (Interact E, Left Click, Jump Space, Flashlight F)
                        VStack(spacing: 12) {
                            HStack(spacing: 14) {
                                roundActionButton(label: "F", sub: "Light", color: .yellow) {
                                    inputRouter.tapKey(.f)
                                }
                                roundActionButton(label: "E", sub: "Use", color: .green) {
                                    inputRouter.tapKey(.e)
                                }
                            }
                            HStack(spacing: 14) {
                                roundActionButton(label: "LMB", sub: "Click", color: .blue) {
                                    inputRouter.sendMouseClick(leftButton: true, isDown: true)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        inputRouter.sendMouseClick(leftButton: true, isDown: false)
                                    }
                                }
                                roundActionButton(label: "JMP", sub: "Space", color: .purple) {
                                    inputRouter.tapKey(.space)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, max(geo.safeAreaInsets.leading, 26))
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 18))
                }
            }
        }
    }

    private func roundActionButton(label: String, sub: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(label).font(.system(size: 13, weight: .bold, design: .rounded))
                Text(sub).font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(width: 54, height: 54)
            .background(.black.opacity(0.45))
            .overlay(Circle().stroke(color.opacity(0.85), lineWidth: 2))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func tapKeyPill(label: String, key: WinVirtualKey, color: Color) -> some View {
        Button {
            inputRouter.tapKey(key)
        } label: {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.45))
                .overlay(Capsule().stroke(color.opacity(0.75), lineWidth: 1.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func holdKeyPill(label: String, key: WinVirtualKey, color: Color) -> some View {
        let active = inputRouter.pressedVirtualKeys.contains(key.rawValue)
        return Button {
            inputRouter.sendKey(key, isDown: !active)
        } label: {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(active ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(active ? color : .black.opacity(0.45))
                .overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func clampStick(_ vec: CGSize, maxRadius: CGFloat) -> CGSize {
        let dist = hypot(vec.width, vec.height)
        guard dist > maxRadius else { return vec }
        let s = maxRadius / dist
        return CGSize(width: vec.width * s, height: vec.height * s)
    }
}
