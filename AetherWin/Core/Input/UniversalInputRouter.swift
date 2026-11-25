// UniversalInputRouter.swift
// AetherWin - Unified Win32 Keyboard, Relative Mouse, XInput Gamepad, and Driving Wheel Router
// Supports Hardware Bluetooth Controllers (PS5 DualSense, Xbox, MFi) + Touch Overlays

import Foundation
import GameController
import UIKit

/// Virtual Windows KeyCodes (`VK_*`) used across DirectX & Unity games
enum WinVirtualKey: UInt16 {
    case backspace = 0x08
    case tab = 0x09
    case enter = 0x0D
    case shift = 0x10
    case control = 0x11
    case menuAlt = 0x12
    case escape = 0x1B
    case space = 0x20
    case left = 0x25, up = 0x26, right = 0x27, down = 0x28

    case key0 = 0x30, key1 = 0x31, key2 = 0x32, key3 = 0x33, key4 = 0x34
    case key5 = 0x35, key6 = 0x36, key7 = 0x37, key8 = 0x38, key9 = 0x39

    case a = 0x41, b = 0x42, c = 0x43, d = 0x44, e = 0x45, f = 0x46
    case g = 0x47, h = 0x48, i = 0x49, j = 0x4A, k = 0x4B, l = 0x4C
    case m = 0x4D, n = 0x4E, o = 0x4F, p = 0x50, q = 0x51, r = 0x52
    case s = 0x53, t = 0x54, u = 0x55, v = 0x56, w = 0x57, x = 0x58
    case y = 0x59, z = 0x5A

    case f1 = 0x70, f2 = 0x71, f3 = 0x72, f4 = 0x73, f5 = 0x74
    case f6 = 0x75, f7 = 0x76, f8 = 0x77, f9 = 0x78, f10 = 0x79
}

/// XInput 360/One Controller State exposed to `xinput1_4.dll` & DirectInput
struct XInputGamepadState: Equatable {
    var leftThumbX: Float = 0
    var leftThumbY: Float = 0
    var rightThumbX: Float = 0
    var rightThumbY: Float = 0
    var leftTrigger: Float = 0   // Brake / Clutch / ADS
    var rightTrigger: Float = 0  // Throttle / Shoot
    var buttonsMask: UInt16 = 0
}

/// Routes both touch HUD controls and physical Bluetooth controllers into Wine Win32 & XInput
final class UniversalInputRouter: ObservableObject {
    @Published private(set) var connectedHardwareControllerName: String?
    @Published private(set) var xinputState = XInputGamepadState()
    @Published private(set) var pressedVirtualKeys: Set<UInt16> = []

    private let haptics = UIImpactFeedbackGenerator(style: .light)

    init() {
        haptics.prepare()
        observeHardwareControllers()
    }

    // MARK: - Win32 Virtual Key & Mouse Injection

    func sendKey(_ key: WinVirtualKey, isDown: Bool, haptic: Bool = true) {
        if isDown {
            pressedVirtualKeys.insert(key.rawValue)
            if haptic { haptics.impactOccurred(intensity: 0.65) }
        } else {
            pressedVirtualKeys.remove(key.rawValue)
        }
    }

    func tapKey(_ key: WinVirtualKey) {
        sendKey(key, isDown: true, haptic: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.sendKey(key, isDown: false, haptic: false)
        }
    }

    func sendRelativeMouseDelta(dx: Float, dy: Float) {
        xinputState.rightThumbX = max(min(dx * 0.05, 1.0), -1.0)
        xinputState.rightThumbY = max(min(-dy * 0.05, 1.0), -1.0)
    }

    func sendMouseClick(leftButton: Bool, isDown: Bool) {
        if isDown { haptics.impactOccurred(intensity: 0.8) }
    }

    // MARK: - Analog Axes (FPS & My Summer Car Driving Wheel/Pedals)

    func updateLeftStick(x: Float, y: Float, mapToWASD: Bool) {
        xinputState.leftThumbX = x
        xinputState.leftThumbY = y

        if mapToWASD {
            sendKey(.w, isDown: y > 0.35, haptic: false)
            sendKey(.s, isDown: y < -0.35, haptic: false)
            sendKey(.a, isDown: x < -0.35, haptic: false)
            sendKey(.d, isDown: x > 0.35, haptic: false)
        }
    }

    func updateDrivingAxes(steering: Float, throttle: Float, brake: Float) {
        xinputState.leftThumbX = steering
        xinputState.rightTrigger = throttle
        xinputState.leftTrigger = brake

        // Also mirror to standard My Summer Car keyboard driving binds if XInput mod isn't installed
        sendKey(.a, isDown: steering < -0.22, haptic: false)
        sendKey(.d, isDown: steering > 0.22, haptic: false)
        sendKey(.w, isDown: throttle > 0.15, haptic: false)
        sendKey(.s, isDown: brake > 0.15, haptic: false)
    }

    // MARK: - Hardware Bluetooth Controller Discovery (PS5 / Xbox / Backbone)

    private func observeHardwareControllers() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let ctrl = note.object as? GCController else { return }
            self?.bindHardwareController(ctrl)
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.connectedHardwareControllerName = GCController.controllers().first?.vendorName
        }

        if let existing = GCController.controllers().first {
            bindHardwareController(existing)
        }
    }

    private func bindHardwareController(_ controller: GCController) {
        connectedHardwareControllerName = controller.vendorName ?? "Bluetooth Gamepad"
        guard let gp = controller.extendedGamepad else { return }

        gp.valueChangedHandler = { [weak self] pad, _ in
            guard let self = self else { return }
            self.xinputState.leftThumbX = pad.leftThumbstick.xAxis.value
            self.xinputState.leftThumbY = pad.leftThumbstick.yAxis.value
            self.xinputState.rightThumbX = pad.rightThumbstick.xAxis.value
            self.xinputState.rightThumbY = pad.rightThumbstick.yAxis.value
            self.xinputState.leftTrigger = pad.leftTrigger.value
            self.xinputState.rightTrigger = pad.rightTrigger.value
        }
    }
}
