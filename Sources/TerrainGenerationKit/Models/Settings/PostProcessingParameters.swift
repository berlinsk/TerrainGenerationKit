import Foundation

public struct PostProcessingParameters: Codable, Sendable, Equatable {
    
    public var smoothingPasses: Int
    public var smoothingStrength: Float
    public var normalizeHeightmap: Bool
    public var contrastEnhancement: Float
    public var terraceCount: Int
    public var terraceSharpness: Float
    
    public init(
        smoothingPasses: Int = 2,
        smoothingStrength: Float = 0.5,
        normalizeHeightmap: Bool = true,
        contrastEnhancement: Float = 1.0,
        terraceCount: Int = 0,
        terraceSharpness: Float = 0.5
    ) {
        self.smoothingPasses = smoothingPasses
        self.smoothingStrength = smoothingStrength
        self.normalizeHeightmap = normalizeHeightmap
        self.contrastEnhancement = contrastEnhancement
        self.terraceCount = terraceCount
        self.terraceSharpness = terraceSharpness
    }
    
    public static let `default` = PostProcessingParameters()
}
