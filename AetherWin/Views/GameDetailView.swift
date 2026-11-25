// GameDetailView.swift
// AetherWin - Per-Game Launch & Anti-Crash Tuning Inspector

import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var manager: GameLibraryManager
    @State var game: WindowsGame
    @State private var launchingFullscreen = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Button {
                    manager.updateGame(game)
                    launchingFullscreen = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Launch Game (Zero-Crash Guard)", systemImage: "play.fill")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.blue)
                .foregroundStyle(.white)
            }

            Section("Game Executable Path (Files App)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Place your PC game folder inside:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("On My iPhone/AetherWin/Containers/\(game.id.uuidString)/drive_c/Games/")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cyan)
                }
                TextField("Relative .exe path", text: $game.executableRelativePath)
                    .font(.caption.monospaced())
            }

            Section("Graphics & MetalFX Upscaling") {
                Picker("Graphics Backend", selection: $game.profile.graphicsAPI) {
                    ForEach(WindowsGraphicsAPI.allCases) { api in
                        Text(api.rawValue).tag(api)
                    }
                }

                Picker("Internal Resolution", selection: $game.profile.internalRenderHeight) {
                    Text("960 x 540 (Ultra High FPS)").tag(540)
                    Text("1136 x 640 (Recommended MiSide)").tag(640)
                    Text("1280 x 720 (HD Balanced)").tag(720)
                }
                .onChange(of: game.profile.internalRenderHeight) { newH in
                    switch newH {
                    case 540: game.profile.internalRenderWidth = 960
                    case 640: game.profile.internalRenderWidth = 1136
                    default:  game.profile.internalRenderWidth = 1280
                    }
                }

                Toggle("Apple MetalFX Spatial Upscaling", isOn: $game.profile.enableMetalFXUpscaling)
                Stepper("Target FPS: \(game.profile.targetFPS)", value: $game.profile.targetFPS, in: 30...60, step: 15)
            }

            Section("iPhone 13 Anti-Crash Memory Protection") {
                Stepper(
                    "NVMe Virtual Swap: \(game.profile.nvmeVirtualSwapMB) MB",
                    value: $game.profile.nvmeVirtualSwapMB,
                    in: 1024...4096,
                    step: 512
                )
                Stepper(
                    "Mono / Unity GC Cap: \(game.profile.monoMaxHeapMB) MB",
                    value: $game.profile.monoMaxHeapMB,
                    in: 256...768,
                    step: 64
                )
                Picker("Max Texture Clamp", selection: $game.profile.maxTextureDimension) {
                    Text("1024 px (Zero OOM Crash)").tag(1024)
                    Text("2048 px (High Detail)").tag(2048)
                }
                Toggle("Zero-Copy Unity .assets Mmap", isOn: $game.profile.enableZeroCopyUnityAssetMmap)
                Toggle("Hardware BC1-BC7 Texture Compression", isOn: $game.profile.enableHardwareBCTextures)
            }

            Section("CPU & Touch Controller") {
                Picker("Dynarec Mode", selection: $game.profile.dynarecTuning) {
                    ForEach(DynarecTuningPreset.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Picker("Touch HUD", selection: $game.profile.touchHUDLayout) {
                    ForEach(TouchHUDLayout.allCases) { hud in
                        Text(hud.rawValue).tag(hud)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    manager.deleteGame(game)
                    dismiss()
                } label: {
                    Label("Delete Container", systemImage: "trash")
                }
            }
        }
        .navigationTitle(game.title)
        .onDisappear {
            manager.updateGame(game)
        }
        .fullScreenCover(isPresented: $launchingFullscreen) {
            ActiveGameSessionView(game: game)
                .environmentObject(manager)
        }
    }
}
