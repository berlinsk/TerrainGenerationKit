import Foundation

public enum CitySize: Int, CaseIterable, Codable, Sendable {
    case village = 0
    case town = 1
    case city = 2
    case capital = 3
    
    public var buildingRange: ClosedRange<Int> {
        switch self {
        case .village:
            return 3...5
        case .town:
            return 8...15
        case .city:
            return 20...40
        case .capital:
            return 50...100
        }
    }
    
    public var baseRadius: Float {
        switch self {
        case .village:
            return 8
        case .town:
            return 15
        case .city:
            return 25
        case .capital:
            return 40
        }
    }
    
    public var hasWallsProbability: Float {
        switch self {
        case .village:
            return 0.1
        case .town:
            return 0.3
        case .city:
            return 0.6
        case .capital:
            return 0.85
        }
    }
    
    public var name: String {
        switch self {
        case .village:
            return "Village"
        case .town:
            return "Town"
        case .city:
            return "City"
        case .capital:
            return "Capital"
        }
    }
}
