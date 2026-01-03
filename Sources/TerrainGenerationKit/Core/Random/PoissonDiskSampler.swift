import Foundation
import simd

public final class PoissonDiskSampler: @unchecked Sendable {
    
    private let random: SeededRandom
    private let width: Float
    private let height: Float
    private let minDistance: Float
    private let cellSize: Float
    private var grid: [[SIMD2<Float>?]]
    private var gridWidth: Int
    private var gridHeight: Int
    
    public init(random: SeededRandom, width: Float, height: Float, minDistance: Float) {
        self.random = random
        self.width = width
        self.height = height
        self.minDistance = minDistance
        self.cellSize = minDistance / sqrt(2)
        self.gridWidth = Int(ceil(width / cellSize))
        self.gridHeight = Int(ceil(height / cellSize))
        self.grid = [[SIMD2<Float>?]](
            repeating: [SIMD2<Float>?](repeating: nil, count: gridHeight),
            count: gridWidth
        )
    }
    
    public func generate(maxAttempts: Int = 30) -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []
        var activeList: [SIMD2<Float>] = []
        
        let initial = SIMD2<Float>(
            random.nextFloat(in: 0...width),
            random.nextFloat(in: 0...height)
        )
        addPoint(initial, to: &points, active: &activeList)
        
        while !activeList.isEmpty {
            let randomIndex = random.nextInt(in: 0...activeList.count - 1)
            let point = activeList[randomIndex]
            
            var found = false
            for _ in 0..<maxAttempts {
                let angle = random.nextFloat() * Float.pi * 2
                let distance = random.nextFloat(in: minDistance...minDistance * 2)
                let candidate = SIMD2<Float>(
                    point.x + cos(angle) * distance,
                    point.y + sin(angle) * distance
                )
                
                if isValid(candidate) {
                    addPoint(candidate, to: &points, active: &activeList)
                    found = true
                    break
                }
            }
            
            if !found {
                activeList.remove(at: randomIndex)
            }
        }
        
        return points
    }
    
    private func addPoint(_ point: SIMD2<Float>, to points: inout [SIMD2<Float>], active: inout [SIMD2<Float>]) {
        points.append(point)
        active.append(point)
        
        let gx = Int(point.x / cellSize)
        let gy = Int(point.y / cellSize)
        if gx >= 0 && gx < gridWidth && gy >= 0 && gy < gridHeight {
            grid[gx][gy] = point
        }
    }
    
    private func isValid(_ point: SIMD2<Float>) -> Bool {
        guard point.x >= 0 && point.x < width && point.y >= 0 && point.y < height else {
            return false
        }
        
        let gx = Int(point.x / cellSize)
        let gy = Int(point.y / cellSize)
        
        let startX = max(0, gx - 2)
        let endX = min(gridWidth - 1, gx + 2)
        let startY = max(0, gy - 2)
        let endY = min(gridHeight - 1, gy + 2)
        
        for x in startX...endX {
            for y in startY...endY {
                if let neighbor = grid[x][y] {
                    let dist = simd_distance(point, neighbor)
                    if dist < minDistance {
                        return false
                    }
                }
            }
        }
        
        return true
    }
}
