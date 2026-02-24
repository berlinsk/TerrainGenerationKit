import Foundation
import Metal

final class GPUHeightmapProcessor: @unchecked Sendable {

    private let gpu: GPUComputeEngine

    init(gpu: GPUComputeEngine) {
        self.gpu = gpu
    }

    struct BlendParams {
        var count: UInt32
        var layerCount: UInt32
        var weight0: Float
        var weight1: Float
        var weight2: Float
        var invTotalWeight: Float
    }

    struct NormalizeParams {
        var count: UInt32
        var minVal: Float
        var invRange: Float
    }

    struct ContrastParams {
        var count: UInt32
        var strength: Float
    }

    struct TerraceParams {
        var count: UInt32
        var steps: Float
        var sharpness: Float
    }

    struct MaskParams {
        var width: UInt32
        var height: UInt32
        var param0: Float
        var param1: Float
    }

    struct SmoothParams {
        var width: UInt32
        var height: UInt32
        var strength: Float
    }

    struct BlurParams {
        var width: UInt32
        var height: UInt32
        var radius: Int32
    }

    struct NormalMapParams {
        var width: UInt32
        var height: UInt32
        var strength: Float
    }

    struct AOParams {
        var width: UInt32
        var height: UInt32
        var radius: Int32
        var intensity: Float
    }

    struct SteepnessParams {
        var width: UInt32
        var height: UInt32
        var invMaxSteepness: Float
    }

    func blendLayers(
        layers: [[Float]],
        weights: [Float]
    ) -> [Float]? {
        guard let first = layers.first,
              !first.isEmpty,
              layers.count == weights.count,
              layers.count <= 3 else {
            return nil
        }

        guard let pipeline = gpu.pipeline(for: "blendNoiseLayers") else {
            return nil
        }

        let count = first.count
        var managedBuffers: [GPUBuffer<Float>] = []
        defer {
            for buf in managedBuffers {
                gpu.recycle(buf)
            }
        }

        for i in 0..<3 {
            if i < layers.count {
                guard let buf = gpu.makeBuffer(from: layers[i]) else {
                    return nil
                }
                managedBuffers.append(buf)
            } else {
                guard let buf = gpu.makeBuffer(type: Float.self, count: count) else {
                    return nil
                }
                buf.fill(repeating: 0)
                managedBuffers.append(buf)
            }
        }

        guard let outputBuffer = gpu.makeBuffer(type: Float.self, count: count) else {
            return nil
        }
        managedBuffers.append(outputBuffer)

        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return nil
        }

        var params = BlendParams(
            count: UInt32(count),
            layerCount: UInt32(layers.count),
            weight0: weights[0],
            weight1: layers.count >= 2 ? weights[1] : 0,
            weight2: layers.count >= 3 ? weights[2] : 0,
            invTotalWeight: 1.0 / totalWeight
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<BlendParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let success = gpu.encode1D(
            pipeline: pipeline,
            buffers: [
                (managedBuffers[0].buffer, 0),
                (managedBuffers[1].buffer, 1),
                (managedBuffers[2].buffer, 2),
                (managedBuffers[3].buffer, 3),
                (paramsBuffer, 4)
            ],
            count: count
        )

        guard success else {
            return nil
        }

        return managedBuffers[3].toArray()
    }

    func normalize(_ array: inout [Float]) -> Bool {
        guard !array.isEmpty else {
            return true
        }

        var minVal = Float.greatestFiniteMagnitude
        var maxVal = -Float.greatestFiniteMagnitude
        for value in array {
            minVal = min(minVal, value)
            maxVal = max(maxVal, value)
        }

        let range = maxVal - minVal
        guard range > 0 else {
            return true
        }

        guard let pipeline = gpu.pipeline(for: "normalizeArray") else {
            return false
        }

        guard let dataBuffer = gpu.makeBuffer(from: array) else {
            return false
        }
        defer {
            gpu.recycle(dataBuffer)
        }

        var params = NormalizeParams(
            count: UInt32(array.count),
            minVal: minVal,
            invRange: 1.0 / range
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<NormalizeParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        let success = gpu.encode1D(
            pipeline: pipeline,
            buffers: [
                (dataBuffer.buffer, 0),
                (paramsBuffer, 1)
            ],
            count: array.count
        )

        guard success else {
            return false
        }

        dataBuffer.copyTo(&array)
        return true
    }

    func applyContrast(_ array: inout [Float], strength: Float) -> Bool {
        guard !array.isEmpty else {
            return true
        }

        guard let pipeline = gpu.pipeline(for: "applyContrast") else {
            return false
        }

        guard let dataBuffer = gpu.makeBuffer(from: array) else {
            return false
        }
        defer {
            gpu.recycle(dataBuffer)
        }

        var params = ContrastParams(
            count: UInt32(array.count),
            strength: strength
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<ContrastParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        let success = gpu.encode1D(
            pipeline: pipeline,
            buffers: [
                (dataBuffer.buffer, 0),
                (paramsBuffer, 1)
            ],
            count: array.count
        )

        guard success else {
            return false
        }

        dataBuffer.copyTo(&array)
        return true
    }

    func applyTerracing(
        _ array: inout [Float],
        steps: Int,
        sharpness: Float
    ) -> Bool {
        guard !array.isEmpty,
              steps > 0 else {
            return true
        }

        guard let pipeline = gpu.pipeline(for: "applyTerracing") else {
            return false
        }

        guard let dataBuffer = gpu.makeBuffer(from: array) else {
            return false
        }
        defer {
            gpu.recycle(dataBuffer)
        }

        var params = TerraceParams(
            count: UInt32(array.count),
            steps: Float(steps),
            sharpness: sharpness
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<TerraceParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        let success = gpu.encode1D(
            pipeline: pipeline,
            buffers: [
                (dataBuffer.buffer, 0),
                (paramsBuffer, 1)
            ],
            count: array.count
        )

        guard success else {
            return false
        }

        dataBuffer.copyTo(&array)
        return true
    }

    func applyRadialMask(
        _ array: inout [Float],
        width: Int,
        height: Int,
        falloff: Float,
        blend: Float
    ) -> Bool {
        guard !array.isEmpty else {
            return true
        }

        guard let pipeline = gpu.pipeline(for: "applyRadialMask") else {
            return false
        }

        guard let dataBuffer = gpu.makeBuffer(from: array, width: width, height: height) else {
            return false
        }
        defer {
            gpu.recycle(dataBuffer)
        }

        var params = MaskParams(
            width: UInt32(width),
            height: UInt32(height),
            param0: falloff,
            param1: blend
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<MaskParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        let success = gpu.encode(
            pipeline: pipeline,
            buffers: [
                (dataBuffer.buffer, 0),
                (paramsBuffer, 1)
            ],
            gridWidth: width,
            gridHeight: height
        )

        guard success else {
            return false
        }

        dataBuffer.copyTo(&array)
        return true
    }

    func applyIslandMask(
        _ array: inout [Float],
        width: Int,
        height: Int,
        coastWidth: Float
    ) -> Bool {
        guard !array.isEmpty else {
            return true
        }

        guard let pipeline = gpu.pipeline(for: "applyIslandMask") else {
            return false
        }

        guard let dataBuffer = gpu.makeBuffer(from: array, width: width, height: height) else {
            return false
        }
        defer {
            gpu.recycle(dataBuffer)
        }

        var params = MaskParams(
            width: UInt32(width),
            height: UInt32(height),
            param0: coastWidth,
            param1: 0
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<MaskParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        let success = gpu.encode(
            pipeline: pipeline,
            buffers: [
                (dataBuffer.buffer, 0),
                (paramsBuffer, 1)
            ],
            gridWidth: width,
            gridHeight: height
        )

        guard success else {
            return false
        }

        dataBuffer.copyTo(&array)
        return true
    }

    func applyPangaeaMask(
        _ array: inout [Float],
        width: Int,
        height: Int
    ) -> Bool {
        guard !array.isEmpty else {
            return true
        }

        guard let pipeline = gpu.pipeline(for: "applyPangaeaMask") else {
            return false
        }

        guard let dataBuffer = gpu.makeBuffer(from: array, width: width, height: height) else {
            return false
        }
        defer {
            gpu.recycle(dataBuffer)
        }

        var params = MaskParams(
            width: UInt32(width),
            height: UInt32(height),
            param0: 0,
            param1: 0
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<MaskParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        let success = gpu.encode(
            pipeline: pipeline,
            buffers: [
                (dataBuffer.buffer, 0),
                (paramsBuffer, 1)
            ],
            gridWidth: width,
            gridHeight: height
        )

        guard success else {
            return false
        }

        dataBuffer.copyTo(&array)
        return true
    }

    func smooth(
        _ array: inout [Float],
        width: Int,
        height: Int,
        passes: Int,
        strength: Float
    ) -> Bool {
        guard !array.isEmpty,
              passes > 0 else {
            return true
        }

        guard let pipeline = gpu.pipeline(for: "smoothPass") else {
            return false
        }

        guard let bufferA = gpu.makeBuffer(from: array, width: width, height: height),
              let bufferB = gpu.makeBuffer(type: Float.self, count: array.count, width: width, height: height) else {
            return false
        }
        defer {
            gpu.recycle(bufferA)
            gpu.recycle(bufferB)
        }

        var params = SmoothParams(
            width: UInt32(width),
            height: UInt32(height),
            strength: strength
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<SmoothParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        var readFromA = true
        for _ in 0..<passes {
            let input = readFromA ? bufferA : bufferB
            let output = readFromA ? bufferB : bufferA

            let success = gpu.encode(
                pipeline: pipeline,
                buffers: [
                    (input.buffer, 0),
                    (output.buffer, 1),
                    (paramsBuffer, 2)
                ],
                gridWidth: width,
                gridHeight: height
            )

            guard success else {
                return false
            }

            readFromA = !readFromA
        }

        let finalBuffer = readFromA ? bufferA : bufferB
        finalBuffer.copyTo(&array)
        return true
    }

    func gaussianBlur(
        _ array: inout [Float],
        width: Int,
        height: Int,
        radius: Int
    ) -> Bool {
        guard !array.isEmpty,
              radius > 0 else {
            return true
        }

        guard let hPipeline = gpu.pipeline(for: "gaussianBlurH"),
              let vPipeline = gpu.pipeline(for: "gaussianBlurV") else {
            return false
        }

        guard let bufferA = gpu.makeBuffer(from: array, width: width, height: height),
              let bufferB = gpu.makeBuffer(type: Float.self, count: array.count, width: width, height: height) else {
            return false
        }
        defer {
            gpu.recycle(bufferA)
            gpu.recycle(bufferB)
        }

        var params = BlurParams(
            width: UInt32(width),
            height: UInt32(height),
            radius: Int32(radius)
        )

        guard let paramsBuffer = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<BlurParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        let hSuccess = gpu.encode(
            pipeline: hPipeline,
            buffers: [
                (bufferA.buffer, 0),
                (bufferB.buffer, 1),
                (paramsBuffer, 2)
            ],
            gridWidth: width,
            gridHeight: height
        )

        guard hSuccess else {
            return false
        }

        let vSuccess = gpu.encode(
            pipeline: vPipeline,
            buffers: [
                (bufferB.buffer, 0),
                (bufferA.buffer, 1),
                (paramsBuffer, 2)
            ],
            gridWidth: width,
            gridHeight: height
        )

        guard vSuccess else {
            return false
        }

        bufferA.copyTo(&array)
        return true
    }

    func generateNormalMap(
        heightmap: [Float],
        width: Int,
        height: Int,
        strength: Float
    ) -> [SIMD3<Float>]? {
        let count = width * height

        guard let pipeline = gpu.pipeline(for: "generateNormalMapKernel") else {
            return nil
        }

        guard let heightmapBuf = gpu.makeBuffer(from: heightmap, width: width, height: height),
              let normalsBuf = gpu.makeBuffer(type: Float.self, count: count * 3) else {
            return nil
        }
        defer {
            gpu.recycle(heightmapBuf)
            gpu.recycle(normalsBuf)
        }

        var params = NormalMapParams(
            width: UInt32(width),
            height: UInt32(height),
            strength: strength
        )
        guard let paramsBuf = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<NormalMapParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let success = gpu.encode(
            pipeline: pipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (normalsBuf.buffer, 1),
                (paramsBuf, 2)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard success else {
            return nil
        }

        let rawFloats: [Float] = normalsBuf.toArray()
        var normals = [SIMD3<Float>](repeating: .zero, count: count)
        for i in 0..<count {
            let base = i * 3
            normals[i] = SIMD3(rawFloats[base], rawFloats[base + 1], rawFloats[base + 2])
        }
        return normals
    }

    func generateAmbientOcclusion(
        heightmap: [Float],
        width: Int,
        height: Int,
        radius: Int,
        intensity: Float
    ) -> [Float]? {
        let count = width * height

        guard let pipeline = gpu.pipeline(for: "generateAmbientOcclusionKernel") else {
            return nil
        }

        guard let heightmapBuf = gpu.makeBuffer(from: heightmap, width: width, height: height),
              let aoBuf = gpu.makeBuffer(type: Float.self, count: count) else {
            return nil
        }
        defer {
            gpu.recycle(heightmapBuf)
            gpu.recycle(aoBuf)
        }

        var params = AOParams(
            width: UInt32(width),
            height: UInt32(height),
            radius: Int32(radius),
            intensity: intensity
        )
        guard let paramsBuf = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<AOParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let success = gpu.encode(
            pipeline: pipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (aoBuf.buffer, 1),
                (paramsBuf, 2)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard success else {
            return nil
        }

        return aoBuf.toArray()
    }

    func computeSteepnessMap(
        heightmap: [Float],
        width: Int,
        height: Int
    ) -> [Float]? {
        let count = width * height

        guard let gradientPipeline = gpu.pipeline(for: "computeSteepnessKernel"),
              let normalizePipeline = gpu.pipeline(for: "normalizeSteepnessKernel") else {
            return nil
        }

        guard let heightmapBuf = gpu.makeBuffer(from: heightmap, width: width, height: height),
              let steepnessBuf = gpu.makeBuffer(type: Float.self, count: count) else {
            return nil
        }
        defer {
            gpu.recycle(heightmapBuf)
            gpu.recycle(steepnessBuf)
        }

        var gradientParams = SteepnessParams(
            width: UInt32(width),
            height: UInt32(height),
            invMaxSteepness: 0
        )
        guard let gradientParamsBuf = gpu.device.makeBuffer(
            bytes: &gradientParams,
            length: MemoryLayout<SteepnessParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let gradientOk = gpu.encode(
            pipeline: gradientPipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (steepnessBuf.buffer, 1),
                (gradientParamsBuf, 2)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard gradientOk else {
            return nil
        }

        let rawSteepness: [Float] = steepnessBuf.toArray()
        guard let maxVal = rawSteepness.max(), maxVal > 0 else {
            return rawSteepness
        }

        var normalizeParams = SteepnessParams(
            width: UInt32(width),
            height: UInt32(height),
            invMaxSteepness: 1.0 / maxVal
        )
        guard let normalizeParamsBuf = gpu.device.makeBuffer(
            bytes: &normalizeParams,
            length: MemoryLayout<SteepnessParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let normalizeOk = gpu.encode1D(
            pipeline: normalizePipeline,
            buffers: [
                (steepnessBuf.buffer, 0),
                (normalizeParamsBuf, 1)
            ],
            count: count
        )
        guard normalizeOk else {
            return nil
        }

        return steepnessBuf.toArray()
    }
}
