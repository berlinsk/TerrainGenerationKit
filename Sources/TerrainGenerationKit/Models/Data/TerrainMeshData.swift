import simd

public struct TerrainMeshData: Sendable {
    public let vertices: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let uvs: [SIMD2<Float>]
    public let indices: [UInt32]
    public let meshWidth: Int
    public let meshHeight: Int
}
