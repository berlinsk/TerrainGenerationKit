import Foundation
import Metal

final class GPUCityProcessor: @unchecked Sendable {

    private let gpu: GPUComputeEngine
    private let distanceBatchSize: Int = 30

    struct DistanceInitParams {
        var width: UInt32
        var height: UInt32
        var type: UInt32
        var maxDistance: UInt32
        var seaLevel: Float
    }

    struct DistanceRelaxParams {
        var width: UInt32
        var height: UInt32
        var maxDistance: UInt32
    }

    struct CostMapParams {
        var width: UInt32
        var height: UInt32
        var seaLevel: Float
    }

    struct CityScoreParams {
        var width: UInt32
        var height: UInt32
        var seaLevel: Float
        var preferRivers: Float
        var preferCoast: Float
        var avoidMountains: Float
    }

    init(gpu: GPUComputeEngine) {
        self.gpu = gpu
    }

    func computeDistanceMap(
        heightmap: [Float],
        riverMask: [Float],
        width: Int,
        height: Int,
        type: Int,
        maxDistance: Int,
        seaLevel: Float
    ) -> [Int]? {
        let count = width * height

        guard let initPipeline = gpu.pipeline(for: "initDistanceMap"),
              let relaxPipeline = gpu.pipeline(for: "wavefrontDistancePass") else {
            return nil
        }

        guard let heightmapBuf = gpu.makeBuffer(from: heightmap, width: width, height: height),
              let riverMaskBuf = gpu.makeBuffer(from: riverMask, width: width, height: height),
              let distA = gpu.makeBuffer(type: Int32.self, count: count),
              let distB = gpu.makeBuffer(type: Int32.self, count: count) else {
            return nil
        }

        defer {
            gpu.recycle(heightmapBuf)
            gpu.recycle(riverMaskBuf)
            gpu.recycle(distA)
            gpu.recycle(distB)
        }

        var initParams = DistanceInitParams(
            width: UInt32(width), height: UInt32(height),
            type: UInt32(type), maxDistance: UInt32(maxDistance),
            seaLevel: seaLevel
        )
        guard let initParamsBuf = gpu.device.makeBuffer(
            bytes: &initParams,
            length: MemoryLayout<DistanceInitParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let initOk = gpu.encode(
            pipeline: initPipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (riverMaskBuf.buffer, 1),
                (distA.buffer, 2),
                (initParamsBuf, 3)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard initOk else {
            return nil
        }

        var relaxParams = DistanceRelaxParams(
            width: UInt32(width), height: UInt32(height),
            maxDistance: UInt32(maxDistance)
        )
        guard let relaxParamsBuf = gpu.device.makeBuffer(
            bytes: &relaxParams,
            length: MemoryLayout<DistanceRelaxParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        guard let changedBuf = gpu.device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        var readFromA = true
        var totalPasses = 0

        while totalPasses < maxDistance {
            changedBuf.contents().storeBytes(of: UInt32(0), as: UInt32.self)

            guard let cmdBuffer = gpu.commandQueue.makeCommandBuffer() else {
                return nil
            }

            let batchCount = min(distanceBatchSize, maxDistance - totalPasses)
            for _ in 0..<batchCount {
                guard let encoder = cmdBuffer.makeComputeCommandEncoder() else {
                    return nil
                }
                encoder.setComputePipelineState(relaxPipeline)

                let inputBuf = readFromA ? distA : distB
                let outputBuf = readFromA ? distB : distA

                encoder.setBuffer(inputBuf.buffer, offset: 0, index: 0)
                encoder.setBuffer(outputBuf.buffer, offset: 0, index: 1)
                encoder.setBuffer(changedBuf, offset: 0, index: 2)
                encoder.setBuffer(relaxParamsBuf, offset: 0, index: 3)

                gpu.dispatchThreadsSafe(
                    encoder: encoder,
                    pipeline: relaxPipeline,
                    width: width,
                    height: height
                )
                encoder.endEncoding()
                readFromA = !readFromA
            }

            cmdBuffer.commit()
            cmdBuffer.waitUntilCompleted()
            guard cmdBuffer.status != .error else {
                return nil
            }

            totalPasses += batchCount
            if changedBuf.contents().load(as: UInt32.self) == 0 {
                break
            }
        }

        let finalBuf = readFromA ? distA : distB
        let int32Array: [Int32] = finalBuf.toArray()
        return int32Array.map {
            Int($0)
        }
    }

    func buildTerrainCostMap(
        heightmap: [Float],
        biomeMap: [UInt8],
        riverMask: [Float],
        lakeMask: [Float],
        width: Int,
        height: Int,
        seaLevel: Float
    ) -> [Float]? {
        let count = width * height

        guard let pipeline = gpu.pipeline(for: "buildTerrainCostKernel") else {
            return nil
        }

        guard let heightmapBuf = gpu.makeBuffer(from: heightmap, width: width, height: height),
              let biomeBuf = gpu.makeBuffer(from: biomeMap, width: width, height: height),
              let riverBuf = gpu.makeBuffer(from: riverMask, width: width, height: height),
              let lakeBuf = gpu.makeBuffer(from: lakeMask, width: width, height: height),
              let costBuf = gpu.makeBuffer(type: Float.self, count: count) else {
            return nil
        }

        defer {
            gpu.recycle(heightmapBuf)
            gpu.recycle(biomeBuf)
            gpu.recycle(riverBuf)
            gpu.recycle(lakeBuf)
            gpu.recycle(costBuf)
        }

        var params = CostMapParams(
            width: UInt32(width), height: UInt32(height), seaLevel: seaLevel
        )
        guard let paramsBuf = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<CostMapParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let ok = gpu.encode(
            pipeline: pipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (biomeBuf.buffer, 1),
                (riverBuf.buffer, 2),
                (lakeBuf.buffer, 3),
                (costBuf.buffer, 4),
                (paramsBuf, 5)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard ok else {
            return nil
        }

        return costBuf.toArray()
    }

    func scoreCityLocations(
        heightmap: [Float],
        biomeMap: [UInt8],
        riverDistMap: [Int],
        coastDistMap: [Int],
        width: Int,
        height: Int,
        seaLevel: Float,
        preferRivers: Float,
        preferCoast: Float,
        avoidMountains: Float
    ) -> [Float]? {
        let count = width * height

        guard let pipeline = gpu.pipeline(for: "scoreCityLocationsKernel") else {
            return nil
        }

        let riverDist32 = riverDistMap.map {
            Int32($0)
        }
        let coastDist32 = coastDistMap.map {
            Int32($0)
        }

        guard let heightmapBuf = gpu.makeBuffer(from: heightmap, width: width, height: height),
              let biomeBuf = gpu.makeBuffer(from: biomeMap, width: width, height: height),
              let riverDistBuf = gpu.makeBuffer(from: riverDist32, width: width, height: height),
              let coastDistBuf = gpu.makeBuffer(from: coastDist32, width: width, height: height),
              let scoresBuf = gpu.makeBuffer(type: Float.self, count: count) else {
            return nil
        }

        defer {
            gpu.recycle(heightmapBuf)
            gpu.recycle(biomeBuf)
            gpu.recycle(riverDistBuf)
            gpu.recycle(coastDistBuf)
            gpu.recycle(scoresBuf)
        }

        var params = CityScoreParams(
            width: UInt32(width), height: UInt32(height),
            seaLevel: seaLevel,
            preferRivers: preferRivers,
            preferCoast: preferCoast,
            avoidMountains: avoidMountains
        )
        guard let paramsBuf = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<CityScoreParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let ok = gpu.encode(
            pipeline: pipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (biomeBuf.buffer, 1),
                (riverDistBuf.buffer, 2),
                (coastDistBuf.buffer, 3),
                (scoresBuf.buffer, 4),
                (paramsBuf, 5)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard ok else {
            return nil
        }

        return scoresBuf.toArray()
    }

    func createRoadFinder(
        costMap: [Float],
        width: Int,
        height: Int,
        roadDiscount: Float
    ) -> GPURoadFinder? {
        return GPURoadFinder(
            gpu: gpu,
            costMap: costMap,
            width: width,
            height: height,
            roadDiscount: roadDiscount
        )
    }
}
