import Foundation

public struct BiomeSelection: Codable, Sendable, Equatable {
    
    public var enabledBiomes: Set<BiomeType>
    
    public init(enabledBiomes: Set<BiomeType> = Set(BiomeType.allCases)) {
        self.enabledBiomes = enabledBiomes
    }
    
    public mutating func toggle(_ biome: BiomeType) {
        if enabledBiomes.contains(biome) {
            enabledBiomes.remove(biome)
        } else {
            enabledBiomes.insert(biome)
        }
    }
    
    public func isEnabled(_ biome: BiomeType) -> Bool {
        enabledBiomes.contains(biome)
    }
    
    public static let `default` = BiomeSelection()
    
    public static let landOnly: BiomeSelection = {
        var sel = BiomeSelection()
        sel.enabledBiomes.remove(.deepOcean)
        sel.enabledBiomes.remove(.ocean)
        sel.enabledBiomes.remove(.shallowWater)
        return sel
    }()
}
