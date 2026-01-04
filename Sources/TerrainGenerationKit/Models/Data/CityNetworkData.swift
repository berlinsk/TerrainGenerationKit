import Foundation
import simd

public struct CityNetworkData: Codable, Sendable {
    
    public var cities: [City]
    public var roads: [Road]
    public var cityMask: [UInt8]
    public var roadSDF: [Float]
    public var wallMask: [UInt8]
    
    public init(width: Int, height: Int) {
        self.cities = []
        self.roads = []
        self.cityMask = [UInt8](repeating: 0, count: width * height)
        self.roadSDF = [Float](repeating: 1000, count: width * height)
        self.wallMask = [UInt8](repeating: 0, count: width * height)
    }
    
    public mutating func updateMasks(width: Int, height: Int, gpuEngine: GPUComputeEngine? = nil) {
        cityMask = [UInt8](repeating: 0, count: width * height)
        roadSDF = [Float](repeating: 1000, count: width * height)
        wallMask = [UInt8](repeating: 0, count: width * height)
        
        for (cityIndex, city) in cities.enumerated() {
            for block in city.blocks {
                for tile in block.occupiedTiles() {
                    if tile.x >= 0 && tile.x < width && tile.y >= 0 && tile.y < height {
                        cityMask[tile.y * width + tile.x] = UInt8(cityIndex + 1)
                    }
                }
            }
            
            for tile in city.wallTiles {
                if tile.x >= 0 && tile.x < width && tile.y >= 0 && tile.y < height {
                    wallMask[tile.y * width + tile.x] = 1
                }
            }
            for tile in city.gateTiles {
                if tile.x >= 0 && tile.x < width && tile.y >= 0 && tile.y < height {
                    wallMask[tile.y * width + tile.x] = 2
                }
            }
        }
        
        var roadMask = [Float](repeating: 0, count: width * height)
        for road in roads {
            for point in road.path {
                if point.x >= 0 && point.x < width && point.y >= 0 && point.y < height {
                    let idx = point.y * width + point.x
                    if cityMask[idx] == 0 {
                        roadMask[idx] = 1.0
                    }
                }
            }
        }
        
        if let gpu = gpuEngine {
            roadSDF = gpu.computeRoadSDF(roadMask: roadMask, width: width, height: height)
        } else {
            computeRoadSDFCPU(roadMask: roadMask, width: width, height: height)
        }
    }
    
    private mutating func computeRoadSDFCPU(roadMask: [Float], width: Int, height: Int) {
        var queue: [(Int, Int)] = []
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if roadMask[idx] > 0.5 {
                    roadSDF[idx] = 0
                    queue.append((x, y))
                }
            }
        }
        
        let directions = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
        let diagonalDist: Float = 1.414
        var head = 0
        
        while head < queue.count {
            let (cx, cy) = queue[head]
            head += 1
            
            let currentIdx = cy * width + cx
            let currentDist = roadSDF[currentIdx]
            if currentDist > 8 {
                continue
            }
            
            for (i, (dx, dy)) in directions.enumerated() {
                let nx = cx + dx
                let ny = cy + dy
                
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let nidx = ny * width + nx
                    if cityMask[nidx] == 0 {
                        let stepDist: Float = i < 4 ? 1.0 : diagonalDist
                        let newDist = currentDist + stepDist
                        if newDist < roadSDF[nidx] {
                            roadSDF[nidx] = newDist
                            queue.append((nx, ny))
                        }
                    }
                }
            }
        }
    }
}
