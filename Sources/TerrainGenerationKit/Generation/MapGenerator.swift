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
        let logger = GenerationLogger.shared
        logger.clear()

        let seed = settings.seed
        let width = settings.width
        let height = settings.height
        let noiseSeed = NoiseSeed(seed)
        let startTime = CFAbsoluteTimeGetCurrent()

        logger.log(stage: "init", message: "starting generation \(width)×\(height)")

        func report(_ stage: GenerationStage, _ progress: Float, _ message: String) {
            progressHandler?(GenerationProgress(stage: stage, progress: progress, message: message))
        }

        report(.heightmap, 0.0, "Initializing terrain generation...")

        report(.heightmap, 0.05, "Generating base noise layers...")
        logger.startStage("heightmap")
        var heightmap = await heightmapService.generateHeightmap(
            width: width,
            height: height,
            settings: settings,
            seed: noiseSeed.derive(0)
        )
        logger.endStage("heightmap", message: "generated")
        report(.heightmap, 0.20, "Terrain base complete")

        if settings.erosion.type != .none {
            report(.erosion, 0.22, "Preparing erosion simulation...")

            let erosionTypeText = settings.erosion.type == .hydraulic ? "hydraulic" : "thermal"
            report(.erosion, 0.25, "Simulating \(erosionTypeText) erosion...")
            logger.startStage("erosion")
            await heightmapService.applyErosion(
                heightmap: &heightmap,
                width: width,
                height: height,
                params: settings.erosion,
                seed: noiseSeed.derive(1)
            )
            logger.endStage("erosion", message: "\(erosionTypeText) erosion applied")
            report(.erosion, 0.35, "Erosion simulation complete")
        } else {
            logger.log(stage: "erosion", message: "skipped")
            report(.erosion, 0.35, "Skipping erosion (disabled)")
        }

        report(.climate, 0.37, "Generating temperature map...")
        logger.startStage("temperature")
        let temperatureMap = await biomeService.generateTemperatureMap(
            heightmap: heightmap,
            width: width,
            height: height,
            params: settings.biome,
            seed: noiseSeed.derive(2)
        )
        logger.endStage("temperature", message: "generated")

        report(.climate, 0.42, "Generating humidity map...")
        logger.startStage("humidity")
        let humidityMap = await biomeService.generateHumidityMap(
            heightmap: heightmap,
            width: width,
            height: height,
            params: settings.biome,
            seed: noiseSeed.derive(3)
        )
        logger.endStage("humidity", message: "generated")

        report(.climate, 0.50, "Climate simulation complete")

        report(.water, 0.52, "Detecting water sources...")

        let waterData: WaterData
        if settings.water.enabled {
            report(.water, 0.55, "Simulating river flow...")
            logger.startStage("water")
            waterData = waterFlowService.generateWaterBodies(
                heightmap: heightmap,
                width: width,
                height: height,
                params: settings.water,
                seaLevel: settings.biome.seaLevel,
                seed: noiseSeed.derive(4)
            )
            logger.endStage("water", message: "generated")
            report(.water, 0.65, "Water systems complete")
        } else {
            logger.log(stage: "water", message: "skipped")
            report(.water, 0.55, "Skipping water generation...")
            waterData = WaterData(width: width, height: height)
            report(.water, 0.65, "Water disabled")
        }

        report(.biomes, 0.67, "Classifying terrain zones...")

        report(.biomes, 0.72, "Assigning biomes based on climate...")
        logger.startStage("biomes")
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
        logger.endStage("biomes", message: "classified")
        report(.biomes, 0.78, "Biome distribution complete")

        var mapData = MapData(
            width: width,
            height: height,
            seed: seed,
            settings: settings
        )
        mapData.heightmap = heightmap
        mapData.temperatureMap = temperatureMap
        mapData.humidityMap = humidityMap
        mapData.biomeMap = biomeMap
        mapData.waterData = waterData

        report(.objects, 0.78, "Analyzing placement zones...")

        report(.objects, 0.80, "Placing trees and vegetation...")
        logger.startStage("objects")
        mapData.objectLayer = objectScatterService.scatterObjects(
            mapData: mapData,
            params: settings.objects,
            seed: noiseSeed.derive(5)
        )
        logger.endStage("objects", message: "scattered")
        report(.objects, 0.84, "Object placement complete")

        if settings.cities.enabled {
            report(.cities, 0.85, "Finding city locations...")

            report(.cities, 0.87, "Building cities and quarters...")
            logger.startStage("cities")
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
            logger.endStage("cities", message: "generated")
            report(.roads, 0.90, "Generating road network...")
        } else {
            logger.log(stage: "cities", message: "skipped")
        }
        report(.objects, 0.92, "Cities and roads complete")

        report(.postProcessing, 0.93, "Applying terrain smoothing...")
        logger.startStage("postprocessing")
        postProcessingService.process(
            mapData: &mapData,
            params: settings.postProcessing
        )
        logger.startStage("steepness")
        mapData.computeSteepnessMap()
        logger.endStage("steepness", message: "computed")
        logger.endStage("postprocessing", message: "complete")
        report(.postProcessing, 0.96, "Post-processing complete")

        report(.rendering, 0.97, "Calculating statistics...")
        logger.startStage("statistics")
        let generationTimeMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        mapData.updateStatistics(generationTimeMs: generationTimeMs)
        logger.endStage("statistics", message: "calculated")

        report(.rendering, 0.99, "Preparing render...")
        report(.complete, 1.0, "Generation complete!")

        let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
        logger.log(stage: "complete", message: "total: \(Int(totalDuration * 1000))ms")

        return mapData
    }
}
