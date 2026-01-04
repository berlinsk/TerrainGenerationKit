import Foundation

public struct GenerationProgress: Sendable {
    public var stage: GenerationStage
    public var progress: Float
    public var message: String
    
    public init(stage: GenerationStage, progress: Float, message: String) {
        self.stage = stage
        self.progress = progress
        self.message = message
    }
    
    public static let idle = GenerationProgress(stage: .idle, progress: 0, message: "Ready")
}
