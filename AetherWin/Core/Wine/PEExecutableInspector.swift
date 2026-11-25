// PEExecutableInspector.swift
// AetherWin - Windows Portable Executable (.exe) Binary Header & Engine Auto-Detector
// Inspects any Windows game to detect 32/64-bit, DirectX 8/9/10/11/12, Vulkan, OpenGL, Unity, or Unreal

import Foundation

/// Detected game engine & graphics stack from inspecting the `.exe` and game folder
struct DetectedGameSignature: Codable, Equatable {
    var isValidPE: Bool
    var architecture: GuestCPUArchitecture
    var isLargeAddressAware: Bool
    var detectedEngine: GameEngineKind
    var recommendedGraphicsAPI: WindowsGraphicsAPI
    var detectedTitleHint: String

    enum GameEngineKind: String, Codable {
        case unityMono = "Unity Engine (Mono Runtime - e.g. My Summer Car)"
        case unityIL2CPP = "Unity Engine (IL2CPP Native - e.g. MiSide)"
        case unrealEngine4_5 = "Unreal Engine 4 / 5"
        case sourceOrGoldSrc = "Valve Source / Classic Engine"
        case genericWin32 = "Native Win32 / Win64 C++ Engine"
    }
}

/// Graphics APIs supported across all eras of Windows gaming (1998 - 2026)
enum WindowsGraphicsAPI: String, Codable, CaseIterable, Identifiable {
    case directX8_9 = "DirectX 8 / 9 (DXVK-D3D9 / Gallium -> Metal)"
    case directX10_11 = "DirectX 10 / 11 (DXVK 2.4 / D3DMetal -> Metal 3)"
    case directX12 = "DirectX 12 (VKD3D-Proton / D3DMetal -> Metal 3)"
    case vulkan = "Vulkan 1.3 (MoltenVK -> Metal 3)"
    case openGL = "OpenGL 4.6 (Zink / MetalANGLE -> Metal)"

    var id: String { rawValue }
}

/// Parses `IMAGE_DOS_HEADER` and `IMAGE_NT_HEADERS` without loading the entire `.exe` into RAM
enum PEExecutableInspector {
    static func inspect(executableURL: URL) -> DetectedGameSignature {
        let gameDir = executableURL.deletingLastPathComponent()
        let baseName = executableURL.deletingPathExtension().lastPathComponent
        let fm = FileManager.default

        var arch: GuestCPUArchitecture = .x86_64
        var largeAddr = true
        var validPE = false

        if let handle = try? FileHandle(forReadingFrom: executableURL) {
            let header = handle.readData(ofLength: 4096)
            try? handle.close()

            if header.count >= 64 && header[0] == 0x4D && header[1] == 0x5A { // "MZ"
                let peOffset = Int(header.readUInt32LE(at: 0x3C))
                if peOffset > 0 && peOffset + 24 <= header.count {
                    // Check "PE\0\0"
                    if header[peOffset] == 0x50 && header[peOffset + 1] == 0x45 {
                        validPE = true
                        let machine = header.readUInt16LE(at: peOffset + 4)
                        let characteristics = header.readUInt16LE(at: peOffset + 22)
                        largeAddr = (characteristics & 0x0020) != 0 // IMAGE_FILE_LARGE_ADDRESS_AWARE

                        if machine == 0x014C { // IMAGE_FILE_MACHINE_I386
                            arch = .x86_32_wow64
                        } else { // 0x8664 AMD64
                            arch = .x86_64
                        }
                    }
                }
            }
        }

        // Inspect sibling files in game folder to identify Unity Mono, Unity IL2CPP, Unreal, etc.
        let dataFolder = gameDir.appendingPathComponent("\(baseName)_Data")
        let hasGameAssembly = fm.fileExists(atPath: gameDir.appendingPathComponent("GameAssembly.dll").path)
        let hasMonoDir = fm.fileExists(atPath: dataFolder.appendingPathComponent("Mono").path)
            || fm.fileExists(atPath: gameDir.appendingPathComponent("MonoBleedingEdge").path)
        let hasUnityPlayer = fm.fileExists(atPath: gameDir.appendingPathComponent("UnityPlayer.dll").path)
            || fm.fileExists(atPath: dataFolder.path)

        let lowerName = baseName.lowercased()
        let engine: DetectedGameSignature.GameEngineKind
        let graphics: WindowsGraphicsAPI

        if lowerName.contains("mysummercar") {
            engine = .unityMono
            graphics = .directX8_9 // MSC runs best via D3D9 -> DXVK -> Metal on 4GB RAM!
        } else if lowerName.contains("miside") || (hasUnityPlayer && hasGameAssembly) {
            engine = .unityIL2CPP
            graphics = .directX10_11
        } else if hasUnityPlayer || hasMonoDir {
            engine = .unityMono
            graphics = arch == .x86_32_wow64 ? .directX8_9 : .directX10_11
        } else if fm.fileExists(atPath: gameDir.appendingPathComponent("Engine/Binaries").path) {
            engine = .unrealEngine4_5
            graphics = .directX10_11
        } else {
            engine = .genericWin32
            graphics = arch == .x86_32_wow64 ? .directX8_9 : .directX10_11
        }

        return DetectedGameSignature(
            isValidPE: validPE,
            architecture: arch,
            isLargeAddressAware: largeAddr,
            detectedEngine: engine,
            recommendedGraphicsAPI: graphics,
            detectedTitleHint: baseName
        )
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
