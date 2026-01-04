import Foundation

public struct WaterParameters: Codable, Sendable, Equatable {
    
    public var enabled: Bool
    public var riverCount: Int
    public var riverWidth: Float
    public var riverMeandering: Float
    public var lakeThreshold: Float
    public var lakeMinSize: Int
    public var flowSimulationIterations: Int
    public var evaporationRate: Float
    
    public init(
        enabled: Bool = true,
        riverCount: Int = 8,
        riverWidth: Float = 0.015,
        riverMeandering: Float = 0.3,
        lakeThreshold: Float = 0.15,
        lakeMinSize: Int = 50,
        flowSimulationIterations: Int = 100,
        evaporationRate: Float = 0.02
    ) {
        self.enabled = enabled
        self.riverCount = riverCount
        self.riverWidth = riverWidth
        self.riverMeandering = riverMeandering
        self.lakeThreshold = lakeThreshold
        self.lakeMinSize = lakeMinSize
        self.flowSimulationIterations = flowSimulationIterations
        self.evaporationRate = evaporationRate
    }
    
    public static let `default` = WaterParameters()
}
