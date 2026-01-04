import Foundation
import simd

public struct City: Codable, Identifiable, Sendable {
    
    public let id: UUID
    public var name: String
    public var center: SIMD2<Int>
    public var size: CitySize
    public var blocks: [BuildingBlock]
    public var hasWalls: Bool
    public var wallTiles: [SIMD2<Int>]
    public var gateTiles: [SIMD2<Int>]
    
    public init(name: String, center: SIMD2<Int>, size: CitySize) {
        self.id = UUID()
        self.name = name
        self.center = center
        self.size = size
        self.blocks = []
        self.hasWalls = false
        self.wallTiles = []
        self.gateTiles = []
    }
    
    public func allOccupiedTiles() -> Set<SIMD2<Int>> {
        var tiles = Set<SIMD2<Int>>()
        for block in blocks {
            for tile in block.occupiedTiles() {
                tiles.insert(tile)
            }
        }
        return tiles
    }
}
