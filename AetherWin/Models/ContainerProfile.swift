// ContainerProfile.swift
// AetherWin - Per-Game Hardware, Graphics, Dynarec, and Anti-OOM Configuration Model

import Foundation

/// On-screen touch controller layout tailored to different PC game genres
enum TouchHUDLayout: String, Codable, CaseIterable, Identifiable {
    case fpsDualStick = "3D First-Person / MiSide HUD"
    case drivingAndMechanic = "My Summer Car Driving & Mechanic HUD"
    case pcMouseAndKeyboard = "Desktop Trackpad + Full PC Keyboard"

    var id: String { rawValue }
}

/// Complete container & anti-crash memory profile for a Windows game on iPhone 13
struct ContainerProfile: Codable, Equatable {
    var presetName: String
    var osPersonality: WindowsOSPersonality
    var cpuArchitecture: GuestCPUArchitecture
    var dynarecTuning: DynarecTuningPreset
    var graphicsAPI: WindowsGraphicsAPI

    // Resolution & MetalFX
    var internalRenderWidth: Int
    var internalRenderHeight: Int
    var targetFPS: Int
    var enableMetalFXUpscaling: Bool
    var enableHardwareBCTextures: Bool

    // iPhone 13 Anti-OOM Memory Engineering
    var nvmeVirtualSwapMB: Int
    var jitCodeCacheCapMB: Int
    var monoMaxHeapMB: Int
    var maxTextureDimension: Int
    var reportedVRAMMB: Int
    var enableZeroCopyUnityAssetMmap: Bool
    var disablePostProcessBloomOnLowMemory: Bool

    // Input & Custom Launch Flags
    var touchHUDLayout: TouchHUDLayout
    var customLaunchArguments: String
}
