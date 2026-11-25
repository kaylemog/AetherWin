// WindowsGame.swift
// AetherWin - Installed Windows Game Model & Container Path Resolver

import Foundation

enum GameSessionState: String, Codable {
    case idle = "Ready"
    case preparingMemory = "Mounting NVMe Swap & Assets..."
    case running = "Running"
    case paused = "Suspended"
    case error = "Error"
}

struct WindowsGame: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var executableRelativePath: String
    var presetID: GamePresetID
    var profile: ContainerProfile
    var detectedSignature: DetectedGameSignature?
    var lastPlayedDate: Date?
    var totalPlayMinutes: Int

    init(
        id: UUID = UUID(),
        title: String,
        executableRelativePath: String,
        presetID: GamePresetID,
        profile: ContainerProfile? = nil,
        detectedSignature: DetectedGameSignature? = nil
    ) {
        self.id = id
        self.title = title
        self.executableRelativePath = executableRelativePath
        self.presetID = presetID
        self.profile = profile ?? presetID.profile
        self.detectedSignature = detectedSignature
        self.lastPlayedDate = nil
        self.totalPlayMinutes = 0
    }

    var containerDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Containers/\(id.uuidString)", isDirectory: true)
    }

    var resolvedExecutableURL: URL {
        containerDirectoryURL
            .appendingPathComponent("drive_c/Games", isDirectory: true)
            .appendingPathComponent(executableRelativePath)
    }
}
