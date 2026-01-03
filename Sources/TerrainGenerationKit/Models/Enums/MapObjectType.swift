import Foundation
import simd

public enum MapObjectType: Int, CaseIterable, Codable, Sendable {
    case pine = 0
    case oak = 1
    case palm = 2
    case cactus = 3
    case bush = 4
    case flower = 5
    case grass = 6
    case rock = 7
    case boulder = 8
    case ruin = 9
    case tower = 10
    case village = 11
    case crystal = 12
    
    public var name: String {
        switch self {
        case .pine:
            return "Pine Tree"
        case .oak:
            return "Oak Tree"
        case .palm:
            return "Palm Tree"
        case .cactus:
            return "Cactus"
        case .bush:
            return "Bush"
        case .flower:
            return "Flower"
        case .grass:
            return "Grass"
        case .rock:
            return "Rock"
        case .boulder:
            return "Boulder"
        case .ruin:
            return "Ruin"
        case .tower:
            return "Tower"
        case .village:
            return "Village"
        case .crystal:
            return "Crystal"
        }
    }
    
    public var baseSize: SIMD2<Float> {
        switch self {
        case .pine:
            return SIMD2(3.0, 8.0)
        case .oak:
            return SIMD2(5.0, 6.0)
        case .palm:
            return SIMD2(2.0, 7.0)
        case .cactus:
            return SIMD2(1.0, 3.0)
        case .bush:
            return SIMD2(2.0, 1.5)
        case .flower:
            return SIMD2(0.5, 0.5)
        case .grass:
            return SIMD2(0.3, 0.4)
        case .rock:
            return SIMD2(1.5, 1.0)
        case .boulder:
            return SIMD2(4.0, 3.0)
        case .ruin:
            return SIMD2(8.0, 5.0)
        case .tower:
            return SIMD2(4.0, 12.0)
        case .village:
            return SIMD2(15.0, 6.0)
        case .crystal:
            return SIMD2(1.0, 2.0)
        }
    }
    
    public var color: SIMD4<Float> {
        switch self {
        case .pine:
            return SIMD4(0.15, 0.35, 0.20, 1.0)
        case .oak:
            return SIMD4(0.25, 0.45, 0.20, 1.0)
        case .palm:
            return SIMD4(0.30, 0.50, 0.25, 1.0)
        case .cactus:
            return SIMD4(0.35, 0.55, 0.30, 1.0)
        case .bush:
            return SIMD4(0.30, 0.50, 0.25, 1.0)
        case .flower:
            return SIMD4(0.85, 0.40, 0.50, 1.0)
        case .grass:
            return SIMD4(0.40, 0.60, 0.30, 1.0)
        case .rock:
            return SIMD4(0.55, 0.52, 0.50, 1.0)
        case .boulder:
            return SIMD4(0.45, 0.43, 0.42, 1.0)
        case .ruin:
            return SIMD4(0.60, 0.55, 0.50, 1.0)
        case .tower:
            return SIMD4(0.50, 0.48, 0.45, 1.0)
        case .village:
            return SIMD4(0.70, 0.55, 0.40, 1.0)
        case .crystal:
            return SIMD4(0.70, 0.80, 0.95, 1.0)
        }
    }
    
    public var compatibleBiomes: Set<BiomeType> {
        switch self {
        case .pine:
            return [.taiga, .forest, .mountain]
        case .oak:
            return [.forest, .grassland, .rainforest]
        case .palm:
            return [.beach, .savanna]
        case .cactus:
            return [.desert, .savanna]
        case .bush:
            return [.grassland, .forest, .savanna, .tundra]
        case .flower:
            return [.grassland, .forest, .rainforest, .marsh]
        case .grass:
            return [.grassland, .savanna, .forest, .beach]
        case .rock:
            return [.mountain, .tundra, .desert, .beach, .snowyMountain]
        case .boulder:
            return [.mountain, .snowyMountain, .tundra]
        case .ruin:
            return [.grassland, .desert, .forest, .savanna]
        case .tower:
            return [.grassland, .mountain, .forest]
        case .village:
            return [.grassland, .forest, .savanna]
        case .crystal:
            return [.mountain, .snowyMountain, .tundra]
        }
    }
    
    public var rarity: Float {
        switch self {
        case .pine, .oak, .palm, .cactus:
            return 0.3
        case .bush, .flower, .grass:
            return 0.6
        case .rock:
            return 0.4
        case .boulder:
            return 0.2
        case .ruin:
            return 0.03
        case .tower:
            return 0.02
        case .village:
            return 0.01
        case .crystal:
            return 0.05
        }
    }
}
