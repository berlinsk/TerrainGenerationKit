import Foundation

public struct BiomeClassifier: Sendable {
    
    public let seaLevel: Float
    public let snowLevel: Float
    public let beachWidth: Float
    public let desertThreshold: Float
    
    public init(parameters: BiomeParameters) {
        self.seaLevel = parameters.seaLevel
        self.snowLevel = parameters.snowLevel
        self.beachWidth = parameters.beachWidth
        self.desertThreshold = parameters.desertThreshold
    }
    
    public func classify(
        height: Float,
        temperature: Float,
        humidity: Float,
        isRiver: Bool = false,
        isLake: Bool = false
    ) -> BiomeType {
        
        if isRiver {
            return .river
        }
        if isLake {
            return .lake
        }
        
        if height < seaLevel - 0.15 {
            return .deepOcean
        }
        if height < seaLevel - 0.05 {
            return .ocean
        }
        if height < seaLevel {
            return .shallowWater
        }
        
        if height < seaLevel + beachWidth {
            return .beach
        }
        
        if height > snowLevel {
            if temperature < 0.3 {
                return .snowyMountain
            }
            return .mountain
        }
        
        if height > snowLevel - 0.1 {
            if temperature < 0.2 {
                return .snowyMountain
            }
            return .mountain
        }
        
        if temperature < 0.15 {
            return .snow
        }
        
        if temperature < 0.25 {
            if humidity > 0.4 {
                return .tundra
            }
            return .snow
        }
        
        if temperature < 0.4 {
            if humidity > 0.5 {
                return .taiga
            }
            return .tundra
        }
        
        if humidity > 0.8 && height < seaLevel + 0.1 {
            return .marsh
        }
        
        if temperature < 0.65 {
            if humidity < 0.3 {
                return .grassland
            }
            if humidity < 0.6 {
                return .forest
            }
            return .rainforest
        }
        
        if humidity < desertThreshold {
            return .desert
        }
        if humidity < 0.5 {
            return .savanna
        }
        if humidity < 0.7 {
            return .grassland
        }
        return .rainforest
    }
}
