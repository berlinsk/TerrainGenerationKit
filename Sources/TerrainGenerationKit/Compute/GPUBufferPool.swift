import Foundation
import Metal

public final class GPUBufferPool: @unchecked Sendable {

    private let device: MTLDevice
    private var pool: [Int: [MTLBuffer]] = [:]
    private let lock = NSLock()

    init(device: MTLDevice) {
        self.device = device
    }

    func acquire(byteLength: Int) -> MTLBuffer? {
        let aligned = alignSize(byteLength)
        lock.lock()
        if var available = pool[aligned], !available.isEmpty {
            let buffer = available.removeLast()
            pool[aligned] = available
            lock.unlock()
            return buffer
        }
        lock.unlock()
        return device.makeBuffer(length: aligned, options: .storageModeShared)
    }

    func release(_ buffer: MTLBuffer) {
        let size = buffer.length
        lock.lock()
        pool[size, default: []].append(buffer)
        lock.unlock()
    }

    func drain() {
        lock.lock()
        pool.removeAll()
        lock.unlock()
    }

    private func alignSize(_ size: Int) -> Int {
        let pageSize = 16384
        return ((size + pageSize - 1) / pageSize) * pageSize
    }
}
