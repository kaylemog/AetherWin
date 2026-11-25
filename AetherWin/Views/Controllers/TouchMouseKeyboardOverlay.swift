// TouchMouseKeyboardOverlay.swift
// AetherWin - Precision Desktop Trackpad + Compact PC Keyboard Overlay

import SwiftUI

struct TouchMouseKeyboardOverlay: View {
    @ObservedObject var inputRouter: UniversalInputRouter
    @State private var showCompactKeyboard: Bool = false
    @State private var lastDrag: CGPoint?

    private let topRow: [(String, WinVirtualKey)] = [
        ("ESC", .escape), ("TAB", .tab), ("Q", .q), ("W", .w), ("E", .e),
        ("R", .r), ("T", .t), ("Y", .y), ("U", .u), ("I", .i), ("O", .o), ("P", .p)
    ]
    private let midRow: [(String, WinVirtualKey)] = [
        ("SHFT", .shift), ("A", .a), ("S", .s), ("D", .d), ("F", .f),
        ("G", .g), ("H", .h), ("J", .j), ("K", .k), ("L", .l), ("ENT", .enter)
    ]
    private let botRow: [(String, WinVirtualKey)] = [
        ("CTRL", .control), ("ALT", .menuAlt), ("Z", .z), ("X", .x), ("C", .c),
        ("V", .v), ("B", .b), ("N", .n), ("M", .m), ("SPC", .space), ("BKSP", .backspace)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full-screen precision relative mouse trackpad
                Color.white.opacity(0.001)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                if let prev = lastDrag {
                                    inputRouter.sendRelativeMouseDelta(
                                        dx: Float(val.location.x - prev.x) * 1.35,
                                        dy: Float(val.location.y - prev.y) * 1.35
                                    )
                                }
                                lastDrag = val.location
                            }
                            .onEnded { _ in lastDrag = nil }
                    )
                    .onTapGesture {
                        inputRouter.sendMouseClick(leftButton: true, isDown: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            inputRouter.sendMouseClick(leftButton: true, isDown: false)
                        }
                    }

                VStack {
                    Spacer()

                    // Mouse Left / Right + Keyboard Drawer Toggle
                    HStack(spacing: 10) {
                        Button {
                            inputRouter.sendMouseClick(leftButton: true, isDown: true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                inputRouter.sendMouseClick(leftButton: true, isDown: false)
                            }
                        } label: {
                            Label("Left Click", systemImage: "computermouse.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.black.opacity(0.55))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }

                        Button {
                            inputRouter.sendMouseClick(leftButton: false, isDown: true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                inputRouter.sendMouseClick(leftButton: false, isDown: false)
                            }
                        } label: {
                            Text("Right Click")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.black.opacity(0.55))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                showCompactKeyboard.toggle()
                            }
                        } label: {
                            Label(showCompactKeyboard ? "Hide Keys" : "PC Keyboard", systemImage: "keyboard")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(showCompactKeyboard ? Color.accentColor : .black.opacity(0.55))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, max(geo.safeAreaInsets.leading, 20))
                    .padding(.bottom, showCompactKeyboard ? 6 : max(geo.safeAreaInsets.bottom, 14))

                    if showCompactKeyboard {
                        VStack(spacing: 4) {
                            keyRow(topRow)
                            keyRow(midRow)
                            keyRow(botRow)
                        }
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, max(geo.safeAreaInsets.leading, 12))
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 8))
                    }
                }
            }
        }
    }

    private func keyRow(_ items: [(String, WinVirtualKey)]) -> some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.0) { label, vk in
                Button {
                    inputRouter.tapKey(vk)
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color(.systemGray5).opacity(0.85))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
