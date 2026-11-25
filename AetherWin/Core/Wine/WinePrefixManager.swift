// WinePrefixManager.swift
// AetherWin - Universal Windows XP / 7 / 10 / 11 Container & Registry Builder
// Configures DLL overrides for DXVK (D3D8/9/10/11), VKD3D-Proton (D3D12), D3DMetal, and VC++ Runtime

import Foundation

/// Supported Windows OS personalities inside Wine
enum WindowsOSPersonality: String, Codable, CaseIterable, Identifiable {
    case windows11_23H2 = "Windows 11 (64-bit 23H2)"
    case windows10_22H2 = "Windows 10 (64-bit 22H2)"
    case windows7_SP1 = "Windows 7 SP1 (64-bit / WOW64)"
    case windowsXP_SP3 = "Windows XP SP3 (32-bit Legacy)"

    var id: String { rawValue }
}

/// Manages the isolated Wine container (`drive_c`, registry hives, DirectX/Vulkan DLL routing)
final class WinePrefixManager {
    let containerRootURL: URL

    var driveCURL: URL { containerRootURL.appendingPathComponent("drive_c", isDirectory: true) }
    var system32URL: URL { driveCURL.appendingPathComponent("windows/system32", isDirectory: true) }
    var syswow64URL: URL { driveCURL.appendingPathComponent("windows/syswow64", isDirectory: true) }
    var gamesDirectoryURL: URL { driveCURL.appendingPathComponent("Games", isDirectory: true) }

    init(containerRootURL: URL) {
        self.containerRootURL = containerRootURL
    }

    /// Initializes the complete Windows filesystem layout, save-game folders, and registry overrides
    func provisionPrefix(for profile: ContainerProfile) throws {
        let fm = FileManager.default
        let localLow = driveCURL.appendingPathComponent("users/steamuser/AppData/LocalLow/Amistech/My Summer Car", isDirectory: true)
        let misideSave = driveCURL.appendingPathComponent("users/steamuser/AppData/LocalLow/AIHASTO/MiSideFull", isDirectory: true)
        let documents = driveCURL.appendingPathComponent("users/steamuser/Documents", isDirectory: true)

        for dir in [system32URL, syswow64URL, gamesDirectoryURL, localLow, misideSave, documents] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try writeRegistryHives(profile: profile)
        try deployGraphicsBridgeDLLManifest(profile: profile)
    }

    /// Builds `WINEDLLOVERRIDES` and `DXVK` / `VKD3D` / `MTL_HUD` environment variables
    func buildWineEnvironment(profile: ContainerProfile) -> [String: String] {
        var dllOverrides: [String] = [
            "winemenubuilder.exe=d", // Disable background desktop scanner to save RAM
            "mscoree=n,b",
            "mshtml=d"               // Disable embedded IE engine to save ~140MB RAM!
        ]

        switch profile.graphicsAPI {
        case .directX8_9:
            dllOverrides.append("d3d8,d3d9,ddraw=n,b")
        case .directX10_11:
            dllOverrides.append("dxgi,d3d10core,d3d11,d3dcompiler_47=n,b")
        case .directX12:
            dllOverrides.append("dxgi,d3d12,d3d12core=n,b")
        case .vulkan:
            dllOverrides.append("vulkan-1=n,b")
        case .openGL:
            dllOverrides.append("opengl32=n,b")
        }

        return [
            "WINEPREFIX": containerRootURL.path,
            "WINEARCH": "win64",
            "WINEESYNC": "1",
            "WINEFSYNC": "1",
            "WINE_LARGE_ADDRESS_AWARE": "1", // Essential so 32-bit games can address >2GB VA without crashing!
            "WINEDEBUG": "-all",             // Zero console log I/O overhead
            "WINEDLLOVERRIDES": dllOverrides.joined(separator: ";"),
            "DXVK_ASYNC": "1",               // Async pipeline compilation eliminates shader stutter
            "DXVK_STATE_CACHE": "1",
            "DXVK_FRAME_RATE": "\(profile.targetFPS)",
            "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS": "1",
            "MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS": "0",
            "MVK_CONFIG_RESUME_LOST_DEVICE": "1"
        ]
    }

    private func writeRegistryHives(profile: ContainerProfile) throws {
        let userRegURL = containerRootURL.appendingPathComponent("user.reg")
        let csmtHex = "00000003"
        // Report 2048 MB VRAM to games so Unity doesn't refuse to boot while keeping internal mipmaps bounded
        let vramSizeMB = "\(min(profile.reportedVRAMMB, 2048))"

        let regContents = """
        WINE REGISTRY Version 2

        [Software\\Wine\\Direct3D]
        "csmt"=dword:\(csmtHex)
        "VideoMemorySize"="\(vramSizeMB)"
        "MaxVersionGL"=dword:00040006
        "shader_backend"="glsl"
        "UseGLSL"="enabled"

        [Software\\Wine\\Drivers]
        "Audio"="coreaudio"

        [Control Panel\\Desktop]
        "LogPixels"=dword:00000060
        """
        try regContents.write(to: userRegURL, atomically: true, encoding: .utf8)
    }

    private func deployGraphicsBridgeDLLManifest(profile: ContainerProfile) throws {
        let manifestURL = containerRootURL.appendingPathComponent("graphics_bridge_manifest.json")
        let info: [String: String] = [
            "osPersonality": profile.osPersonality.rawValue,
            "graphicsAPI": profile.graphicsAPI.rawValue,
            "metalFXUpscaling": "\(profile.enableMetalFXUpscaling)",
            "hardwareBCCompression": "\(profile.enableHardwareBCTextures)"
        ]
        let data = try JSONEncoder().encode(info)
        try data.write(to: manifestURL, options: .atomic)
    }
}
