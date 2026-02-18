import Foundation
import Metal
import simd

public final class TerrainMeshGenerator: TerrainMeshGeneratorProtocol {

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private let supportsNonUniformThreadgroups: Bool

    public init() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue(),
              let library = try? dev.makeDefaultLibrary(bundle: Bundle.module),
              let function = library.makeFunction(name: "generateTerrainMesh"),
              let state = try? dev.makeComputePipelineState(function: function) else {
            device = nil
            commandQueue = nil
            pipeline = nil
            supportsNonUniformThreadgroups = false
            return
        }
        device = dev
        commandQueue = queue
        pipeline = state
        supportsNonUniformThreadgroups = dev.supportsFamily(.apple4)
    }

    public func generateMesh(from mapData: MapData, settings: TerrainMeshSettings) -> TerrainMeshData {
        if let mesh = generateMeshGPU(mapData: mapData, settings: settings) {
            return mesh
        }
        return generateMeshCPU(mapData: mapData, settings: settings)
    }

    private struct MeshParams {
        var mapWidth: UInt32
        var mapHeight: UInt32
        var meshWidth: UInt32
        var meshHeight: UInt32
        var step: UInt32
        var heightScale: Float
    }

    private func meshDimensions(mapWidth: Int, mapHeight: Int, step: Int) -> (Int, Int) {
        let mw = (mapWidth - 1) / step + 1
        let mh = (mapHeight - 1) / step + 1
        return (mw, mh)
    }

    private func buildIndices(meshWidth: Int, meshHeight: Int) -> [UInt32] {
        let quadCount = (meshWidth - 1) * (meshHeight - 1)
        var indices = [UInt32]()
        indices.reserveCapacity(quadCount * 6)
        for row in 0..<(meshHeight - 1) {
            for col in 0..<(meshWidth - 1) {
                let v0 = UInt32(row * meshWidth + col)
                let v1 = v0 + 1
                let v2 = v0 + UInt32(meshWidth)
                let v3 = v2 + 1
                indices.append(contentsOf: [v0, v2, v1, v1, v2, v3])
            }
        }
        return indices
    }

    private func generateMeshGPU(mapData: MapData, settings: TerrainMeshSettings) -> TerrainMeshData? {
        guard let device, let commandQueue, let pipeline else { return nil }

        let step = settings.resolution.rawValue
        let mapW = mapData.width
        let mapH = mapData.height
        let (meshW, meshH) = meshDimensions(mapWidth: mapW, mapHeight: mapH, step: step)
        let vertexCount = meshW * meshH

        guard let heightBuf = mapData.heightmap.withUnsafeBytes({ ptr in
            device.makeBuffer(bytes: ptr.baseAddress!, length: ptr.count, options: .storageModeShared)
        }),
        let vertexBuf = device.makeBuffer(length: vertexCount * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared),
        let normalBuf = device.makeBuffer(length: vertexCount * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared),
        let uvBuf = device.makeBuffer(length: vertexCount * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared)
        else { return nil }

        var params = MeshParams(
            mapWidth: UInt32(mapW),
            mapHeight: UInt32(mapH),
            meshWidth: UInt32(meshW),
            meshHeight: UInt32(meshH),
            step: UInt32(step),
            heightScale: settings.heightScale
        )
        guard let paramBuf = device.makeBuffer(bytes: &params, length: MemoryLayout<MeshParams>.stride, options: .storageModeShared) else { return nil }

        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(heightBuf, offset: 0, index: 0)
        encoder.setBuffer(paramBuf, offset: 0, index: 1)
        encoder.setBuffer(vertexBuf, offset: 0, index: 2)
        encoder.setBuffer(normalBuf, offset: 0, index: 3)
        encoder.setBuffer(uvBuf, offset: 0, index: 4)

        let w = max(1, min(16, pipeline.threadExecutionWidth))
        let h = max(1, min(16, pipeline.maxTotalThreadsPerThreadgroup / w))
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)

        #if targetEnvironment(simulator)
        let useNonUniform = false
        #else
        let useNonUniform = supportsNonUniformThreadgroups
        #endif

        if useNonUniform {
            encoder.dispatchThreads(MTLSize(width: meshW, height: meshH, depth: 1), threadsPerThreadgroup: threadsPerGroup)
        } else {
            let gw = (meshW + threadsPerGroup.width - 1) / threadsPerGroup.width
            let gh = (meshH + threadsPerGroup.height - 1) / threadsPerGroup.height
            encoder.dispatchThreadgroups(MTLSize(width: gw, height: gh, depth: 1), threadsPerThreadgroup: threadsPerGroup)
        }

        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if cmdBuf.status == .error { return nil }

        let vPtr = vertexBuf.contents().bindMemory(to: SIMD3<Float>.self, capacity: vertexCount)
        let nPtr = normalBuf.contents().bindMemory(to: SIMD3<Float>.self, capacity: vertexCount)
        let uPtr = uvBuf.contents().bindMemory(to: SIMD2<Float>.self, capacity: vertexCount)

        let vertices = Array(UnsafeBufferPointer(start: vPtr, count: vertexCount))
        let normals = Array(UnsafeBufferPointer(start: nPtr, count: vertexCount))
        let uvs = Array(UnsafeBufferPointer(start: uPtr, count: vertexCount))
        let indices = buildIndices(meshWidth: meshW, meshHeight: meshH)

        return TerrainMeshData(
            vertices: vertices,
            normals: normals,
            uvs: uvs,
            indices: indices,
            meshWidth: meshW,
            meshHeight: meshH
        )
    }

    private func generateMeshCPU(mapData: MapData, settings: TerrainMeshSettings) -> TerrainMeshData {
        let step = settings.resolution.rawValue
        let mapW = mapData.width
        let mapH = mapData.height
        let (meshW, meshH) = meshDimensions(mapWidth: mapW, mapHeight: mapH, step: step)
        let vertexCount = meshW * meshH

        var vertices = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        var normals = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        var uvs = [SIMD2<Float>](repeating: .zero, count: vertexCount)

        let hs = settings.heightScale

        for row in 0..<meshH {
            for col in 0..<meshW {
                let mapCol = min(col * step, mapW - 1)
                let mapRow = min(row * step, mapH - 1)
                let mapIdx = mapRow * mapW + mapCol
                let h = mapData.heightmap[mapIdx]

                let meshIdx = row * meshW + col
                vertices[meshIdx] = SIMD3<Float>(Float(mapCol), h * hs, Float(mapRow))
                uvs[meshIdx] = SIMD2<Float>(Float(mapCol) / Float(mapW - 1), Float(mapRow) / Float(mapH - 1))

                let hL = mapCol > 0 ? mapData.heightmap[mapRow * mapW + (mapCol - 1)] : h
                let hR = mapCol < mapW - 1 ? mapData.heightmap[mapRow * mapW + (mapCol + 1)] : h
                let hU = mapRow > 0 ? mapData.heightmap[(mapRow - 1) * mapW + mapCol] : h
                let hD = mapRow < mapH - 1 ? mapData.heightmap[(mapRow + 1) * mapW + mapCol] : h

                let tx = SIMD3<Float>(2.0, (hR - hL) * hs, 0.0)
                let tz = SIMD3<Float>(0.0, (hD - hU) * hs, 2.0)
                let n = cross(tz, tx)
                let len = simd_length(n)
                normals[meshIdx] = len > 0 ? n / len : SIMD3<Float>(0, 1, 0)
            }
        }

        return TerrainMeshData(
            vertices: vertices,
            normals: normals,
            uvs: uvs,
            indices: buildIndices(meshWidth: meshW, meshHeight: meshH),
            meshWidth: meshW,
            meshHeight: meshH
        )
    }
}
