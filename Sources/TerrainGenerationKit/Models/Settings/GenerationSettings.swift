import Foundation
import simd

public struct GenerationSettings: Codable, Sendable, Equatable {
    
    public var seed: UInt64
    public var width: Int
    public var height: Int
    public var mode: GenerationMode
    
    public var primaryNoise: NoiseParameters
    public var secondaryNoise: NoiseParameters?
    public var detailNoise: NoiseParameters?
    
    public var biome: BiomeParameters
    public var biomeSelection: BiomeSelection
    public var water: WaterParameters
    public var erosion: ErosionParameters
    public var objects: ObjectScatterParameters
    public var cities: CityGenerationParameters
    public var postProcessing: PostProcessingParameters
    
    public var primaryWeight: Float
    public var secondaryWeight: Float
    public var detailWeight: Float
    
    public init(
        seed: UInt64 = UInt64.random(in: 0...UInt64.max),
        width: Int = 512,
        height: Int = 512,
        mode: GenerationMode = .continental,
        primaryNoise: NoiseParameters = .continental,
        secondaryNoise: NoiseParameters? = nil,
        detailNoise: NoiseParameters? = NoiseParameters(
            type: .simplex,
            octaves: 4,
            frequency: 0.02,
            persistence: 0.4,
            lacunarity: 2.0,
            amplitude: 0.15
        ),
        biome: BiomeParameters = .default,
        biomeSelection: BiomeSelection = .default,
        water: WaterParameters = .default,
        erosion: ErosionParameters = .default,
        objects: ObjectScatterParameters = .default,
        cities: CityGenerationParameters = .default,
        postProcessing: PostProcessingParameters = .default,
        primaryWeight: Float = 0.7,
        secondaryWeight: Float = 0.2,
        detailWeight: Float = 0.1
    ) {
        self.seed = seed
        self.width = width
        self.height = height
        self.mode = mode
        self.primaryNoise = primaryNoise
        self.secondaryNoise = secondaryNoise
        self.detailNoise = detailNoise
        self.biome = biome
        self.biomeSelection = biomeSelection
        self.water = water
        self.erosion = erosion
        self.objects = objects
        self.cities = cities
        self.postProcessing = postProcessing
        self.primaryWeight = primaryWeight
        self.secondaryWeight = secondaryWeight
        self.detailWeight = detailWeight
    }
    
    public static var `default`: GenerationSettings {
        GenerationSettings()
    }
    
    public static var small: GenerationSettings {
        var s = GenerationSettings()
        s.width = 256
        s.height = 256
        return s
    }
    
    public static var large: GenerationSettings {
        var s = GenerationSettings()
        s.width = 1024
        s.height = 1024
        s.erosion.iterations = 100000
        return s
    }
    
    public mutating func randomizeSeed() {
        seed = UInt64.random(in: 0...UInt64.max)
    }
}

extension GenerationSettings {
    
    public static var presets: [String: GenerationSettings] {
        [
            "Continental": .continental,
            "Archipelago": .archipelago,
            "Desert": .desert,
            "Tundra": .tundra,
            "Volcanic": .volcanic
        ]
    }
    
    public static var continental: GenerationSettings {
        var settings = GenerationSettings()
        settings.mode = .continental
        settings.primaryNoise = .continental
        settings.biome.seaLevel = 0.35
        return settings
    }
    
    public static var archipelago: GenerationSettings {
        var settings = GenerationSettings()
        settings.mode = .archipelago
        settings.primaryNoise = .archipelago
        settings.biome.seaLevel = 0.55
        settings.water.riverCount = 3
        return settings
    }
    
    public static var desert: GenerationSettings {
        var settings = GenerationSettings()
        settings.biome.humidityVariation = 0.2
        settings.biome.desertThreshold = 0.6
        settings.water.riverCount = 2
        settings.objects.treeDensity = 0.05
        settings.objects.vegetationDensity = 0.1
        return settings
    }
    
    public static var tundra: GenerationSettings {
        var settings = GenerationSettings()
        settings.biome.temperatureVariation = 0.3
        settings.biome.snowLevel = 0.5
        settings.water.riverCount = 5
        settings.objects.treeDensity = 0.15
        return settings
    }
    
    public static var volcanic: GenerationSettings {
        var settings = GenerationSettings()
        settings.primaryNoise = NoiseParameters(
            type: .ridged,
            octaves: 7,
            frequency: 0.006,
            persistence: 0.65,
            lacunarity: 2.3,
            amplitude: 1.4
        )
        settings.erosion.type = .thermal
        settings.erosion.thermalTalusAngle = 0.4
        settings.biome.seaLevel = 0.25
        return settings
    }
}
