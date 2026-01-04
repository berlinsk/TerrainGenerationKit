import Foundation

public struct ObjectScatterParameters: Codable, Sendable, Equatable {
    
    public var treeDensity: Float
    public var rockDensity: Float
    public var structureDensity: Float
    public var vegetationDensity: Float
    public var minObjectSpacing: Float
    public var clusteringStrength: Float
    
    public init(
        treeDensity: Float = 0.4,
        rockDensity: Float = 0.2,
        structureDensity: Float = 0.02,
        vegetationDensity: Float = 0.5,
        minObjectSpacing: Float = 2.0,
        clusteringStrength: Float = 0.6
    ) {
        self.treeDensity = treeDensity
        self.rockDensity = rockDensity
        self.structureDensity = structureDensity
        self.vegetationDensity = vegetationDensity
        self.minObjectSpacing = minObjectSpacing
        self.clusteringStrength = clusteringStrength
    }
    
    public static let `default` = ObjectScatterParameters()
}
