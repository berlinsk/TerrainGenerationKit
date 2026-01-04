import Foundation

public struct MapStatistics: Codable, Sendable {
    
    public var minHeight: Float
    public var maxHeight: Float
    public var averageHeight: Float
    public var waterCoverage: Float
    public var biomeCounts: [BiomeType: Int]
    public var objectCounts: [MapObjectType: Int]
    public var cityCount: Int
    public var roadCount: Int
    
    public init() {
        self.minHeight = 0
        self.maxHeight = 1
        self.averageHeight = 0.5
        self.waterCoverage = 0
        self.biomeCounts = [:]
        self.objectCounts = [:]
        self.cityCount = 0
        self.roadCount = 0
    }
}
