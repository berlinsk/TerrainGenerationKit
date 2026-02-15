import Foundation
import simd

public final class RoadGenerator: @unchecked Sendable {
    
    private let params: CityGenerationParameters
    private var rng: SeededRandom
    
    private struct TerrainCost {
        static let deepWater: Float = 10000
        static let shallowWater: Float = 500
        static let river: Float = 300
        static let mountain: Float = 80
        static let highHill: Float = 40
        static let hill: Float = 15
        static let forest: Float = 8
        static let marsh: Float = 25
        static let desert: Float = 4
        static let snow: Float = 12
        static let plain: Float = 1
        static let beach: Float = 2
        static let existingRoad: Float = 0.3
    }
    
    public init(params: CityGenerationParameters, seed: UInt64) {
        self.params = params
        self.rng = SeededRandom(seed: seed)
    }
    
    public func generateRoads(
        cities: [City],
        heightmap: [Float],
        biomeMap: [UInt8],
        waterData: WaterData,
        width: Int,
        height: Int,
        seaLevel: Float
    ) -> [Road] {
        guard cities.count >= 2 else {
            return []
        }
        
        let costMap = buildCostMap(
            heightmap: heightmap,
            biomeMap: biomeMap,
            waterData: waterData,
            cities: cities,
            width: width,
            height: height,
            seaLevel: seaLevel
        )
        
        let connections = findMinimumSpanningTree(
            cities: cities,
            costMap: costMap,
            width: width,
            height: height
        )
        
        var roads: [Road] = []
        var existingRoadTiles = Set<SIMD2<Int>>()
        
        for (fromIdx, toIdx) in connections {
            let fromCity = cities[fromIdx]
            let toCity = cities[toIdx]
            
            if let path = findPathOptimized(
                from: fromCity.center,
                to: toCity.center,
                costMap: costMap,
                existingRoads: existingRoadTiles,
                width: width,
                height: height
            ) {
                let smoothedPath = smoothPath(path, costMap: costMap, width: width, height: height)
                
                var road = Road(from: fromCity.id, to: toCity.id, path: smoothedPath)
                road.hasBridge = pathCrossesWater(
                    path: smoothedPath,
                    waterData: waterData,
                    heightmap: heightmap,
                    seaLevel: seaLevel
                )
                
                roads.append(road)
                
                for point in smoothedPath {
                    existingRoadTiles.insert(point)
                    for dx in -1...1 {
                        for dy in -1...1 {
                            existingRoadTiles.insert(SIMD2(point.x + dx, point.y + dy))
                        }
                    }
                }
            }
        }
        
        if cities.count > 4 {
            let additionalConnections = findAdditionalConnections(
                cities: cities,
                existingConnections: connections
            )
            
            for (fromIdx, toIdx) in additionalConnections {
                let fromCity = cities[fromIdx]
                let toCity = cities[toIdx]
                
                if let path = findPathOptimized(
                    from: fromCity.center,
                    to: toCity.center,
                    costMap: costMap,
                    existingRoads: existingRoadTiles,
                    width: width,
                    height: height
                ) {
                    let smoothedPath = smoothPath(path, costMap: costMap, width: width, height: height)
                    var road = Road(from: fromCity.id, to: toCity.id, path: smoothedPath)
                    road.hasBridge = pathCrossesWater(
                        path: smoothedPath,
                        waterData: waterData,
                        heightmap: heightmap,
                        seaLevel: seaLevel
                    )
                    roads.append(road)
                    
                    for point in smoothedPath {
                        existingRoadTiles.insert(point)
                    }
                }
            }
        }
        
        return roads
    }
    
    private func buildCostMap(
        heightmap: [Float],
        biomeMap: [UInt8],
        waterData: WaterData,
        cities: [City],
        width: Int,
        height: Int,
        seaLevel: Float
    ) -> [Float] {
        var costMap = [Float](repeating: 1, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let h = heightmap[idx]
                let biome = BiomeType(rawValue: Int(biomeMap[idx])) ?? .grassland
                
                var cost: Float = TerrainCost.plain
                
                if waterData.riverMask[idx] > 0.5 {
                    cost = TerrainCost.river
                } else if waterData.lakeMask[idx] > 0.5 {
                    cost = TerrainCost.shallowWater
                } else if h < seaLevel {
                    let depth = seaLevel - h
                    if depth > 0.15 {
                        cost = TerrainCost.deepWater
                    } else {
                        cost = TerrainCost.shallowWater
                    }
                } else {
                    switch biome {
                    case .deepOcean, .ocean:
                        cost = TerrainCost.deepWater
                    case .shallowWater, .lake, .river:
                        cost = TerrainCost.shallowWater
                    case .beach:
                        cost = TerrainCost.beach
                    case .grassland:
                        cost = TerrainCost.plain
                    case .forest:
                        cost = TerrainCost.forest
                    case .rainforest:
                        cost = TerrainCost.forest * 1.5
                    case .desert:
                        cost = TerrainCost.desert
                    case .savanna:
                        cost = TerrainCost.plain * 1.5
                    case .taiga:
                        cost = TerrainCost.forest * 1.2
                    case .tundra:
                        cost = TerrainCost.snow * 0.7
                    case .snow:
                        cost = TerrainCost.snow
                    case .mountain:
                        cost = TerrainCost.mountain
                    case .snowyMountain:
                        cost = TerrainCost.mountain * 1.5
                    case .marsh:
                        cost = TerrainCost.marsh
                    }
                    
                    if h > 0.7 {
                        cost += (h - 0.7) * TerrainCost.highHill * 3
                    } else if h > 0.55 {
                        cost += (h - 0.55) * TerrainCost.hill
                    }
                    
                    let slope = calculateSlope(heightmap: heightmap, x: x, y: y, width: width, height: height)
                    cost += slope * 20
                }
                
                if costMap[idx] < 50000 {
                    costMap[idx] = cost
                }
            }
        }
        
        return costMap
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
    
    private func findPathOptimized(
        from start: SIMD2<Int>,
        to goal: SIMD2<Int>,
        costMap: [Float],
        existingRoads: Set<SIMD2<Int>>,
        width: Int,
        height: Int
    ) -> [SIMD2<Int>]? {
        let distance = abs(start.x - goal.x) + abs(start.y - goal.y)
        
        if distance > 200 {
            return findPathHierarchical(
                from: start,
                to: goal,
                costMap: costMap,
                existingRoads: existingRoads,
                width: width,
                height: height
            )
        }
        
        let pathfinder = AStarPathfinder(costMap: costMap, width: width, height: height)
        return pathfinder.findPath(from: start, to: goal, existingRoads: existingRoads, maxIterations: 150000)
    }
    
    private func findPathHierarchical(
        from start: SIMD2<Int>,
        to goal: SIMD2<Int>,
        costMap: [Float],
        existingRoads: Set<SIMD2<Int>>,
        width: Int,
        height: Int
    ) -> [SIMD2<Int>]? {
        let waypoints = findWaypoints(from: start, to: goal, costMap: costMap, width: width, height: height)
        
        var fullPath: [SIMD2<Int>] = []
        var currentStart = start
        var currentRoads = existingRoads
        
        let pathfinder = AStarPathfinder(costMap: costMap, width: width, height: height)
        
        for waypoint in waypoints {
            let dist = abs(currentStart.x - waypoint.x) + abs(currentStart.y - waypoint.y)
            if let segment = pathfinder.findPath(
                from: currentStart,
                to: waypoint,
                existingRoads: currentRoads,
                maxIterations: max(10000, dist * dist)
            ) {
                if !fullPath.isEmpty {
                    fullPath.removeLast()
                }
                fullPath.append(contentsOf: segment)
                for p in segment {
                    currentRoads.insert(p)
                }
                currentStart = waypoint
            } else {
                let smartSegment = createSmartPath(
                    from: currentStart,
                    to: waypoint,
                    costMap: costMap,
                    width: width,
                    height: height
                )
                fullPath.append(contentsOf: smartSegment)
                currentStart = smartSegment.last ?? waypoint
            }
        }

        let finalDist = abs(currentStart.x - goal.x) + abs(currentStart.y - goal.y)
        if let finalSegment = pathfinder.findPath(
            from: currentStart,
            to: goal,
            existingRoads: currentRoads,
            maxIterations: max(10000, finalDist * finalDist)
        ) {
            if !fullPath.isEmpty {
                fullPath.removeLast()
            }
            fullPath.append(contentsOf: finalSegment)
        } else {
            fullPath.append(contentsOf: createSmartPath(
                from: currentStart,
                to: goal,
                costMap: costMap,
                width: width,
                height: height
            ))
        }
        
        return fullPath.last == goal ? fullPath : nil
    }
    
    private func findWaypoints(
        from start: SIMD2<Int>,
        to goal: SIMD2<Int>,
        costMap: [Float],
        width: Int,
        height: Int
    ) -> [SIMD2<Int>] {
        var waypoints: [SIMD2<Int>] = []
        
        let dx = goal.x - start.x
        let dy = goal.y - start.y
        let distance = max(abs(dx), abs(dy))
        let numWaypoints = max(2, distance / 100)
        
        for i in 1..<numWaypoints {
            let t = Float(i) / Float(numWaypoints)
            var x = start.x + Int(Float(dx) * t)
            var y = start.y + Int(Float(dy) * t)
            
            (x, y) = findBetterPosition(x: x, y: y, costMap: costMap, width: width, height: height, searchRadius: 15)
            
            waypoints.append(SIMD2(x, y))
        }
        
        return waypoints
    }
    
    private func findBetterPosition(
        x: Int,
        y: Int,
        costMap: [Float],
        width: Int,
        height: Int,
        searchRadius: Int
    ) -> (Int, Int) {
        var bestX = x
        var bestY = y
        var bestCost = costMap[y * width + x]
        
        for dy in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                let nx = x + dx
                let ny = y + dy
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let cost = costMap[ny * width + nx]
                    if cost < bestCost {
                        bestCost = cost
                        bestX = nx
                        bestY = ny
                    }
                }
            }
        }
        
        return (bestX, bestY)
    }
    
    private func createSmartPath(
        from start: SIMD2<Int>,
        to goal: SIMD2<Int>,
        costMap: [Float],
        width: Int,
        height: Int
    ) -> [SIMD2<Int>] {
        var path: [SIMD2<Int>] = [start]
        var current = start
        
        while current != goal {
            let dx = goal.x - current.x
            let dy = goal.y - current.y
            
            var candidates: [(SIMD2<Int>, Float)] = []
            
            let directions: [(Int, Int)] = [
                (dx.signum(), dy.signum()),
                (dx.signum(), 0),
                (0, dy.signum()),
                (dx.signum(), -dy.signum()),
                (-dx.signum(), dy.signum()),
            ]
            
            for (ddx, ddy) in directions {
                if ddx == 0 && ddy == 0 {
                    continue
                }
                let nx = current.x + ddx
                let ny = current.y + ddy
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let cost = costMap[ny * width + nx]
                    candidates.append((SIMD2(nx, ny), cost))
                }
            }
            
            candidates.sort { $0.1 < $1.1 }
            if let best = candidates.first {
                current = best.0
                path.append(current)
            } else {
                break
            }
            
            if path.count > width + height {
                break
            }
        }
        
        return path
    }
    
    private func smoothPath(
        _ path: [SIMD2<Int>],
        costMap: [Float],
        width: Int,
        height: Int
    ) -> [SIMD2<Int>] {
        guard path.count > 2 else {
            return path
        }
        
        var bridgedPath = makeBridgesStraight(path, costMap: costMap, width: width, height: height)
        
        var smoothed = [bridgedPath[0]]
        var i = 0
        
        while i < bridgedPath.count - 1 {
            var farthest = i + 1
            
            for j in (i + 2)..<min(i + 10, bridgedPath.count) {
                if canSkipTo(from: bridgedPath[i], to: bridgedPath[j], costMap: costMap, width: width, height: height) {
                    farthest = j
                }
            }
            
            let segment = interpolatePath(from: bridgedPath[i], to: bridgedPath[farthest])
            smoothed.append(contentsOf: segment.dropFirst())
            
            i = farthest
        }
        
        return smoothed
    }
    
    private func makeBridgesStraight(
        _ path: [SIMD2<Int>],
        costMap: [Float],
        width: Int,
        height: Int
    ) -> [SIMD2<Int>] {
        guard path.count > 2 else {
            return path
        }
        
        var result: [SIMD2<Int>] = []
        var i = 0
        
        while i < path.count {
            let point = path[i]
            let idx = point.y * width + point.x
            let isWater = idx >= 0 && idx < costMap.count && costMap[idx] >= 200
            
            if isWater {
                var waterStart = i
                var waterEnd = i
                
                while waterStart > 0 {
                    let prevIdx = path[waterStart - 1].y * width + path[waterStart - 1].x
                    if prevIdx >= 0 && prevIdx < costMap.count && costMap[prevIdx] >= 200 {
                        waterStart -= 1
                    } else {
                        break
                    }
                }
                
                while waterEnd < path.count - 1 {
                    let nextIdx = path[waterEnd + 1].y * width + path[waterEnd + 1].x
                    if nextIdx >= 0 && nextIdx < costMap.count && costMap[nextIdx] >= 200 {
                        waterEnd += 1
                    } else {
                        break
                    }
                }
                
                if waterStart > 0 && (result.isEmpty || result.last != path[waterStart - 1]) {
                    result.append(path[max(0, waterStart - 1)])
                }
                
                let bridgeStart = path[max(0, waterStart - 1)]
                let bridgeEnd = path[min(path.count - 1, waterEnd + 1)]
                let bridgePath = interpolatePath(from: bridgeStart, to: bridgeEnd)
                
                for bp in bridgePath {
                    if result.isEmpty || result.last != bp {
                        result.append(bp)
                    }
                }
                
                i = waterEnd + 2
            } else {
                if result.isEmpty || result.last != point {
                    result.append(point)
                }
                i += 1
            }
        }
        
        return result.isEmpty ? path : result
    }
    
    private func canSkipTo(
        from: SIMD2<Int>,
        to: SIMD2<Int>,
        costMap: [Float],
        width: Int,
        height: Int
    ) -> Bool {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let steps = max(abs(dx), abs(dy))
        
        for step in 0...steps {
            let t = Float(step) / Float(max(steps, 1))
            let x = from.x + Int(Float(dx) * t)
            let y = from.y + Int(Float(dy) * t)
            
            if x >= 0 && x < width && y >= 0 && y < height {
                let cost = costMap[y * width + x]
                if cost > 100 {
                    return false
                }
            }
        }
        
        return true
    }
    
    private func interpolatePath(from: SIMD2<Int>, to: SIMD2<Int>) -> [SIMD2<Int>] {
        var path: [SIMD2<Int>] = []
        
        var x0 = from.x
        var y0 = from.y
        let x1 = to.x
        let y1 = to.y
        
        let dx = abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        
        while true {
            path.append(SIMD2(x0, y0))
            if x0 == x1 && y0 == y1 {
                break
            }
            
            let e2 = 2 * err
            if e2 >= dy {
                err += dy
                x0 += sx
            }
            if e2 <= dx {
                err += dx
                y0 += sy
            }
        }
        
        return path
    }
    
    private func findMinimumSpanningTree(
        cities: [City],
        costMap: [Float],
        width: Int,
        height: Int
    ) -> [(Int, Int)] {
        let n = cities.count
        guard n >= 2 else {
            return []
        }
        
        var distances = [[Float]](repeating: [Float](repeating: Float.infinity, count: n), count: n)
        
        for i in 0..<n {
            for j in (i + 1)..<n {
                let dx = Float(cities[i].center.x - cities[j].center.x)
                let dy = Float(cities[i].center.y - cities[j].center.y)
                let directDist = sqrt(dx * dx + dy * dy)
                
                let sampleCost = sampleTerrainCost(
                    from: cities[i].center,
                    to: cities[j].center,
                    costMap: costMap,
                    width: width
                )
                
                let estimatedCost = directDist * sampleCost
                distances[i][j] = estimatedCost
                distances[j][i] = estimatedCost
            }
        }
        
        var inMST = [Bool](repeating: false, count: n)
        var minEdge = [Float](repeating: Float.infinity, count: n)
        var parent = [Int](repeating: -1, count: n)
        
        minEdge[0] = 0
        var edges: [(Int, Int)] = []
        
        for _ in 0..<n {
            var minIdx = -1
            var minVal = Float.infinity
            
            for j in 0..<n {
                if !inMST[j] && minEdge[j] < minVal {
                    minVal = minEdge[j]
                    minIdx = j
                }
            }
            
            guard minIdx >= 0 else {
                break
            }
            
            inMST[minIdx] = true
            if parent[minIdx] >= 0 {
                edges.append((parent[minIdx], minIdx))
            }
            
            for j in 0..<n {
                if !inMST[j] && distances[minIdx][j] < minEdge[j] {
                    minEdge[j] = distances[minIdx][j]
                    parent[j] = minIdx
                }
            }
        }
        
        return edges
    }
    
    private func sampleTerrainCost(
        from: SIMD2<Int>,
        to: SIMD2<Int>,
        costMap: [Float],
        width: Int
    ) -> Float {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let steps = max(abs(dx), abs(dy))
        guard steps > 0 else {
            return 1
        }
        
        var totalCost: Float = 0
        let samples = min(steps, 30)
        
        for i in 0..<samples {
            let t = Float(i) / Float(samples)
            let x = from.x + Int(Float(dx) * t)
            let y = from.y + Int(Float(dy) * t)
            let idx = y * width + x
            
            if idx >= 0 && idx < costMap.count {
                totalCost += min(costMap[idx], 200)
            }
        }
        
        return totalCost / Float(samples)
    }
    
    private func findAdditionalConnections(
        cities: [City],
        existingConnections: [(Int, Int)]
    ) -> [(Int, Int)] {
        var additionalEdges: [(Int, Int)] = []
        let existingSet = Set(existingConnections.map { Set([$0.0, $0.1]) })
        
        for i in 0..<cities.count {
            if cities[i].size.rawValue < CitySize.city.rawValue {
                continue
            }
            
            var connectionCount = 0
            for (a, b) in existingConnections {
                if a == i || b == i {
                    connectionCount += 1
                }
            }
            
            if connectionCount < 2 {
                var bestJ = -1
                var bestDist = Float.infinity
                
                for j in 0..<cities.count {
                    if i == j {
                        continue
                    }
                    if existingSet.contains(Set([i, j])) {
                        continue
                    }
                    
                    let dx = Float(cities[i].center.x - cities[j].center.x)
                    let dy = Float(cities[i].center.y - cities[j].center.y)
                    let dist = sqrt(dx * dx + dy * dy)
                    
                    if dist < bestDist {
                        bestDist = dist
                        bestJ = j
                    }
                }
                
                if bestJ >= 0 {
                    additionalEdges.append((i, bestJ))
                }
            }
        }
        
        return additionalEdges
    }
    
    private func pathCrossesWater(
        path: [SIMD2<Int>],
        waterData: WaterData,
        heightmap: [Float],
        seaLevel: Float
    ) -> Bool {
        for point in path {
            let idx = point.y * waterData.riverMask.count / heightmap.count * heightmap.count / waterData.riverMask.count + point.x
            if idx >= 0 && idx < waterData.riverMask.count {
                if waterData.riverMask[idx] > 0.5 {
                    return true
                }
                if waterData.lakeMask[idx] > 0.5 {
                    return true
                }
            }
        }
        return false
    }
}

extension Int {
    func signum() -> Int {
        if self > 0 {
            return 1
        }
        if self < 0 {
            return -1
        }
        return 0
    }
}
