import Foundation
import simd

public final class HydraulicErosion: @unchecked Sendable {
    
    public let params: ErosionParameters
    private let random: SeededRandom
    
    private var brushIndices: [[Int]] = []
    private var brushWeights: [[Float]] = []
    private let brushRadius: Int = 3
    
    public init(params: ErosionParameters, seed: UInt64) {
        self.params = params
        self.random = SeededRandom(seed: seed)
    }
    
    public func erode(heightmap: inout [Float], width: Int, height: Int) {
        guard params.iterations > 0 else {
            return
        }
        
        initializeBrush(width: width, height: height)
        
        for _ in 0..<params.iterations {
            simulateDroplet(heightmap: &heightmap, width: width, height: height)
        }
    }
    
    private func initializeBrush(width: Int, height: Int) {
        brushIndices = []
        brushWeights = []
        
        for y in 0..<height {
            for x in 0..<width {
                var indices = [Int]()
                var weights = [Float]()
                var weightSum: Float = 0
                
                for dy in -brushRadius...brushRadius {
                    for dx in -brushRadius...brushRadius {
                        let nx = x + dx
                        let ny = y + dy
                        
                        if nx >= 0 && nx < width && ny >= 0 && ny < height {
                            let dist = sqrt(Float(dx * dx + dy * dy))
                            if dist <= Float(brushRadius) {
                                let weight = 1 - dist / Float(brushRadius)
                                indices.append(ny * width + nx)
                                weights.append(weight)
                                weightSum += weight
                            }
                        }
                    }
                }
                
                if weightSum > 0 {
                    for i in 0..<weights.count {
                        weights[i] /= weightSum
                    }
                }
                
                brushIndices.append(indices)
                brushWeights.append(weights)
            }
        }
    }
    
    private func simulateDroplet(heightmap: inout [Float], width: Int, height: Int) {
        var pos = SIMD2<Float>(
            random.nextFloat(in: Float(brushRadius)...Float(width - brushRadius - 1)),
            random.nextFloat(in: Float(brushRadius)...Float(height - brushRadius - 1))
        )
        var dir = SIMD2<Float>.zero
        var vel: Float = 1
        var water: Float = 1
        var sediment: Float = 0
        
        for _ in 0..<params.dropletLifetime {
            let nodeX = Int(pos.x)
            let nodeY = Int(pos.y)
            let cellOffsetX = pos.x - Float(nodeX)
            let cellOffsetY = pos.y - Float(nodeY)
            let dropletIndex = nodeY * width + nodeX
            
            let (currentHeight, gradient) = calculateHeightAndGradient(
                heightmap: heightmap,
                width: width,
                height: height,
                posX: pos.x,
                posY: pos.y
            )
            
            dir = dir * params.inertia - gradient * (1 - params.inertia)
            
            let len = sqrt(dir.x * dir.x + dir.y * dir.y)
            if len > 0 {
                dir /= len
            } else {
                let angle = random.nextFloat() * Float.pi * 2
                dir = SIMD2(cos(angle), sin(angle))
            }
            
            let newPos = pos + dir
            
            if newPos.x < Float(brushRadius) || newPos.x >= Float(width - brushRadius - 1) ||
               newPos.y < Float(brushRadius) || newPos.y >= Float(height - brushRadius - 1) {
                break
            }
            
            let newHeight = calculateHeight(
                heightmap: heightmap,
                width: width,
                posX: newPos.x,
                posY: newPos.y
            )
            let deltaHeight = newHeight - currentHeight
            
            let sedimentCapacity = max(
                -deltaHeight * vel * water * params.sedimentCapacity,
                params.minSlope
            )
            
            if sediment > sedimentCapacity || deltaHeight > 0 {
                let depositAmount: Float
                if deltaHeight > 0 {
                    depositAmount = min(deltaHeight, sediment)
                } else {
                    depositAmount = (sediment - sedimentCapacity) * params.depositionRate
                }
                
                sediment -= depositAmount
                deposit(
                    heightmap: &heightmap,
                    index: dropletIndex,
                    amount: depositAmount,
                    cellOffsetX: cellOffsetX,
                    cellOffsetY: cellOffsetY,
                    width: width
                )
            } else {
                let erodeAmount = min(
                    (sedimentCapacity - sediment) * params.erosionStrength,
                    -deltaHeight
                )
                
                if dropletIndex >= 0 && dropletIndex < brushIndices.count {
                    let indices = brushIndices[dropletIndex]
                    let weights = brushWeights[dropletIndex]
                    
                    for i in 0..<indices.count {
                        let idx = indices[i]
                        if idx >= 0 && idx < heightmap.count {
                            let eroded = min(heightmap[idx], erodeAmount * weights[i])
                            heightmap[idx] -= eroded
                            sediment += eroded
                        }
                    }
                }
            }
            
            vel = sqrt(max(0, vel * vel + deltaHeight * params.gravity))
            water *= (1 - params.evaporationRate)
            pos = newPos
            
            if vel < 0.01 || water < 0.01 {
                break
            }
        }
    }
    
    private func calculateHeightAndGradient(
        heightmap: [Float],
        width: Int,
        height: Int,
        posX: Float,
        posY: Float
    ) -> (height: Float, gradient: SIMD2<Float>) {
        let coordX = Int(posX)
        let coordY = Int(posY)
        
        let x = posX - Float(coordX)
        let y = posY - Float(coordY)
        
        let idx = coordY * width + coordX
        
        let heightNW = heightmap[idx]
        let heightNE = heightmap[idx + 1]
        let heightSW = heightmap[idx + width]
        let heightSE = heightmap[idx + width + 1]
        
        let gradX = (heightNE - heightNW) * (1 - y) + (heightSE - heightSW) * y
        let gradY = (heightSW - heightNW) * (1 - x) + (heightSE - heightNE) * x
        
        let h = heightNW * (1 - x) * (1 - y) +
                heightNE * x * (1 - y) +
                heightSW * (1 - x) * y +
                heightSE * x * y
        
        return (h, SIMD2(gradX, gradY))
    }
    
    private func calculateHeight(
        heightmap: [Float],
        width: Int,
        posX: Float,
        posY: Float
    ) -> Float {
        let coordX = Int(posX)
        let coordY = Int(posY)
        
        let x = posX - Float(coordX)
        let y = posY - Float(coordY)
        
        let idx = coordY * width + coordX
        
        let heightNW = heightmap[idx]
        let heightNE = heightmap[idx + 1]
        let heightSW = heightmap[idx + width]
        let heightSE = heightmap[idx + width + 1]
        
        return heightNW * (1 - x) * (1 - y) +
               heightNE * x * (1 - y) +
               heightSW * (1 - x) * y +
               heightSE * x * y
    }
    
    private func deposit(
        heightmap: inout [Float],
        index: Int,
        amount: Float,
        cellOffsetX: Float,
        cellOffsetY: Float,
        width: Int
    ) {
        heightmap[index] += amount * (1 - cellOffsetX) * (1 - cellOffsetY)
        heightmap[index + 1] += amount * cellOffsetX * (1 - cellOffsetY)
        heightmap[index + width] += amount * (1 - cellOffsetX) * cellOffsetY
        heightmap[index + width + 1] += amount * cellOffsetX * cellOffsetY
    }
}
