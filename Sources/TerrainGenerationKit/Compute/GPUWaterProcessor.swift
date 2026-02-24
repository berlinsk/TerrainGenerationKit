import Foundation
import Metal
import simd

final class GPUWaterProcessor: @unchecked Sendable {

    private let gpu: GPUComputeEngine
    private let maxLakes: Int = 4096
    private let relaxBatchSize: Int = 200
    private let floodBatchSize: Int = 100

    struct FlowDirParams {
        var width: UInt32
        var height: UInt32
        var seaLevel: Float
    }

    struct FlowAccumParams {
        var width: UInt32
        var height: UInt32
    }

    struct RiverScoreParams {
        var width: UInt32
        var height: UInt32
        var seaLevel: Float
        var maxAccum: Float
    }

    struct GPURiverSource {
        var x: UInt32
        var y: UInt32
    }

    struct TraceRiverParams {
        var width: UInt32
        var height: UInt32
        var riverCount: UInt32
        var riverStartWidth: Float
        var riverWidthGrowth: Float
        var riverMaxWidth: Float
        var meandering: Float
        var seaLevel: Float
        var baseSeed: UInt32
    }

    struct WidenParams {
        var width: UInt32
        var height: UInt32
        var maxFlow: Float
    }

    struct SmoothRiverParams {
        var width: UInt32
        var height: UInt32
    }

    struct DeltaParams {
        var width: UInt32
        var height: UInt32
        var seaLevel: Float
        var deltaSize: UInt32
    }

    struct DepressionParams {
        var width: UInt32
        var height: UInt32
        var seaLevel: Float
        var lakeThreshold: Float
    }

    struct LakeFloodParams {
        var width: UInt32
        var height: UInt32
    }

    struct LakeFinalizeParams {
        var width: UInt32
        var height: UInt32
        var lakeMinSize: UInt32
    }

    struct FlowXYParams {
        var width: UInt32
        var height: UInt32
    }

    init(gpu: GPUComputeEngine) {
        self.gpu = gpu
    }

    func simulateWaterFlow(
        heightmap: [Float],
        width: Int,
        height: Int,
        params: WaterParameters,
        seaLevel: Float,
        seed: UInt64
    ) -> WaterData? {
        let count = width * height

        guard let flowDirPipeline = gpu.pipeline(for: "computeFlowDirections"),
              let relaxPipeline = gpu.pipeline(for: "relaxFlowAccumulation"),
              let scorePipeline = gpu.pipeline(for: "computeRiverScores"),
              let tracePipeline = gpu.pipeline(for: "traceRiversKernel"),
              let widenPipeline = gpu.pipeline(for: "widenRiversKernel"),
              let smoothPipeline = gpu.pipeline(for: "smoothRiversKernel"),
              let deltaPipeline = gpu.pipeline(for: "riverDeltasKernel"),
              let depressPipeline = gpu.pipeline(for: "detectDepressions"),
              let floodPipeline = gpu.pipeline(for: "lakeFloodFillPass"),
              let countPipeline = gpu.pipeline(for: "countLakePixels"),
              let finalizePipeline = gpu.pipeline(for: "finalizeLakes"),
              let flowXYPipeline = gpu.pipeline(for: "assignFlowXY") else {
            return nil
        }

        guard let heightmapBuf = gpu.makeBuffer(from: heightmap, width: width, height: height),
              let directionsBuf = gpu.makeBuffer(type: Int32.self, count: count),
              let accumA = gpu.makeBuffer(type: Float.self, count: count),
              let accumB = gpu.makeBuffer(type: Float.self, count: count),
              let scoresBuf = gpu.makeBuffer(type: Float.self, count: count),
              let riverMaskBuf = gpu.makeBuffer(type: Float.self, count: count),
              let riverMaskOut = gpu.makeBuffer(type: Float.self, count: count),
              let waterDepthBuf = gpu.makeBuffer(type: Float.self, count: count),
              let lakeMaskBuf = gpu.makeBuffer(type: Float.self, count: count),
              let lakeIdsA = gpu.makeBuffer(type: UInt32.self, count: count),
              let lakeIdsB = gpu.makeBuffer(type: UInt32.self, count: count),
              let waterLevelsA = gpu.makeBuffer(type: Float.self, count: count),
              let waterLevelsB = gpu.makeBuffer(type: Float.self, count: count),
              let flowDirXBuf = gpu.makeBuffer(type: Float.self, count: count),
              let flowDirYBuf = gpu.makeBuffer(type: Float.self, count: count) else {
            return nil
        }

        defer {
            gpu.recycle(heightmapBuf)
            gpu.recycle(directionsBuf)
            gpu.recycle(accumA)
            gpu.recycle(accumB)
            gpu.recycle(scoresBuf)
            gpu.recycle(riverMaskBuf)
            gpu.recycle(riverMaskOut)
            gpu.recycle(waterDepthBuf)
            gpu.recycle(lakeMaskBuf)
            gpu.recycle(lakeIdsA)
            gpu.recycle(lakeIdsB)
            gpu.recycle(waterLevelsA)
            gpu.recycle(waterLevelsB)
            gpu.recycle(flowDirXBuf)
            gpu.recycle(flowDirYBuf)
        }

        accumA.fill(repeating: 1)
        riverMaskBuf.fill(repeating: 0)
        waterDepthBuf.fill(repeating: 0)
        lakeMaskBuf.fill(repeating: 0)
        lakeIdsA.fill(repeating: 0)
        waterLevelsA.fill(repeating: 0)

        var flowDirParams = FlowDirParams(
            width: UInt32(width), height: UInt32(height), seaLevel: seaLevel
        )
        guard let flowDirParamsBuf = gpu.device.makeBuffer(
            bytes: &flowDirParams,
            length: MemoryLayout<FlowDirParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let flowDirOk = gpu.encode(
            pipeline: flowDirPipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (directionsBuf.buffer, 1),
                (flowDirParamsBuf, 2)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard flowDirOk else {
            return nil
        }

        var accumParams = FlowAccumParams(
            width: UInt32(width), height: UInt32(height)
        )
        guard let accumParamsBuf = gpu.device.makeBuffer(
            bytes: &accumParams,
            length: MemoryLayout<FlowAccumParams>.stride,
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
        let maxRelaxPasses = width + height

        var totalPasses = 0
        while totalPasses < maxRelaxPasses {
            changedBuf.contents().storeBytes(of: UInt32(0), as: UInt32.self)

            guard let cmdBuffer = gpu.commandQueue.makeCommandBuffer() else {
                return nil
            }

            let batchCount = min(relaxBatchSize, maxRelaxPasses - totalPasses)
            for _ in 0..<batchCount {
                guard let encoder = cmdBuffer.makeComputeCommandEncoder() else {
                    return nil
                }
                encoder.setComputePipelineState(relaxPipeline)

                let inputBuf = readFromA ? accumA : accumB
                let outputBuf = readFromA ? accumB : accumA

                encoder.setBuffer(directionsBuf.buffer, offset: 0, index: 0)
                encoder.setBuffer(inputBuf.buffer, offset: 0, index: 1)
                encoder.setBuffer(outputBuf.buffer, offset: 0, index: 2)
                encoder.setBuffer(changedBuf, offset: 0, index: 3)
                encoder.setBuffer(accumParamsBuf, offset: 0, index: 4)

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

            let changed = changedBuf.contents().load(as: UInt32.self)
            if changed == 0 {
                break
            }
        }

        let finalAccumBuf = readFromA ? accumA : accumB
        let accumArray = finalAccumBuf.toArray()
        let maxAccum = accumArray.max() ?? 1

        var scoreParams = RiverScoreParams(
            width: UInt32(width), height: UInt32(height),
            seaLevel: seaLevel, maxAccum: maxAccum
        )
        guard let scoreParamsBuf = gpu.device.makeBuffer(
            bytes: &scoreParams,
            length: MemoryLayout<RiverScoreParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let scoreOk = gpu.encode(
            pipeline: scorePipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (finalAccumBuf.buffer, 1),
                (scoresBuf.buffer, 2),
                (scoreParamsBuf, 3)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard scoreOk else {
            return nil
        }

        let scores = scoresBuf.toArray()
        let sources = selectRiverSources(
            scores: scores,
            width: width,
            height: height,
            count: params.riverCount
        )

        if !sources.isEmpty {
            let gpuSources = sources.map {
                GPURiverSource(x: UInt32($0.x), y: UInt32($0.y))
            }
            guard let sourcesBuf = gpu.device.makeBuffer(
                bytes: gpuSources,
                length: gpuSources.count * MemoryLayout<GPURiverSource>.stride,
                options: .storageModeShared
            ) else {
                return nil
            }

            var traceParams = TraceRiverParams(
                width: UInt32(width), height: UInt32(height),
                riverCount: UInt32(sources.count),
                riverStartWidth: params.riverWidth * 0.5,
                riverWidthGrowth: 0.001,
                riverMaxWidth: params.riverWidth * 2,
                meandering: params.riverMeandering,
                seaLevel: seaLevel,
                baseSeed: UInt32(truncatingIfNeeded: seed)
            )
            guard let traceParamsBuf = gpu.device.makeBuffer(
                bytes: &traceParams,
                length: MemoryLayout<TraceRiverParams>.stride,
                options: .storageModeShared
            ) else {
                return nil
            }

            let traceOk = gpu.encode1D(
                pipeline: tracePipeline,
                buffers: [
                    (directionsBuf.buffer, 0),
                    (heightmapBuf.buffer, 1),
                    (riverMaskBuf.buffer, 2),
                    (waterDepthBuf.buffer, 3),
                    (sourcesBuf, 4),
                    (traceParamsBuf, 5)
                ],
                count: sources.count
            )
            guard traceOk else {
                return nil
            }

            var widenParams = WidenParams(
                width: UInt32(width), height: UInt32(height), maxFlow: maxAccum
            )
            guard let widenParamsBuf = gpu.device.makeBuffer(
                bytes: &widenParams,
                length: MemoryLayout<WidenParams>.stride,
                options: .storageModeShared
            ) else {
                return nil
            }

            let widenOk = gpu.encode(
                pipeline: widenPipeline,
                buffers: [
                    (riverMaskBuf.buffer, 0),
                    (finalAccumBuf.buffer, 1),
                    (riverMaskOut.buffer, 2),
                    (widenParamsBuf, 3)
                ],
                gridWidth: width,
                gridHeight: height
            )
            guard widenOk else {
                return nil
            }

            var smoothParams = SmoothRiverParams(
                width: UInt32(width), height: UInt32(height)
            )
            guard let smoothParamsBuf = gpu.device.makeBuffer(
                bytes: &smoothParams,
                length: MemoryLayout<SmoothRiverParams>.stride,
                options: .storageModeShared
            ) else {
                return nil
            }

            let smoothOk = gpu.encode(
                pipeline: smoothPipeline,
                buffers: [
                    (riverMaskOut.buffer, 0),
                    (riverMaskBuf.buffer, 1),
                    (smoothParamsBuf, 2)
                ],
                gridWidth: width,
                gridHeight: height
            )
            guard smoothOk else {
                return nil
            }

            var deltaParams = DeltaParams(
                width: UInt32(width), height: UInt32(height),
                seaLevel: seaLevel, deltaSize: 3
            )
            guard let deltaParamsBuf = gpu.device.makeBuffer(
                bytes: &deltaParams,
                length: MemoryLayout<DeltaParams>.stride,
                options: .storageModeShared
            ) else {
                return nil
            }

            let deltaOk = gpu.encode(
                pipeline: deltaPipeline,
                buffers: [
                    (heightmapBuf.buffer, 0),
                    (riverMaskBuf.buffer, 1),
                    (deltaParamsBuf, 2)
                ],
                gridWidth: width,
                gridHeight: height
            )
            guard deltaOk else {
                return nil
            }
        }

        var depressParams = DepressionParams(
            width: UInt32(width), height: UInt32(height),
            seaLevel: seaLevel, lakeThreshold: params.lakeThreshold
        )
        guard let depressParamsBuf = gpu.device.makeBuffer(
            bytes: &depressParams,
            length: MemoryLayout<DepressionParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        guard let depCountBuf = gpu.device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }
        depCountBuf.contents().storeBytes(of: UInt32(0), as: UInt32.self)

        let depOk = gpu.encode(
            pipeline: depressPipeline,
            buffers: [
                (heightmapBuf.buffer, 0),
                (riverMaskBuf.buffer, 1),
                (lakeIdsA.buffer, 2),
                (waterLevelsA.buffer, 3),
                (depCountBuf, 4),
                (depressParamsBuf, 5)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard depOk else {
            return nil
        }

        let depressionCount = depCountBuf.contents().load(as: UInt32.self)

        if depressionCount > 0 {
            var floodParams = LakeFloodParams(
                width: UInt32(width), height: UInt32(height)
            )
            guard let floodParamsBuf = gpu.device.makeBuffer(
                bytes: &floodParams,
                length: MemoryLayout<LakeFloodParams>.stride,
                options: .storageModeShared
            ) else {
                return nil
            }

            var lakeReadA = true
            let maxFloodPasses = min(width + height, 500)
            var floodTotal = 0

            while floodTotal < maxFloodPasses {
                changedBuf.contents().storeBytes(of: UInt32(0), as: UInt32.self)

                guard let cmdBuffer = gpu.commandQueue.makeCommandBuffer() else {
                    return nil
                }

                let batchCount = min(floodBatchSize, maxFloodPasses - floodTotal)
                for _ in 0..<batchCount {
                    guard let encoder = cmdBuffer.makeComputeCommandEncoder() else {
                        return nil
                    }
                    encoder.setComputePipelineState(floodPipeline)

                    let idsIn = lakeReadA ? lakeIdsA : lakeIdsB
                    let idsOut = lakeReadA ? lakeIdsB : lakeIdsA
                    let wlIn = lakeReadA ? waterLevelsA : waterLevelsB
                    let wlOut = lakeReadA ? waterLevelsB : waterLevelsA

                    encoder.setBuffer(heightmapBuf.buffer, offset: 0, index: 0)
                    encoder.setBuffer(idsIn.buffer, offset: 0, index: 1)
                    encoder.setBuffer(idsOut.buffer, offset: 0, index: 2)
                    encoder.setBuffer(wlIn.buffer, offset: 0, index: 3)
                    encoder.setBuffer(wlOut.buffer, offset: 0, index: 4)
                    encoder.setBuffer(changedBuf, offset: 0, index: 5)
                    encoder.setBuffer(floodParamsBuf, offset: 0, index: 6)

                    gpu.dispatchThreadsSafe(
                        encoder: encoder,
                        pipeline: floodPipeline,
                        width: width,
                        height: height
                    )
                    encoder.endEncoding()
                    lakeReadA = !lakeReadA
                }

                cmdBuffer.commit()
                cmdBuffer.waitUntilCompleted()
                guard cmdBuffer.status != .error else {
                    return nil
                }

                floodTotal += batchCount
                let changed = changedBuf.contents().load(as: UInt32.self)
                if changed == 0 {
                    break
                }
            }

            let finalLakeIds = lakeReadA ? lakeIdsA : lakeIdsB
            let finalWaterLevels = lakeReadA ? waterLevelsA : waterLevelsB

            let lakeSizesCount = min(Int(depressionCount) + 1, maxLakes)
            guard let lakeSizesBuf = gpu.device.makeBuffer(
                length: lakeSizesCount * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            ) else {
                return nil
            }
            memset(lakeSizesBuf.contents(), 0, lakeSizesCount * MemoryLayout<UInt32>.stride)

            let countOk = gpu.encode1D(
                pipeline: countPipeline,
                buffers: [
                    (finalLakeIds.buffer, 0),
                    (lakeSizesBuf, 1)
                ],
                count: count
            )
            guard countOk else {
                return nil
            }

            var finalizeParams = LakeFinalizeParams(
                width: UInt32(width), height: UInt32(height),
                lakeMinSize: UInt32(params.lakeMinSize)
            )
            guard let finalizeParamsBuf = gpu.device.makeBuffer(
                bytes: &finalizeParams,
                length: MemoryLayout<LakeFinalizeParams>.stride,
                options: .storageModeShared
            ) else {
                return nil
            }

            let finalizeOk = gpu.encode(
                pipeline: finalizePipeline,
                buffers: [
                    (finalLakeIds.buffer, 0),
                    (finalWaterLevels.buffer, 1),
                    (heightmapBuf.buffer, 2),
                    (lakeSizesBuf, 3),
                    (lakeMaskBuf.buffer, 4),
                    (waterDepthBuf.buffer, 5),
                    (finalizeParamsBuf, 6)
                ],
                gridWidth: width,
                gridHeight: height
            )
            guard finalizeOk else {
                return nil
            }
        }

        var flowXYParams = FlowXYParams(
            width: UInt32(width), height: UInt32(height)
        )
        guard let flowXYParamsBuf = gpu.device.makeBuffer(
            bytes: &flowXYParams,
            length: MemoryLayout<FlowXYParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let flowXYOk = gpu.encode(
            pipeline: flowXYPipeline,
            buffers: [
                (directionsBuf.buffer, 0),
                (flowDirXBuf.buffer, 1),
                (flowDirYBuf.buffer, 2),
                (flowXYParamsBuf, 3)
            ],
            gridWidth: width,
            gridHeight: height
        )
        guard flowXYOk else {
            return nil
        }

        var waterData = WaterData(width: width, height: height)
        riverMaskBuf.copyTo(&waterData.riverMask)
        lakeMaskBuf.copyTo(&waterData.lakeMask)
        flowDirXBuf.copyTo(&waterData.flowDirectionX)
        flowDirYBuf.copyTo(&waterData.flowDirectionY)
        waterDepthBuf.copyTo(&waterData.waterDepth)

        if let maxDepth = waterData.waterDepth.max(), maxDepth > 0 {
            for i in 0..<waterData.waterDepth.count {
                waterData.waterDepth[i] /= maxDepth
            }
        }

        return waterData
    }

    private func selectRiverSources(
        scores: [Float],
        width: Int,
        height: Int,
        count: Int
    ) -> [(x: Int, y: Int)] {
        var candidates: [(x: Int, y: Int, score: Float)] = []

        for i in 0..<scores.count where scores[i] > 0 {
            let x = i % width
            let y = i / width
            candidates.append((x, y, scores[i]))
        }

        candidates.sort { $0.score > $1.score }

        var sources: [(x: Int, y: Int)] = []
        let minDistance = Float(min(width, height)) / Float(count + 1)

        for candidate in candidates {
            if sources.count >= count {
                break
            }

            let pos = SIMD2<Float>(Float(candidate.x), Float(candidate.y))
            var tooClose = false

            for existing in sources {
                let existPos = SIMD2<Float>(Float(existing.x), Float(existing.y))
                if simd_distance(pos, existPos) < minDistance {
                    tooClose = true
                    break
                }
            }

            if !tooClose {
                sources.append((candidate.x, candidate.y))
            }
        }

        return sources
    }
}
