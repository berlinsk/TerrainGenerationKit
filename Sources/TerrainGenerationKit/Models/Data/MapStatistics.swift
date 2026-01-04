import Foundation

public struct MapStatistics: Codable, Sendable {
    
    public var landPercentage: Float = 0
    public var waterPercentage: Float = 0
    public var averageHeight: Float = 0
    public var maxHeight: Float = 0
    public var minHeight: Float = 0
    public var biomeDistribution: [Int: Float] = [:]
    public var riverCount: Int = 0
    public var lakeCount: Int = 0
    public var objectCount: Int = 0
    public var cityCount: Int = 0
    public var roadCount: Int = 0
    public var totalBuildingCount: Int = 0
    
    public init() {}
    
    public mutating func calculate(from mapData: MapData) {
        let totalPixels = Float(mapData.width * mapData.height)
        var landCount: Float = 0
        var heightSum: Float = 0
        var minH: Float = Float.greatestFiniteMagnitude
        var maxH: Float = -Float.greatestFiniteMagnitude
        var biomeCounts: [Int: Int] = [:]
        
        for y in 0..<mapData.height {
            for x in 0..<mapData.width {
                let idx = y * mapData.width + x
                let h = mapData.heightmap[idx]
                let biome = mapData.biomeMap[idx]
                
                heightSum += h
                minH = min(minH, h)
                maxH = max(maxH, h)
                
                if !BiomeType(rawValue: Int(biome))!.isWater {
                    landCount += 1
                }
                
                biomeCounts[Int(biome), default: 0] += 1
            }
        }
        
        self.landPercentage = landCount / totalPixels
        self.waterPercentage = 1.0 - landPercentage
        self.averageHeight = heightSum / totalPixels
        self.minHeight = minH
        self.maxHeight = maxH
        
        for (biome, count) in biomeCounts {
            self.biomeDistribution[biome] = Float(count) / totalPixels
        }
        
        self.objectCount = mapData.objectLayer.objectCount
        self.cityCount = mapData.cityNetwork.cities.count
        self.roadCount = mapData.cityNetwork.roads.count
        self.totalBuildingCount = mapData.cityNetwork.cities.reduce(0) { $0 + $1.blocks.count }
    }
}
