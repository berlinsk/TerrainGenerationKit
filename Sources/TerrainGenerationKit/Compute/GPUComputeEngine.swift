import Foundation
import Metal
import simd

public final class GPUComputeEngine: @unchecked Sendable {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let supportsNonUniformThreadgroups: Bool
    private let isSimulator: Bool
    
    private var jfaInitPipeline: MTLComputePipelineState?
    private var jfaStepPipeline: MTLComputePipelineState?
    private var jfaFinalizePipeline: MTLComputePipelineState?
    
    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.supportsNonUniformThreadgroups = device.supportsFamily(.apple4)
        
        #if targetEnvironment(simulator)
        self.isSimulator = true
        #else
        self.isSimulator = false
        #endif
        
        setupPipelines()
    }
    
    private func setupPipelines() {
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
            return
        }
        
        if let function = library.makeFunction(name: "jumpFloodInit") {
            jfaInitPipeline = try? device.makeComputePipelineState(function: function)
        }
        
        if let function = library.makeFunction(name: "jumpFloodStep") {
            jfaStepPipeline = try? device.makeComputePipelineState(function: function)
        }
        
        if let function = library.makeFunction(name: "jumpFloodFinalize") {
            jfaFinalizePipeline = try? device.makeComputePipelineState(function: function)
        }
    }
    
    private func dispatchThreadsSafe(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        width: Int,
        height: Int
    ) {
        let w = max(1, min(16, pipeline.threadExecutionWidth))
        let h = max(1, min(16, pipeline.maxTotalThreadsPerThreadgroup / w))
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        
        if supportsNonUniformThreadgroups && !isSimulator {
            let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
            encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        } else {
            let threadgroupsPerGrid = MTLSize(
                width: (width + threadsPerGroup.width - 1) / threadsPerGroup.width,
                height: (height + threadsPerGroup.height - 1) / threadsPerGroup.height,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        }
    }
    
    public func generatePoissonDiskSamples(
        width: Int,
        height: Int,
        minDistance: Float,
        seed: UInt64
    ) -> [SIMD2<Float>] {
        return generatePoissonDiskSamplesCPU(
            width: width,
            height: height,
            minDistance: minDistance,
            seed: seed
        )
    }
    
    private func generatePoissonDiskSamplesCPU(
        width: Int,
        height: Int,
        minDistance: Float,
        seed: UInt64
    ) -> [SIMD2<Float>] {
        let cellSize = minDistance / sqrt(2.0)
        let gridWidth = Int(ceil(Float(width) / cellSize))
        let gridHeight = Int(ceil(Float(height) / cellSize))
        
        let rng = SeededRandom(seed: seed)
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(gridWidth * gridHeight)
        
        for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                let baseX = Float(gx) * cellSize
                let baseY = Float(gy) * cellSize
                let jitterX = rng.nextFloat() * cellSize
                let jitterY = rng.nextFloat() * cellSize
                let point = SIMD2<Float>(baseX + jitterX, baseY + jitterY)
                
                if point.x >= 0 && point.x < Float(width) && point.y >= 0 && point.y < Float(height) {
                    points.append(point)
                }
            }
        }
        
        return points
    }
    
    struct JFAParams {
        var width: UInt32
        var height: UInt32
        var step: Int32
        var _padding: Int32 = 0
    }
    
    public func computeRoadSDF(
        roadMask: [Float],
        width: Int,
        height: Int
    ) -> [Float] {
        if let result = computeRoadSDFGPU(roadMask: roadMask, width: width, height: height) {
            return result
        }
        return computeRoadSDFCPU(roadMask: roadMask, width: width, height: height)
    }
    
    private func computeRoadSDFGPU(
        roadMask: [Float],
        width: Int,
        height: Int
    ) -> [Float]? {
        guard let initPipeline = jfaInitPipeline,
              let stepPipeline = jfaStepPipeline,
              let finalizePipeline = jfaFinalizePipeline else {
            return nil
        }
        
        let pixelCount = width * height
        
        guard let roadMaskBuffer = device.makeBuffer(
            bytes: roadMask,
            length: pixelCount * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ),
        let seedBuffer1 = device.makeBuffer(
            length: pixelCount * MemoryLayout<SIMD2<Int32>>.stride,
            options: .storageModeShared
        ),
        let seedBuffer2 = device.makeBuffer(
            length: pixelCount * MemoryLayout<SIMD2<Int32>>.stride,
            options: .storageModeShared
        ),
        let sdfBuffer = device.makeBuffer(
            length: pixelCount * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }
        
        var params = JFAParams(width: UInt32(width), height: UInt32(height), step: 0)
        guard let paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<JFAParams>.stride,
            options: .storageModeShared
        ),
        let initCmdBuffer = commandQueue.makeCommandBuffer(),
        let initEncoder = initCmdBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        initEncoder.setComputePipelineState(initPipeline)
        initEncoder.setBuffer(roadMaskBuffer, offset: 0, index: 0)
        initEncoder.setBuffer(seedBuffer1, offset: 0, index: 1)
        initEncoder.setBuffer(paramsBuffer, offset: 0, index: 2)
        dispatchThreadsSafe(encoder: initEncoder, pipeline: initPipeline, width: width, height: height)
        initEncoder.endEncoding()
        initCmdBuffer.commit()
        initCmdBuffer.waitUntilCompleted()
        
        if initCmdBuffer.status == .error {
            return nil
        }
        
        var step = max(width, height) / 2
        var useBuffer1 = true
        
        while step >= 1 {
            params.step = Int32(step)
            paramsBuffer.contents().copyMemory(from: &params, byteCount: MemoryLayout<JFAParams>.stride)
            
            guard let stepCmdBuffer = commandQueue.makeCommandBuffer(),
                  let stepEncoder = stepCmdBuffer.makeComputeCommandEncoder() else {
                return nil
            }
            
            stepEncoder.setComputePipelineState(stepPipeline)
            stepEncoder.setBuffer(useBuffer1 ? seedBuffer1 : seedBuffer2, offset: 0, index: 0)
            stepEncoder.setBuffer(useBuffer1 ? seedBuffer2 : seedBuffer1, offset: 0, index: 1)
            stepEncoder.setBuffer(paramsBuffer, offset: 0, index: 2)
            dispatchThreadsSafe(encoder: stepEncoder, pipeline: stepPipeline, width: width, height: height)
            stepEncoder.endEncoding()
            stepCmdBuffer.commit()
            stepCmdBuffer.waitUntilCompleted()
            
            if stepCmdBuffer.status == .error {
                return nil
            }
            
            useBuffer1 = !useBuffer1
            step /= 2
        }
        
        guard let finalizeCmdBuffer = commandQueue.makeCommandBuffer(),
              let finalizeEncoder = finalizeCmdBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        finalizeEncoder.setComputePipelineState(finalizePipeline)
        finalizeEncoder.setBuffer(useBuffer1 ? seedBuffer1 : seedBuffer2, offset: 0, index: 0)
        finalizeEncoder.setBuffer(sdfBuffer, offset: 0, index: 1)
        finalizeEncoder.setBuffer(paramsBuffer, offset: 0, index: 2)
        dispatchThreadsSafe(encoder: finalizeEncoder, pipeline: finalizePipeline, width: width, height: height)
        finalizeEncoder.endEncoding()
        finalizeCmdBuffer.commit()
        finalizeCmdBuffer.waitUntilCompleted()
        
        if finalizeCmdBuffer.status == .error {
            return nil
        }
        
        let sdfPtr = sdfBuffer.contents().bindMemory(to: Float.self, capacity: pixelCount)
        var results = [Float](repeating: 1000, count: pixelCount)
        for i in 0..<pixelCount {
            results[i] = sdfPtr[i]
        }
        
        return results
    }
    
    private func computeRoadSDFCPU(
        roadMask: [Float],
        width: Int,
        height: Int
    ) -> [Float] {
        var sdf = [Float](repeating: 1000, count: width * height)
        var queue: [(Int, Int)] = []
        queue.reserveCapacity(width * height / 10)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if roadMask[idx] > 0.5 {
                    sdf[idx] = 0
                    queue.append((x, y))
                }
            }
        }
        
        let maxDist: Float = 10.0
        let directions: [(Int, Int, Float)] = [
            (-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
            (-1, -1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (1, 1, 1.414)
        ]
        var head = 0
        
        while head < queue.count {
            let (cx, cy) = queue[head]
            head += 1
            
            let currentIdx = cy * width + cx
            let currentDist = sdf[currentIdx]
            
            if currentDist >= maxDist {
                continue
            }
            
            for (dx, dy, stepDist) in directions {
                let nx = cx + dx
                let ny = cy + dy
                
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let nidx = ny * width + nx
                    let newDist = currentDist + stepDist
                    if newDist < sdf[nidx] {
                        sdf[nidx] = newDist
                        queue.append((nx, ny))
                    }
                }
            }
        }
        
        return sdf
    }
}

public extension GPUComputeEngine {
    static let shared: GPUComputeEngine? = GPUComputeEngine()
}
