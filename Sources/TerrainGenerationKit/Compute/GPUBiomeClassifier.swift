import Foundation
import Metal

final class GPUBiomeClassifier: @unchecked Sendable {

    private let gpu: GPUComputeEngine

    struct BiomeClassifyParams {
        var width: UInt32
        var height: UInt32
        var seaLevel: Float
        var snowLevel: Float
        var beachWidth: Float
        var desertThreshold: Float
        var enabledBitmask: UInt32
    }

    struct BiomeSmoothParams {
        var width: UInt32
        var height: UInt32
    }

    init(gpu: GPUComputeEngine) {
        self.gpu = gpu
    }

    func classifyBiomes(
        heightmap: [Float],
        temperatureMap: [Float],
        humidityMap: [Float],
        waterData: WaterData,
        width: Int,
        height: Int,
        params: BiomeParameters,
        selection: BiomeSelection
    ) -> [UInt8]? {
        let count = width * height

        guard let classifyPipeline = gpu.pipeline(for: "classifyBiomesKernel"),
              let smoothPipeline = gpu.pipeline(for: "smoothBiomeTransitionsKernel") else {
            return nil
        }

        guard let heightmapBuf = gpu.makeBuffer(from: heightmap, width: width, height: height),
              let tempBuf = gpu.makeBuffer(from: temperatureMap, width: width, height: height),
              let humBuf = gpu.makeBuffer(from: humidityMap, width: width, height: height),
              let riverBuf = gpu.makeBuffer(from: waterData.riverMask, width: width, height: height),
              let lakeBuf = gpu.makeBuffer(from: waterData.lakeMask, width: width, height: height),
              let biomeA = gpu.makeBuffer(type: UInt8.self, count: count),
              let biomeB = gpu.makeBuffer(type: UInt8.self, count: count) else {
            return nil
        }

        defer {
            gpu.recycle(heightmapBuf)
            gpu.recycle(tempBuf)
            gpu.recycle(humBuf)
            gpu.recycle(riverBuf)
            gpu.recycle(lakeBuf)
            gpu.recycle(biomeA)
            gpu.recycle(biomeB)
        }

        var bitmask: UInt32 = 0
        for biome in selection.enabledBiomes {
            bitmask |= 1 << UInt32(biome.rawValue)
        }

        var classifyParams = BiomeClassifyParams(
            width: UInt32(width),
            height: UInt32(height),
            seaLevel: params.seaLevel,
            snowLevel: params.snowLevel,
            beachWidth: params.beachWidth,
            desertThreshold: params.desertThreshold,
            enabledBitmask: bitmask
        )
        guard let classifyParamsBuf = gpu.device.makeBuffer(
            bytes: &classifyParams,
            length: MemoryLayout<BiomeClassifyParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let classifyOk = gpu.encode(
            pipeline: classifyPipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (tempBuf.buffer, 1),
                (humBuf.buffer, 2),
                (riverBuf.buffer, 3),
                (lakeBuf.buffer, 4),
                (biomeA.buffer, 5),
                (classifyParamsBuf, 6)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard classifyOk else {
            return nil
        }

        var smoothParams = BiomeSmoothParams(
            width: UInt32(width), height: UInt32(height)
        )
        guard let smoothParamsBuf = gpu.device.makeBuffer(
            bytes: &smoothParams,
            length: MemoryLayout<BiomeSmoothParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let smoothOk = gpu.encode(
            pipeline: smoothPipeline,
            buffers: [
                (biomeA.buffer, 0),
                (biomeB.buffer, 1),
                (smoothParamsBuf, 2)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard smoothOk else {
            return nil
        }

        var result = [UInt8](repeating: 0, count: count)
        biomeB.copyTo(&result)
        return result
    }
}
