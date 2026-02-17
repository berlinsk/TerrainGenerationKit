import Foundation

public struct TerrainMeshSettings: Sendable {
    public var heightScale: Float
    public var resolution: MeshResolution

    public init(heightScale: Float = 50.0, resolution: MeshResolution = .full) {
        self.heightScale = heightScale
        self.resolution  = resolution
    }
}
