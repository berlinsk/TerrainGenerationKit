import Foundation
import simd

public protocol WaterFlowServiceProtocol: Sendable {
    func generateWaterBodies(
        heightmap: [Float],
        width: Int,
        height: Int,
        params: WaterParameters,
        seaLevel: Float,
        seed: UInt64
    ) -> WaterData
}

public final class WaterFlowService: WaterFlowServiceProtocol, @unchecked Sendable {
    
    public init() {}
    
    public func generateWaterBodies(
        heightmap: [Float],
        width: Int,
        height: Int,
        params: WaterParameters,
        seaLevel: Float,
        seed: UInt64
    ) -> WaterData {
        let simulator = WaterFlowSimulator(params: params, seed: seed)
        
        var waterData = simulator.simulate(
            heightmap: heightmap,
            width: width,
            height: height,
            seaLevel: seaLevel
        )
        
        smoothRivers(
            waterData: &waterData,
            width: width,
            height: height
        )
        
        addRiverDeltas(
            waterData: &waterData,
            heightmap: heightmap,
            width: width,
            height: height,
            seaLevel: seaLevel
        )

        normalizeWaterDepth(waterData: &waterData)

        return waterData
    }
    
    private func smoothRivers(
        waterData: inout WaterData,
        width: Int,
        height: Int
    ) {
        var smoothed = waterData.riverMask
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                
                if waterData.riverMask[idx] > 0 {
                    var sum: Float = waterData.riverMask[idx] * 4
                    var count: Float = 4
                    
                    let neighbors = [
                        (0, -1), (0, 1), (-1, 0), (1, 0),
                        (-1, -1), (1, -1), (-1, 1), (1, 1)
                    ]
                    
                    for (dx, dy) in neighbors {
                        let nidx = (y + dy) * width + (x + dx)
                        let weight: Float = abs(dx) + abs(dy) == 1 ? 2 : 1
                        sum += waterData.riverMask[nidx] * weight
                        count += weight
                    }
                    
                    smoothed[idx] = sum / count
                }
            }
        }
        
        waterData.riverMask = smoothed
    }
    
    private func normalizeWaterDepth(waterData: inout WaterData) {
        guard let maxDepth = waterData.waterDepth.max(), maxDepth > 0 else { return }
        for i in 0..<waterData.waterDepth.count {
            waterData.waterDepth[i] /= maxDepth
        }
    }

    private func addRiverDeltas(
        waterData: inout WaterData,
        heightmap: [Float],
        width: Int,
        height: Int,
        seaLevel: Float
    ) {
        var riverMouths: [(x: Int, y: Int)] = []
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                
                if waterData.riverMask[idx] > 0.5 && heightmap[idx] >= seaLevel {
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nidx = (y + dy) * width + (x + dx)
                        if heightmap[nidx] < seaLevel {
                            riverMouths.append((x, y))
                            break
                        }
                    }
                }
            }
        }
        
        for mouth in riverMouths {
            let deltaSize = 3
            
            for dy in -deltaSize...deltaSize {
                for dx in -deltaSize...deltaSize {
                    let nx = mouth.x + dx
                    let ny = mouth.y + dy
                    
                    if nx >= 0 && nx < width && ny >= 0 && ny < height {
                        let nidx = ny * width + nx
                        let dist = sqrt(Float(dx * dx + dy * dy))
                        
                        if dist <= Float(deltaSize) && heightmap[nidx] < seaLevel + 0.02 {
                            let strength = 1 - dist / Float(deltaSize + 1)
                            waterData.riverMask[nidx] = max(
                                waterData.riverMask[nidx],
                                strength * 0.6
                            )
                        }
                    }
                }
            }
        }
    }
}
