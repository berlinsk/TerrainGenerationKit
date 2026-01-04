import Foundation

public protocol MapGeneratorProtocol: Sendable {
    func generate(
        settings: GenerationSettings,
        progressHandler: (@Sendable (GenerationProgress) -> Void)?
    ) async throws -> MapData
}
