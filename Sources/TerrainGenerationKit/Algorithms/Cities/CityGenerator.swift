import Foundation
import simd

public final class CityGenerator: @unchecked Sendable {
    
    private let params: CityGenerationParameters
    private var rng: SeededRandom
    private let streetWidth: Int = 2
    
    private let prefixes = [
        "North", "South", "East", "West", "New", "Old", "Port", "Fort",
        "Mount", "Lake", "River", "King's", "Queen's", "Saint", "High",
        "Low", "Great", "Upper", "Lower"
    ]
    
    private let roots = [
        "haven", "ford", "bridge", "ton", "ville", "burg", "dale", "field",
        "gate", "hill", "wood", "stone", "creek", "bay", "cliff", "vale",
        "brook", "marsh", "grove", "peak", "hollow", "spring", "meadow", "crest"
    ]
    
    private let suffixes = [
        "", " City", " Town", " Keep", " Hold", " Landing",
        " Crossing", " Falls", " Springs", " Harbor"
    ]
    
    public init(params: CityGenerationParameters, seed: UInt64) {
        self.params = params
        self.rng = SeededRandom(seed: seed)
    }
    
    public func generateCities(
        heightmap: [Float],
        biomeMap: [BiomeType],
        waterData: WaterData,
        width: Int,
        height: Int,
        seaLevel: Float
    ) -> [City] {
        guard params.enabled && params.cityCount > 0 else {
            return []
        }
        
        let riverDistanceMap = computeDistanceMap(
            width: width,
            height: height,
            isSeed: { x, y in waterData.riverMask[y * width + x] > 0.5 },
            maxDistance: 25
        )
        
        let coastDistanceMap = computeDistanceMap(
            width: width,
            height: height,
            isSeed: { x, y in heightmap[y * width + x] < seaLevel },
            maxDistance: 30
        )
        
        let locations = findCityLocations(
            heightmap: heightmap,
            biomeMap: biomeMap,
            riverDistanceMap: riverDistanceMap,
            coastDistanceMap: coastDistanceMap,
            width: width,
            height: height,
            seaLevel: seaLevel
        )
        
        var cities: [City] = []
        
        for (index, location) in locations.enumerated() {
            let citySize = determineCitySize(index: index, total: locations.count)
            let name = generateCityName()
            
            var city = City(name: name, center: location, size: citySize)
            
            generateCityLayout(
                city: &city,
                heightmap: heightmap,
                waterData: waterData,
                width: width,
                height: height,
                seaLevel: seaLevel
            )
            
            if rng.nextFloat() < citySize.hasWallsProbability {
                city.hasWalls = true
                generateOrganicWalls(
                    city: &city,
                    heightmap: heightmap,
                    waterData: waterData,
                    width: width,
                    height: height,
                    seaLevel: seaLevel
                )
            }
            
            cities.append(city)
        }
        
        return cities
    }
    
    private func computeDistanceMap(
        width: Int,
        height: Int,
        isSeed: (Int, Int) -> Bool,
        maxDistance: Int
    ) -> [Int] {
        var distanceMap = [Int](repeating: maxDistance + 1, count: width * height)
        var queue: [(Int, Int)] = []
        
        for y in 0..<height {
            for x in 0..<width {
                if isSeed(x, y) {
                    distanceMap[y * width + x] = 0
                    queue.append((x, y))
                }
            }
        }
        
        var head = 0
        let directions = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        
        while head < queue.count {
            let (x, y) = queue[head]
            head += 1
            
            let currentDist = distanceMap[y * width + x]
            if currentDist >= maxDistance {
                continue
            }
            
            for (dx, dy) in directions {
                let nx = x + dx
                let ny = y + dy
                
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let nidx = ny * width + nx
                    if distanceMap[nidx] > currentDist + 1 {
                        distanceMap[nidx] = currentDist + 1
                        queue.append((nx, ny))
                    }
                }
            }
        }
        
        return distanceMap
    }
    
    private func findCityLocations(
        heightmap: [Float],
        biomeMap: [BiomeType],
        riverDistanceMap: [Int],
        coastDistanceMap: [Int],
        width: Int,
        height: Int,
        seaLevel: Float
    ) -> [SIMD2<Int>] {
        let gridStep = max(8, min(width, height) / 64)
        var candidates: [(SIMD2<Int>, Float)] = []
        
        for y in stride(from: gridStep, to: height - gridStep, by: gridStep) {
            for x in stride(from: gridStep, to: width - gridStep, by: gridStep) {
                let idx = y * width + x
                let h = heightmap[idx]
                let biome = biomeMap[idx]
                
                if h < seaLevel || biome.isWater {
                    continue
                }
                if h > 0.72 {
                    continue
                }
                
                var score: Float = 0.5
                
                let flatness = calculateFlatness(
                    heightmap: heightmap,
                    x: x, y: y,
                    width: width, height: height
                )
                score += flatness * 0.3
                
                let riverDist = riverDistanceMap[idx]
                if riverDist > 2 && riverDist < 18 {
                    score += (1.0 - Float(riverDist) / 18.0) * params.preferRivers * 0.4
                }
                
                let coastDist = coastDistanceMap[idx]
                if coastDist > 5 && coastDist < 25 {
                    score += (1.0 - Float(coastDist) / 25.0) * params.preferCoast * 0.35
                }
                
                if h > 0.6 {
                    score -= (h - 0.6) * params.avoidMountains * 2.5
                }
                
                switch biome {
                case .grassland, .forest:
                    score += 0.15
                case .savanna:
                    score += 0.1
                case .beach:
                    score += 0.08
                case .tundra, .taiga:
                    score -= 0.1
                case .desert:
                    score -= 0.12
                case .mountain, .snowyMountain:
                    score -= 0.5
                default:
                    break
                }
                
                if score > 0.35 {
                    candidates.append((SIMD2(x, y), score))
                }
            }
        }
        
        candidates.sort { $0.1 > $1.1 }
        
        var locations: [SIMD2<Int>] = []
        let minDistSq = params.minCityDistance * params.minCityDistance
        
        for (candidate, _) in candidates {
            if locations.count >= params.cityCount {
                break
            }
            
            var tooClose = false
            for existing in locations {
                let dx = Float(candidate.x - existing.x)
                let dy = Float(candidate.y - existing.y)
                if dx * dx + dy * dy < minDistSq {
                    tooClose = true
                    break
                }
            }
            
            if !tooClose {
                locations.append(candidate)
            }
        }
        
        return locations
    }
    
    private func generateCityLayout(
        city: inout City,
        heightmap: [Float],
        waterData: WaterData,
        width: Int,
        height: Int,
        seaLevel: Float
    ) {
        let baseRadius = Int(city.size.baseRadius)
        let numBlocks = rng.nextInt(in: city.size.buildingRange)
        
        var occupiedArea = Set<SIMD2<Int>>()
        var blockPositions: [(origin: SIMD2<Int>, size: SIMD2<Int>)] = []
        
        let centralSize = SIMD2(rng.nextInt(in: 4...6), rng.nextInt(in: 4...6))
        let centralOrigin = SIMD2(city.center.x - centralSize.x/2, city.center.y - centralSize.y/2)
        
        if canPlaceBlock(
            origin: centralOrigin,
            size: centralSize,
            shape: .rectangle,
            occupied: occupiedArea,
            heightmap: heightmap,
            waterData: waterData,
            width: width,
            height: height,
            seaLevel: seaLevel
        ) {
            let centralBlock = BuildingBlock(
                origin: centralOrigin,
                size: centralSize,
                shape: .rectangle,
                type: .civic
            )
            city.blocks.append(centralBlock)
            markOccupiedByBlock(block: centralBlock, into: &occupiedArea, withStreet: true)
            blockPositions.append((centralOrigin, centralSize))
        }
        
        var attempts = 0
        let maxAttempts = numBlocks * 8
        
        while city.blocks.count < numBlocks && attempts < maxAttempts {
            attempts += 1
            
            guard !blockPositions.isEmpty else {
                break
            }
            let sourceBlock = blockPositions[rng.nextInt(in: 0...(blockPositions.count - 1))]
            
            let directions: [(dx: Int, dy: Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
            let dir = directions[rng.nextInt(in: 0...3)]
            
            let blockWidth = rng.nextInt(in: 3...5)
            let blockHeight = rng.nextInt(in: 3...5)
            let size = SIMD2(blockWidth, blockHeight)
            
            var origin: SIMD2<Int>
            if dir.dx > 0 {
                origin = SIMD2(
                    sourceBlock.origin.x + sourceBlock.size.x + streetWidth,
                    sourceBlock.origin.y + rng.nextInt(in: -1...1)
                )
            } else if dir.dx < 0 {
                origin = SIMD2(
                    sourceBlock.origin.x - blockWidth - streetWidth,
                    sourceBlock.origin.y + rng.nextInt(in: -1...1)
                )
            } else if dir.dy > 0 {
                origin = SIMD2(
                    sourceBlock.origin.x + rng.nextInt(in: -1...1),
                    sourceBlock.origin.y + sourceBlock.size.y + streetWidth
                )
            } else {
                origin = SIMD2(
                    sourceBlock.origin.x + rng.nextInt(in: -1...1),
                    sourceBlock.origin.y - blockHeight - streetWidth
                )
            }
            
            let dx = origin.x + blockWidth/2 - city.center.x
            let dy = origin.y + blockHeight/2 - city.center.y
            if dx * dx + dy * dy > baseRadius * baseRadius {
                continue
            }
            
            let distFromCenter = sqrt(Float(dx * dx + dy * dy))
            let buildingType = randomBuildingType(distanceRatio: distFromCenter / Float(baseRadius))
            let shape = randomBlockShape(size: size)
            
            if canPlaceBlock(
                origin: origin,
                size: size,
                shape: shape,
                occupied: occupiedArea,
                heightmap: heightmap,
                waterData: waterData,
                width: width,
                height: height,
                seaLevel: seaLevel
            ) {
                let block = BuildingBlock(origin: origin, size: size, shape: shape, type: buildingType)
                city.blocks.append(block)
                markOccupiedByBlock(block: block, into: &occupiedArea, withStreet: true)
                blockPositions.append((origin, size))
            }
        }
    }
    
    private func markOccupiedByBlock(block: BuildingBlock, into set: inout Set<SIMD2<Int>>, withStreet: Bool) {
        let occupiedTiles = block.occupiedTiles()
        for tile in occupiedTiles {
            set.insert(tile)
            
            if withStreet {
                for dy in -streetWidth...streetWidth {
                    for dx in -streetWidth...streetWidth {
                        if abs(dx) == streetWidth || abs(dy) == streetWidth {
                            set.insert(SIMD2(tile.x + dx, tile.y + dy))
                        }
                    }
                }
            }
        }
    }
    
    private func canPlaceBlock(
        origin: SIMD2<Int>,
        size: SIMD2<Int>,
        shape: BlockShape,
        occupied: Set<SIMD2<Int>>,
        heightmap: [Float],
        waterData: WaterData,
        width: Int,
        height: Int,
        seaLevel: Float
    ) -> Bool {
        let tempBlock = BuildingBlock(origin: origin, size: size, shape: shape, type: .residential)
        let tiles = tempBlock.occupiedTiles()
        
        guard !tiles.isEmpty else {
            return false
        }
        
        for tile in tiles {
            if tile.x < 2 || tile.y < 2 || tile.x >= width - 2 || tile.y >= height - 2 {
                return false
            }
            
            let idx = tile.y * width + tile.x
            if idx < 0 || idx >= heightmap.count {
                return false
            }
            
            if heightmap[idx] < seaLevel || heightmap[idx] > 0.72 {
                return false
            }
            if waterData.riverMask[idx] > 0.5 || waterData.lakeMask[idx] > 0.5 {
                return false
            }
            
            if occupied.contains(tile) {
                return false
            }
        }
        
        return true
    }
    
    private func randomBuildingType(distanceRatio: Float) -> BuildingType {
        let roll = rng.nextFloat()
        
        if distanceRatio < 0.3 {
            if roll < 0.08 {
                return .civic
            }
            if roll < 0.25 {
                return .commercial
            }
            if roll < 0.45 {
                return .market
            }
            return .residential
        } else if distanceRatio < 0.65 {
            if roll < 0.12 {
                return .commercial
            }
            if roll < 0.22 {
                return .industrial
            }
            return .residential
        } else {
            if roll < 0.15 {
                return .industrial
            }
            if roll < 0.22 {
                return .military
            }
            return .residential
        }
    }
    
    private func randomBlockShape(size: SIMD2<Int>) -> BlockShape {
        guard size.x >= 4 && size.y >= 4 else {
            return .rectangle
        }
        
        let roll = rng.nextFloat()
        
        if roll < 0.45 {
            return .rectangle
        } else if roll < 0.65 {
            let corners = BlockShape.Corner.allCases
            return .lShape(cutCorner: corners[rng.nextInt(in: 0...(corners.count - 1))])
        } else if roll < 0.78 {
            let directions = BlockShape.Direction.allCases
            return .tShape(orientation: directions[rng.nextInt(in: 0...(directions.count - 1))])
        } else if roll < 0.88 {
            let directions = BlockShape.Direction.allCases
            return .uShape(openSide: directions[rng.nextInt(in: 0...(directions.count - 1))])
        } else if roll < 0.95 {
            return .plusShape
        } else {
            return .zShape(flipped: rng.nextFloat() < 0.5)
        }
    }
    
    private func generateOrganicWalls(
        city: inout City,
        heightmap: [Float],
        waterData: WaterData,
        width: Int,
        height: Int,
        seaLevel: Float
    ) {
        let occupied = city.allOccupiedTiles()
        guard occupied.count > 10 else {
            return
        }
        
        func isWater(_ x: Int, _ y: Int) -> Bool {
            if x < 0 || x >= width || y < 0 || y >= height {
                return true
            }
            let idx = y * width + x
            if heightmap[idx] < seaLevel {
                return true
            }
            if waterData.riverMask[idx] > 0.5 {
                return true
            }
            if waterData.lakeMask[idx] > 0.5 {
                return true
            }
            return false
        }
        
        var boundaryTiles = Set<SIMD2<Int>>()
        let directions = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
        
        for tile in occupied {
            for (dx, dy) in directions {
                let neighbor = SIMD2(tile.x + dx, tile.y + dy)
                if !occupied.contains(neighbor) && !isWater(neighbor.x, neighbor.y) {
                    boundaryTiles.insert(neighbor)
                }
            }
        }
        
        var wallTiles = Set<SIMD2<Int>>()
        let wallPadding = 2
        
        for boundary in boundaryTiles {
            for dy in 0...wallPadding {
                for dx in 0...wallPadding {
                    let wallTile = SIMD2(
                        boundary.x + dx - wallPadding/2,
                        boundary.y + dy - wallPadding/2
                    )
                    if wallTile.x >= 0 && wallTile.x < width &&
                       wallTile.y >= 0 && wallTile.y < height {
                        if !occupied.contains(wallTile) && !isWater(wallTile.x, wallTile.y) {
                            wallTiles.insert(wallTile)
                        }
                    }
                }
            }
        }
        
        var finalWallTiles: [SIMD2<Int>] = []
        for tile in wallTiles {
            var isOuter = false
            for (dx, dy) in directions {
                let neighbor = SIMD2(tile.x + dx, tile.y + dy)
                if !wallTiles.contains(neighbor) && !occupied.contains(neighbor) {
                    isOuter = true
                    break
                }
            }
            if isOuter {
                finalWallTiles.append(tile)
            }
        }
        
        var gateTiles: [SIMD2<Int>] = []
        let validWalls = finalWallTiles.filter { !isWater($0.x, $0.y) }
        
        if let northmost = validWalls.min(by: { $0.y < $1.y }) {
            addGate(near: northmost, direction: (0, -1), wallTiles: &finalWallTiles, gateTiles: &gateTiles)
        }
        if let southmost = validWalls.max(by: { $0.y < $1.y }) {
            addGate(near: southmost, direction: (0, 1), wallTiles: &finalWallTiles, gateTiles: &gateTiles)
        }
        if let eastmost = validWalls.max(by: { $0.x < $1.x }) {
            addGate(near: eastmost, direction: (1, 0), wallTiles: &finalWallTiles, gateTiles: &gateTiles)
        }
        if let westmost = validWalls.min(by: { $0.x < $1.x }) {
            addGate(near: westmost, direction: (-1, 0), wallTiles: &finalWallTiles, gateTiles: &gateTiles)
        }
        
        city.wallTiles = finalWallTiles
        city.gateTiles = gateTiles
    }
    
    private func addGate(
        near tile: SIMD2<Int>,
        direction: (Int, Int),
        wallTiles: inout [SIMD2<Int>],
        gateTiles: inout [SIMD2<Int>]
    ) {
        let gateCenter = tile
        let perpendicular = direction.0 == 0 ? (1, 0) : (0, 1)
        
        for offset in -1...1 {
            let gateTile = SIMD2(
                gateCenter.x + perpendicular.0 * offset,
                gateCenter.y + perpendicular.1 * offset
            )
            gateTiles.append(gateTile)
            wallTiles.removeAll { $0 == gateTile }
        }
    }
    
    private func calculateFlatness(
        heightmap: [Float],
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) -> Float {
        let centerH = heightmap[y * width + x]
        var totalDiff: Float = 0
        
        let neighbors = [(0, -2), (0, 2), (-2, 0), (2, 0)]
        for (dx, dy) in neighbors {
            let nx = x + dx
            let ny = y + dy
            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                totalDiff += abs(heightmap[ny * width + nx] - centerH)
            }
        }
        
        return max(0, 1.0 - totalDiff * 2.5)
    }
    
    private func generateCityName() -> String {
        let usePrefix = rng.nextFloat() < 0.35
        let useSuffix = rng.nextFloat() < 0.25
        
        var name = ""
        
        if usePrefix {
            name += prefixes[rng.nextInt(in: 0...(prefixes.count - 1))] + " "
        }
        
        let root = roots[rng.nextInt(in: 0...(roots.count - 1))]
        name += root.prefix(1).uppercased() + root.dropFirst()
        
        if useSuffix {
            name += suffixes[rng.nextInt(in: 0...(suffixes.count - 1))]
        }
        
        return name
    }
    
    private func determineCitySize(index: Int, total: Int) -> CitySize {
        if index == 0 && total >= 3 {
            return .capital
        }
        
        let roll = rng.nextFloat()
        let cumVillage = params.villageRatio
        let cumTown = cumVillage + params.townRatio
        let cumCity = cumTown + params.cityRatio
        
        if roll < cumVillage {
            return .village
        }
        if roll < cumTown {
            return .town
        }
        if roll < cumCity {
            return .city
        }
        return .capital
    }
}
