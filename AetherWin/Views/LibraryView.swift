// LibraryView.swift
// AetherWin - Windows Game Library with Pre-Configured My Summer Car & MiSide Cards

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var manager: GameLibraryManager
    @State private var showingAddContainer = false
    @State private var showingExeImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hardwareBanner

                HStack {
                    Text("Installed Containers")
                        .font(.title3.bold())
                    Spacer()
                    Button {
                        showingExeImporter = true
                    } label: {
                        Label("Import .exe", systemImage: "folder.badge.plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                }

                ForEach(manager.games) { game in
                    NavigationLink {
                        GameDetailView(game: game)
                    } label: {
                        GameCardView(game: game)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("AetherWin")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddContainer = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showingAddContainer) {
            ContainerEditorView()
                .environmentObject(manager)
        }
        .fileImporter(
            isPresented: $showingExeImporter,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                manager.importWindowsExecutable(from: first)
            }
        }
    }

    private var hardwareBanner: some View {
        let jitOK = APRRJITAllocator.shared.isJITActive
        let entOK = MachMemoryProbe.isIncreasedMemoryEntitlementActive

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundStyle(.cyan)
                Text("iPhone 13 • A15 Bionic Tuned Runtime")
                    .font(.subheadline.bold())
                Spacer()
                Text(jitOK ? "JIT ACTIVE" : "JIT STANDBY")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(jitOK ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundStyle(jitOK ? .green : .orange)
                    .clipShape(Capsule())
            }

            Text(entOK
                 ? "Extended 3.0 GB RAM Entitlement Active • NVMe Demand Swap Ready • MetalFX Enabled"
                 : "NVMe Demand Swap & Zero-Copy Unity Asset Mmap Ready • Enable Extended RAM via AltStore/TrollStore")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct GameCardView: View {
    let game: WindowsGame

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [.blue.opacity(0.35), .purple.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)

                    Image(systemName: game.presetID.badgeIcon)
                        .font(.title2)
                        .foregroundStyle(.cyan)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(game.profile.graphicsAPI.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        badge("\(game.profile.internalRenderWidth)x\(game.profile.internalRenderHeight)", color: .blue)
                        badge("Swap \(game.profile.nvmeVirtualSwapMB)MB", color: .green)
                        if game.profile.enableMetalFXUpscaling {
                            badge("MetalFX", color: .purple)
                        }
                    }
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
