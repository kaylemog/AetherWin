// MemoryDiagnosticsView.swift
// AetherWin - Real-Time iPhone 13 Jetsam Footprint, Entitlement, and NVMe Swap Dashboard

import SwiftUI

struct MemoryDiagnosticsView: View {
    @StateObject private var memoryGuard = JetsamMemoryGuard.shared
    @StateObject private var jitAllocator = APRRJITAllocator.shared
    @State private var liveSnapshot = MachMemoryProbe.captureSnapshot()
    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section("Live XNU Jetsam Telemetry (iPhone 13)") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Dirty Footprint")
                        Spacer()
                        Text(String(format: "%.1f MB / %.0f MB", liveSnapshot.footprintMB, liveSnapshot.totalBudgetMB))
                            .font(.subheadline.monospacedDigit().bold())
                    }

                    ProgressView(value: liveSnapshot.pressureRatio)
                        .tint(liveSnapshot.availableHeadroomMB > 450 ? .green : .orange)

                    HStack {
                        Text("Available Headroom Before Crash:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f MB", liveSnapshot.availableHeadroomMB))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)

                row("Defense Governor Stage", value: memoryGuard.currentStage.rawValue)
                row("Emergency Crash Saves", value: "\(memoryGuard.emergencySavesCount)")
                row("Total RAM Reclaimed to NVMe", value: String(format: "%.1f MB", memoryGuard.totalReclaimedMB))
            }

            Section("Hardware Capabilities & Entitlements") {
                row("3.0 GB Extended RAM Limit",
                    value: MachMemoryProbe.isIncreasedMemoryEntitlementActive ? "Active" : "Standard (2.05 GB)")
                row("Hardware Page Size (A15)", value: "\(MachMemoryProbe.pageSizeA15 / 1024) KB")
                row("APRR Hardware JIT Status", value: jitAllocator.isJITActive ? "Enabled" : "Requires AltJIT/SideStore")
                row("JIT Code Cache Slab", value: String(format: "%.1f / %.0f MB", jitAllocator.usedCacheMB, jitAllocator.maxCacheMB))
            }

            Section("Why My Summer Car & MiSide Don't Crash") {
                Label("Zero-Copy `mmap` keeps `.assets` files out of dirty RAM", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                Label("A15 `.memoryless` Depth/Stencil uses 0 MB of system RAM", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                Label("Sparse NVMe Pagefile evicts cold Win32 VirtualAlloc pages", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                Label("Mono GC Soft-Heap Cap stops PlayMaker FSM memory runaway", systemImage: "checkmark.shield.fill")
                    .font(.caption)
            }
        }
        .navigationTitle("iPhone 13 Shield")
        .onReceive(refreshTimer) { _ in
            liveSnapshot = MachMemoryProbe.captureSnapshot()
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.secondary)
        }
    }
}
