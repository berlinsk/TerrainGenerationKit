import Foundation
import simd

public protocol ObjectScatterServiceProtocol: Sendable {
    func scatterObjects(
        mapData: MapData,
        params: ObjectScatterParameters,
        seed: UInt64
    ) -> ObjectLayer
}

public final class ObjectScatterService: ObjectScatterServiceProtocol, @unchecked Sendable {
    
    public init() {}
    
    public func scatterObjects(
        mapData: MapData,
        params: ObjectScatterParameters,
        seed: UInt64
    ) -> ObjectLayer {
        let width = mapData.width
        let height = mapData.height
        
        var objectLayer = ObjectLayer(width: width, height: height)
        
        if let gpu = GPUComputeEngine.shared {
            let candidates = gpu.generatePoissonDiskSamples(
                width: width,
                height: height,
                minDistance: params.minObjectSpacing,
                seed: seed
            )
            
            let objects = gpu.placeObjects(
                candidates: candidates,
                heightmap: mapData.heightmap,
                biomeMap: mapData.biomeMap,
                width: width,
                height: height,
                params: params,
                seaLevel: mapData.metadata.settings.biome.seaLevel,
                seed: seed + 1
            )
            
            objectLayer.objects = objects
        } else {
            objectLayer = scatterObjectsCPU(mapData: mapData, params: params, seed: seed)
        }
        
        objectLayer.objects.sort { $0.position.y < $1.position.y }
        
        return objectLayer
    }
    
    private func scatterObjectsCPU(
        mapData: MapData,
        params: ObjectScatterParameters,
        seed: UInt64
    ) -> ObjectLayer {
        let width = mapData.width
        let height = mapData.height
        var objectLayer = ObjectLayer(width: width, height: height)
        var rng = SeededRandom(seed: seed)
        
        let cellSize = params.minObjectSpacing / sqrt(2.0)
        let gridWidth = Int(ceil(Float(width) / cellSize))
        let gridHeight = Int(ceil(Float(height) / cellSize))
        
        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                let baseX = Float(gx) * cellSize
                let baseY = Float(gy) * cellSize
                let jitterX = rng.nextFloat() * cellSize
                let jitterY = rng.nextFloat() * cellSize
                let point = SIMD2<Float>(baseX + jitterX, baseY + jitterY)
                
                let x = Int(point.x)
                let y = Int(point.y)
                
                guard x >= 0 && x < width && y >= 0 && y < height else {
                    continue
                }
                
                let idx = y * width + x
                let h = mapData.heightmap[idx]
                let biome = BiomeType(rawValue: Int(mapData.biomeMap[idx])) ?? .ocean
                
                if biome.isWater || h < mapData.metadata.settings.biome.seaLevel {
                    continue
                }
                if mapData.waterData.isRiver(at: x, y: y) {
                    continue
                }
                
                if let objType = selectObjectForBiome(biome: biome, height: h, rng: &rng, params: params) {
                    let obj = MapObject(
                        type: objType,
                        position: point,
                        height: h,
                        scale: 0.7 + rng.nextFloat() * 0.6,
                        rotation: rng.nextFloat() * .pi * 2,
                        variation: rng.nextInt(in: 0...3)
                    )
                    objectLayer.add(obj)
                }
            }
        }
        
        return objectLayer
    }
    
    private func selectObjectForBiome(
        biome: BiomeType,
        height: Float,
        rng: inout SeededRandom,
        params: ObjectScatterParameters
    ) -> MapObjectType? {
        let roll = rng.nextFloat()
        
        switch biome {
        case .forest, .rainforest:
            if roll < params.treeDensity * 0.3 {
                return .oak
            } else if roll < params.vegetationDensity * 0.2 {
                return .bush
            }
        case .taiga:
            if roll < params.treeDensity * 0.3 {
                return .pine
            }
        case .grassland, .savanna:
            if roll < params.treeDensity * 0.1 {
                return .oak
            } else if roll < params.vegetationDensity * 0.3 {
                return rng.nextFloat() > 0.5 ? .grass : .flower
            }
        case .desert:
            if roll < params.vegetationDensity * 0.1 {
                return .cactus
            } else if roll < params.rockDensity * 0.1 {
                return .rock
            }
        case .mountain, .snowyMountain:
            if roll < params.rockDensity * 0.2 {
                return rng.nextFloat() > 0.7 ? .boulder : .rock
            }
        case .beach:
            if roll < params.treeDensity * 0.1 {
                return .palm
            }
        case .tundra, .snow:
            if roll < params.rockDensity * 0.1 {
                return .rock
            }
        case .marsh:
            if roll < params.vegetationDensity * 0.2 {
                return .grass
            }
        default:
            break
        }
        
        return nil
    }
}
