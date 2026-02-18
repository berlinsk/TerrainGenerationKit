import Foundation
import simd

public protocol HeightmapServiceProtocol: Sendable {
    func generateHeightmap(
        width: Int,
        height: Int,
        settings: GenerationSettings,
        seed: UInt64
    ) async -> [Float]
    
    func applyErosion(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        params: ErosionParameters,
        seed: UInt64
    )
}

public final class HeightmapService: HeightmapServiceProtocol, @unchecked Sendable {
    
    private let noiseService: NoiseService
    
    public init(noiseService: NoiseService = NoiseService()) {
        self.noiseService = noiseService
    }
    
    public func generateHeightmap(
        width: Int,
        height: Int,
        settings: GenerationSettings,
        seed: UInt64
    ) async -> [Float] {
        let noiseSeed = NoiseSeed(seed)
        
        var noiseResults = [Int: [Float]](minimumCapacity: 3)
        await withTaskGroup(of: (Int, [Float]).self) { group in
            group.addTask { [noiseService] in
                (0, await noiseService.generateNoise(width: width, height: height, parameters: settings.primaryNoise, seed: noiseSeed.derive(0)))
            }
            if let params = settings.secondaryNoise {
                group.addTask { [noiseService] in
                    (1, await noiseService.generateNoise(width: width, height: height, parameters: params, seed: noiseSeed.derive(1)))
                }
            }
            if let params = settings.detailNoise {
                group.addTask { [noiseService] in
                    (2, await noiseService.generateNoise(width: width, height: height, parameters: params, seed: noiseSeed.derive(2)))
                }
            }
            for await (idx, noise) in group {
                noiseResults[idx] = noise
            }
        }

        var layers: [[Float]] = [noiseResults[0]!]
        var weights: [Float] = [settings.primaryWeight]
        if settings.secondaryNoise != nil, let noise = noiseResults[1] {
            layers.append(noise)
            weights.append(settings.secondaryWeight)
        }
        if settings.detailNoise != nil, let noise = noiseResults[2] {
            layers.append(noise)
            weights.append(settings.detailWeight)
        }
        
        var heightmap = noiseService.blendNoiseLayers(layers: layers, weights: weights)
        
        applyGenerationMode(
            heightmap: &heightmap,
            width: width,
            height: height,
            mode: settings.mode,
            seaLevel: settings.biome.seaLevel
        )
        
        noiseService.normalizeNoise(&heightmap)
        
        return heightmap
    }
    
    public func applyErosion(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        params: ErosionParameters,
        seed: UInt64
    ) {
        guard params.type != .none && params.iterations > 0 else {
            return
        }
        
        let simulator = ErosionSimulator(params: params, seed: seed)
        simulator.simulate(
            heightmap: &heightmap,
            width: width,
            height: height,
            type: params.type
        )
        
        MathUtils.normalizeArray(&heightmap)
    }
    
    private func applyGenerationMode(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        mode: GenerationMode,
        seaLevel: Float
    ) {
        switch mode {
        case .continental:
            applyContinentalMask(
                heightmap: &heightmap,
                width: width,
                height: height,
                seaLevel: seaLevel
            )
            
        case .archipelago:
            applyArchipelagoMask(
                heightmap: &heightmap,
                width: width,
                height: height
            )
            
        case .pangaea:
            applyPangaeaMask(
                heightmap: &heightmap,
                width: width,
                height: height,
                seaLevel: seaLevel
            )
            
        case .fractal:
            break
            
        case .custom:
            break
        }
    }
    
    private func applyContinentalMask(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        seaLevel: Float
    ) {
        let mask = noiseService.generateGradientMask(
            width: width,
            height: height,
            type: .radial(falloff: 1.5)
        )
        
        for i in 0..<heightmap.count {
            heightmap[i] = heightmap[i] * 0.7 + mask[i] * 0.3
        }
    }
    
    private func applyArchipelagoMask(
        heightmap: inout [Float],
        width: Int,
        height: Int
    ) {
        let mask = noiseService.generateGradientMask(
            width: width,
            height: height,
            type: .island(coastWidth: Float(min(width, height)) * 0.15)
        )
        
        for i in 0..<heightmap.count {
            heightmap[i] = heightmap[i] * mask[i]
        }
    }
    
    private func applyPangaeaMask(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        seaLevel: Float
    ) {
        let centerX = Float(width) / 2
        let centerY = Float(height) / 2
        let maxDist = min(centerX, centerY) * 0.8
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                let dist = sqrt(dx * dx + dy * dy)
                
                let landMask: Float
                if dist < maxDist * 0.6 {
                    landMask = 1.0
                } else if dist < maxDist {
                    let t = (dist - maxDist * 0.6) / (maxDist * 0.4)
                    landMask = 1 - MathUtils.smootherstep(0, 1, t)
                } else {
                    landMask = 0
                }
                
                heightmap[idx] = heightmap[idx] * 0.5 + landMask * 0.5
            }
        }
    }
    
    public func applySmoothing(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        passes: Int,
        strength: Float
    ) {
        for _ in 0..<passes {
            var smoothed = heightmap
            
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let idx = y * width + x
                    
                    var sum: Float = heightmap[idx]
                    var count: Float = 1
                    
                    for dy in -1...1 {
                        for dx in -1...1 {
                            if dx == 0 && dy == 0 {
                                continue
                            }
                            let nidx = (y + dy) * width + (x + dx)
                            sum += heightmap[nidx]
                            count += 1
                        }
                    }
                    
                    let avg = sum / count
                    smoothed[idx] = MathUtils.lerp(heightmap[idx], avg, strength)
                }
            }
            
            heightmap = smoothed
        }
    }
    
    public func applyTerracing(
        heightmap: inout [Float],
        steps: Int,
        sharpness: Float
    ) {
        guard steps > 0 else {
            return
        }
        
        for i in 0..<heightmap.count {
            heightmap[i] = MathUtils.smoothTerrace(
                heightmap[i],
                steps: steps,
                sharpness: sharpness
            )
        }
    }
    
    public func applyContrastEnhancement(
        heightmap: inout [Float],
        strength: Float
    ) {
        guard strength != 1.0 else {
            return
        }
        MathUtils.applyContrast(&heightmap, strength: strength)
    }
}
