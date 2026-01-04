import Foundation
import simd

public struct NoiseParameters: Codable, Sendable, Equatable {
    
    public var type: NoiseType
    public var octaves: Int
    public var frequency: Float
    public var persistence: Float
    public var lacunarity: Float
    public var amplitude: Float
    public var offset: SIMD2<Float>
    
    public init(
        type: NoiseType = .simplex,
        octaves: Int = 6,
        frequency: Float = 0.005,
        persistence: Float = 0.5,
        lacunarity: Float = 2.0,
        amplitude: Float = 1.0,
        offset: SIMD2<Float> = .zero
    ) {
        self.type = type
        self.octaves = octaves
        self.frequency = frequency
        self.persistence = persistence
        self.lacunarity = lacunarity
        self.amplitude = amplitude
        self.offset = offset
    }
    
    public static let `default` = NoiseParameters()
    
    public static let continental = NoiseParameters(
        type: .simplex,
        octaves: 8,
        frequency: 0.003,
        persistence: 0.55,
        lacunarity: 2.1,
        amplitude: 1.2
    )
    
    public static let archipelago = NoiseParameters(
        type: .ridged,
        octaves: 5,
        frequency: 0.008,
        persistence: 0.6,
        lacunarity: 2.5,
        amplitude: 0.9
    )
}
