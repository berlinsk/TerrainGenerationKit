import Foundation

public struct BiomeParameters: Codable, Sendable, Equatable {
    
    public var temperatureVariation: Float
    public var humidityVariation: Float
    public var seaLevel: Float
    public var snowLevel: Float
    public var beachWidth: Float
    public var forestDensity: Float
    public var desertThreshold: Float
    
    public init(
        temperatureVariation: Float = 1.0,
        humidityVariation: Float = 1.0,
        seaLevel: Float = 0.35,
        snowLevel: Float = 0.85,
        beachWidth: Float = 0.03,
        forestDensity: Float = 0.6,
        desertThreshold: Float = 0.25
    ) {
        self.temperatureVariation = temperatureVariation
        self.humidityVariation = humidityVariation
        self.seaLevel = seaLevel
        self.snowLevel = snowLevel
        self.beachWidth = beachWidth
        self.forestDensity = forestDensity
        self.desertThreshold = desertThreshold
    }
    
    public static let `default` = BiomeParameters()
}
