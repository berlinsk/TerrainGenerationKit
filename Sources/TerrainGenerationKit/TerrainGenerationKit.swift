import Foundation
import simd

public enum TerrainGenerationKit {
    public static let version = "1.0.0"
    
    public static func createGenerator() -> MapGenerator {
        return MapGenerator()
    }
}

@_exported import struct simd.SIMD2
@_exported import struct simd.SIMD3
@_exported import struct simd.SIMD4
