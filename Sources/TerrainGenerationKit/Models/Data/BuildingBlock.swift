import Foundation
import simd

public struct BuildingBlock: Codable, Identifiable, Sendable {
    
    public let id: UUID
    public var origin: SIMD2<Int>
    public var size: SIMD2<Int>
    public var shape: BlockShape
    public var buildingType: BuildingType
    
    public init(
        origin: SIMD2<Int>,
        size: SIMD2<Int>,
        shape: BlockShape = .rectangle,
        type: BuildingType = .residential
    ) {
        self.id = UUID()
        self.origin = origin
        self.size = size
        self.shape = shape
        self.buildingType = type
    }
    
    public func occupiedTiles() -> [SIMD2<Int>] {
        var tiles: [SIMD2<Int>] = []
        let w = size.x
        let h = size.y
        
        switch shape {
        case .rectangle:
            for y in 0..<h {
                for x in 0..<w {
                    tiles.append(SIMD2(origin.x + x, origin.y + y))
                }
            }
            
        case .lShape(let corner):
            let cutW = w / 2
            let cutH = h / 2
            for y in 0..<h {
                for x in 0..<w {
                    let inCut: Bool
                    switch corner {
                    case .topLeft:
                        inCut = x < cutW && y < cutH
                    case .topRight:
                        inCut = x >= w - cutW && y < cutH
                    case .bottomLeft:
                        inCut = x < cutW && y >= h - cutH
                    case .bottomRight:
                        inCut = x >= w - cutW && y >= h - cutH
                    }
                    if !inCut {
                        tiles.append(SIMD2(origin.x + x, origin.y + y))
                    }
                }
            }
            
        case .tShape(let orientation):
            let armW = w / 3
            let armH = h / 3
            for y in 0..<h {
                for x in 0..<w {
                    let include: Bool
                    switch orientation {
                    case .up:
                        include = y >= armH || (x >= armW && x < w - armW)
                    case .down:
                        include = y < h - armH || (x >= armW && x < w - armW)
                    case .left:
                        include = x >= armW || (y >= armH && y < h - armH)
                    case .right:
                        include = x < w - armW || (y >= armH && y < h - armH)
                    }
                    if include {
                        tiles.append(SIMD2(origin.x + x, origin.y + y))
                    }
                }
            }
            
        case .uShape(let openSide):
            let wallW = max(1, w / 3)
            let wallH = max(1, h / 3)
            for y in 0..<h {
                for x in 0..<w {
                    let include: Bool
                    switch openSide {
                    case .up:
                        include = y >= wallH || x < wallW || x >= w - wallW
                    case .down:
                        include = y < h - wallH || x < wallW || x >= w - wallW
                    case .left:
                        include = x >= wallW || y < wallH || y >= h - wallH
                    case .right:
                        include = x < w - wallW || y < wallH || y >= h - wallH
                    }
                    if include {
                        tiles.append(SIMD2(origin.x + x, origin.y + y))
                    }
                }
            }
            
        case .plusShape:
            let armW = w / 3
            let armH = h / 3
            for y in 0..<h {
                for x in 0..<w {
                    let inHorizontal = y >= armH && y < h - armH
                    let inVertical = x >= armW && x < w - armW
                    if inHorizontal || inVertical {
                        tiles.append(SIMD2(origin.x + x, origin.y + y))
                    }
                }
            }
            
        case .zShape(let flipped):
            let stepW = w / 2
            let stepH = h / 2
            for y in 0..<h {
                for x in 0..<w {
                    let include: Bool
                    if flipped {
                        include = (y < stepH && x >= stepW) || (y >= stepH && x < stepW) || (x >= stepW - 1 && x <= stepW)
                    } else {
                        include = (y < stepH && x < stepW) || (y >= stepH && x >= stepW) || (x >= stepW - 1 && x <= stepW)
                    }
                    if include {
                        tiles.append(SIMD2(origin.x + x, origin.y + y))
                    }
                }
            }
        }
        
        return tiles
    }
}
