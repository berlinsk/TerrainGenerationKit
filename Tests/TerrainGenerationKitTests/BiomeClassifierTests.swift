import XCTest
@testable import TerrainGenerationKit

final class BiomeClassifierTests: XCTestCase {
    
    var classifier: BiomeClassifier!
    
    override func setUp() {
        super.setUp()
        classifier = BiomeClassifier(parameters: .default)
    }
    
    func testDeepOcean() {
        let biome = classifier.classify(height: 0.1, temperature: 0.5, humidity: 0.5)
        XCTAssertEqual(biome, .deepOcean)
    }
    
    func testOcean() {
        let biome = classifier.classify(height: 0.25, temperature: 0.5, humidity: 0.5)
        XCTAssertEqual(biome, .ocean)
    }
    
    func testShallowWater() {
        let biome = classifier.classify(height: 0.33, temperature: 0.5, humidity: 0.5)
        XCTAssertEqual(biome, .shallowWater)
    }
    
    func testBeach() {
        let biome = classifier.classify(height: 0.36, temperature: 0.5, humidity: 0.5)
        XCTAssertEqual(biome, .beach)
    }
    
    func testDesert() {
        let biome = classifier.classify(height: 0.5, temperature: 0.8, humidity: 0.1)
        XCTAssertEqual(biome, .desert)
    }
    
    func testSnowyMountain() {
        let biome = classifier.classify(height: 0.9, temperature: 0.1, humidity: 0.5)
        XCTAssertEqual(biome, .snowyMountain)
    }
    
    func testRiver() {
        let biome = classifier.classify(height: 0.5, temperature: 0.5, humidity: 0.5, isRiver: true)
        XCTAssertEqual(biome, .river)
    }
    
    func testLake() {
        let biome = classifier.classify(height: 0.5, temperature: 0.5, humidity: 0.5, isLake: true)
        XCTAssertEqual(biome, .lake)
    }
    
    func testWaterBiomes() {
        XCTAssertTrue(BiomeType.deepOcean.isWater)
        XCTAssertTrue(BiomeType.ocean.isWater)
        XCTAssertTrue(BiomeType.shallowWater.isWater)
        XCTAssertTrue(BiomeType.river.isWater)
        XCTAssertTrue(BiomeType.lake.isWater)
        XCTAssertFalse(BiomeType.grassland.isWater)
        XCTAssertFalse(BiomeType.forest.isWater)
    }
    
    func testTreeBiomes() {
        XCTAssertTrue(BiomeType.forest.canHaveTrees)
        XCTAssertTrue(BiomeType.rainforest.canHaveTrees)
        XCTAssertTrue(BiomeType.taiga.canHaveTrees)
        XCTAssertFalse(BiomeType.desert.canHaveTrees)
        XCTAssertFalse(BiomeType.ocean.canHaveTrees)
    }
    
    func testRockBiomes() {
        XCTAssertTrue(BiomeType.mountain.canHaveRocks)
        XCTAssertTrue(BiomeType.snowyMountain.canHaveRocks)
        XCTAssertTrue(BiomeType.desert.canHaveRocks)
        XCTAssertFalse(BiomeType.forest.canHaveRocks)
        XCTAssertFalse(BiomeType.ocean.canHaveRocks)
    }
    
    func testBiomeColors() {
        for biome in BiomeType.allCases {
            let color = biome.baseColor
            XCTAssertGreaterThanOrEqual(color.x, 0)
            XCTAssertLessThanOrEqual(color.x, 1)
            XCTAssertGreaterThanOrEqual(color.y, 0)
            XCTAssertLessThanOrEqual(color.y, 1)
            XCTAssertGreaterThanOrEqual(color.z, 0)
            XCTAssertLessThanOrEqual(color.z, 1)
            XCTAssertEqual(color.w, 1)
        }
    }
}
