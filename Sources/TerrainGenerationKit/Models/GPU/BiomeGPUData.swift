import Foundation
import simd

public struct BiomeGPUData {
    
    public var baseColor: SIMD4<Float>
    public var secondaryColor: SIMD4<Float>
    public var textureScale: Float
    public var roughness: Float
    public var padding: SIMD2<Float>
    
    public init(
        baseColor: SIMD4<Float>,
        secondaryColor: SIMD4<Float>,
        textureScale: Float,
        roughness: Float
    ) {
        self.baseColor = baseColor
        self.secondaryColor = secondaryColor
        self.textureScale = textureScale
        self.roughness = roughness
        self.padding = .zero
    }
    
    public static func from(_ biome: BiomeType) -> BiomeGPUData {
        BiomeGPUData(
            baseColor: biome.baseColor,
            secondaryColor: biome.secondaryColor,
            textureScale: biome == .ocean ? 0.1 : 0.3,
            roughness: biome.isWater ? 0.1 : 0.8
        )
    }
}
