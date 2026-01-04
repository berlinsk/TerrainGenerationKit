import Foundation
import simd

public protocol NoiseServiceProtocol: Sendable {
    func generateNoise(
        width: Int,
        height: Int,
        parameters: NoiseParameters,
        seed: UInt64
    ) async -> [Float]
    
    func blendNoiseLayers(
        layers: [[Float]],
        weights: [Float]
    ) -> [Float]
}

public final class NoiseService: NoiseServiceProtocol, @unchecked Sendable {
    
    public init() {}
    
    public func generateNoise(
        width: Int,
        height: Int,
        parameters: NoiseParameters,
        seed: UInt64
    ) async -> [Float] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fractalNoise = FractalNoise(seed: seed)
                let result = fractalNoise.generateNoiseMap(
                    width: width,
                    height: height,
                    parameters: parameters
                )
                continuation.resume(returning: result)
            }
        }
    }
    
    public func generateNoiseWithDomainWarp(
        width: Int,
        height: Int,
        parameters: NoiseParameters,
        warpStrength: Float,
        seed: UInt64
    ) async -> [Float] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fractalNoise = FractalNoise(seed: seed)
                var result = [Float](repeating: 0, count: width * height)
                
                let type: FractalNoise.NoiseType
                switch parameters.type {
                case .simplex:
                    type = .simplex
                case .perlin:
                    type = .perlin
                case .openSimplex:
                    type = .openSimplex
                case .voronoi:
                    type = .voronoi
                case .ridged:
                    type = .ridged
                case .billow:
                    type = .billow
                }
                
                DispatchQueue.concurrentPerform(iterations: height) { y in
                    for x in 0..<width {
                        let (warpedX, warpedY) = fractalNoise.domainWarp(
                            x: Float(x),
                            y: Float(y),
                            type: type,
                            octaves: 3,
                            frequency: parameters.frequency * 0.5,
                            warpStrength: warpStrength
                        )
                        
                        let value = fractalNoise.fbm(
                            x: warpedX,
                            y: warpedY,
                            type: type,
                            octaves: parameters.octaves,
                            frequency: parameters.frequency,
                            persistence: parameters.persistence,
                            lacunarity: parameters.lacunarity,
                            amplitude: parameters.amplitude
                        )
                        
                        result[y * width + x] = value
                    }
                }
                
                continuation.resume(returning: result)
            }
        }
    }
    
    public func blendNoiseLayers(
        layers: [[Float]],
        weights: [Float]
    ) -> [Float] {
        guard let first = layers.first else {
            return []
        }
        guard layers.count == weights.count else {
            return first
        }
        
        let count = first.count
        var result = [Float](repeating: 0, count: count)
        
        var totalWeight: Float = 0
        for weight in weights {
            totalWeight += weight
        }
        
        guard totalWeight > 0 else {
            return first
        }
        
        for i in 0..<count {
            var sum: Float = 0
            for (layerIndex, layer) in layers.enumerated() {
                sum += layer[i] * weights[layerIndex]
            }
            result[i] = sum / totalWeight
        }
        
        return result
    }
    
    public func normalizeNoise(_ noise: inout [Float]) {
        MathUtils.normalizeArray(&noise)
    }
    
    public func applyMask(_ noise: inout [Float], mask: [Float], strength: Float = 1.0) {
        guard noise.count == mask.count else {
            return
        }
        
        for i in 0..<noise.count {
            noise[i] = MathUtils.lerp(noise[i], noise[i] * mask[i], strength)
        }
    }
    
    public func generateGradientMask(
        width: Int,
        height: Int,
        type: GradientMaskType
    ) -> [Float] {
        var mask = [Float](repeating: 0, count: width * height)
        
        switch type {
        case .radial(let falloff):
            let centerX = Float(width) / 2
            let centerY = Float(height) / 2
            let maxDist = sqrt(centerX * centerX + centerY * centerY)
            
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Float(x) - centerX
                    let dy = Float(y) - centerY
                    let dist = sqrt(dx * dx + dy * dy)
                    let normalized = dist / maxDist
                    mask[y * width + x] = pow(1 - normalized, falloff)
                }
            }
            
        case .horizontal(let falloff):
            for y in 0..<height {
                for x in 0..<width {
                    let normalized = Float(x) / Float(width - 1)
                    let value = 1 - pow(abs(normalized * 2 - 1), falloff)
                    mask[y * width + x] = value
                }
            }
            
        case .vertical(let falloff):
            for y in 0..<height {
                for x in 0..<width {
                    let normalized = Float(y) / Float(height - 1)
                    let value = 1 - pow(abs(normalized * 2 - 1), falloff)
                    mask[y * width + x] = value
                }
            }
            
        case .island(let coastWidth):
            let centerX = Float(width) / 2
            let centerY = Float(height) / 2
            let maxDist = min(centerX, centerY)
            
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Float(x) - centerX
                    let dy = Float(y) - centerY
                    let dist = max(abs(dx), abs(dy))
                    
                    if dist < maxDist - coastWidth {
                        mask[y * width + x] = 1
                    } else if dist < maxDist {
                        let t = (maxDist - dist) / coastWidth
                        mask[y * width + x] = MathUtils.smootherstep(0, 1, t)
                    } else {
                        mask[y * width + x] = 0
                    }
                }
            }
        }
        
        return mask
    }
}
