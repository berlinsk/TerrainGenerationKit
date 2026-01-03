import Foundation
import simd

public final class SeededRandom: @unchecked Sendable {
    
    private var state: (UInt64, UInt64, UInt64, UInt64)
    private let lock = NSLock()
    
    public init(seed: UInt64) {
        var s = seed
        
        func splitMix64() -> UInt64 {
            s &+= 0x9e3779b97f4a7c15
            var z = s
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
        
        state = (splitMix64(), splitMix64(), splitMix64(), splitMix64())
    }
    
    private func rotl(_ x: UInt64, _ k: Int) -> UInt64 {
        (x << k) | (x >> (64 - k))
    }
    
    public func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        
        let result = rotl(state.1 &* 5, 7) &* 9
        let t = state.1 << 17
        
        state.2 ^= state.0
        state.3 ^= state.1
        state.1 ^= state.2
        state.0 ^= state.3
        
        state.2 ^= t
        state.3 = rotl(state.3, 45)
        
        return result
    }
    
    public func nextFloat() -> Float {
        Float(next() >> 11) * Float(1.0 / 9007199254740992.0)
    }
    
    public func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }
    
    public func nextFloat(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + nextFloat() * (range.upperBound - range.lowerBound)
    }
    
    public func nextInt(in range: ClosedRange<Int>) -> Int {
        let bound = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % bound)
    }
    
    public func nextBool(probability: Float = 0.5) -> Bool {
        nextFloat() < probability
    }
    
    public func nextPoint2D() -> SIMD2<Float> {
        SIMD2<Float>(nextFloat(), nextFloat())
    }
    
    public func nextPoint2D(inX xRange: ClosedRange<Float>, y yRange: ClosedRange<Float>) -> SIMD2<Float> {
        SIMD2<Float>(
            nextFloat(in: xRange),
            nextFloat(in: yRange)
        )
    }
    
    public func nextUnitVector2D() -> SIMD2<Float> {
        let angle = nextFloat() * Float.pi * 2
        return SIMD2<Float>(cos(angle), sin(angle))
    }
    
    public func nextGaussian(mean: Float = 0, stdDev: Float = 1) -> Float {
        let u1 = nextFloat()
        let u2 = nextFloat()
        let z0 = sqrt(-2.0 * log(max(u1, 1e-10))) * cos(2.0 * Float.pi * u2)
        return z0 * stdDev + mean
    }
    
    public func pick<T>(from array: [T]) -> T? {
        guard !array.isEmpty else {
            return nil
        }
        return array[nextInt(in: 0...array.count - 1)]
    }
    
    public func shuffle<T>(_ array: inout [T]) {
        for i in stride(from: array.count - 1, through: 1, by: -1) {
            let j = nextInt(in: 0...i)
            array.swapAt(i, j)
        }
    }
    
    public func shuffled<T>(_ array: [T]) -> [T] {
        var result = array
        shuffle(&result)
        return result
    }
    
    public func fork() -> SeededRandom {
        SeededRandom(seed: next())
    }
}
