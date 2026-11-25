// AetherWinApp.swift
// AetherWin - Universal Windows PC Game Runtime for iPhone 13 (Apple A15 Bionic)

import SwiftUI

@main
struct AetherWinApp: App {
    @StateObject private var libraryManager = GameLibraryManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryManager)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                // Immediately evict cold pages to NVMe when backgrounded so SpringBoard never Jetsam-kills us!
                libraryManager.pauseActiveSession()
            case .active:
                libraryManager.resumeActiveSession()
            default:
                break
            }
        }
    }
}
