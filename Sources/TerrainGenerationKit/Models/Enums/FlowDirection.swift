import Foundation

public enum FlowDirection: Int, Sendable {
    case none = -1
    case north = 0
    case northeast = 1
    case east = 2
    case southeast = 3
    case south = 4
    case southwest = 5
    case west = 6
    case northwest = 7
    
    public var offset: (dx: Int, dy: Int) {
        switch self {
        case .none:
            return (0, 0)
        case .north:
            return (0, -1)
        case .northeast:
            return (1, -1)
        case .east:
            return (1, 0)
        case .southeast:
            return (1, 1)
        case .south:
            return (0, 1)
        case .southwest:
            return (-1, 1)
        case .west:
            return (-1, 0)
        case .northwest:
            return (-1, -1)
        }
    }
    
    public static let all: [FlowDirection] = [
        .north, .northeast, .east, .southeast,
        .south, .southwest, .west, .northwest
    ]
}
