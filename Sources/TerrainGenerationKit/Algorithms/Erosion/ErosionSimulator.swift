import Foundation

public final class ErosionSimulator: @unchecked Sendable {
    
    private let hydraulic: HydraulicErosion
    private let thermal: ThermalErosion
    
    public init(params: ErosionParameters, seed: UInt64) {
        self.hydraulic = HydraulicErosion(params: params, seed: seed)
        self.thermal = ThermalErosion(params: params)
    }
    
    public func simulate(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        type: ErosionType
    ) {
        switch type {
        case .none:
            break
        case .hydraulic:
            hydraulic.erode(heightmap: &heightmap, width: width, height: height)
        case .thermal:
            thermal.erode(heightmap: &heightmap, width: width, height: height)
        case .combined:
            let hydraulicIterations = hydraulic.params.iterations / 2
            let thermalIterations = thermal.params.iterations / 200
            
            for _ in 0..<10 {
                thermal.erode(
                    heightmap: &heightmap,
                    width: width,
                    height: height,
                    iterations: thermalIterations / 10
                )
                
                simulateHydraulicPortion(
                    heightmap: &heightmap,
                    width: width,
                    height: height,
                    iterations: hydraulicIterations / 10
                )
            }
        }
    }
    
    private func simulateHydraulicPortion(
        heightmap: inout [Float],
        width: Int,
        height: Int,
        iterations: Int
    ) {
        var tempParams = hydraulic.params
        tempParams.iterations = iterations
        let tempHydraulic = HydraulicErosion(
            params: tempParams,
            seed: UInt64.random(in: 0...UInt64.max)
        )
        tempHydraulic.erode(heightmap: &heightmap, width: width, height: height)
    }
}
