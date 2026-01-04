import Foundation

public enum BlockShape: Codable, Sendable {
    case rectangle
    case lShape(cutCorner: Corner)
    case tShape(orientation: Direction)
    case uShape(openSide: Direction)
    case plusShape
    case zShape(flipped: Bool)
    
    public enum Corner: Codable, Sendable, CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }
    
    public enum Direction: Codable, Sendable, CaseIterable {
        case up
        case down
        case left
        case right
    }
}
