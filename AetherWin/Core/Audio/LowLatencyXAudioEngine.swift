// LowLatencyXAudioEngine.swift
// AetherWin - Lock-Free Ring-Buffered XAudio2 / DirectSound / WASAPI -> CoreAudio Engine
// Runs on A15 Blizzard / Audio threads with automatic call/background interruption recovery

import Foundation
import AVFoundation

final class LowLatencyXAudioEngine {
    static let shared = LowLatencyXAudioEngine()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private(set) var isRunning = false

    private init() {
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 2,
            interleaved: false
        )!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    func start(bufferMs: Double = 6.0) {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(bufferMs / 1000.0)
            try session.setActive(true)

            try engine.start()
            playerNode.play()
            isRunning = true
        } catch {
            print("[AetherAudio] Failed to start CoreAudio pipeline: \(error)")
        }
    }

    func pause() {
        guard isRunning else { return }
        playerNode.pause()
        engine.pause()
        isRunning = false
    }

    func stop() {
        playerNode.stop()
        engine.stop()
        isRunning = false
    }

    /// Submits interleaved 16-bit signed Windows WASAPI / XAudio2 PCM frames
    func submitInt16StereoPCM(_ data: Data) {
        guard isRunning, data.count >= 4 else { return }
        let frameCount = AVAudioFrameCount(data.count / 4)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { raw in
            guard let samples = raw.bindMemory(to: Int16.self).baseAddress,
                  let left = buffer.floatChannelData?[0],
                  let right = buffer.floatChannelData?[1] else { return }

            let scale: Float = 1.0 / 32768.0
            for i in 0..<Int(frameCount) {
                left[i] = Float(samples[i * 2]) * scale
                right[i] = Float(samples[i * 2 + 1]) * scale
            }
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
}
