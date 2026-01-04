import Foundation
import simd

public protocol BiomeServiceProtocol: Sendable {
    func generateBiomes(
        heightmap: [Float],
        temperatureMap: [Float],
        humidityMap: [Float],
        waterData: WaterData,
        width: Int,
        height: Int,
        params: BiomeParameters,
        selection: BiomeSelection
    ) -> [BiomeType]
    
    func generateTemperatureMap(
        heightmap: [Float],
        width: Int,
        height: Int,
        params: BiomeParameters,
        seed: UInt64
    ) async -> [Float]
    
    func generateHumidityMap(
        heightmap: [Float],
        width: Int,
        height: Int,
        params: BiomeParameters,
        seed: UInt64
    ) async -> [Float]
}

public final class BiomeService: BiomeServiceProtocol, @unchecked Sendable {
    
    private let noiseService: NoiseService
    
    public init(noiseService: NoiseService = NoiseService()) {
        self.noiseService = noiseService
    }
    
    public func generateBiomes(
        heightmap: [Float],
        temperatureMap: [Float],
        humidityMap: [Float],
        waterData: WaterData,
        width: Int,
        height: Int,
        params: BiomeParameters,
        selection: BiomeSelection
    ) -> [BiomeType] {
        let classifier = BiomeClassifier(parameters: params)
        var biomeMap = [BiomeType](repeating: .ocean, count: width * height)
        
        DispatchQueue.concurrentPerform(iterations: height) { y in
            for x in 0..<width {
                let idx = y * width + x
                
                var biome = classifier.classify(
                    height: heightmap[idx],
                    temperature: temperatureMap[idx],
                    humidity: humidityMap[idx],
                    isRiver: waterData.riverMask[idx] > 0.5,
                    isLake: waterData.lakeMask[idx] > 0.5
                )
                
                if !selection.isEnabled(biome) {
                    biome = findAlternativeBiome(for: biome, selection: selection)
                }
                
                biomeMap[idx] = biome
            }
        }
        
        smoothBiomeTransitions(
            biomeMap: &biomeMap,
            heightmap: heightmap,
            width: width,
            height: height,
            params: params
        )
        
        return biomeMap
    }
    
    private func findAlternativeBiome(for biome: BiomeType, selection: BiomeSelection) -> BiomeType {
        let alternatives: [BiomeType: [BiomeType]] = [
            .deepOcean: [.ocean, .shallowWater, .lake],
            .ocean: [.shallowWater, .deepOcean, .lake],
            .shallowWater: [.ocean, .lake, .beach],
            .lake: [.shallowWater, .river, .ocean],
            .river: [.lake, .shallowWater, .marsh],
            .beach: [.desert, .savanna, .grassland],
            .grassland: [.savanna, .forest, .tundra],
            .forest: [.taiga, .rainforest, .grassland],
            .rainforest: [.forest, .marsh, .grassland],
            .desert: [.savanna, .beach, .tundra],
            .savanna: [.grassland, .desert, .beach],
            .taiga: [.forest, .tundra, .snow],
            .tundra: [.taiga, .snow, .grassland],
            .snow: [.tundra, .snowyMountain, .taiga],
            .mountain: [.snowyMountain, .tundra, .grassland],
            .snowyMountain: [.mountain, .snow, .tundra],
            .marsh: [.lake, .rainforest, .grassland]
        ]
        
        if let alts = alternatives[biome] {
            for alt in alts {
                if selection.isEnabled(alt) {
                    return alt
                }
            }
        }
        
        for b in BiomeType.allCases {
            if selection.isEnabled(b) {
                return b
            }
        }
        
        return .grassland
    }
    
    public func generateTemperatureMap(
        heightmap: [Float],
        width: Int,
        height: Int,
        params: BiomeParameters,
        seed: UInt64
    ) async -> [Float] {
        let noiseParams = NoiseParameters(
            type: .simplex,
            octaves: 4,
            frequency: 0.003,
            persistence: 0.5,
            lacunarity: 2.0,
            amplitude: 1.0
        )
        
        var temperatureNoise = await noiseService.generateNoise(
            width: width,
            height: height,
            parameters: noiseParams,
            seed: seed
        )
        
        noiseService.normalizeNoise(&temperatureNoise)
        
        var temperatureMap = [Float](repeating: 0, count: width * height)
        
        DispatchQueue.concurrentPerform(iterations: height) { y in
            for x in 0..<width {
                let idx = y * width + x
                
                let latitudeNormalized = Float(y) / Float(height - 1)
                let latitudeTemp = MathUtils.temperatureFromLatitude(
                    latitudeNormalized,
                    height: heightmap[idx]
                )
                
                let noiseInfluence = (temperatureNoise[idx] - 0.5) * params.temperatureVariation
                
                temperatureMap[idx] = MathUtils.clamp(
                    latitudeTemp + noiseInfluence,
                    0, 1
                )
            }
        }
        
        return temperatureMap
    }
    
    public func generateHumidityMap(
        heightmap: [Float],
        width: Int,
        height: Int,
        params: BiomeParameters,
        seed: UInt64
    ) async -> [Float] {
        let noiseParams = NoiseParameters(
            type: .simplex,
            octaves: 5,
            frequency: 0.004,
            persistence: 0.55,
            lacunarity: 2.0,
            amplitude: 1.0
        )
        
        var humidityNoise = await noiseService.generateNoise(
            width: width,
            height: height,
            parameters: noiseParams,
            seed: seed + 12345
        )
        
        noiseService.normalizeNoise(&humidityNoise)
        
        var humidityMap = [Float](repeating: 0, count: width * height)
        
        let waterDistance = calculateWaterDistance(
            heightmap: heightmap,
            width: width,
            height: height,
            seaLevel: params.seaLevel
        )
        
        DispatchQueue.concurrentPerform(iterations: height) { y in
            for x in 0..<width {
                let idx = y * width + x
                
                var humidity = humidityNoise[idx]
                
                let distInfluence = max(0, 1 - waterDistance[idx] / 50)
                humidity = humidity * 0.6 + distInfluence * 0.4
                
                let heightPenalty = max(0, (heightmap[idx] - 0.6) * 0.5)
                humidity -= heightPenalty
                
                humidity = 0.5 + (humidity - 0.5) * params.humidityVariation
                
                humidityMap[idx] = MathUtils.clamp(humidity, 0, 1)
            }
        }
        
        return humidityMap
    }
    
    private func calculateWaterDistance(
        heightmap: [Float],
        width: Int,
        height: Int,
        seaLevel: Float
    ) -> [Float] {
        var distance = [Float](repeating: Float.greatestFiniteMagnitude, count: width * height)
        var queue: [(x: Int, y: Int)] = []
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if heightmap[idx] < seaLevel {
                    distance[idx] = 0
                    queue.append((x, y))
                }
            }
        }
        
        let directions = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        var head = 0
        
        while head < queue.count {
            let (x, y) = queue[head]
            head += 1
            
            let currentIdx = y * width + x
            let currentDist = distance[currentIdx]
            
            for (dx, dy) in directions {
                let nx = x + dx
                let ny = y + dy
                
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let nidx = ny * width + nx
                    let newDist = currentDist + 1
                    
                    if newDist < distance[nidx] {
                        distance[nidx] = newDist
                        queue.append((nx, ny))
                    }
                }
            }
        }
        
        return distance
    }
    
    private func smoothBiomeTransitions(
        biomeMap: inout [BiomeType],
        heightmap: [Float],
        width: Int,
        height: Int,
        params: BiomeParameters
    ) {
        var smoothed = biomeMap
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let currentBiome = biomeMap[idx]
                
                if currentBiome.isWater {
                    continue
                }
                
                var biomeCounts: [BiomeType: Int] = [:]
                biomeCounts[biomeMap[idx]] = 2
                
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 {
                            continue
                        }
                        
                        let nidx = (y + dy) * width + (x + dx)
                        let neighborBiome = biomeMap[nidx]
                        
                        if !neighborBiome.isWater {
                            biomeCounts[neighborBiome, default: 0] += 1
                        }
                    }
                }
                
                if let mostCommon = biomeCounts.max(by: { $0.value < $1.value }) {
                    if mostCommon.value >= 5 && mostCommon.key != biomeMap[idx] {
                        smoothed[idx] = mostCommon.key
                    }
                }
            }
        }
        
        biomeMap = smoothed
    }
}
