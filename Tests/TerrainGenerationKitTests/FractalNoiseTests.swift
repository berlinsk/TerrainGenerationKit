import XCTest
@testable import TerrainGenerationKit

final class FractalNoiseTests: XCTestCase {
    
    func testDeterminism() {
        let noise1 = FractalNoise(seed: 12345)
        let noise2 = FractalNoise(seed: 12345)
        
        let params = NoiseParameters.default
        
        let map1 = noise1.generateNoiseMap(width: 64, height: 64, parameters: params)
        let map2 = noise2.generateNoiseMap(width: 64, height: 64, parameters: params)
        
        XCTAssertEqual(map1, map2)
    }
    
    func testDifferentSeeds() {
        let noise1 = FractalNoise(seed: 12345)
        let noise2 = FractalNoise(seed: 54321)
        
        let params = NoiseParameters.default
        
        let map1 = noise1.generateNoiseMap(width: 64, height: 64, parameters: params)
        let map2 = noise2.generateNoiseMap(width: 64, height: 64, parameters: params)
        
        XCTAssertNotEqual(map1, map2)
    }
    
    func testOutputRange() {
        let noise = FractalNoise(seed: 42)
        let params = NoiseParameters.default
        
        let map = noise.generateNoiseMap(width: 128, height: 128, parameters: params)
        
        for value in map {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }
    
    func testCorrectSize() {
        let noise = FractalNoise(seed: 42)
        let params = NoiseParameters.default
        
        let map = noise.generateNoiseMap(width: 100, height: 50, parameters: params)
        
        XCTAssertEqual(map.count, 100 * 50)
    }
    
    func testPerlinNoise() {
        let noise = FractalNoise(seed: 42)
        var params = NoiseParameters.default
        params.type = .perlin
        
        let map = noise.generateNoiseMap(width: 64, height: 64, parameters: params)
        
        XCTAssertEqual(map.count, 64 * 64)
        XCTAssertFalse(map.allSatisfy { $0 == map[0] })
    }
    
    func testSimplexNoise() {
        let noise = FractalNoise(seed: 42)
        var params = NoiseParameters.default
        params.type = .simplex
        
        let map = noise.generateNoiseMap(width: 64, height: 64, parameters: params)
        
        XCTAssertEqual(map.count, 64 * 64)
        XCTAssertFalse(map.allSatisfy { $0 == map[0] })
    }
    
    func testRidgedNoise() {
        let noise = FractalNoise(seed: 42)
        var params = NoiseParameters.default
        params.type = .ridged
        
        let map = noise.generateNoiseMap(width: 64, height: 64, parameters: params)
        
        XCTAssertEqual(map.count, 64 * 64)
        XCTAssertFalse(map.allSatisfy { $0 == map[0] })
    }
    
    func testVoronoiNoise() {
        let noise = FractalNoise(seed: 42)
        var params = NoiseParameters.default
        params.type = .voronoi
        
        let map = noise.generateNoiseMap(width: 64, height: 64, parameters: params)
        
        XCTAssertEqual(map.count, 64 * 64)
        XCTAssertFalse(map.allSatisfy { $0 == map[0] })
    }
    
    func testFBM() {
        let noise = FractalNoise(seed: 42)
        
        let v1 = noise.fbm(x: 10, y: 20, type: .simplex, octaves: 4, frequency: 0.01, persistence: 0.5, lacunarity: 2.0, amplitude: 1.0)
        let v2 = noise.fbm(x: 10, y: 20, type: .simplex, octaves: 4, frequency: 0.01, persistence: 0.5, lacunarity: 2.0, amplitude: 1.0)
        
        XCTAssertEqual(v1, v2)
    }
}
