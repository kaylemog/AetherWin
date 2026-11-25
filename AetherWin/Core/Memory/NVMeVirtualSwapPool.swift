// NVMeVirtualSwapPool.swift
// AetherWin - File-Backed Demand-Paged Virtual Memory & Unity Asset Zero-Copy Streamer
// Prevents iOS Jetsam OOM crashes in My Summer Car & MiSide on 4GB iPhone 13

import Foundation
import Darwin

/// Represents a virtual allocation backed by an NVMe memory-mapped swap file
struct SwapAllocation {
    let id: UUID
    let baseAddress: UnsafeMutableRawPointer
    let byteLength: Int
    let fileOffset: off_t
    var lastAccessTick: UInt64
    var isEvictedToNVMe: Bool
}

/// Implements user-space NVMe demand paging using XNU `mmap(MAP_SHARED)` + `madvise`
/// Clean file-backed pages are reclaimable by XNU and DO NOT count toward Jetsam kills!
final class NVMeVirtualSwapPool {
    private let swapDirectoryURL: URL
    private var swapFileDescriptor: Int32 = -1
    private var swapFileURL: URL?
    private(set) var capacityBytes: Int = 0
    private var nextOffset: Int = 0

    private var allocations: [UUID: SwapAllocation] = [:]
    private var mappedAssets: [URL: (ptr: UnsafeMutableRawPointer, size: Int, fd: Int32)] = [:]
    private let lock = NSLock()
    private var accessCounter: UInt64 = 0

    /// Statistics
    private(set) var activeSwappedBytes: Int = 0
    private(set) var zeroCopyAssetBytes: Int = 0

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.swapDirectoryURL = caches.appendingPathComponent("AetherNVMeSwap", isDirectory: true)
    }

    deinit {
        shutdown()
    }

    /// Initializes the sparse NVMe swap file (e.g., 2048 MB for My Summer Car / MiSide)
    func initializePool(sizeMB: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        shutdownLocked()

        try FileManager.default.createDirectory(at: swapDirectoryURL, withIntermediateDirectories: true)
        let fileURL = swapDirectoryURL.appendingPathComponent("win_virtual_pagefile.sys")
        self.swapFileURL = fileURL

        // Open RW, create, truncate existing stale swap
        let fd = open(fileURL.path, O_RDWR | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw NSError(domain: "AetherSwap", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to open NVMe swap file"
            ])
        }

        // Disable macOS/iOS unified buffer cache bloat where supported via F_NOCACHE = 48
        _ = fcntl(fd, F_NOCACHE, 1)

        let alignedBytes = alignTo16KB(sizeMB * 1_048_576)
        guard ftruncate(fd, off_t(alignedBytes)) == 0 else {
            close(fd)
            throw NSError(domain: "AetherSwap", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Insufficient storage for \(sizeMB)MB NVMe virtual swap"
            ])
        }

        self.swapFileDescriptor = fd
        self.capacityBytes = alignedBytes
        self.nextOffset = 0
    }

    /// Allocates guest Win32 `VirtualAlloc` heap backed by the NVMe pagefile instead of dirty anonymous RAM
    func allocatePageableRegion(bytes: Int) -> SwapAllocation? {
        lock.lock()
        defer { lock.unlock() }

        guard swapFileDescriptor >= 0 else { return nil }
        let alignedLen = alignTo16KB(bytes)
        guard nextOffset + alignedLen <= capacityBytes else { return nil }

        let offset = off_t(nextOffset)
        let ptr = mmap(
            nil,
            alignedLen,
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            swapFileDescriptor,
            offset
        )

        guard ptr != MAP_FAILED, let validPtr = ptr else { return nil }

        // Advise kernel of random page access pattern typical for Mono/IL2CPP heaps
        madvise(validPtr, alignedLen, MADV_RANDOM)

        nextOffset += alignedLen
        accessCounter += 1

        let alloc = SwapAllocation(
            id: UUID(),
            baseAddress: validPtr,
            byteLength: alignedLen,
            fileOffset: offset,
            lastAccessTick: accessCounter,
            isEvictedToNVMe: false
        )
        allocations[alloc.id] = alloc
        return alloc
    }

    /// Flushes dirty pages to NVMe and marks them clean/reclaimable so Jetsam footprint drops immediately
    @discardableResult
    func evictColdPages(targetReclaimBytes: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var reclaimed = 0
        let sorted = allocations.values
            .filter { !$0.isEvictedToNVMe }
            .sorted { $0.lastAccessTick < $1.lastAccessTick }

        for var item in sorted {
            guard reclaimed < targetReclaimBytes else { break }

            // Flush modified pages asynchronously to NVMe flash and release physical RAM backing
            msync(item.baseAddress, item.byteLength, MS_ASYNC)
            madvise(item.baseAddress, item.byteLength, MADV_DONTNEED)

            item.isEvictedToNVMe = true
            allocations[item.id] = item
            reclaimed += item.byteLength
            activeSwappedBytes += item.byteLength
        }

        return reclaimed
    }

    /// Zero-copy read-only memory map for huge Unity `.assets` / `.ress` / `.pak` files
    /// Crucial for My Summer Car (`sharedassets0.assets`) and MiSide (`resources.assets`)!
    func mapGameAssetReadOnly(fileURL: URL) -> UnsafeRawBufferPointer? {
        lock.lock()
        defer { lock.unlock() }

        if let existing = mappedAssets[fileURL] {
            return UnsafeRawBufferPointer(start: existing.ptr, count: existing.size)
        }

        let fd = open(fileURL.path, O_RDONLY)
        guard fd >= 0 else { return nil }

        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size > 0 else {
            close(fd)
            return nil
        }

        let size = Int(st.st_size)
        let ptr = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0)
        guard ptr != MAP_FAILED, let validPtr = ptr else {
            close(fd)
            return nil
        }

        // Read-only clean file mappings NEVER count against iOS Jetsam dirty memory!
        madvise(validPtr, size, MADV_WILLNEED)
        mappedAssets[fileURL] = (validPtr, size, fd)
        zeroCopyAssetBytes += size

        return UnsafeRawBufferPointer(start: validPtr, count: size)
    }

    /// Drops cached clean asset pages from resident RAM when headroom gets tight
    func trimMappedAssetPages() {
        lock.lock()
        defer { lock.unlock() }

        for (_, asset) in mappedAssets {
            madvise(asset.ptr, asset.size, MADV_DONTNEED)
        }
    }

    func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        shutdownLocked()
    }

    private func shutdownLocked() {
        for (_, alloc) in allocations {
            munmap(alloc.baseAddress, alloc.byteLength)
        }
        allocations.removeAll()

        for (_, asset) in mappedAssets {
            munmap(asset.ptr, asset.size)
            close(asset.fd)
        }
        mappedAssets.removeAll()

        if swapFileDescriptor >= 0 {
            close(swapFileDescriptor)
            swapFileDescriptor = -1
        }
        if let url = swapFileURL {
            try? FileManager.default.removeItem(at: url)
            swapFileURL = nil
        }
        activeSwappedBytes = 0
        zeroCopyAssetBytes = 0
        nextOffset = 0
    }

    @inline(__always)
    private func alignTo16KB(_ size: Int) -> Int {
        let mask = 16384 - 1
        return (max(size, 16384) + mask) & ~mask
    }
}
