import Foundation
import Metal

final class GPUClimateGenerator: @unchecked Sendable {

    private let gpu: GPUComputeEngine

    struct TemperatureParams {
        var width: UInt32
        var height: UInt32
        var temperatureVariation: Float
    }

    struct HumidityParams {
        var width: UInt32
        var height: UInt32
        var humidityVariation: Float
    }

    init(gpu: GPUComputeEngine) {
        self.gpu = gpu
    }

    func generateTemperatureMap(
        heightmap: [Float],
        noise: [Float],
        width: Int,
        height: Int,
        temperatureVariation: Float
    ) -> [Float]? {
        guard let pipeline = gpu.pipeline(for: "generateTemperatureMap") else {
            return nil
        }

        let count = width * height

        guard let heightmapBuffer = gpu.makeBuffer(from: heightmap),
              let noiseBuffer = gpu.makeBuffer(from: noise),
              let outputBuffer = gpu.makeBuffer(type: Float.self, count: count) else {
            return nil
        }
        defer {
            gpu.recycle(heightmapBuffer)
            gpu.recycle(noiseBuffer)
            gpu.recycle(outputBuffer)
        }

        var params = TemperatureParams(
            width: UInt32(width),
            height: UInt32(height),
            temperatureVariation: temperatureVariation
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<TemperatureParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let success = gpu.encode(
            pipeline: pipeline,
            buffers: [
                (heightmapBuffer.buffer, 0),
                (noiseBuffer.buffer, 1),
                (outputBuffer.buffer, 2),
                (paramsBuffer, 3)
            ],
            gridWidth: width,
            gridHeight: height
        )

        guard success else {
            return nil
        }

        return outputBuffer.toArray()
    }

    func generateHumidityMap(
        heightmap: [Float],
        noise: [Float],
        waterDistance: [Float],
        width: Int,
        height: Int,
        humidityVariation: Float
    ) -> [Float]? {
        guard let pipeline = gpu.pipeline(for: "generateHumidityMap") else {
            return nil
        }

        let count = width * height

        guard let heightmapBuffer = gpu.makeBuffer(from: heightmap),
              let noiseBuffer = gpu.makeBuffer(from: noise),
              let waterDistBuffer = gpu.makeBuffer(from: waterDistance),
              let outputBuffer = gpu.makeBuffer(type: Float.self, count: count) else {
            return nil
        }
        defer {
            gpu.recycle(heightmapBuffer)
            gpu.recycle(noiseBuffer)
            gpu.recycle(waterDistBuffer)
            gpu.recycle(outputBuffer)
        }

        var params = HumidityParams(
            width: UInt32(width),
            height: UInt32(height),
            humidityVariation: humidityVariation
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<HumidityParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let success = gpu.encode(
            pipeline: pipeline,
            buffers: [
                (heightmapBuffer.buffer, 0),
                (noiseBuffer.buffer, 1),
                (waterDistBuffer.buffer, 2),
                (outputBuffer.buffer, 3),
                (paramsBuffer, 4)
            ],
            gridWidth: width,
            gridHeight: height
        )

        guard success else {
            return nil
        }

        return outputBuffer.toArray()
    }
}
