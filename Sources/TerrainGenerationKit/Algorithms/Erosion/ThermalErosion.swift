import Foundation

public final class ThermalErosion: @unchecked Sendable {
    
    public let params: ErosionParameters
    
    public init(params: ErosionParameters) {
        self.params = params
    }
    
    public func erode(heightmap: inout [Float], width: Int, height: Int, iterations: Int? = nil) {
        let iters = iterations ?? params.iterations / 100
        
        let talusAngle = params.thermalTalusAngle
        let erosionRate: Float = 0.5
        
        for _ in 0..<iters {
            var newHeightmap = heightmap
            
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let idx = y * width + x
                    let h = heightmap[idx]
                    
                    let neighbors: [(dx: Int, dy: Int)] = [
                        (-1, -1), (0, -1), (1, -1),
                        (-1, 0),          (1, 0),
                        (-1, 1),  (0, 1),  (1, 1)
                    ]
                    
                    var maxDiff: Float = 0
                    var totalDiff: Float = 0
                    var diffs: [(idx: Int, diff: Float)] = []
                    
                    for (dx, dy) in neighbors {
                        let nidx = (y + dy) * width + (x + dx)
                        let nh = heightmap[nidx]
                        let diff = h - nh
                        
                        if diff > talusAngle {
                            diffs.append((nidx, diff))
                            totalDiff += diff
                            maxDiff = max(maxDiff, diff)
                        }
                    }
                    
                    if totalDiff > 0 {
                        let redistributed = (maxDiff - talusAngle) * erosionRate
                        newHeightmap[idx] -= redistributed
                        
                        for (nidx, diff) in diffs {
                            let proportion = diff / totalDiff
                            newHeightmap[nidx] += redistributed * proportion
                        }
                    }
                }
            }
            
            heightmap = newHeightmap
        }
    }
}
