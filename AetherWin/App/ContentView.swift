// ContentView.swift
// AetherWin - Root Navigation Shell

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var libraryManager: GameLibraryManager
    @State private var selectedTab: Tab = .library

    enum Tab {
        case library
        case memoryShield
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("PC Games", systemImage: "gamecontroller.fill")
            }
            .tag(Tab.library)

            NavigationStack {
                MemoryDiagnosticsView()
            }
            .tabItem {
                Label("iPhone 13 Shield", systemImage: "memorychip.fill")
            }
            .tag(Tab.memoryShield)
        }
        .tint(Color(red: 0.18, green: 0.58, blue: 1.0))
    }
}
