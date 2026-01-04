import Foundation

public struct MapMetadata: Codable, Sendable {
    
    public var name: String
    public var createdAt: Date
    public var generationTime: TimeInterval
    public var settings: GenerationSettings
    
    public init(
        name: String = "Untitled Map",
        createdAt: Date = Date(),
        generationTime: TimeInterval = 0,
        settings: GenerationSettings = .default
    ) {
        self.name = name
        self.createdAt = createdAt
        self.generationTime = generationTime
        self.settings = settings
    }
}
