import Foundation
import Metal
import simd

final class GPUNoiseGenerator: @unchecked Sendable {

    private let gpu: GPUComputeEngine
    private let noisePipeline: MTLComputePipelineState

    init?(gpu: GPUComputeEngine) {
        guard let pipeline = gpu.pipeline(for: "generateNoise") else {
            return nil
        }
        self.gpu = gpu
        self.noisePipeline = pipeline
    }

    struct NoiseParams {
        var width: UInt32
        var height: UInt32
        var noiseType: UInt32
        var octaves: UInt32
        var frequency: Float
        var persistence: Float
        var lacunarity: Float
        var amplitude: Float
    }

    func generateNoise(
        width: Int,
        height: Int,
        parameters: NoiseParameters,
        seed: UInt64
    ) -> GPUBuffer<Float>? {
        let pixelCount = width * height

        let permutation = buildPermutationTable(seed: seed)
        let gradients = buildGradientTable(seed: seed)

        guard let outputBuffer = gpu.makeBuffer(
            type: Float.self,
            count: pixelCount,
            width: width,
            height: height
        ) else {
            return nil
        }

        guard let permBuffer = gpu.makeBuffer(from: permutation) else {
            gpu.recycle(outputBuffer)
            return nil
        }

        guard let gradBuffer = gpu.makeBuffer(from: gradients) else {
            gpu.recycle(outputBuffer)
            gpu.recycle(permBuffer)
            return nil
        }

        var params = NoiseParams(
            width: UInt32(width),
            height: UInt32(height),
            noiseType: noiseTypeIndex(parameters.type),
            octaves: UInt32(parameters.octaves),
            frequency: parameters.frequency,
            persistence: parameters.persistence,
            lacunarity: parameters.lacunarity,
            amplitude: parameters.amplitude
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<NoiseParams>.stride,
            options: .storageModeShared
        ) else {
            gpu.recycle(outputBuffer)
            gpu.recycle(permBuffer)
            gpu.recycle(gradBuffer)
            return nil
        }

        let success = gpu.encode(
            pipeline: noisePipeline,
            buffers: [
                (outputBuffer.buffer, 0),
                (permBuffer.buffer, 1),
                (gradBuffer.buffer, 2),
                (paramsBuffer, 3)
            ],
            gridWidth: width,
            gridHeight: height
        )

        gpu.recycle(permBuffer)
        gpu.recycle(gradBuffer)

        guard success else {
            gpu.recycle(outputBuffer)
            return nil
        }

        return outputBuffer
    }

    func generateNoiseArray(
        width: Int,
        height: Int,
        parameters: NoiseParameters,
        seed: UInt64
    ) -> [Float]? {
        guard let buffer = generateNoise(
            width: width,
            height: height,
            parameters: parameters,
            seed: seed
        ) else {
            return nil
        }

        let result = buffer.toArray()
        gpu.recycle(buffer)
        return result
    }

    private func buildPermutationTable(seed: UInt64) -> [UInt32] {
        var perm = Array(0..<256)
        var rng = SeededRandom(seed: seed)
        perm.shuffle(using: &rng)
        let doubled = perm + perm
        return doubled.map { UInt32($0) }
    }

    private func buildGradientTable(seed: UInt64) -> [SIMD2<Float>] {
        var grads: [SIMD2<Float>] = []
        grads.reserveCapacity(256)
        for i in 0..<256 {
            let angle = Float(i) / 256.0 * Float.pi * 2.0
            grads.append(SIMD2<Float>(cos(angle), sin(angle)))
        }
        return grads
    }

    private func noiseTypeIndex(_ type: NoiseType) -> UInt32 {
        switch type {
        case .perlin:
            return 0
        case .simplex:
            return 1
        case .openSimplex:
            return 2
        case .voronoi:
            return 3
        case .ridged:
            return 4
        case .billow:
            return 5
        }
    }
}
