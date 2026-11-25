// MachMemoryProbe.swift
// AetherWin - Exact XNU Mach Kernel Footprint & Jetsam Headroom Telemetry
// Engineered for iPhone 13 (4GB LPDDR4X Unified Memory, 16KB Hardware Pages)

import Foundation
import Darwin

/// Exact snapshot of iPhone 13 physical memory and Jetsam budget
struct MemoryTelemetrySnapshot: Codable, Equatable {
    /// Current dirty physical memory counted by iOS Jetsam (`phys_footprint`)
    let footprintBytes: UInt64
    /// Exact bytes remaining before iOS Jetsam kills the app (`os_proc_available_memory`)
    let availableHeadroomBytes: UInt64
    /// Resident memory size (includes clean file-backed mmap pages)
    let residentBytes: UInt64
    /// Virtual address space reserved (Wine64 + WOW64 + NVMe swap)
    let virtualBytes: UInt64
    /// Timestamp of reading
    let timestamp: Date

    var footprintMB: Double { Double(footprintBytes) / 1_048_576.0 }
    var availableHeadroomMB: Double { Double(availableHeadroomBytes) / 1_048_576.0 }
    var residentMB: Double { Double(residentBytes) / 1_048_576.0 }
    var totalBudgetMB: Double { footprintMB + availableHeadroomMB }

    /// Percentage of total allowed Jetsam budget consumed (0.0 - 1.0)
    var pressureRatio: Double {
        let total = totalBudgetMB
        guard total > 0 else { return 0 }
        return min(max(footprintMB / total, 0.0), 1.0)
    }

    static let zero = MemoryTelemetrySnapshot(
        footprintBytes: 0,
        availableHeadroomBytes: 2_800 * 1_048_576,
        residentBytes: 0,
        virtualBytes: 0,
        timestamp: Date()
    )
}

/// Queries Darwin Mach `task_vm_info` and `os_proc_available_memory` with zero allocations
enum MachMemoryProbe {
    /// Hardware page size on Apple A15 Bionic (16,384 bytes)
    static let pageSizeA15: Int = Int(vm_kernel_page_size)

    private static let availableMemSym: (@convention(c) () -> Int)? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "os_proc_available_memory") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) () -> Int).self)
    }()

    private static func c_os_proc_available_memory() -> Int {
        availableMemSym?() ?? 0
    }

    /// Reads real-time Jetsam metrics directly from the XNU kernel
    static func captureSnapshot() -> MemoryTelemetrySnapshot {
        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let kr: kern_return_t = withUnsafeMutablePointer(to: &vmInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }

        let footprint = (kr == KERN_SUCCESS) ? UInt64(vmInfo.phys_footprint) : 0
        let resident = (kr == KERN_SUCCESS) ? UInt64(vmInfo.resident_size) : 0
        let virtualSize = (kr == KERN_SUCCESS) ? UInt64(vmInfo.virtual_size) : 0

        let rawAvailable = c_os_proc_available_memory()
        let available = rawAvailable > 0 ? UInt64(rawAvailable) : 512 * 1_048_576

        return MemoryTelemetrySnapshot(
            footprintBytes: footprint,
            availableHeadroomBytes: available,
            residentBytes: resident,
            virtualBytes: virtualSize,
            timestamp: Date()
        )
    }

    /// Checks whether `com.apple.developer.kernel.increased-memory-limit` is active on this iPhone 13
    static var isIncreasedMemoryEntitlementActive: Bool {
        let snap = captureSnapshot()
        // Standard limit on 4GB iPhone 13 is ~2098MB; increased limit unlocks ~2850-3072MB
        return snap.totalBudgetMB > 2300.0
    }
}
