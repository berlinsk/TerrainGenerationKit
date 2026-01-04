import Foundation

public struct MapMetadata: Codable, Sendable {
    
    public var seed: UInt64
    public var width: Int
    public var height: Int
    public var generationDate: Date
    public var generationTimeMs: Int
    public var settings: GenerationSettings
    public var statistics: MapStatistics
    
    public init(
        seed: UInt64,
        width: Int,
        height: Int,
        settings: GenerationSettings,
        generationTimeMs: Int = 0,
        statistics: MapStatistics = MapStatistics()
    ) {
        self.seed = seed
        self.width = width
        self.height = height
        self.generationDate = Date()
        self.generationTimeMs = generationTimeMs
        self.settings = settings
        self.statistics = statistics
    }
}
