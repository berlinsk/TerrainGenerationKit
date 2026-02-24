import Foundation
import Metal

public final class GPUBuffer<Element>: @unchecked Sendable {

    public let buffer: MTLBuffer
    public let count: Int
    public let width: Int
    public let height: Int

    init(buffer: MTLBuffer, count: Int, width: Int = 0, height: Int = 0) {
        self.buffer = buffer
        self.count = count
        self.width = width
        self.height = height
    }

    public func toArray() -> [Element] {
        let ptr = buffer.contents().bindMemory(to: Element.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    public func copyTo(_ destination: inout [Element]) {
        guard destination.count == count else {
            return
        }
        destination.withUnsafeMutableBufferPointer { dst in
            let src = buffer.contents().bindMemory(to: Element.self, capacity: count)
            dst.baseAddress?.update(from: src, count: count)
        }
    }

    public func copyFrom(_ source: [Element]) {
        guard source.count <= count else {
            return
        }
        source.withUnsafeBufferPointer { src in
            buffer.contents().copyMemory(
                from: src.baseAddress!,
                byteCount: source.count * MemoryLayout<Element>.stride
            )
        }
    }

    public func fill(repeating value: Element) {
        let ptr = buffer.contents().bindMemory(to: Element.self, capacity: count)
        for i in 0..<count {
            ptr[i] = value
        }
    }

    public var byteLength: Int {
        count * MemoryLayout<Element>.stride
    }
}
