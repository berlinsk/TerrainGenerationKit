import Foundation
import simd

public enum BiomeType: Int, CaseIterable, Codable, Sendable, Hashable {
    case deepOcean = 0
    case ocean = 1
    case shallowWater = 2
    case beach = 3
    case desert = 4
    case savanna = 5
    case grassland = 6
    case forest = 7
    case rainforest = 8
    case taiga = 9
    case tundra = 10
    case snow = 11
    case mountain = 12
    case snowyMountain = 13
    case marsh = 14
    case river = 15
    case lake = 16
    
    public var name: String {
        switch self {
        case .deepOcean:
            return "Deep Ocean"
        case .ocean:
            return "Ocean"
        case .shallowWater:
            return "Shallow Water"
        case .beach:
            return "Beach"
        case .desert:
            return "Desert"
        case .savanna:
            return "Savanna"
        case .grassland:
            return "Grassland"
        case .forest:
            return "Forest"
        case .rainforest:
            return "Rainforest"
        case .taiga:
            return "Taiga"
        case .tundra:
            return "Tundra"
        case .snow:
            return "Snow"
        case .mountain:
            return "Mountain"
        case .snowyMountain:
            return "Snowy Mountain"
        case .marsh:
            return "Marsh"
        case .river:
            return "River"
        case .lake:
            return "Lake"
        }
    }
    
    public var isWater: Bool {
        switch self {
        case .deepOcean, .ocean, .shallowWater, .river, .lake:
            return true
        default:
            return false
        }
    }
    
    public var canHaveTrees: Bool {
        switch self {
        case .forest, .rainforest, .taiga, .grassland, .savanna, .marsh:
            return true
        default:
            return false
        }
    }
    
    public var canHaveRocks: Bool {
        switch self {
        case .mountain, .snowyMountain, .tundra, .desert, .beach:
            return true
        default:
            return false
        }
    }
    
    public var baseColor: SIMD4<Float> {
        switch self {
        case .deepOcean:
            return SIMD4(0.05, 0.15, 0.35, 1.0)
        case .ocean:
            return SIMD4(0.10, 0.25, 0.50, 1.0)
        case .shallowWater:
            return SIMD4(0.20, 0.45, 0.65, 1.0)
        case .beach:
            return SIMD4(0.85, 0.80, 0.60, 1.0)
        case .desert:
            return SIMD4(0.90, 0.80, 0.55, 1.0)
        case .savanna:
            return SIMD4(0.70, 0.65, 0.35, 1.0)
        case .grassland:
            return SIMD4(0.40, 0.65, 0.30, 1.0)
        case .forest:
            return SIMD4(0.20, 0.45, 0.20, 1.0)
        case .rainforest:
            return SIMD4(0.10, 0.35, 0.15, 1.0)
        case .taiga:
            return SIMD4(0.25, 0.40, 0.35, 1.0)
        case .tundra:
            return SIMD4(0.65, 0.70, 0.65, 1.0)
        case .snow:
            return SIMD4(0.95, 0.97, 1.00, 1.0)
        case .mountain:
            return SIMD4(0.50, 0.48, 0.45, 1.0)
        case .snowyMountain:
            return SIMD4(0.85, 0.88, 0.92, 1.0)
        case .marsh:
            return SIMD4(0.35, 0.45, 0.30, 1.0)
        case .river:
            return SIMD4(0.25, 0.50, 0.70, 1.0)
        case .lake:
            return SIMD4(0.20, 0.45, 0.65, 1.0)
        }
    }
    
    public var secondaryColor: SIMD4<Float> {
        switch self {
        case .deepOcean:
            return SIMD4(0.03, 0.12, 0.30, 1.0)
        case .ocean:
            return SIMD4(0.08, 0.20, 0.45, 1.0)
        case .shallowWater:
            return SIMD4(0.25, 0.50, 0.70, 1.0)
        case .beach:
            return SIMD4(0.80, 0.75, 0.55, 1.0)
        case .desert:
            return SIMD4(0.85, 0.75, 0.50, 1.0)
        case .savanna:
            return SIMD4(0.65, 0.60, 0.30, 1.0)
        case .grassland:
            return SIMD4(0.45, 0.70, 0.35, 1.0)
        case .forest:
            return SIMD4(0.15, 0.40, 0.15, 1.0)
        case .rainforest:
            return SIMD4(0.08, 0.30, 0.12, 1.0)
        case .taiga:
            return SIMD4(0.20, 0.35, 0.30, 1.0)
        case .tundra:
            return SIMD4(0.60, 0.65, 0.60, 1.0)
        case .snow:
            return SIMD4(0.90, 0.92, 0.95, 1.0)
        case .mountain:
            return SIMD4(0.45, 0.43, 0.40, 1.0)
        case .snowyMountain:
            return SIMD4(0.80, 0.83, 0.87, 1.0)
        case .marsh:
            return SIMD4(0.30, 0.40, 0.25, 1.0)
        case .river:
            return SIMD4(0.20, 0.45, 0.65, 1.0)
        case .lake:
            return SIMD4(0.15, 0.40, 0.60, 1.0)
        }
    }
}
