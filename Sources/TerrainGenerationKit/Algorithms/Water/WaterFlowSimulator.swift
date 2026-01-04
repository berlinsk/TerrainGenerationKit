import Foundation
import simd

public final class WaterFlowSimulator: @unchecked Sendable {
    
    public let params: WaterParameters
    private let random: SeededRandom
    
    public init(params: WaterParameters, seed: UInt64) {
        self.params = params
        self.random = SeededRandom(seed: seed)
    }
    
    public func simulate(
        heightmap: [Float],
        width: Int,
        height: Int,
        seaLevel: Float
    ) -> WaterData {
        var waterData = WaterData(width: width, height: height)
        
        let (flowAccumulation, flowDirections) = calculateFlowAccumulation(
            heightmap: heightmap,
            width: width,
            height: height,
            seaLevel: seaLevel
        )
        
        let riverSources = findRiverSources(
            heightmap: heightmap,
            flowAccumulation: flowAccumulation,
            width: width,
            height: height,
            seaLevel: seaLevel,
            count: params.riverCount
        )
        
        for source in riverSources {
            traceRiver(
                from: source,
                heightmap: heightmap,
                flowDirections: flowDirections,
                waterData: &waterData,
                width: width,
                height: height,
                seaLevel: seaLevel
            )
        }
        
        widenRivers(
            waterData: &waterData,
            flowAccumulation: flowAccumulation,
            width: width,
            height: height
        )
        
        fillLakes(
            heightmap: heightmap,
            waterData: &waterData,
            width: width,
            height: height,
            seaLevel: seaLevel
        )
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                waterData.flowDirection[idx] = flowDirections[idx].rawValue
            }
        }
        
        return waterData
    }
    
    private func calculateFlowAccumulation(
        heightmap: [Float],
        width: Int,
        height: Int,
        seaLevel: Float
    ) -> (accumulation: [Float], directions: [FlowDirection]) {
        var flowDirections = [FlowDirection](repeating: .none, count: width * height)
        var flowAccumulation = [Float](repeating: 1, count: width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let h = heightmap[idx]
                
                if h < seaLevel {
                    continue
                }
                
                var steepestDir = FlowDirection.none
                var steepestSlope: Float = 0
                
                for dir in FlowDirection.all {
                    let (dx, dy) = dir.offset
                    let nx = x + dx
                    let ny = y + dy
                    
                    if nx >= 0 && nx < width && ny >= 0 && ny < height {
                        let nidx = ny * width + nx
                        let nh = heightmap[nidx]
                        let dist = sqrt(Float(dx * dx + dy * dy))
                        let slope = (h - nh) / dist
                        
                        if slope > steepestSlope {
                            steepestSlope = slope
                            steepestDir = dir
                        }
                    }
                }
                
                flowDirections[idx] = steepestDir
            }
        }
        
        var sortedIndices = Array(0..<(width * height))
        sortedIndices.sort { heightmap[$0] > heightmap[$1] }
        
        for idx in sortedIndices {
            let dir = flowDirections[idx]
            if dir == .none {
                continue
            }
            
            let y = idx / width
            let x = idx % width
            let (dx, dy) = dir.offset
            let nx = x + dx
            let ny = y + dy
            
            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                let nidx = ny * width + nx
                flowAccumulation[nidx] += flowAccumulation[idx]
            }
        }
        
        return (flowAccumulation, flowDirections)
    }
    
    private func findRiverSources(
        heightmap: [Float],
        flowAccumulation: [Float],
        width: Int,
        height: Int,
        seaLevel: Float,
        count: Int
    ) -> [RiverSource] {
        var candidates: [(x: Int, y: Int, score: Float)] = []
        
        let minHeight = seaLevel + 0.15
        let maxHeight: Float = 0.9
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let h = heightmap[idx]
                
                if h >= minHeight && h <= maxHeight {
                    let heightScore = (h - seaLevel) / (1 - seaLevel)
                    let flowScore = min(flowAccumulation[idx] / 100, 1)
                    let score = heightScore * 0.7 + flowScore * 0.3
                    
                    candidates.append((x, y, score))
                }
            }
        }
        
        candidates.sort { $0.score > $1.score }
        
        var sources: [RiverSource] = []
        let minDistance: Float = Float(min(width, height)) / Float(count + 1)
        
        for candidate in candidates {
            if sources.count >= count {
                break
            }
            
            let pos = SIMD2<Float>(Float(candidate.x), Float(candidate.y))
            var tooClose = false
            
            for existing in sources {
                let existingPos = SIMD2<Float>(
                    Float(existing.position.x),
                    Float(existing.position.y)
                )
                if simd_distance(pos, existingPos) < minDistance {
                    tooClose = true
                    break
                }
            }
            
            if !tooClose {
                sources.append(RiverSource(
                    x: candidate.x,
                    y: candidate.y,
                    strength: candidate.score
                ))
            }
        }
        
        return sources
    }
    
    private func traceRiver(
        from source: RiverSource,
        heightmap: [Float],
        flowDirections: [FlowDirection],
        waterData: inout WaterData,
        width: Int,
        height: Int,
        seaLevel: Float
    ) {
        var x = source.position.x
        var y = source.position.y
        var riverWidth: Float = params.riverWidth * 0.5
        var visited = Set<Int>()
        
        let maxSteps = width + height
        
        for _ in 0..<maxSteps {
            let idx = y * width + x
            
            if visited.contains(idx) {
                break
            }
            if heightmap[idx] < seaLevel {
                break
            }
            
            visited.insert(idx)
            
            waterData.riverMask[idx] = 1.0
            waterData.waterLevel[idx] = riverWidth
            
            riverWidth = min(riverWidth + 0.001, params.riverWidth * 2)
            
            let dir = flowDirections[idx]
            if dir == .none {
                var foundDir = false
                for checkDir in FlowDirection.all {
                    let (dx, dy) = checkDir.offset
                    let nx = x + dx
                    let ny = y + dy
                    
                    if nx >= 0 && nx < width && ny >= 0 && ny < height {
                        let nidx = ny * width + nx
                        if heightmap[nidx] < heightmap[idx] {
                            x = nx
                            y = ny
                            foundDir = true
                            break
                        }
                    }
                }
                if !foundDir {
                    break
                }
            } else {
                let (dx, dy) = dir.offset
                x += dx
                y += dy
            }
            
            if random.nextFloat() < params.riverMeandering {
                let perpendicular: [(dx: Int, dy: Int)]
                let currentDir = flowDirections[idx]
                switch currentDir {
                case .north, .south:
                    perpendicular = [(1, 0), (-1, 0)]
                case .east, .west:
                    perpendicular = [(0, 1), (0, -1)]
                default:
                    perpendicular = []
                }
                
                if let offset = random.pick(from: perpendicular) {
                    let nx = x + offset.dx
                    let ny = y + offset.dy
                    if nx >= 0 && nx < width && ny >= 0 && ny < height {
                        let nidx = ny * width + nx
                        waterData.riverMask[nidx] = max(waterData.riverMask[nidx], 0.5)
                    }
                }
            }
            
            if x < 0 || x >= width || y < 0 || y >= height {
                break
            }
        }
    }
    
    private func widenRivers(
        waterData: inout WaterData,
        flowAccumulation: [Float],
        width: Int,
        height: Int
    ) {
        var newRiverMask = waterData.riverMask
        
        let maxFlow = flowAccumulation.max() ?? 1
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                
                if waterData.riverMask[idx] > 0 {
                    let flowRatio = flowAccumulation[idx] / maxFlow
                    let extraWidth = Int(flowRatio * 3)
                    
                    for dy in -extraWidth...extraWidth {
                        for dx in -extraWidth...extraWidth {
                            let nx = x + dx
                            let ny = y + dy
                            
                            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                                let dist = sqrt(Float(dx * dx + dy * dy))
                                if dist <= Float(extraWidth) {
                                    let nidx = ny * width + nx
                                    let strength = 1 - dist / Float(extraWidth + 1)
                                    newRiverMask[nidx] = max(
                                        newRiverMask[nidx],
                                        waterData.riverMask[idx] * strength
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        
        waterData.riverMask = newRiverMask
    }
    
    private func fillLakes(
        heightmap: [Float],
        waterData: inout WaterData,
        width: Int,
        height: Int,
        seaLevel: Float
    ) {
        var depressions: [(x: Int, y: Int, depth: Float)] = []
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let h = heightmap[idx]
                
                if h < seaLevel || waterData.riverMask[idx] > 0.5 {
                    continue
                }
                
                var isMinimum = true
                var minNeighbor: Float = Float.greatestFiniteMagnitude
                
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 {
                            continue
                        }
                        
                        let nidx = (y + dy) * width + (x + dx)
                        let nh = heightmap[nidx]
                        
                        if nh < h {
                            isMinimum = false
                            break
                        }
                        minNeighbor = min(minNeighbor, nh)
                    }
                    if !isMinimum {
                        break
                    }
                }
                
                if isMinimum && minNeighbor > h {
                    let depth = minNeighbor - h
                    if depth > params.lakeThreshold * 0.1 {
                        depressions.append((x, y, depth))
                    }
                }
            }
        }
        
        for depression in depressions {
            floodFillLake(
                startX: depression.x,
                startY: depression.y,
                heightmap: heightmap,
                waterData: &waterData,
                width: width,
                height: height,
                maxDepth: depression.depth
            )
        }
    }
    
    private func floodFillLake(
        startX: Int,
        startY: Int,
        heightmap: [Float],
        waterData: inout WaterData,
        width: Int,
        height: Int,
        maxDepth: Float
    ) {
        let startIdx = startY * width + startX
        let waterLevel = heightmap[startIdx] + maxDepth * 0.5
        
        var queue: [(x: Int, y: Int)] = [(startX, startY)]
        var visited = Set<Int>()
        var lakePixels: [Int] = []
        
        while !queue.isEmpty {
            let (x, y) = queue.removeFirst()
            let idx = y * width + x
            
            if visited.contains(idx) {
                continue
            }
            visited.insert(idx)
            
            if heightmap[idx] > waterLevel {
                continue
            }
            
            lakePixels.append(idx)
            
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let nx = x + dx
                let ny = y + dy
                
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let nidx = ny * width + nx
                    if !visited.contains(nidx) {
                        queue.append((nx, ny))
                    }
                }
            }
        }
        
        if lakePixels.count >= params.lakeMinSize {
            for idx in lakePixels {
                waterData.lakeMask[idx] = 1.0
                waterData.waterLevel[idx] = waterLevel - heightmap[idx]
            }
        }
    }
}

struct RiverSource {
    let position: SIMD2<Int>
    let strength: Float
    
    init(x: Int, y: Int, strength: Float = 1.0) {
        self.position = SIMD2(x, y)
        self.strength = strength
    }
}
