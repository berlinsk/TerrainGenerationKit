import Foundation
import simd

public final class MapGenerator: MapGeneratorProtocol, @unchecked Sendable {
    
    private let noiseService: NoiseService
    private let heightmapService: HeightmapService
    private let biomeService: BiomeService
    private let waterFlowService: WaterFlowService
    private let objectScatterService: ObjectScatterService
    private let cityService: CityService
    private let postProcessingService: PostProcessingService
    
    public init() {
        self.noiseService = NoiseService()
        self.heightmapService = HeightmapService(noiseService: noiseService)
        self.biomeService = BiomeService(noiseService: noiseService)
        self.waterFlowService = WaterFlowService()
        self.objectScatterService = ObjectScatterService()
        self.cityService = CityService()
        self.postProcessingService = PostProcessingService(heightmapService: heightmapService)
    }
    
    public func generate(
        settings: GenerationSettings,
        progressHandler: (@Sendable (GenerationProgress) -> Void)?
    ) async throws -> MapData {
        let seed = settings.seed
        let width = settings.width
        let height = settings.height
        let noiseSeed = NoiseSeed(seed)
        
        func report(_ stage: GenerationStage, _ progress: Float, _ message: String) {
            progressHandler?(GenerationProgress(stage: stage, progress: progress, message: message))
        }
        
        report(.heightmap, 0.0, "Initializing terrain generation...")
        
        report(.heightmap, 0.05, "Generating base noise layers...")
        var heightmap = await heightmapService.generateHeightmap(
            width: width,
            height: height,
            settings: settings,
            seed: noiseSeed.derive(0)
        )
        report(.heightmap, 0.20, "Terrain base complete")
        
        if settings.erosion.type != .none {
            report(.erosion, 0.22, "Preparing erosion simulation...")
            
            let erosionTypeText = settings.erosion.type == .hydraulic ? "hydraulic" : "thermal"
            report(.erosion, 0.25, "Simulating \(erosionTypeText) erosion...")
            heightmapService.applyErosion(
                heightmap: &heightmap,
                width: width,
                height: height,
                params: settings.erosion,
                seed: noiseSeed.derive(1)
            )
            report(.erosion, 0.35, "Erosion simulation complete")
        } else {
            report(.erosion, 0.35, "Skipping erosion (disabled)")
        }
        
        report(.climate, 0.37, "Generating temperature map...")
        async let temperatureMapTask = biomeService.generateTemperatureMap(
            heightmap: heightmap,
            width: width,
            height: height,
            params: settings.biome,
            seed: noiseSeed.derive(2)
        )
        
        report(.climate, 0.42, "Generating humidity map...")
        async let humidityMapTask = biomeService.generateHumidityMap(
            heightmap: heightmap,
            width: width,
            height: height,
            params: settings.biome,
            seed: noiseSeed.derive(3)
        )
        
        let (temperatureMap, humidityMap) = await (temperatureMapTask, humidityMapTask)
        report(.climate, 0.50, "Climate simulation complete")
        
        report(.water, 0.52, "Detecting water sources...")
        
        let waterData: WaterData
        if settings.water.enabled {
            report(.water, 0.55, "Simulating river flow...")
            waterData = waterFlowService.generateWaterBodies(
                heightmap: heightmap,
                width: width,
                height: height,
                params: settings.water,
                seaLevel: settings.biome.seaLevel,
                seed: noiseSeed.derive(4)
            )
            report(.water, 0.65, "Water systems complete")
        } else {
            report(.water, 0.55, "Skipping water generation...")
            waterData = WaterData(width: width, height: height)
            report(.water, 0.65, "Water disabled")
        }
        
        report(.biomes, 0.67, "Classifying terrain zones...")
        
        report(.biomes, 0.72, "Assigning biomes based on climate...")
        let biomeMap = biomeService.generateBiomes(
            heightmap: heightmap,
            temperatureMap: temperatureMap,
            humidityMap: humidityMap,
            waterData: waterData,
            width: width,
            height: height,
            params: settings.biome,
            selection: settings.biomeSelection
        )
        report(.biomes, 0.78, "Biome distribution complete")
        
        var mapData = MapData(
            seed: seed,
            width: width,
            height: height,
            heightmap: heightmap,
            biomeMap: biomeMap,
            temperatureMap: temperatureMap,
            humidityMap: humidityMap,
            waterData: waterData
        )
        
        report(.objects, 0.78, "Analyzing placement zones...")
        
        report(.objects, 0.80, "Placing trees and vegetation...")
        mapData.objectLayer = objectScatterService.scatterObjects(
            heightmap: heightmap,
            biomeMap: biomeMap,
            temperatureMap: temperatureMap,
            humidityMap: humidityMap,
            waterData: waterData,
            width: width,
            height: height,
            params: settings.objects,
            seed: noiseSeed.derive(5)
        )
        report(.objects, 0.84, "Object placement complete")
        
        if settings.cities.enabled {
            report(.cities, 0.85, "Finding city locations...")
            
            report(.cities, 0.87, "Building cities and quarters...")
            mapData.cityNetwork = cityService.generateCityNetwork(
                heightmap: mapData.heightmap,
                biomeMap: mapData.biomeMap,
                waterData: mapData.waterData,
                width: width,
                height: height,
                params: settings.cities,
                seaLevel: settings.biome.seaLevel,
                seed: noiseSeed.derive(6)
            )
            
            report(.roads, 0.90, "Generating road network...")
        }
        report(.objects, 0.92, "Cities and roads complete")
        
        report(.postProcessing, 0.93, "Applying terrain smoothing...")
        postProcessingService.process(
            mapData: &mapData,
            params: settings.postProcessing
        )
        report(.postProcessing, 0.96, "Post-processing complete")
        
        report(.rendering, 0.97, "Calculating statistics...")
        mapData.statistics = calculateStatistics(mapData: mapData, settings: settings)
        
        report(.rendering, 0.99, "Preparing render...")
        report(.complete, 1.0, "Generation complete!")
        
        return mapData
    }
    
    private func calculateStatistics(mapData: MapData, settings: GenerationSettings) -> MapStatistics {
        var stats = MapStatistics()
        
        let totalPixels = mapData.width * mapData.height
        var waterCount = 0
        var biomeCount: [BiomeType: Int] = [:]
        var minH: Float = 1
        var maxH: Float = 0
        var sumH: Float = 0
        
        for i in 0..<totalPixels {
            let h = mapData.heightmap[i]
            let biome = mapData.biomeMap[i]
            
            minH = min(minH, h)
            maxH = max(maxH, h)
            sumH += h
            
            if biome.isWater {
                waterCount += 1
            }
            
            biomeCount[biome, default: 0] += 1
        }
        
        stats.minHeight = minH
        stats.maxHeight = maxH
        stats.averageHeight = sumH / Float(totalPixels)
        stats.waterPercentage = Float(waterCount) / Float(totalPixels) * 100
        stats.landPercentage = 100 - stats.waterPercentage
        
        for (biome, count) in biomeCount {
            stats.biomeDistribution[biome] = Float(count) / Float(totalPixels) * 100
        }
        
        return stats
    }
}
