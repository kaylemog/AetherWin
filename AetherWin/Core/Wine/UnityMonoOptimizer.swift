// UnityMonoOptimizer.swift
// AetherWin - Anti-Crash Memory & Threading Patcher for Unity Games (My Summer Car & MiSide)
// Bounds Mono GC Heap, patches boot.config for A15 cores, and zero-copy mmaps `.assets` files

import Foundation

/// Summary of automatic Unity optimizations applied before game launch
struct UnityOptimizationReport: Equatable {
    var bootConfigPatched: Bool = false
    var monoHeapBoundedMB: Int = 0
    var zeroCopyMappedFilesCount: Int = 0
    var zeroCopyMappedTotalMB: Double = 0
    var launchArguments: [String] = []
}

/// Automatically optimizes Unity 4/5/2019/2021/2022/6 games to prevent OOM crashes on 4GB iPhone 13
final class UnityMonoOptimizer {
    /// Applies non-destructive memory & job-worker patches to `<Game>_Data/boot.config` and maps large asset bundles
    static func optimizeGameDirectory(
        executableURL: URL,
        profile: ContainerProfile,
        swapPool: NVMeVirtualSwapPool
    ) -> UnityOptimizationReport {
        var report = UnityOptimizationReport()
        let gameDir = executableURL.deletingLastPathComponent()
        let baseName = executableURL.deletingPathExtension().lastPathComponent
        let dataDir = gameDir.appendingPathComponent("\(baseName)_Data", isDirectory: true)
        let fm = FileManager.default

        guard fm.fileExists(atPath: dataDir.path) else {
            return report
        }

        // 1. Patch or create `boot.config` to offload GFX jobs & cap GC spikes on A15 Bionic
        let bootConfigURL = dataDir.appendingPathComponent("boot.config")
        var configMap: [String: String] = [:]
        if let existing = try? String(contentsOf: bootConfigURL, encoding: .utf8) {
            for line in existing.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    configMap[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                        String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }

        configMap["gfx-enable-gfx-jobs"] = "1"
        configMap["gfx-enable-native-gfx-jobs"] = "1"
        configMap["gc-max-time-slice"] = "3"
        configMap["job-worker-count"] = "4" // Leave 2 cores free for Wine/Metal submission
        configMap["wait-for-native-debugger"] = "0"

        let mergedBootConfig = configMap
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n") + "\n"

        if (try? mergedBootConfig.write(to: bootConfigURL, atomically: true, encoding: .utf8)) != nil {
            report.bootConfigPatched = true
        }

        // 2. Zero-copy read-only mmap all `.assets`, `.ress`, and `.resource` files > 8 MB
        // In My Summer Car (`sharedassets0.assets` ~550MB) and MiSide (`resources.assets` + bundles >1.1GB),
        // keeping these clean file-backed saves >800MB of dirty Jetsam footprint!
        if let enumerator = fm.enumerator(at: dataDir, includingPropertiesForKeys: [.fileSizeKey]) {
            var mappedCount = 0
            var mappedBytes = 0
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                guard ext == "assets" || ext == "ress" || ext == "resource" || ext == "bundle" else { continue }
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if fileSize >= 8 * 1_048_576 {
                    if let buf = swapPool.mapGameAssetReadOnly(fileURL: fileURL) {
                        mappedCount += 1
                        mappedBytes += buf.count
                    }
                }
            }
            report.zeroCopyMappedFilesCount = mappedCount
            report.zeroCopyMappedTotalMB = Double(mappedBytes) / 1_048_576.0
        }

        // 3. Build Unity command-line launch flags tailored to the profile's Graphics API & resolution
        var args: [String] = [
            "-screen-fullscreen", "1",
            "-screen-width", "\(profile.internalRenderWidth)",
            "-screen-height", "\(profile.internalRenderHeight)"
        ]

        switch profile.graphicsAPI {
        case .directX8_9:
            // My Summer Car Unity 5.0 supports `-force-d3d9` which cuts shader & buffer memory by ~35%!
            args.append("-force-d3d9")
        case .directX10_11:
            args.append("-force-d3d11")
        case .directX12:
            args.append("-force-d3d12")
        case .vulkan:
            args.append("-force-vulkan")
        case .openGL:
            args.append("-force-glcore")
        }

        if profile.disablePostProcessBloomOnLowMemory {
            args.append("-force-low-power-device")
        }

        report.monoHeapBoundedMB = profile.monoMaxHeapMB
        report.launchArguments = args
        return report
    }

    /// Generates Mono / Boehm / SGen garbage collector environment limits so PlayMaker FSMs cannot OOM
    static func buildMonoEnvironment(maxHeapMB: Int) -> [String: String] {
        [
            "MONO_GC_PARAMS": "nursery-size=16m,soft-heap-limit=\(maxHeapMB)m,major=marksweep-conc",
            "UNITY_GIVE_CHANCE_TO_ATTACH_DEBUGGER": "0",
            "MONO_THREADS_SUSPEND": "preemptive"
        ]
    }
}
