import Foundation
import simd

public final class ObjectScatterEngine: @unchecked Sendable {
    
    private let random: SeededRandom
    private let params: ObjectScatterParameters
    
    public init(params: ObjectScatterParameters, seed: UInt64) {
        self.params = params
        self.random = SeededRandom(seed: seed)
    }
    
    public func scatter(
        heightmap: [Float],
        biomeMap: [BiomeType],
        temperatureMap: [Float],
        humidityMap: [Float],
        waterData: WaterData,
        width: Int,
        height: Int
    ) -> ObjectLayer {
        var objectLayer = ObjectLayer(width: width, height: height)
        
        let sampler = PoissonDiskSampler(
            random: random.fork(),
            width: Float(width),
            height: Float(height),
            minDistance: params.minObjectSpacing
        )
        let candidatePoints = sampler.generate()
        
        for point in candidatePoints {
            let x = Int(point.x)
            let y = Int(point.y)
            
            guard x >= 0 && x < width && y >= 0 && y < height else {
                continue
            }
            
            let idx = y * width + x
            let biome = biomeMap[idx]
            let heightValue = heightmap[idx]
            let slope = calculateSlope(heightmap: heightmap, x: x, y: y, width: width, height: height)
            
            if biome.isWater {
                continue
            }
            
            if waterData.riverMask[idx] > 0.5 {
                continue
            }
            
            if let (objectType, rule) = selectObjectType(
                biome: biome,
                height: heightValue,
                slope: slope,
                temperature: temperatureMap[idx],
                humidity: humidityMap[idx]
            ) {
                let density = calculateDensity(
                    rule: rule,
                    biome: biome,
                    height: heightValue,
                    slope: slope
                )
                
                if random.nextFloat() < density {
                    let object = createObject(
                        type: objectType,
                        rule: rule,
                        position: point,
                        heightValue: heightValue
                    )
                    objectLayer.add(object)
                    
                    if random.nextFloat() < rule.clusterProbability {
                        addCluster(
                            around: point,
                            type: objectType,
                            rule: rule,
                            heightmap: heightmap,
                            biomeMap: biomeMap,
                            objectLayer: &objectLayer,
                            width: width,
                            height: height
                        )
                    }
                }
            }
        }
        
        return objectLayer
    }
    
    private func calculateSlope(heightmap: [Float], x: Int, y: Int, width: Int, height: Int) -> Float {
        let h = heightmap[y * width + x]
        var maxDiff: Float = 0
        
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let nx = x + dx
            let ny = y + dy
            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                let nh = heightmap[ny * width + nx]
                maxDiff = max(maxDiff, abs(h - nh))
            }
        }
        
        return maxDiff
    }
    
    private func selectObjectType(
        biome: BiomeType,
        height: Float,
        slope: Float,
        temperature: Float,
        humidity: Float
    ) -> (MapObjectType, ScatterRule)? {
        var candidates: [(MapObjectType, Float)] = []
        
        for objectType in MapObjectType.allCases {
            if objectType.compatibleBiomes.contains(biome) {
                let rule = ScatterRule.forType(objectType)
                
                if height >= rule.heightRange.lowerBound &&
                   height <= rule.heightRange.upperBound &&
                   slope >= rule.slopeRange.lowerBound &&
                   slope <= rule.slopeRange.upperBound {
                    let weight = rule.baseDensity * objectType.rarity * getDensityMultiplier(for: objectType)
                    candidates.append((objectType, weight))
                }
            }
        }
        
        if candidates.isEmpty {
            return nil
        }
        
        let totalWeight = candidates.reduce(0) { $0 + $1.1 }
        var r = random.nextFloat() * totalWeight
        
        for (type, weight) in candidates {
            r -= weight
            if r <= 0 {
                return (type, ScatterRule.forType(type))
            }
        }
        
        let selected = candidates.last!.0
        return (selected, ScatterRule.forType(selected))
    }
    
    private func getDensityMultiplier(for type: MapObjectType) -> Float {
        switch type {
        case .pine, .oak, .palm:
            return params.treeDensity
        case .rock, .boulder:
            return params.rockDensity
        case .ruin, .tower, .village:
            return params.structureDensity
        case .bush, .flower, .grass, .cactus:
            return params.vegetationDensity
        case .crystal:
            return params.rockDensity * 0.5
        }
    }
    
    private func calculateDensity(
        rule: ScatterRule,
        biome: BiomeType,
        height: Float,
        slope: Float
    ) -> Float {
        var density = rule.baseDensity
        
        let heightRange = rule.heightRange.upperBound - rule.heightRange.lowerBound
        let heightCenter = (rule.heightRange.lowerBound + rule.heightRange.upperBound) / 2
        let heightDeviation = abs(height - heightCenter) / (heightRange / 2)
        density *= (1 - heightDeviation * 0.5)
        
        if rule.preferEdges && slope > 0.05 {
            density *= 1.5
        }
        
        return density * params.clusteringStrength
    }
    
    private func createObject(
        type: MapObjectType,
        rule: ScatterRule,
        position: SIMD2<Float>,
        heightValue: Float
    ) -> MapObject {
        MapObject(
            type: type,
            position: position,
            height: heightValue,
            scale: random.nextFloat(in: rule.scaleRange),
            rotation: random.nextFloat() * Float.pi * 2,
            variation: random.nextInt(in: 0...3)
        )
    }
    
    private func addCluster(
        around center: SIMD2<Float>,
        type: MapObjectType,
        rule: ScatterRule,
        heightmap: [Float],
        biomeMap: [BiomeType],
        objectLayer: inout ObjectLayer,
        width: Int,
        height: Int
    ) {
        let clusterCount = random.nextInt(in: rule.clusterSize)
        let clusterRadius = params.minObjectSpacing * 0.8
        
        for _ in 0..<clusterCount {
            let angle = random.nextFloat() * Float.pi * 2
            let dist = random.nextFloat(in: 0...clusterRadius)
            
            let offset = SIMD2<Float>(
                cos(angle) * dist,
                sin(angle) * dist
            )
            let newPos = center + offset
            
            let x = Int(newPos.x)
            let y = Int(newPos.y)
            
            guard x >= 0 && x < width && y >= 0 && y < height else {
                continue
            }
            
            let idx = y * width + x
            let biome = biomeMap[idx]
            let heightValue = heightmap[idx]
            
            if biome.isWater {
                continue
            }
            if !type.compatibleBiomes.contains(biome) {
                continue
            }
            if heightValue < rule.heightRange.lowerBound ||
               heightValue > rule.heightRange.upperBound {
                continue
            }
            
            let object = createObject(
                type: type,
                rule: rule,
                position: newPos,
                heightValue: heightValue
            )
            objectLayer.add(object)
        }
    }
}
