import Foundation
import Metal

final class GPUErosionSimulator: @unchecked Sendable {

    private let gpu: GPUComputeEngine
    private let maxDropletsPerBatch: Int = 50000
    private let thermalPassesPerBatch: Int = 50

    struct HydraulicParams {
        var width: UInt32
        var height: UInt32
        var dropletCount: UInt32
        var dropletLifetime: UInt32
        var brushRadius: UInt32
        var erosionStrength: Float
        var depositionRate: Float
        var evaporationRate: Float
        var sedimentCapacity: Float
        var gravity: Float
        var inertia: Float
        var minSlope: Float
        var baseSeed: UInt32
    }

    struct ThermalParams {
        var width: UInt32
        var height: UInt32
        var talusAngle: Float
        var erosionRate: Float
    }

    init(gpu: GPUComputeEngine) {
        self.gpu = gpu
    }

    func hydraulicErode(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        params: ErosionParameters,
        seed: UInt64,
        dropletCount: Int? = nil
    ) -> Bool {
        let totalDroplets = dropletCount ?? params.iterations
        guard totalDroplets > 0 else {
            return true
        }

        guard let pipeline = gpu.pipeline(for: "hydraulicErosion") else {
            return false
        }

        guard let heightmapBuffer = gpu.makeBuffer(from: heightmap) else {
            return false
        }
        defer {
            gpu.recycle(heightmapBuffer)
        }

        var remaining = totalDroplets
        var batchIndex: UInt32 = 0

        while remaining > 0 {
            let batchCount = min(maxDropletsPerBatch, remaining)
            let baseSeed = UInt32(truncatingIfNeeded: seed) ^ (batchIndex &* 2654435761)

            var metalParams = HydraulicParams(
                width: UInt32(width),
                height: UInt32(height),
                dropletCount: UInt32(batchCount),
                dropletLifetime: UInt32(params.dropletLifetime),
                brushRadius: 3,
                erosionStrength: params.erosionStrength,
                depositionRate: params.depositionRate,
                evaporationRate: params.evaporationRate,
                sedimentCapacity: params.sedimentCapacity,
                gravity: params.gravity,
                inertia: params.inertia,
                minSlope: params.minSlope,
                baseSeed: baseSeed
            )

            guard let paramsBuffer = gpu.device.makeBuffer(
                bytes: &metalParams,
                length: MemoryLayout<HydraulicParams>.stride,
                options: .storageModeShared
            ) else {
                return false
            }

            let success = gpu.encode1D(
                pipeline: pipeline,
                buffers: [
                    (heightmapBuffer.buffer, 0),
                    (paramsBuffer, 1)
                ],
                count: batchCount
            )

            guard success else {
                return false
            }

            remaining -= batchCount
            batchIndex += 1
        }

        heightmapBuffer.copyTo(&heightmap)
        return true
    }

    func thermalErode(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        talusAngle: Float,
        iterations: Int
    ) -> Bool {
        guard iterations > 0 else {
            return true
        }

        guard let pipeline = gpu.pipeline(for: "thermalErosionPass") else {
            return false
        }

        guard let bufferA = gpu.makeBuffer(from: heightmap, width: width, height: height),
              let bufferB = gpu.makeBuffer(type: Float.self, count: heightmap.count, width: width, height: height) else {
            return false
        }
        defer {
            gpu.recycle(bufferA)
            gpu.recycle(bufferB)
        }

        var metalParams = ThermalParams(
            width: UInt32(width),
            height: UInt32(height),
            talusAngle: talusAngle,
            erosionRate: 0.5
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &metalParams,
            length: MemoryLayout<ThermalParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        var readFromA = true
        var remaining = iterations

        while remaining > 0 {
            let batchPasses = min(thermalPassesPerBatch, remaining)

            guard let cmdBuffer = gpu.commandQueue.makeCommandBuffer() else {
                return false
            }

            for _ in 0..<batchPasses {
                guard let encoder = cmdBuffer.makeComputeCommandEncoder() else {
                    return false
                }

                encoder.setComputePipelineState(pipeline)

                let input = readFromA ? bufferA : bufferB
                let output = readFromA ? bufferB : bufferA

                encoder.setBuffer(input.buffer, offset: 0, index: 0)
                encoder.setBuffer(output.buffer, offset: 0, index: 1)
                encoder.setBuffer(paramsBuffer, offset: 0, index: 2)

                gpu.dispatchThreadsSafe(
                    encoder: encoder,
                    pipeline: pipeline,
                    width: width,
                    height: height
                )

                encoder.endEncoding()
                readFromA = !readFromA
            }

            cmdBuffer.commit()
            cmdBuffer.waitUntilCompleted()

            guard cmdBuffer.status != .error else {
                return false
            }

            remaining -= batchPasses
        }

        let finalBuffer = readFromA ? bufferA : bufferB
        finalBuffer.copyTo(&heightmap)
        return true
    }
}
