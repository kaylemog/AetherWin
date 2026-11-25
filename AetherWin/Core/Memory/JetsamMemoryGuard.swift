// JetsamMemoryGuard.swift
// AetherWin - 4-Stage Anti-Crash Memory Governor for iPhone 13
// Actively prevents EXC_RESOURCE (Jetsam High-Watermark) kills in My Summer Car & MiSide

import Foundation
import UIKit
import Combine

/// Defense level of the anti-crash memory governor
enum MemoryDefenseStage: String, Codable {
    case nominal = "Nominal (Full Speed)"
    case stage1SoftTrim = "Stage 1: Soft Cache Trim"
    case stage2TextureAndGCTrim = "Stage 2: Mono GC & Mipmap Drop"
    case stage3EmergencyShield = "Stage 3: Emergency Jetsam Shield"
}

/// Callbacks triggered into the emulation subsystems when memory headroom tightens
protocol JetsamMitigationResponder: AnyObject {
    func onRequestMipmapBiasIncrease(newBias: Int)
    func onRequestJITCacheCompaction(keepRatio: Double)
    func onRequestGuestGarbageCollection()
    func onRequestDynamicResolutionScaleDrop()
}

/// Polls `os_proc_available_memory` every 250ms and intercepts XNU kernel memory pressure signals
final class JetsamMemoryGuard: ObservableObject {
    static let shared = JetsamMemoryGuard()

    @Published private(set) var latestTelemetry: MemoryTelemetrySnapshot = .zero
    @Published private(set) var currentStage: MemoryDefenseStage = .nominal
    @Published private(set) var emergencySavesCount: Int = 0
    @Published private(set) var totalReclaimedMB: Double = 0

    weak var responder: JetsamMitigationResponder?
    private var swapPool: NVMeVirtualSwapPool?
    private var metalAllocator: UnifiedMetalHeapAllocator?

    private var timer: DispatchSourceTimer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private let guardQueue = DispatchQueue(label: "com.aetherwin.jetsamguard", qos: .userInteractive)

    // Headroom thresholds specifically calibrated for iPhone 13 (4GB RAM)
    private let stage1HeadroomMB: Double = 550.0
    private let stage2HeadroomMB: Double = 340.0
    private let stage3HeadroomMB: Double = 180.0

    private init() {}

    func attachSubsystems(swapPool: NVMeVirtualSwapPool, metalAllocator: UnifiedMetalHeapAllocator?) {
        self.swapPool = swapPool
        self.metalAllocator = metalAllocator
    }

    /// Starts real-time 4Hz hardware telemetry and kernel pressure listener
    func startMonitoring() {
        stopMonitoring()

        // 1. 250ms high-priority polling timer
        let t = DispatchSource.makeTimerSource(queue: guardQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in
            self?.evaluateMemoryState()
        }
        t.resume()
        self.timer = t

        // 2. XNU Kernel DispatchSourceMemoryPressure
        let ps = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: guardQueue)
        ps.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = ps.data
            if event.contains(.critical) {
                self.executeMitigation(stage: .stage3EmergencyShield, snapshot: MachMemoryProbe.captureSnapshot())
            } else if event.contains(.warning) {
                self.executeMitigation(stage: .stage2TextureAndGCTrim, snapshot: MachMemoryProbe.captureSnapshot())
            }
        }
        ps.resume()
        self.pressureSource = ps

        // 3. UIKit memory warning fallback
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUIKitMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        pressureSource?.cancel()
        pressureSource = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleUIKitMemoryWarning() {
        guardQueue.async { [weak self] in
            guard let self = self else { return }
            self.executeMitigation(stage: .stage3EmergencyShield, snapshot: MachMemoryProbe.captureSnapshot())
        }
    }

    private func evaluateMemoryState() {
        let snap = MachMemoryProbe.captureSnapshot()
        let headroom = snap.availableHeadroomMB

        let targetStage: MemoryDefenseStage
        if headroom < stage3HeadroomMB {
            targetStage = .stage3EmergencyShield
        } else if headroom < stage2HeadroomMB {
            targetStage = .stage2TextureAndGCTrim
        } else if headroom < stage1HeadroomMB {
            targetStage = .stage1SoftTrim
        } else {
            targetStage = .nominal
        }

        if targetStage != .nominal {
            executeMitigation(stage: targetStage, snapshot: snap)
        } else if currentStage != .nominal {
            // Recovered sufficient headroom -> relax mipmap bias
            responder?.onRequestMipmapBiasIncrease(newBias: 0)
            DispatchQueue.main.async {
                self.currentStage = .nominal
                self.latestTelemetry = snap
            }
        } else {
            DispatchQueue.main.async {
                self.latestTelemetry = snap
            }
        }
    }

    private func executeMitigation(stage: MemoryDefenseStage, snapshot: MemoryTelemetrySnapshot) {
        var bytesFreed = 0

        switch stage {
        case .nominal:
            break

        case .stage1SoftTrim:
            // Evict 128MB of cold Win32 virtual heap pages to NVMe SSD & drop clean asset pages
            bytesFreed += swapPool?.evictColdPages(targetReclaimBytes: 128 * 1_048_576) ?? 0
            swapPool?.trimMappedAssetPages()
            responder?.onRequestMipmapBiasIncrease(newBias: 1)

        case .stage2TextureAndGCTrim:
            // Evict 256MB to NVMe + purge Metal staging + trigger Unity Mono / Wine WorkingSet GC
            bytesFreed += swapPool?.evictColdPages(targetReclaimBytes: 256 * 1_048_576) ?? 0
            let metalMB = metalAllocator?.purgeVolatileResources() ?? 0
            bytesFreed += Int(metalMB * 1_048_576.0)
            responder?.onRequestJITCacheCompaction(keepRatio: 0.65)
            responder?.onRequestGuestGarbageCollection()
            responder?.onRequestMipmapBiasIncrease(newBias: 2)

        case .stage3EmergencyShield:
            // Prevent crash at all costs: flush 512MB to NVMe, compact JIT by 70%, drop internal MetalFX scale
            bytesFreed += swapPool?.evictColdPages(targetReclaimBytes: 512 * 1_048_576) ?? 0
            swapPool?.trimMappedAssetPages()
            let metalMB = metalAllocator?.purgeVolatileResources() ?? 0
            bytesFreed += Int(metalMB * 1_048_576.0)
            responder?.onRequestJITCacheCompaction(keepRatio: 0.30)
            responder?.onRequestGuestGarbageCollection()
            responder?.onRequestDynamicResolutionScaleDrop()
            URLCache.shared.removeAllCachedResponses()
        }

        let reclaimedMB = Double(bytesFreed) / 1_048_576.0
        let postSnap = MachMemoryProbe.captureSnapshot()

        DispatchQueue.main.async {
            self.currentStage = stage
            self.latestTelemetry = postSnap
            self.totalReclaimedMB += reclaimedMB
            if stage == .stage3EmergencyShield {
                self.emergencySavesCount += 1
            }
        }
    }
}
