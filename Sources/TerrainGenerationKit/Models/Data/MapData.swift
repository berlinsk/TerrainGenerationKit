import Foundation
import simd

public struct MapData: Codable, Sendable {
    
    public let width: Int
    public let height: Int
    public let seed: UInt64
    
    public var heightmap: [Float]
    public var biomeMap: [BiomeType]
    public var temperatureMap: [Float]
    public var humidityMap: [Float]
    public var waterData: WaterData
    public var objectLayer: ObjectLayer
    public var cityNetwork: CityNetworkData
    public var metadata: MapMetadata
    
    public init(width: Int, height: Int, seed: UInt64) {
        self.width = width
        self.height = height
        self.seed = seed
        
        let size = width * height
        self.heightmap = [Float](repeating: 0, count: size)
        self.biomeMap = [BiomeType](repeating: .ocean, count: size)
        self.temperatureMap = [Float](repeating: 0.5, count: size)
        self.humidityMap = [Float](repeating: 0.5, count: size)
        self.waterData = WaterData(width: width, height: height)
        self.objectLayer = ObjectLayer(width: width, height: height)
        self.cityNetwork = CityNetworkData(width: width, height: height)
        self.metadata = MapMetadata()
    }
    
    public func index(x: Int, y: Int) -> Int {
        y * width + x
    }
    
    public func coordinates(index: Int) -> (x: Int, y: Int) {
        (index % width, index / width)
    }
    
    public func isValid(x: Int, y: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height
    }
    
    public func height(at x: Int, _ y: Int) -> Float {
        guard isValid(x: x, y: y) else {
            return 0
        }
        return heightmap[index(x: x, y: y)]
    }
    
    public func biome(at x: Int, _ y: Int) -> BiomeType {
        guard isValid(x: x, y: y) else {
            return .ocean
        }
        return biomeMap[index(x: x, y: y)]
    }
    
    public func calculateStatistics() -> MapStatistics {
        var stats = MapStatistics()
        
        var minH: Float = .greatestFiniteMagnitude
        var maxH: Float = -.greatestFiniteMagnitude
        var sumH: Float = 0
        var waterCount = 0
        
        for i in 0..<heightmap.count {
            let h = heightmap[i]
            minH = min(minH, h)
            maxH = max(maxH, h)
            sumH += h
            
            let biome = biomeMap[i]
            stats.biomeCounts[biome, default: 0] += 1
            
            if biome.isWater {
                waterCount += 1
            }
        }
        
        stats.minHeight = minH
        stats.maxHeight = maxH
        stats.averageHeight = sumH / Float(heightmap.count)
        stats.waterCoverage = Float(waterCount) / Float(heightmap.count)
        stats.objectCounts = objectLayer.statistics
        stats.cityCount = cityNetwork.cities.count
        stats.roadCount = cityNetwork.roads.count
        
        return stats
    }
}
