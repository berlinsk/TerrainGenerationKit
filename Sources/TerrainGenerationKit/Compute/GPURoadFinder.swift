import Foundation
import Metal
import simd

final class GPURoadFinder {

    private let gpu: GPUComputeEngine
    private let costMapBuf: GPUBuffer<Float>
    private let coarseCostBuf: GPUBuffer<Float>
    private let roadMaskBuf: GPUBuffer<Float>
    private let distA: GPUBuffer<Float>
    private let distB: GPUBuffer<Float>
    private let coarseDistA: GPUBuffer<Float>
    private let coarseDistB: GPUBuffer<Float>
    private let width: Int
    private let height: Int
    private let coarseWidth: Int
    private let coarseHeight: Int
    private let downsampleScale: Int
    private let roadDiscount: Float
    private let count: Int
    private let coarseCount: Int
    private let relaxBatchSize: Int
    private let shortDistanceThreshold: Int
    private let coarseSearchMargin: Int
    private let fineSearchMargin: Int

    struct DownsampleParams {
        var fullWidth: UInt32
        var fullHeight: UInt32
        var coarseWidth: UInt32
        var coarseHeight: UInt32
        var scale: UInt32
    }

    struct BoundedPathParams {
        var mapWidth: UInt32
        var mapHeight: UInt32
        var bboxMinX: UInt32
        var bboxMinY: UInt32
        var bboxWidth: UInt32
        var bboxHeight: UInt32
        var sourceX: UInt32
        var sourceY: UInt32
        var roadDiscount: Float
    }

    private struct BBox {
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int

        var width: Int {
            maxX - minX
        }

        var height: Int {
            maxY - minY
        }
    }

    init?(
        gpu: GPUComputeEngine,
        costMap: [Float],
        width: Int,
        height: Int,
        roadDiscount: Float
    ) {
        self.gpu = gpu
        self.width = width
        self.height = height
        self.count = width * height
        self.roadDiscount = roadDiscount
        self.downsampleScale = 8
        self.relaxBatchSize = 100
        self.shortDistanceThreshold = 150
        self.coarseSearchMargin = 10
        self.fineSearchMargin = 40
        self.coarseWidth = (width + downsampleScale - 1) / downsampleScale
        self.coarseHeight = (height + downsampleScale - 1) / downsampleScale
        self.coarseCount = coarseWidth * coarseHeight

        guard let costBuf = gpu.makeBuffer(from: costMap, width: width, height: height),
              let maskBuf = gpu.makeBuffer(type: Float.self, count: count),
              let dA = gpu.makeBuffer(type: Float.self, count: count),
              let dB = gpu.makeBuffer(type: Float.self, count: count),
              let cdA = gpu.makeBuffer(type: Float.self, count: coarseCount),
              let cdB = gpu.makeBuffer(type: Float.self, count: coarseCount),
              let coarseBuf = gpu.makeBuffer(type: Float.self, count: coarseCount) else {
            return nil
        }

        self.costMapBuf = costBuf
        self.roadMaskBuf = maskBuf
        self.distA = dA
        self.distB = dB
        self.coarseDistA = cdA
        self.coarseDistB = cdB
        self.coarseCostBuf = coarseBuf

        memset(maskBuf.buffer.contents(), 0, count * MemoryLayout<Float>.stride)

        guard runDownsample() else {
            return nil
        }
    }

    deinit {
        gpu.recycle(costMapBuf)
        gpu.recycle(coarseCostBuf)
        gpu.recycle(roadMaskBuf)
        gpu.recycle(distA)
        gpu.recycle(distB)
        gpu.recycle(coarseDistA)
        gpu.recycle(coarseDistB)
    }

    func findPath(
        from source: SIMD2<Int>,
        to destination: SIMD2<Int>
    ) -> [SIMD2<Int>]? {
        let manhattan = abs(source.x - destination.x) + abs(source.y - destination.y)

        let fineBBox: BBox

        if manhattan >= shortDistanceThreshold {
            guard let corridor = computeCoarseCorridor(
                source: source,
                destination: destination
            ) else {
                return nil
            }
            fineBBox = corridor
        } else {
            let margin = max(fineSearchMargin, manhattan / 2)
            fineBBox = computeBBox(
                from: source,
                to: destination,
                margin: margin,
                mapWidth: width,
                mapHeight: height
            )
        }

        guard fineBBox.width > 0 && fineBBox.height > 0 else {
            return nil
        }

        guard let readFromA = runBoundedWavefront(
            costBuf: costMapBuf,
            distBufferA: distA,
            distBufferB: distB,
            mapWidth: width,
            mapHeight: height,
            bbox: fineBBox,
            source: source,
            currentRoadDiscount: roadDiscount
        ) else {
            return nil
        }

        let resultBuf = readFromA ? distA : distB
        let path = extractPath(
            distBuffer: resultBuf,
            from: source,
            to: destination,
            mapWidth: width,
            mapHeight: height,
            bbox: fineBBox
        )

        if path.isEmpty {
            return nil
        }

        return path
    }

    func markRoadTiles(_ path: [SIMD2<Int>]) {
        let maskPtr = roadMaskBuf.buffer.contents().bindMemory(
            to: Float.self,
            capacity: count
        )
        for point in path {
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = point.x + dx
                    let ny = point.y + dy
                    if nx >= 0 && nx < width && ny >= 0 && ny < height {
                        maskPtr[ny * width + nx] = 1.0
                    }
                }
            }
        }
    }

    private func runDownsample() -> Bool {
        guard let pipeline = gpu.pipeline(for: "downsampleCostMap") else {
            return false
        }

        var params = DownsampleParams(
            fullWidth: UInt32(width),
            fullHeight: UInt32(height),
            coarseWidth: UInt32(coarseWidth),
            coarseHeight: UInt32(coarseHeight),
            scale: UInt32(downsampleScale)
        )
        guard let paramsBuf = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<DownsampleParams>.stride,
            options: .storageModeShared
        ) else {
            return false
        }

        return gpu.encode(
            pipeline: pipeline,
            buffers: [
                (costMapBuf.buffer, 0),
                (coarseCostBuf.buffer, 1),
                (paramsBuf, 2)
            ],
            gridWidth: coarseWidth,
            gridHeight: coarseHeight
        )
    }

    private func computeCoarseCorridor(
        source: SIMD2<Int>,
        destination: SIMD2<Int>
    ) -> BBox? {
        let coarseSrc = SIMD2(
            source.x / downsampleScale,
            source.y / downsampleScale
        )
        let coarseDst = SIMD2(
            destination.x / downsampleScale,
            destination.y / downsampleScale
        )

        let coarseBBox = computeBBox(
            from: coarseSrc,
            to: coarseDst,
            margin: coarseSearchMargin,
            mapWidth: coarseWidth,
            mapHeight: coarseHeight
        )

        guard coarseBBox.width > 0 && coarseBBox.height > 0 else {
            return nil
        }

        guard let readFromA = runBoundedWavefront(
            costBuf: coarseCostBuf,
            distBufferA: coarseDistA,
            distBufferB: coarseDistB,
            mapWidth: coarseWidth,
            mapHeight: coarseHeight,
            bbox: coarseBBox,
            source: coarseSrc,
            currentRoadDiscount: 1.0
        ) else {
            return nil
        }

        let resultBuf = readFromA ? coarseDistA : coarseDistB
        let coarsePath = extractPath(
            distBuffer: resultBuf,
            from: coarseSrc,
            to: coarseDst,
            mapWidth: coarseWidth,
            mapHeight: coarseHeight,
            bbox: coarseBBox
        )

        if coarsePath.isEmpty {
            return nil
        }

        return computeCorridorBBox(coarsePath: coarsePath)
    }

    private func runBoundedWavefront(
        costBuf: GPUBuffer<Float>,
        distBufferA: GPUBuffer<Float>,
        distBufferB: GPUBuffer<Float>,
        mapWidth: Int,
        mapHeight: Int,
        bbox: BBox,
        source: SIMD2<Int>,
        currentRoadDiscount: Float
    ) -> Bool? {
        guard let initPipeline = gpu.pipeline(for: "initBoundedDistance"),
              let relaxPipeline = gpu.pipeline(for: "propagateBoundedDistance") else {
            return nil
        }

        var params = BoundedPathParams(
            mapWidth: UInt32(mapWidth),
            mapHeight: UInt32(mapHeight),
            bboxMinX: UInt32(bbox.minX),
            bboxMinY: UInt32(bbox.minY),
            bboxWidth: UInt32(bbox.width),
            bboxHeight: UInt32(bbox.height),
            sourceX: UInt32(source.x),
            sourceY: UInt32(source.y),
            roadDiscount: currentRoadDiscount
        )
        guard let paramsBuf = gpu.device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<BoundedPathParams>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let initOk = gpu.encode(
            pipeline: initPipeline,
            buffers: [
                (distBufferA.buffer, 0),
                (paramsBuf, 1)
            ],
            gridWidth: bbox.width,
            gridHeight: bbox.height
        )
        guard initOk else {
            return nil
        }

        guard let changedBuf = gpu.device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }

        let maxIterations = (bbox.width + bbox.height) * 2
        var readFromA = true
        var totalPasses = 0

        while totalPasses < maxIterations {
            changedBuf.contents().storeBytes(of: UInt32(0), as: UInt32.self)

            guard let cmdBuffer = gpu.commandQueue.makeCommandBuffer() else {
                return nil
            }

            let batchCount = min(relaxBatchSize, maxIterations - totalPasses)
            for _ in 0..<batchCount {
                guard let encoder = cmdBuffer.makeComputeCommandEncoder() else {
                    return nil
                }
                encoder.setComputePipelineState(relaxPipeline)

                let inputBuf = readFromA ? distBufferA : distBufferB
                let outputBuf = readFromA ? distBufferB : distBufferA

                encoder.setBuffer(costBuf.buffer, offset: 0, index: 0)
                encoder.setBuffer(inputBuf.buffer, offset: 0, index: 1)
                encoder.setBuffer(outputBuf.buffer, offset: 0, index: 2)
                encoder.setBuffer(roadMaskBuf.buffer, offset: 0, index: 3)
                encoder.setBuffer(changedBuf, offset: 0, index: 4)
                encoder.setBuffer(paramsBuf, offset: 0, index: 5)

                gpu.dispatchThreadsSafe(
                    encoder: encoder,
                    pipeline: relaxPipeline,
                    width: bbox.width,
                    height: bbox.height
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

        return readFromA
    }

    private func extractPath(
        distBuffer: GPUBuffer<Float>,
        from source: SIMD2<Int>,
        to destination: SIMD2<Int>,
        mapWidth: Int,
        mapHeight: Int,
        bbox: BBox
    ) -> [SIMD2<Int>] {
        let ptr = distBuffer.buffer.contents().bindMemory(
            to: Float.self,
            capacity: distBuffer.count
        )

        let destIdx = destination.y * mapWidth + destination.x
        if destIdx < 0 || destIdx >= distBuffer.count {
            return []
        }
        if ptr[destIdx] >= 1e29 {
            return []
        }

        var path: [SIMD2<Int>] = [destination]
        var current = destination

        let directions: [(Int, Int)] = [
            (-1, 0), (1, 0), (0, -1), (0, 1),
            (-1, -1), (1, -1), (-1, 1), (1, 1)
        ]

        let maxSteps = bbox.width * bbox.height

        while current != source && path.count < maxSteps {
            var bestNeighbor = current
            var bestDist = ptr[current.y * mapWidth + current.x]

            for (dx, dy) in directions {
                let nx = current.x + dx
                let ny = current.y + dy

                if nx < bbox.minX || nx >= bbox.maxX {
                    continue
                }
                if ny < bbox.minY || ny >= bbox.maxY {
                    continue
                }
                if nx < 0 || nx >= mapWidth || ny < 0 || ny >= mapHeight {
                    continue
                }

                let nDist = ptr[ny * mapWidth + nx]
                if nDist < bestDist {
                    bestDist = nDist
                    bestNeighbor = SIMD2(nx, ny)
                }
            }

            if bestNeighbor == current {
                return []
            }

            current = bestNeighbor
            path.append(current)
        }

        path.reverse()
        return path
    }

    private func computeBBox(
        from: SIMD2<Int>,
        to: SIMD2<Int>,
        margin: Int,
        mapWidth: Int,
        mapHeight: Int
    ) -> BBox {
        let minX = max(0, min(from.x, to.x) - margin)
        let minY = max(0, min(from.y, to.y) - margin)
        let maxX = min(mapWidth, max(from.x, to.x) + 1 + margin)
        let maxY = min(mapHeight, max(from.y, to.y) + 1 + margin)
        return BBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private func computeCorridorBBox(coarsePath: [SIMD2<Int>]) -> BBox {
        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min

        for point in coarsePath {
            let wx = point.x * downsampleScale
            let wy = point.y * downsampleScale
            if wx < minX {
                minX = wx
            }
            if wy < minY {
                minY = wy
            }
            if wx + downsampleScale > maxX {
                maxX = wx + downsampleScale
            }
            if wy + downsampleScale > maxY {
                maxY = wy + downsampleScale
            }
        }

        minX = max(0, minX - fineSearchMargin)
        minY = max(0, minY - fineSearchMargin)
        maxX = min(width, maxX + fineSearchMargin)
        maxY = min(height, maxY + fineSearchMargin)

        return BBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
