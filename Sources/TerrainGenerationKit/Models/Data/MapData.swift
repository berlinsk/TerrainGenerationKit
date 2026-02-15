import Foundation
import simd

public struct MapData: Sendable {
    
    public var heightmap: [Float]
    public var biomeMap: [UInt8]
    public var temperatureMap: [Float]
    public var humidityMap: [Float]
    public var steepnessMap: [Float]
    public var waterData: WaterData
    public var objectLayer: ObjectLayer
    public var cityNetwork: CityNetworkData
    
    public let width: Int
    public let height: Int
    public let seed: UInt64
    
    public var metadata: MapMetadata
    
    public init(width: Int, height: Int, seed: UInt64, settings: GenerationSettings) {
        self.width = width
        self.height = height
        self.seed = seed
        
        let count = width * height
        self.heightmap = [Float](repeating: 0, count: count)
        self.biomeMap = [UInt8](repeating: 0, count: count)
        self.temperatureMap = [Float](repeating: 0.5, count: count)
        self.humidityMap = [Float](repeating: 0.5, count: count)
        self.steepnessMap = [Float](repeating: 0, count: count)
        self.waterData = WaterData(width: width, height: height)
        self.objectLayer = ObjectLayer(width: width, height: height)
        self.cityNetwork = CityNetworkData(width: width, height: height)
        self.metadata = MapMetadata(seed: seed, width: width, height: height, settings: settings)
    }
    
    public func height(at x: Int, y: Int) -> Float {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return 0
        }
        return heightmap[y * width + x]
    }
    
    public func biome(at x: Int, y: Int) -> BiomeType {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return .ocean
        }
        return BiomeType(rawValue: Int(biomeMap[y * width + x])) ?? .ocean
    }
    
    public func temperature(at x: Int, y: Int) -> Float {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return 0.5
        }
        return temperatureMap[y * width + x]
    }
    
    public func humidity(at x: Int, y: Int) -> Float {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return 0.5
        }
        return humidityMap[y * width + x]
    }
    
    public mutating func setHeight(_ value: Float, at x: Int, y: Int) {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return
        }
        heightmap[y * width + x] = value
    }
    
    public mutating func setBiome(_ biome: BiomeType, at x: Int, y: Int) {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return
        }
        biomeMap[y * width + x] = UInt8(biome.rawValue)
    }
    
    public func gradient(at x: Int, y: Int) -> SIMD2<Float> {
        let left = height(at: x - 1, y: y)
        let right = height(at: x + 1, y: y)
        let up = height(at: x, y: y - 1)
        let down = height(at: x, y: y + 1)
        
        return SIMD2<Float>(right - left, down - up) * 0.5
    }
    
    public func steepness(at x: Int, y: Int) -> Float {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return 0
        }
        return steepnessMap[y * width + x]
    }
    
    public func sampleHeight(at position: SIMD2<Float>) -> Float {
        let x = position.x
        let y = position.y
        
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = x0 + 1
        let y1 = y0 + 1
        
        let fx = x - Float(x0)
        let fy = y - Float(y0)
        
        let h00 = height(at: x0, y: y0)
        let h10 = height(at: x1, y: y0)
        let h01 = height(at: x0, y: y1)
        let h11 = height(at: x1, y: y1)
        
        let h0 = h00 * (1 - fx) + h10 * fx
        let h1 = h01 * (1 - fx) + h11 * fx
        
        return h0 * (1 - fy) + h1 * fy
    }
    
    public mutating func computeSteepnessMap() {
        for y in 0..<height {
            for x in 0..<width {
                let grad = gradient(at: x, y: y)
                steepnessMap[y * width + x] = sqrt(grad.x * grad.x + grad.y * grad.y)
            }
        }
        guard let maxSteepness = steepnessMap.max(), maxSteepness > 0 else { return }
        for i in 0..<steepnessMap.count {
            steepnessMap[i] /= maxSteepness
        }
    }

    public mutating func updateStatistics(generationTimeMs: Int) {
        metadata.generationTimeMs = generationTimeMs
        metadata.statistics.calculate(from: self)
    }
}
