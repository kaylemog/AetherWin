// DrivingSimOverlay.swift
// AetherWin - Custom My Summer Car Driving (Satsuma Wheel/Pedals/Gears) & Mechanic Wrench HUD
// Instant toggle between Driving Mode and Engine Building / Walking Mode!

import SwiftUI

struct DrivingSimOverlay: View {
    @ObservedObject var inputRouter: UniversalInputRouter

    @State private var isDrivingMode: Bool = true
    @State private var steeringValue: Float = 0.0
    @State private var isGasPressed: Bool = false
    @State private var isBrakePressed: Bool = false
    @State private var lastLookLocation: CGPoint?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Center screen free-look drag zone (look at dashboard gauges or engine bolts!)
                Color.white.opacity(0.001)
                    .padding(.horizontal, 150)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                if let last = lastLookLocation {
                                    inputRouter.sendRelativeMouseDelta(
                                        dx: Float(val.location.x - last.x),
                                        dy: Float(val.location.y - last.y)
                                    )
                                }
                                lastLookLocation = val.location
                            }
                            .onEnded { _ in lastLookLocation = nil }
                    )

                // Top Mechanic & Mode Bar
                VStack {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                isDrivingMode.toggle()
                                inputRouter.updateDrivingAxes(steering: 0, throttle: 0, brake: 0)
                            }
                        } label: {
                            Label(isDrivingMode ? "SATSUMA DRIVE" : "WRENCH / WALK",
                                  systemImage: isDrivingMode ? "steeringwheel" : "wrench.and.screwdriver.fill")
                                .font(.caption2.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isDrivingMode ? Color.orange : Color.cyan)
                                .foregroundStyle(.black)
                                .clipShape(Capsule())
                        }

                        mscQuickKey("1:HAND", key: .key1)
                        mscQuickKey("2:TOOL", key: .key2)
                        mscQuickKey("F:USE", key: .f)
                        mscQuickKey("C:CROUCH", key: .c)
                        mscQuickKey("J:PUSH", key: .j)
                        Spacer()
                        mscQuickKey("ESC", key: .escape)
                    }
                    .padding(.horizontal, max(geo.safeAreaInsets.leading, 20))
                    .padding(.top, 50)

                    Spacer()
                }

                if isDrivingMode {
                    drivingControls(geo: geo)
                } else {
                    FPSGamepadOverlay(inputRouter: inputRouter)
                }
            }
        }
    }

    private func drivingControls(geo: GeometryProxy) -> some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                // Smooth Self-Centering Analog Steering Slider
                VStack(spacing: 6) {
                    Text(String(format: "STEER %+.0f%%", steeringValue * 100))
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(.white.opacity(0.8))

                    ZStack {
                        Capsule()
                            .fill(.black.opacity(0.45))
                            .frame(width: 190, height: 56)
                            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1.5))

                        Circle()
                            .fill(.orange)
                            .frame(width: 46, height: 46)
                            .offset(x: CGFloat(steeringValue) * 68)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let norm = max(min(Float((val.location.x - 95.0) / 68.0), 1.0), -1.0)
                                steeringValue = norm
                                syncDrivingAxes()
                            }
                            .onEnded { _ in
                                withAnimation(.interpolatingSpring(stiffness: 220, damping: 18)) {
                                    steeringValue = 0
                                }
                                syncDrivingAxes()
                            }
                    )
                }

                Spacer()

                // Shifter (G = Gear Up, B = Gear Down, Space = Handbrake) + Gas/Brake Pedals
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(spacing: 8) {
                        Button { inputRouter.tapKey(.g) } label: {
                            Text("GEAR + (G)")
                                .font(.caption2.bold())
                                .frame(width: 78, height: 38)
                                .background(.black.opacity(0.5))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.green, lineWidth: 1.5))
                                .foregroundStyle(.white)
                        }
                        Button { inputRouter.tapKey(.b) } label: {
                            Text("GEAR - (B)")
                                .font(.caption2.bold())
                                .frame(width: 78, height: 38)
                                .background(.black.opacity(0.5))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.yellow, lineWidth: 1.5))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    // Brake Pedal
                    pedalView(title: "BRAKE", color: .red, isPressed: $isBrakePressed)

                    // Gas Pedal
                    pedalView(title: "GAS", color: .green, isPressed: $isGasPressed)
                }
            }
            .padding(.horizontal, max(geo.safeAreaInsets.leading, 24))
            .padding(.bottom, max(geo.safeAreaInsets.bottom, 16))
        }
    }

    private func pedalView(title: String, color: Color, isPressed: Binding<Bool>) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isPressed.wrappedValue ? color.opacity(0.75) : .black.opacity(0.45))
                .frame(width: 58, height: 104)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color, lineWidth: 2))

            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed.wrappedValue {
                        isPressed.wrappedValue = true
                        syncDrivingAxes()
                    }
                }
                .onEnded { _ in
                    isPressed.wrappedValue = false
                    syncDrivingAxes()
                }
        )
    }

    private func mscQuickKey(_ title: String, key: WinVirtualKey) -> some View {
        Button {
            inputRouter.tapKey(key)
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.black.opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func syncDrivingAxes() {
        inputRouter.updateDrivingAxes(
            steering: steeringValue,
            throttle: isGasPressed ? 1.0 : 0.0,
            brake: isBrakePressed ? 1.0 : 0.0
        )
    }
}
