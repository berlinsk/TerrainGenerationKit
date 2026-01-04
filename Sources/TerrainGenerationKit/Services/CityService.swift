import Foundation
import simd

public protocol CityServiceProtocol: Sendable {
    func generateCityNetwork(
        heightmap: [Float],
        biomeMap: [UInt8],
        waterData: WaterData,
        width: Int,
        height: Int,
        params: CityGenerationParameters,
        seaLevel: Float,
        seed: UInt64
    ) -> CityNetworkData
}

public final class CityService: CityServiceProtocol, @unchecked Sendable {
    
    public init() {}
    
    public func generateCityNetwork(
        heightmap: [Float],
        biomeMap: [UInt8],
        waterData: WaterData,
        width: Int,
        height: Int,
        params: CityGenerationParameters,
        seaLevel: Float,
        seed: UInt64
    ) -> CityNetworkData {
        guard params.enabled else {
            return CityNetworkData(width: width, height: height)
        }
        
        let noiseSeed = NoiseSeed(seed)
        
        let cityGenerator = CityGenerator(params: params, seed: noiseSeed.derive(0))
        let cities = cityGenerator.generateCities(
            heightmap: heightmap,
            biomeMap: biomeMap,
            waterData: waterData,
            width: width,
            height: height,
            seaLevel: seaLevel
        )
        
        let roadGenerator = RoadGenerator(params: params, seed: noiseSeed.derive(1))
        let roads = roadGenerator.generateRoads(
            cities: cities,
            heightmap: heightmap,
            biomeMap: biomeMap,
            waterData: waterData,
            width: width,
            height: height,
            seaLevel: seaLevel
        )
        
        var networkData = CityNetworkData(width: width, height: height)
        networkData.cities = cities
        networkData.roads = roads
        networkData.updateMasks(width: width, height: height)
        
        return networkData
    }
}
