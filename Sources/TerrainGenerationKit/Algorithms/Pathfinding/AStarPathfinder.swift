import Foundation
import simd

public struct PathNode: Comparable {
    public let position: SIMD2<Int>
    public let gCost: Float
    public let hCost: Float
    public let parent: SIMD2<Int>?
    
    public var fCost: Float {
        gCost + hCost
    }
    
    public init(position: SIMD2<Int>, gCost: Float, hCost: Float, parent: SIMD2<Int>?) {
        self.position = position
        self.gCost = gCost
        self.hCost = hCost
        self.parent = parent
    }
    
    public static func < (lhs: PathNode, rhs: PathNode) -> Bool {
        lhs.fCost < rhs.fCost
    }
}

public final class AStarPathfinder {
    
    private let width: Int
    private let height: Int
    private let costMap: [Float]
    
    public init(costMap: [Float], width: Int, height: Int) {
        self.costMap = costMap
        self.width = width
        self.height = height
    }
    
    public func findPath(
        from start: SIMD2<Int>,
        to goal: SIMD2<Int>,
        existingRoads: Set<SIMD2<Int>> = [],
        maxIterations: Int = 150000,
        existingRoadBonus: Float = 0.3
    ) -> [SIMD2<Int>]? {
        var openSet = PriorityQueue<PathNode>()
        var closedSet = Set<SIMD2<Int>>()
        var cameFrom = [SIMD2<Int>: SIMD2<Int>]()
        var gScores = [SIMD2<Int>: Float]()
        
        let startNode = PathNode(
            position: start,
            gCost: 0,
            hCost: heuristic(start, goal),
            parent: nil
        )
        openSet.insert(startNode)
        gScores[start] = 0
        
        let directions: [SIMD2<Int>] = [
            SIMD2(0, -1), SIMD2(0, 1), SIMD2(-1, 0), SIMD2(1, 0),
            SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1), SIMD2(1, 1)
        ]
        
        var iterations = 0
        
        while let current = openSet.pop() {
            iterations += 1
            if iterations > maxIterations {
                return nil
            }
            
            if current.position == goal {
                return reconstructPath(cameFrom: cameFrom, current: goal)
            }
            
            if closedSet.contains(current.position) {
                continue
            }
            closedSet.insert(current.position)
            
            for dir in directions {
                let neighbor = SIMD2(current.position.x + dir.x, current.position.y + dir.y)
                
                if neighbor.x < 0 || neighbor.x >= width || neighbor.y < 0 || neighbor.y >= height {
                    continue
                }
                
                if closedSet.contains(neighbor) {
                    continue
                }
                
                let idx = neighbor.y * width + neighbor.x
                var moveCost = costMap[idx]
                
                if dir.x != 0 && dir.y != 0 {
                    moveCost *= 1.414
                }
                
                if existingRoads.contains(neighbor) {
                    moveCost *= existingRoadBonus
                }
                
                if moveCost >= 5000 {
                    continue
                }
                
                let tentativeG = current.gCost + moveCost
                
                if tentativeG < (gScores[neighbor] ?? Float.infinity) {
                    cameFrom[neighbor] = current.position
                    gScores[neighbor] = tentativeG
                    
                    let hCost = heuristic(neighbor, goal)
                    let node = PathNode(
                        position: neighbor,
                        gCost: tentativeG,
                        hCost: hCost,
                        parent: current.position
                    )
                    openSet.insert(node)
                }
            }
        }
        
        return nil
    }
    
    private func heuristic(_ a: SIMD2<Int>, _ b: SIMD2<Int>) -> Float {
        let dx = Float(a.x - b.x)
        let dy = Float(a.y - b.y)
        return sqrt(dx * dx + dy * dy) * 0.9
    }
    
    private func reconstructPath(cameFrom: [SIMD2<Int>: SIMD2<Int>], current: SIMD2<Int>) -> [SIMD2<Int>] {
        var path = [current]
        var node = current
        
        while let parent = cameFrom[node] {
            path.append(parent)
            node = parent
        }
        
        return path.reversed()
    }
}
