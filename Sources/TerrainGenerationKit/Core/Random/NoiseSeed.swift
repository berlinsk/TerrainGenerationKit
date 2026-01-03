import Foundation

public struct NoiseSeed: Sendable {
    
    public let baseSeed: UInt64
    
    public init(_ seed: UInt64) {
        self.baseSeed = seed
    }
    
    public func derive(_ offset: Int) -> UInt64 {
        var h = baseSeed &+ UInt64(offset) &* 0x9e3779b97f4a7c15
        h = (h ^ (h >> 30)) &* 0xbf58476d1ce4e5b9
        h = (h ^ (h >> 27)) &* 0x94d049bb133111eb
        return h ^ (h >> 31)
    }
    
    public func deriveRandom(_ offset: Int) -> SeededRandom {
        SeededRandom(seed: derive(offset))
    }
}
