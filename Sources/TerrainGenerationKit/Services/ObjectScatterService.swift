import Foundation
import simd

public protocol ObjectScatterServiceProtocol: Sendable {
    func scatterObjects(
        heightmap: [Float],
        biomeMap: [BiomeType],
        temperatureMap: [Float],
        humidityMap: [Float],
        waterData: WaterData,
        width: Int,
        height: Int,
        params: ObjectScatterParameters,
        seed: UInt64
    ) -> ObjectLayer
}

public final class ObjectScatterService: ObjectScatterServiceProtocol, @unchecked Sendable {
    
    public init() {}
    
    public func scatterObjects(
        heightmap: [Float],
        biomeMap: [BiomeType],
        temperatureMap: [Float],
        humidityMap: [Float],
        waterData: WaterData,
        width: Int,
        height: Int,
        params: ObjectScatterParameters,
        seed: UInt64
    ) -> ObjectLayer {
        let engine = ObjectScatterEngine(params: params, seed: seed)
        
        var objectLayer = engine.scatter(
            heightmap: heightmap,
            biomeMap: biomeMap,
            temperatureMap: temperatureMap,
            humidityMap: humidityMap,
            waterData: waterData,
            width: width,
            height: height
        )
        
        objectLayer.objects.sort { $0.position.y < $1.position.y }
        
        return objectLayer
    }
}
