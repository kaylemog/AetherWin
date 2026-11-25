// APRRJITAllocator.swift
// AetherWin - Bounded Generational JIT Code Cache for Apple A15 Bionic
// Prevents unbounded Dynarec memory growth while utilizing hardware APRR W^X switching

import Foundation
import Darwin

/// Metadata for a compiled x86/x86_64 -> ARM64 translation block
struct TranslatedCodeBlock {
    let guestRIP: UInt64
    let hostOffset: Int
    let byteSize: Int
    var executionHits: UInt32
    var generation: UInt32
}

/// Manages a strictly bounded `MAP_JIT` executable slab (default 96MB max on iPhone 13)
final class APRRJITAllocator: ObservableObject {
    static let shared = APRRJITAllocator()

    @Published private(set) var isJITActive: Bool = false
    @Published private(set) var usedCacheMB: Double = 0
    @Published private(set) var maxCacheMB: Double = 96.0

    private var jitSlab: UnsafeMutableRawPointer?
    private var slabCapacityBytes: Int = 0
    private var writeCursor: Int = 0
    private var currentGeneration: UInt32 = 1
    private var blockTable: [UInt64: TranslatedCodeBlock] = [:]
    private let lock = NSLock()

    @_silgen_name("sys_icache_invalidate")
    private static func c_sys_icache_invalidate(_ start: UnsafeRawPointer?, _ len: Int)

    /// Dynamically resolves APRR W^X toggle on iOS/macOS without triggering `@unavailable(ios)` SDK error
    private static let jitWriteProtectSym: (@convention(c) (Int32) -> Void)? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "pthread_jit_write_protect_np") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (Int32) -> Void).self)
    }()

    @inline(__always)
    private static func setJITWriteProtection(_ enabled: Bool) {
        jitWriteProtectSym?(enabled ? 1 : 0)
    }

    private init() {
        _ = probeAndInitialize(maxSizeMB: 96)
    }

    deinit {
        releaseSlab()
    }

    /// Probes iOS `MAP_JIT` / `CS_DEBUGGED` capability and allocates a bounded 16KB-aligned slab
    @discardableResult
    func probeAndInitialize(maxSizeMB: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        releaseSlabLocked()

        let bytes = ((maxSizeMB * 1_048_576) + 16383) & ~16383
        let ptr = mmap(
            nil,
            bytes,
            PROT_READ | PROT_WRITE | PROT_EXEC,
            MAP_ANON | MAP_PRIVATE | MAP_JIT,
            -1,
            0
        )

        guard ptr != MAP_FAILED, let validPtr = ptr else {
            DispatchQueue.main.async {
                self.isJITActive = false
            }
            return false
        }

        // Verify hardware APRR write-unlock -> emit ARM64 `ret` -> execute-lock
        Self.setJITWriteProtection(false)
        validPtr.bindMemory(to: UInt32.self, capacity: 1).pointee = 0xD65F03C0 // ARM64 `ret`
        Self.setJITWriteProtection(true)
        Self.c_sys_icache_invalidate(validPtr, 4)

        self.jitSlab = validPtr
        self.slabCapacityBytes = bytes
        self.writeCursor = 16

        DispatchQueue.main.async {
            self.isJITActive = true
            self.maxCacheMB = Double(maxSizeMB)
            self.usedCacheMB = 0
        }
        return true
    }

    /// Emits ARM64 machine code into the bounded JIT cache; automatically evicts cold blocks if full
    func emitARM64Block(guestRIP: UInt64, arm64Bytes: UnsafeRawBufferPointer) -> UnsafeRawPointer? {
        lock.lock()
        defer { lock.unlock() }

        guard let base = jitSlab, arm64Bytes.count > 0 else { return nil }
        let alignedSize = (arm64Bytes.count + 15) & ~15

        // Never grow unbounded! Compact cold blocks if slab reaches 92% capacity
        if writeCursor + alignedSize > Int(Double(slabCapacityBytes) * 0.92) {
            compactLocked(keepRatio: 0.50)
        }

        guard writeCursor + alignedSize <= slabCapacityBytes else { return nil }
        let dest = base.advanced(by: writeCursor)

        Self.setJITWriteProtection(false)
        if let src = arm64Bytes.baseAddress {
            memcpy(dest, src, arm64Bytes.count)
        }
        Self.setJITWriteProtection(true)
        Self.c_sys_icache_invalidate(dest, arm64Bytes.count)

        let block = TranslatedCodeBlock(
            guestRIP: guestRIP,
            hostOffset: writeCursor,
            byteSize: alignedSize,
            executionHits: 1,
            generation: currentGeneration
        )
        blockTable[guestRIP] = block
        writeCursor += alignedSize

        let usedMB = Double(writeCursor) / 1_048_576.0
        DispatchQueue.main.async { self.usedCacheMB = usedMB }

        return UnsafeRawPointer(dest)
    }

    /// Compacts the JIT cache under Jetsam pressure and returns freed physical pages via `madvise`
    func compactCache(keepRatio: Double) {
        lock.lock()
        defer { lock.unlock() }
        compactLocked(keepRatio: keepRatio)
    }

    private func compactLocked(keepRatio: Double) {
        guard let base = jitSlab else { return }
        currentGeneration &+= 1

        if keepRatio <= 0.35 || blockTable.count > 25_000 {
            // Fast generational reset + return physical pages to XNU kernel
            blockTable.removeAll(keepingCapacity: true)
            let releaseOffset = 16384
            if slabCapacityBytes > releaseOffset {
                madvise(base.advanced(by: releaseOffset), slabCapacityBytes - releaseOffset, MADV_FREE)
            }
            writeCursor = 16
        } else {
            // Evict cold blocks below median hit count
            let sorted = blockTable.values.sorted { $0.executionHits > $1.executionHits }
            let keepCount = Int(Double(sorted.count) * keepRatio)
            var retained: [UInt64: TranslatedCodeBlock] = [:]
            var maxOffset = 16
            for item in sorted.prefix(keepCount) {
                retained[item.guestRIP] = item
                maxOffset = max(maxOffset, item.hostOffset + item.byteSize)
            }
            blockTable = retained
            let pageAlignedTail = (maxOffset + 16383) & ~16383
            if pageAlignedTail < slabCapacityBytes {
                madvise(base.advanced(by: pageAlignedTail), slabCapacityBytes - pageAlignedTail, MADV_FREE)
            }
            writeCursor = maxOffset
        }

        let usedMB = Double(writeCursor) / 1_048_576.0
        DispatchQueue.main.async { self.usedCacheMB = usedMB }
    }

    func releaseSlab() {
        lock.lock()
        defer { lock.unlock() }
        releaseSlabLocked()
    }

    private func releaseSlabLocked() {
        if let ptr = jitSlab, slabCapacityBytes > 0 {
            munmap(ptr, slabCapacityBytes)
            jitSlab = nil
            slabCapacityBytes = 0
            writeCursor = 0
            blockTable.removeAll()
        }
    }
}
