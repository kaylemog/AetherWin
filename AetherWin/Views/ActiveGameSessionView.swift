// ActiveGameSessionView.swift
// AetherWin - Fullscreen Metal 3 Viewport + Live Anti-Crash Jetsam Telemetry Pill

import SwiftUI
import MetalKit

struct ActiveGameSessionView: View {
    @EnvironmentObject var manager: GameLibraryManager
    let game: WindowsGame
    @Environment(\.dismiss) private var dismiss

    @StateObject private var memoryGuard = JetsamMemoryGuard.shared
    @State private var activeHUD: TouchHUDLayout
    @State private var showTelemetryExpanded: Bool = true
    @State private var hideControlsOverlay: Bool = false

    init(game: WindowsGame) {
        self.game = game
        _activeHUD = State(initialValue: game.profile.touchHUDLayout)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Zero-copy Metal 3 + MetalFX Display Surface
            AetherMetalSurface(game: game, manager: manager)
                .ignoresSafeArea()

            // Selected Genre Touch Controller Overlay
            if !hideControlsOverlay {
                switch activeHUD {
                case .fpsDualStick:
                    FPSGamepadOverlay(inputRouter: manager.inputRouter)
                case .drivingAndMechanic:
                    DrivingSimOverlay(inputRouter: manager.inputRouter)
                case .pcMouseAndKeyboard:
                    TouchMouseKeyboardOverlay(inputRouter: manager.inputRouter)
                }
            }

            // Top Floating Anti-Crash Jetsam Shield & Session Control Pill
            VStack {
                topStatusBar
                Spacer()
            }
        }
        .statusBarHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            manager.launch(game: game)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var topStatusBar: some View {
        HStack(spacing: 10) {
            // Live Memory & FPS Pill
            Button {
                withAnimation(.spring(response: 0.25)) {
                    showTelemetryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(defenseStageColor)
                        .frame(width: 8, height: 8)

                    Text(String(format: "%.0f FPS", manager.gpuTelemetry.fps))
                        .font(.caption2.monospacedDigit().bold())
                        .foregroundStyle(.green)

                    if showTelemetryExpanded {
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        Text(String(format: "RAM %.0fMB", memoryGuard.latestTelemetry.footprintMB))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white)
                        Text(String(format: "Free %.0fMB", memoryGuard.latestTelemetry.availableHeadroomMB))
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(defenseStageColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            // Quick HUD Switcher & Manual Memory Purge Menu
            Menu {
                Section("Touch Controller HUD") {
                    ForEach(TouchHUDLayout.allCases) { layout in
                        Button {
                            activeHUD = layout
                        } label: {
                            if activeHUD == layout {
                                Label(layout.rawValue, systemImage: "checkmark")
                            } else {
                                Text(layout.rawValue)
                            }
                        }
                    }
                    Button {
                        hideControlsOverlay.toggle()
                    } label: {
                        Label(hideControlsOverlay ? "Show Touch HUD" : "Hide HUD (Bluetooth Pad)",
                              systemImage: "gamecontroller")
                    }
                }

                Section("iPhone 13 Anti-Crash Memory Guard") {
                    Button {
                        _ = manager.swapPool.evictColdPages(targetReclaimBytes: 384 * 1_048_576)
                        _ = manager.activeGraphicsRouter?.heapAllocator.purgeVolatileResources()
                    } label: {
                        Label("Purge Cold RAM to NVMe Now", systemImage: "memorychip")
                    }
                }

                Section("Session") {
                    Button(role: .destructive) {
                        manager.stopActiveSession()
                        dismiss()
                    } label: {
                        Label("Exit Windows Game", systemImage: "power")
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var defenseStageColor: Color {
        switch memoryGuard.currentStage {
        case .nominal: return .green
        case .stage1SoftTrim: return .yellow
        case .stage2TextureAndGCTrim: return .orange
        case .stage3EmergencyShield: return .red
        }
    }
}

// MARK: - MTKView SwiftUI Bridge

struct AetherMetalSurface: UIViewRepresentable {
    let game: WindowsGame
    let manager: GameLibraryManager

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor = .black
        if let router = UniversalGraphicsRouter(metalView: view, profile: game.profile) {
            router.onTelemetryUpdate = { [weak manager] stats in
                DispatchQueue.main.async {
                    manager?.gpuTelemetry = stats
                }
            }
            context.coordinator.router = router
            DispatchQueue.main.async {
                manager.activeGraphicsRouter = router
            }
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var router: UniversalGraphicsRouter?
    }
}
