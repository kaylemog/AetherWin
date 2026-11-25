// MetalFXUpscaler.swift
// AetherWin - Apple MetalFX Spatial Upscaling & Dynamic Resolution Scaling for iPhone 13
// Renders MiSide & My Summer Car at 540p-720p and upscales to 2532x1170 Super Retina XDR OLED

import Foundation
import Metal

#if canImport(MetalFX)
import MetalFX
#endif

/// Manages hardware MetalFX spatial upscaling on Apple A15 Bionic
final class MetalFXUpscaler {
    let device: MTLDevice
    private(set) var inputWidth: Int
    private(set) var inputHeight: Int
    private(set) var outputWidth: Int
    private(set) var outputHeight: Int

    #if canImport(MetalFX)
    private var scaler: MTLFXSpatialScaler?
    #endif

    var isHardwareMetalFXActive: Bool {
        #if canImport(MetalFX)
        return scaler != nil
        #else
        return false
        #endif
    }

    init(device: MTLDevice, inputWidth: Int = 1280, inputHeight: Int = 720, outputWidth: Int = 2532, outputHeight: Int = 1170) {
        self.device = device
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        rebuildScaler()
    }

    func updateResolutions(inputWidth: Int, inputHeight: Int, outputWidth: Int, outputHeight: Int) {
        guard inputWidth != self.inputWidth || inputHeight != self.inputHeight ||
              outputWidth != self.outputWidth || outputHeight != self.outputHeight else { return }
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        rebuildScaler()
    }

    /// Drops internal rendering resolution by one step during Stage 3 Jetsam emergency to free framebuffer RAM
    func stepDownInternalResolution() -> (width: Int, height: Int) {
        let nextW: Int
        let nextH: Int
        if inputHeight > 640 {
            nextW = 1136; nextH = 640
        } else {
            nextW = 960; nextH = 540
        }
        updateResolutions(inputWidth: nextW, inputHeight: nextH, outputWidth: outputWidth, outputHeight: outputHeight)
        return (nextW, nextH)
    }

    private func rebuildScaler() {
        #if canImport(MetalFX)
        if #available(iOS 16.0, *) {
            let desc = MTLFXSpatialScalerDescriptor()
            desc.inputWidth = inputWidth
            desc.inputHeight = inputHeight
            desc.outputWidth = outputWidth
            desc.outputHeight = outputHeight
            desc.colorTextureFormat = .bgra8Unorm
            desc.outputTextureFormat = .bgra8Unorm
            desc.colorProcessingMode = .perceptual
            self.scaler = desc.makeSpatialScaler(device: device)
        }
        #endif
    }

    /// Encodes MetalFX upscale pass into the active command buffer
    func encodeUpscale(source: MTLTexture, destination: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        #if canImport(MetalFX)
        if #available(iOS 16.0, *), let scaler = scaler {
            scaler.colorTexture = source
            scaler.outputTexture = destination
            scaler.encode(commandBuffer: commandBuffer)
            return true
        }
        #endif
        return false
    }
}
