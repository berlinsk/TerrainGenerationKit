import Foundation

public struct CityGenerationParameters: Codable, Sendable, Equatable {
    
    public var enabled: Bool
    public var cityCount: Int
    public var minCityDistance: Float
    public var villageRatio: Float
    public var townRatio: Float
    public var cityRatio: Float
    public var capitalRatio: Float
    public var preferRivers: Float
    public var preferCoast: Float
    public var avoidMountains: Float
    public var roadCurviness: Float
    
    public init(
        enabled: Bool = true,
        cityCount: Int = 5,
        minCityDistance: Float = 60,
        villageRatio: Float = 0.4,
        townRatio: Float = 0.3,
        cityRatio: Float = 0.2,
        capitalRatio: Float = 0.1,
        preferRivers: Float = 0.7,
        preferCoast: Float = 0.5,
        avoidMountains: Float = 0.8,
        roadCurviness: Float = 0.3
    ) {
        self.enabled = enabled
        self.cityCount = cityCount
        self.minCityDistance = minCityDistance
        self.villageRatio = villageRatio
        self.townRatio = townRatio
        self.cityRatio = cityRatio
        self.capitalRatio = capitalRatio
        self.preferRivers = preferRivers
        self.preferCoast = preferCoast
        self.avoidMountains = avoidMountains
        self.roadCurviness = roadCurviness
    }
    
    public static let `default` = CityGenerationParameters()
}
