import Foundation

public protocol TerrainMeshGeneratorProtocol: Sendable {
    func generateMesh(from mapData: MapData, settings: TerrainMeshSettings) -> TerrainMeshData
}
