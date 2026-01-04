import Foundation
import simd

public protocol PostProcessingServiceProtocol: Sendable {
    func process(
        mapData: inout MapData,
        params: PostProcessingParameters
    )
}

public final class PostProcessingService: PostProcessingServiceProtocol, @unchecked Sendable {
    
    private let heightmapService: HeightmapService
    
    public init(heightmapService: HeightmapService = HeightmapService()) {
        self.heightmapService = heightmapService
    }
    
    public func process(
        mapData: inout MapData,
        params: PostProcessingParameters
    ) {
        if params.smoothingPasses > 0 {
            applySmoothing(
                heightmap: &mapData.heightmap,
                width: mapData.width,
                height: mapData.height,
                passes: params.smoothingPasses,
                strength: params.smoothingStrength
            )
        }
        
        if params.normalizeHeightmap {
            MathUtils.normalizeArray(&mapData.heightmap)
        }
        
        if params.contrastEnhancement != 1.0 {
            MathUtils.applyContrast(&mapData.heightmap, strength: params.contrastEnhancement)
        }
        
        if params.terraceCount > 0 {
            applyTerracing(
                heightmap: &mapData.heightmap,
                steps: params.terraceCount,
                sharpness: params.terraceSharpness
            )
        }
    }
    
    private func applySmoothing(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        passes: Int,
        strength: Float
    ) {
        heightmapService.applySmoothing(
            heightmap: &heightmap,
            width: width,
            height: height,
            passes: passes,
            strength: strength
        )
    }
    
    private func applyTerracing(
        heightmap: inout [Float],
        steps: Int,
        sharpness: Float
    ) {
        heightmapService.applyTerracing(
            heightmap: &heightmap,
            steps: steps,
            sharpness: sharpness
        )
    }
    
    public func applyColorCorrection(
        colors: inout [SIMD4<Float>],
        brightness: Float = 1.0,
        contrast: Float = 1.0,
        saturation: Float = 1.0
    ) {
        for i in 0..<colors.count {
            var color = colors[i]
            
            color.x *= brightness
            color.y *= brightness
            color.z *= brightness
            
            color.x = (color.x - 0.5) * contrast + 0.5
            color.y = (color.y - 0.5) * contrast + 0.5
            color.z = (color.z - 0.5) * contrast + 0.5
            
            let gray = color.x * 0.299 + color.y * 0.587 + color.z * 0.114
            color.x = MathUtils.lerp(gray, color.x, saturation)
            color.y = MathUtils.lerp(gray, color.y, saturation)
            color.z = MathUtils.lerp(gray, color.z, saturation)
            
            color.x = MathUtils.clamp(color.x, 0, 1)
            color.y = MathUtils.clamp(color.y, 0, 1)
            color.z = MathUtils.clamp(color.z, 0, 1)
            
            colors[i] = color
        }
    }
    
    public func generateNormalMap(
        heightmap: [Float],
        width: Int,
        height: Int,
        strength: Float = 1.0
    ) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: width * height)
        
        DispatchQueue.concurrentPerform(iterations: height) { y in
            for x in 0..<width {
                let idx = y * width + x
                
                let left = x > 0 ? heightmap[idx - 1] : heightmap[idx]
                let right = x < width - 1 ? heightmap[idx + 1] : heightmap[idx]
                let up = y > 0 ? heightmap[idx - width] : heightmap[idx]
                let down = y < height - 1 ? heightmap[idx + width] : heightmap[idx]
                
                let dx = (right - left) * strength
                let dy = (down - up) * strength
                
                var normal = SIMD3<Float>(-dx, -dy, 1)
                normal = normalize(normal)
                
                normals[idx] = normal
            }
        }
        
        return normals
    }
    
    public func generateAmbientOcclusion(
        heightmap: [Float],
        width: Int,
        height: Int,
        radius: Int = 3,
        intensity: Float = 1.0
    ) -> [Float] {
        var ao = [Float](repeating: 1, count: width * height)
        
        DispatchQueue.concurrentPerform(iterations: height) { y in
            for x in 0..<width {
                let idx = y * width + x
                let h = heightmap[idx]
                
                var occlusion: Float = 0
                var samples: Float = 0
                
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        if dx == 0 && dy == 0 {
                            continue
                        }
                        
                        let nx = x + dx
                        let ny = y + dy
                        
                        if nx >= 0 && nx < width && ny >= 0 && ny < height {
                            let nidx = ny * width + nx
                            let nh = heightmap[nidx]
                            
                            if nh > h {
                                let dist = sqrt(Float(dx * dx + dy * dy))
                                let heightDiff = nh - h
                                occlusion += heightDiff / dist
                            }
                            
                            samples += 1
                        }
                    }
                }
                
                if samples > 0 {
                    let normalizedOcclusion = min(occlusion / samples * intensity, 1)
                    ao[idx] = 1 - normalizedOcclusion
                }
            }
        }
        
        return ao
    }
}
