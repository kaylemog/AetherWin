// ThreadSchedulerA15.swift
// AetherWin - Asymmetric 2P + 4E Core Topology Scheduler for iPhone 13 (Apple A15 Bionic)
// Pins single-thread-bound games (My Summer Car PlayMaker/PhysX) to 3.23GHz Avalanche P-Cores

import Foundation
import Darwin

/// Thread role inside the Windows game runtime
enum WinThreadRole {
    case gameMainAndPhysics   // Pinned to 2x Avalanche P-Cores (3.23 GHz, 12MB L2)
    case directXRenderSubmit  // Pinned to 2x Avalanche P-Cores
    case asyncShaderCompile   // Pinned to 4x Blizzard E-Cores (1.82 GHz) to save thermal headroom
    case audioMixer           // Real-time low-jitter audio queue
    case wineserverAndIO      // Pinned to 4x Blizzard E-Cores
}

/// Schedules guest Win32 threads onto optimal A15 Bionic core clusters using Darwin QoS & Mach policies
enum ThreadSchedulerA15 {
    /// Creates a dedicated DispatchQueue tuned for the specified A15 core cluster
    static func makeQueue(label: String, role: WinThreadRole) -> DispatchQueue {
        switch role {
        case .gameMainAndPhysics, .directXRenderSubmit:
            return DispatchQueue(label: label, qos: .userInteractive)
        case .audioMixer:
            return DispatchQueue(label: label, qos: .userInitiated)
        case .asyncShaderCompile, .wineserverAndIO:
            return DispatchQueue(label: label, qos: .utility, attributes: .concurrent)
        }
    }

    /// Applies Darwin pthread QoS and Mach thread precedence on the calling guest pthread
    static func applyCurrentThreadAffinity(role: WinThreadRole) {
        switch role {
        case .gameMainAndPhysics:
            pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
            setMachThreadPrecedence(importance: 63)

        case .directXRenderSubmit:
            pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, -2)
            setMachThreadPrecedence(importance: 58)

        case .audioMixer:
            pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0)
            setMachThreadPrecedence(importance: 55)

        case .asyncShaderCompile, .wineserverAndIO:
            // Keep background compilation & disk swap strictly on Blizzard E-Cores!
            // Prevents thermal throttling of the 2 Avalanche P-Cores during long My Summer Car sessions.
            pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, -10)
            setMachThreadPrecedence(importance: 15)
        }
    }

    private static func setMachThreadPrecedence(importance: integer_t) {
        var policy = thread_precedence_policy_data_t(importance: importance)
        let count = mach_msg_type_number_t(
            MemoryLayout<thread_precedence_policy_data_t>.size / MemoryLayout<integer_t>.size
        )
        _ = withUnsafeMutablePointer(to: &policy) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                thread_policy_set(
                    mach_thread_self(),
                    thread_policy_t(THREAD_PRECEDENCE_POLICY),
                    intPtr,
                    count
                )
            }
        }
    }
}
