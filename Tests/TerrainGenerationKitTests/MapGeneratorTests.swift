import XCTest
@testable import TerrainGenerationKit

final class MapGeneratorTests: XCTestCase {
    
    func testBasicGeneration() async throws {
        let generator = MapGenerator()
        var settings = GenerationSettings.default
        settings.width = 64
        settings.height = 64
        settings.seed = 12345
        settings.erosion.type = .none
        settings.cities.enabled = false
        
        let mapData = try await generator.generate(settings: settings, progressHandler: nil)
        
        XCTAssertEqual(mapData.width, 64)
        XCTAssertEqual(mapData.height, 64)
        XCTAssertEqual(mapData.seed, 12345)
        XCTAssertEqual(mapData.heightmap.count, 64 * 64)
        XCTAssertEqual(mapData.biomeMap.count, 64 * 64)
    }
    
    func testDeterministicGeneration() async throws {
        let generator = MapGenerator()
        var settings = GenerationSettings.default
        settings.width = 32
        settings.height = 32
        settings.seed = 42
        settings.erosion.type = .none
        settings.cities.enabled = false
        
        let map1 = try await generator.generate(settings: settings, progressHandler: nil)
        let map2 = try await generator.generate(settings: settings, progressHandler: nil)
        
        XCTAssertEqual(map1.heightmap, map2.heightmap)
        XCTAssertEqual(map1.biomeMap, map2.biomeMap)
    }
    
    func testProgressCallback() async throws {
        let generator = MapGenerator()
        var settings = GenerationSettings.default
        settings.width = 32
        settings.height = 32
        settings.erosion.type = .none
        settings.cities.enabled = false
        
        var progressUpdates: [GenerationProgress] = []
        
        _ = try await generator.generate(settings: settings) { progress in
            progressUpdates.append(progress)
        }
        
        XCTAssertGreaterThan(progressUpdates.count, 0)
        XCTAssertEqual(progressUpdates.last?.stage, .complete)
        XCTAssertEqual(progressUpdates.last?.progress, 1.0)
    }
    
    func testHeightmapRange() async throws {
        let generator = MapGenerator()
        var settings = GenerationSettings.default
        settings.width = 64
        settings.height = 64
        settings.erosion.type = .none
        settings.cities.enabled = false
        
        let mapData = try await generator.generate(settings: settings, progressHandler: nil)
        
        for value in mapData.heightmap {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }
    
    func testStatisticsCalculation() async throws {
        let generator = MapGenerator()
        var settings = GenerationSettings.default
        settings.width = 64
        settings.height = 64
        settings.erosion.type = .none
        settings.cities.enabled = false
        
        let mapData = try await generator.generate(settings: settings, progressHandler: nil)
        
        XCTAssertGreaterThanOrEqual(mapData.statistics.minHeight, 0)
        XCTAssertLessThanOrEqual(mapData.statistics.maxHeight, 1)
        XCTAssertEqual(mapData.statistics.landPercentage + mapData.statistics.waterPercentage, 100, accuracy: 0.01)
    }
    
    func testWaterDataGeneration() async throws {
        let generator = MapGenerator()
        var settings = GenerationSettings.default
        settings.width = 64
        settings.height = 64
        settings.erosion.type = .none
        settings.cities.enabled = false
        settings.water.enabled = true
        settings.water.riverCount = 2
        
        let mapData = try await generator.generate(settings: settings, progressHandler: nil)
        
        XCTAssertEqual(mapData.waterData.riverMask.count, 64 * 64)
        XCTAssertEqual(mapData.waterData.lakeMask.count, 64 * 64)
    }
    
    func testTemperatureAndHumidityMaps() async throws {
        let generator = MapGenerator()
        var settings = GenerationSettings.default
        settings.width = 64
        settings.height = 64
        settings.erosion.type = .none
        settings.cities.enabled = false
        
        let mapData = try await generator.generate(settings: settings, progressHandler: nil)
        
        XCTAssertEqual(mapData.temperatureMap.count, 64 * 64)
        XCTAssertEqual(mapData.humidityMap.count, 64 * 64)
        
        for value in mapData.temperatureMap {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
        
        for value in mapData.humidityMap {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }
    
    func testDifferentGenerationModes() async throws {
        let generator = MapGenerator()
        
        for mode in GenerationMode.allCases {
            var settings = GenerationSettings.default
            settings.width = 32
            settings.height = 32
            settings.mode = mode
            settings.erosion.type = .none
            settings.cities.enabled = false
            
            let mapData = try await generator.generate(settings: settings, progressHandler: nil)
            XCTAssertEqual(mapData.heightmap.count, 32 * 32)
        }
    }
}
