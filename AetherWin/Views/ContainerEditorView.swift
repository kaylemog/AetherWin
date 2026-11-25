// ContainerEditorView.swift
// AetherWin - Create New Windows Game Container Sheet

import SwiftUI

struct ContainerEditorView: View {
    @EnvironmentObject var manager: GameLibraryManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var exePath: String = "GameFolder/game.exe"
    @State private var selectedPreset: GamePresetID = .universalDX11

    var body: some View {
        NavigationStack {
            Form {
                Section("Game Details") {
                    TextField("Game Title (e.g. Fallout New Vegas)", text: $title)
                    TextField("Executable Path inside Games/", text: $exePath)
                        .font(.caption.monospaced())
                }

                Section("Select Engine & DirectX Preset") {
                    ForEach(GamePresetID.allCases) { preset in
                        Button {
                            selectedPreset = preset
                            if preset == .mySummerCar && title.isEmpty {
                                title = "My Summer Car"
                                exePath = "My Summer Car/mysummercar.exe"
                            } else if preset == .miSide && title.isEmpty {
                                title = "MiSide"
                                exePath = "MiSide/MiSideFull.exe"
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: preset.badgeIcon)
                                    .foregroundStyle(.cyan)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.rawValue)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text(preset.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedPreset == preset {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New PC Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let cleanTitle = title.trimmingCharacters(in: .whitespaces).isEmpty
                            ? selectedPreset.rawValue
                            : title
                        manager.addGame(title: cleanTitle, preset: selectedPreset, exeRelativePath: exePath)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
