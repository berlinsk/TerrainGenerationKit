import Foundation

public final class ErosionSimulator: @unchecked Sendable {

    private let hydraulic: HydraulicErosion
    private let thermal: ThermalErosion
    private let gpuErosion: GPUErosionSimulator?
    private let seed: UInt64

    public init(params: ErosionParameters, seed: UInt64) {
        self.hydraulic = HydraulicErosion(params: params, seed: seed)
        self.thermal = ThermalErosion(params: params)
        self.seed = seed
        if let gpu = GPUComputeEngine.shared {
            self.gpuErosion = GPUErosionSimulator(gpu: gpu)
        } else {
            self.gpuErosion = nil
        }
    }

    public func simulate(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        type: ErosionType
    ) async {
        switch type {
        case .none:
            break
        case .hydraulic:
            if let gpuErosion = gpuErosion,
               gpuErosion.hydraulicErode(
                   heightmap: &heightmap,
                   width: width,
                   height: height,
                   params: hydraulic.params,
                   seed: seed
               ) {
                return
            }
            await hydraulic.erode(heightmap: &heightmap, width: width, height: height)
        case .thermal:
            let iterations = hydraulic.params.iterations / 100
            if let gpuErosion = gpuErosion,
               gpuErosion.thermalErode(
                   heightmap: &heightmap,
                   width: width,
                   height: height,
                   talusAngle: hydraulic.params.thermalTalusAngle,
                   iterations: iterations
               ) {
                return
            }
            thermal.erode(heightmap: &heightmap, width: width, height: height)
        case .combined:
            if let gpuErosion = gpuErosion,
               simulateCombinedGPU(
                   gpuErosion: gpuErosion,
                   heightmap: &heightmap,
                   width: width,
                   height: height
               ) {
                return
            }
            await simulateCombinedCPU(
                heightmap: &heightmap,
                width: width,
                height: height
            )
        }
    }

    private func simulateCombinedGPU(
        gpuErosion: GPUErosionSimulator,
        heightmap: inout [Float],
        width: Int,
        height: Int
    ) -> Bool {
        let hydraulicPerRound = hydraulic.params.iterations / 20
        let thermalPerRound = hydraulic.params.iterations / 2000

        for round in 0..<10 {
            let thermalOk = gpuErosion.thermalErode(
                heightmap: &heightmap,
                width: width,
                height: height,
                talusAngle: hydraulic.params.thermalTalusAngle,
                iterations: thermalPerRound
            )

            guard thermalOk else {
                return false
            }

            let roundSeed = seed &+ UInt64(round) &* 6364136223846793005

            let hydraulicOk = gpuErosion.hydraulicErode(
                heightmap: &heightmap,
                width: width,
                height: height,
                params: hydraulic.params,
                seed: roundSeed,
                dropletCount: hydraulicPerRound
            )

            guard hydraulicOk else {
                return false
            }
        }

        return true
    }

    private func simulateCombinedCPU(
        heightmap: inout [Float],
        width: Int,
        height: Int
    ) async {
        let hydraulicIterations = hydraulic.params.iterations / 2
        let thermalIterations = thermal.params.iterations / 200

        for _ in 0..<10 {
            thermal.erode(
                heightmap: &heightmap,
                width: width,
                height: height,
                iterations: thermalIterations / 10
            )

            await simulateHydraulicPortion(
                heightmap: &heightmap,
                width: width,
                height: height,
                iterations: hydraulicIterations / 10
            )
        }
    }

    private func simulateHydraulicPortion(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        iterations: Int
    ) async {
        var tempParams = hydraulic.params
        tempParams.iterations = iterations
        let tempHydraulic = HydraulicErosion(
            params: tempParams,
            seed: UInt64.random(in: 0...UInt64.max)
        )
        await tempHydraulic.erode(heightmap: &heightmap, width: width, height: height)
    }
}
