// GameLibraryManager.swift
// AetherWin - Master Game Library & Anti-Crash Session Orchestrator

import Foundation
import SwiftUI
import Combine

final class GameLibraryManager: ObservableObject, JetsamMitigationResponder {
    @Published var games: [WindowsGame] = []
    @Published var activeGame: WindowsGame?
    @Published var sessionState: GameSessionState = .idle
    @Published var lastUnityOptimization: UnityOptimizationReport?
    @Published var lastErrorMessage: String?
    @Published var gpuTelemetry = GPURenderTelemetry()

    // Core Runtime Subsystems
    let memoryGuard = JetsamMemoryGuard.shared
    let jitAllocator = APRRJITAllocator.shared
    let swapPool = NVMeVirtualSwapPool()
    let dynarec = DynarecEngine()
    let inputRouter = UniversalInputRouter()
    let audioEngine = LowLatencyXAudioEngine.shared

    weak var activeGraphicsRouter: UniversalGraphicsRouter?
    private var activeEnvironment: [String: String] = [:]
    private let gameMainQueue = ThreadSchedulerA15.makeQueue(label: "com.aetherwin.pcore.main", role: .gameMainAndPhysics)

    private var libraryStorageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("aetherwin_library.json")
    }

    init() {
        memoryGuard.responder = self
        loadLibrary()
        if games.isEmpty {
            seedFeaturedOptimizedContainers()
        }
    }

    // MARK: - Default Pre-Configured Containers (My Summer Car & MiSide Ready!)

    private func seedFeaturedOptimizedContainers() {
        let msc = WindowsGame(
            title: "My Summer Car",
            executableRelativePath: "My Summer Car/mysummercar.exe",
            presetID: .mySummerCar
        )
        let miside = WindowsGame(
            title: "MiSide",
            executableRelativePath: "MiSide/MiSideFull.exe",
            presetID: .miSide
        )
        games = [msc, miside]
        for game in games {
            let prefix = WinePrefixManager(containerRootURL: game.containerDirectoryURL)
            try? prefix.provisionPrefix(for: game.profile)
        }
        saveLibrary()
    }

    // MARK: - Game Creation & Auto-Detection Import

    @discardableResult
    func addGame(title: String, preset: GamePresetID, exeRelativePath: String) -> WindowsGame {
        let game = WindowsGame(
            title: title,
            executableRelativePath: exeRelativePath,
            presetID: preset
        )
        let prefix = WinePrefixManager(containerRootURL: game.containerDirectoryURL)
        try? prefix.provisionPrefix(for: game.profile)
        games.append(game)
        saveLibrary()
        return game
    }

    /// Imports an external Windows `.exe` or game folder and automatically configures CPU, DirectX, and Memory Guard
    func importWindowsExecutable(from externalURL: URL) {
        let scoped = externalURL.startAccessingSecurityScopedResource()
        defer { if scoped { externalURL.stopAccessingSecurityScopedResource() } }

        let sig = PEExecutableInspector.inspect(executableURL: externalURL)
        let lower = sig.detectedTitleHint.lowercased()

        let chosenPreset: GamePresetID
        if lower.contains("mysummercar") {
            chosenPreset = .mySummerCar
        } else if lower.contains("miside") {
            chosenPreset = .miSide
        } else if sig.architecture == .x86_32_wow64 {
            chosenPreset = .classicDX9_WOW64
        } else {
            chosenPreset = .universalDX11
        }

        var customProfile = chosenPreset.profile
        customProfile.cpuArchitecture = sig.architecture
        customProfile.graphicsAPI = sig.recommendedGraphicsAPI

        var newGame = WindowsGame(
            title: sig.detectedTitleHint,
            executableRelativePath: "\(sig.detectedTitleHint)/\(externalURL.lastPathComponent)",
            presetID: chosenPreset,
            profile: customProfile,
            detectedSignature: sig
        )

        let prefix = WinePrefixManager(containerRootURL: newGame.containerDirectoryURL)
        try? prefix.provisionPrefix(for: newGame.profile)

        // Copy executable into `drive_c/Games/<Title>/`
        let destExeURL = newGame.resolvedExecutableURL
        try? FileManager.default.createDirectory(at: destExeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: externalURL, to: destExeURL)

        newGame.lastPlayedDate = nil
        games.append(newGame)
        saveLibrary()
    }

    func updateGame(_ updated: WindowsGame) {
        if let idx = games.firstIndex(where: { $0.id == updated.id }) {
            games[idx] = updated
            saveLibrary()
        }
    }

    func deleteGame(_ game: WindowsGame) {
        if activeGame?.id == game.id {
            stopActiveSession()
        }
        try? FileManager.default.removeItem(at: game.containerDirectoryURL)
        games.removeAll { $0.id == game.id }
        saveLibrary()
    }

    // MARK: - Anti-Crash Session Lifecycle

    func launch(game: WindowsGame) {
        sessionState = .preparingMemory
        lastErrorMessage = nil

        var mutableGame = game
        mutableGame.lastPlayedDate = Date()
        updateGame(mutableGame)
        activeGame = mutableGame

        let profile = mutableGame.profile

        gameMainQueue.async { [weak self] in
            guard let self = self else { return }
            ThreadSchedulerA15.applyCurrentThreadAffinity(role: .gameMainAndPhysics)

            do {
                // 1. Provision Wine Prefix & Registry overrides
                let prefix = WinePrefixManager(containerRootURL: mutableGame.containerDirectoryURL)
                try prefix.provisionPrefix(for: profile)

                // 2. Mount Sparse NVMe Virtual Swap Pagefile (e.g. 2560MB for My Summer Car!)
                try self.swapPool.initializePool(sizeMB: profile.nvmeVirtualSwapMB)

                // 3. Apply Unity `boot.config` & Zero-Copy `.assets` `mmap` optimizations
                let unityReport: UnityOptimizationReport?
                if profile.enableZeroCopyUnityAssetMmap {
                    unityReport = UnityMonoOptimizer.optimizeGameDirectory(
                        executableURL: mutableGame.resolvedExecutableURL,
                        profile: profile,
                        swapPool: self.swapPool
                    )
                } else {
                    unityReport = nil
                }

                // 4. Assemble merged Box64 + Wine + DXVK + Mono GC environment
                var mergedEnv = prefix.buildWineEnvironment(profile: profile)
                let dynEnv = self.dynarec.buildDynarecEnvironment(
                    architecture: profile.cpuArchitecture,
                    tuning: profile.dynarecTuning,
                    jitCacheLimitMB: profile.jitCodeCacheCapMB
                )
                let monoEnv = UnityMonoOptimizer.buildMonoEnvironment(maxHeapMB: profile.monoMaxHeapMB)
                mergedEnv.merge(dynEnv) { _, new in new }
                mergedEnv.merge(monoEnv) { _, new in new }
                self.activeEnvironment = mergedEnv

                // 5. Start CoreAudio & Real-Time 250ms Jetsam Memory Guard
                DispatchQueue.main.async {
                    self.lastUnityOptimization = unityReport
                    self.memoryGuard.attachSubsystems(
                        swapPool: self.swapPool,
                        metalAllocator: self.activeGraphicsRouter?.heapAllocator
                    )
                    self.memoryGuard.startMonitoring()
                    self.audioEngine.start()
                    self.sessionState = .running
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastErrorMessage = error.localizedDescription
                    self.sessionState = .error
                }
            }
        }
    }

    func pauseActiveSession() {
        guard sessionState == .running else { return }
        audioEngine.pause()
        // Flush dirty pages to NVMe when backgrounded so iOS doesn't Jetsam-kill AetherWin in background!
        swapPool.evictColdPages(targetReclaimBytes: 512 * 1_048_576)
        sessionState = .paused
    }

    func resumeActiveSession() {
        guard sessionState == .paused else { return }
        audioEngine.start()
        sessionState = .running
    }

    func stopActiveSession() {
        memoryGuard.stopMonitoring()
        audioEngine.stop()
        swapPool.shutdown()
        jitAllocator.compactCache(keepRatio: 0.0)
        activeGraphicsRouter = nil
        activeGame = nil
        sessionState = .idle
    }

    // MARK: - JetsamMitigationResponder

    func onRequestMipmapBiasIncrease(newBias: Int) {
        activeGraphicsRouter?.textureManager.setMipmapBias(newBias)
    }

    func onRequestJITCacheCompaction(keepRatio: Double) {
        jitAllocator.compactCache(keepRatio: keepRatio)
    }

    func onRequestGuestGarbageCollection() {
        // Signals Mono SGen / Wine WorkingSet trim
        swapPool.trimMappedAssetPages()
    }

    func onRequestDynamicResolutionScaleDrop() {
        DispatchQueue.main.async { [weak self] in
            self?.activeGraphicsRouter?.dropInternalResolutionStep()
        }
    }

    // MARK: - Persistence

    func saveLibrary() {
        if let data = try? JSONEncoder().encode(games) {
            try? data.write(to: libraryStorageURL, options: .atomic)
        }
    }

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: libraryStorageURL),
              let decoded = try? JSONDecoder().decode([WindowsGame].self, from: data) else { return }
        self.games = decoded
    }
}
