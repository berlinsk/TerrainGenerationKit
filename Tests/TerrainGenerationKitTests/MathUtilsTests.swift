import XCTest
@testable import TerrainGenerationKit

final class MathUtilsTests: XCTestCase {
    
    func testLerp() {
        XCTAssertEqual(MathUtils.lerp(0, 10, 0), 0)
        XCTAssertEqual(MathUtils.lerp(0, 10, 1), 10)
        XCTAssertEqual(MathUtils.lerp(0, 10, 0.5), 5)
    }
    
    func testClamp() {
        XCTAssertEqual(MathUtils.clamp(-1, 0, 1), 0)
        XCTAssertEqual(MathUtils.clamp(2, 0, 1), 1)
        XCTAssertEqual(MathUtils.clamp(0.5, 0, 1), 0.5)
    }
    
    func testRemap() {
        let result = MathUtils.remap(5, 0, 10, 0, 100)
        XCTAssertEqual(result, 50, accuracy: 0.001)
    }
    
    func testSmoothstep() {
        XCTAssertEqual(MathUtils.smoothstep(0, 1, 0), 0)
        XCTAssertEqual(MathUtils.smoothstep(0, 1, 1), 1)
        let mid = MathUtils.smoothstep(0, 1, 0.5)
        XCTAssertEqual(mid, 0.5, accuracy: 0.001)
    }
    
    func testHash() {
        let h1 = MathUtils.hash(42)
        let h2 = MathUtils.hash(42)
        let h3 = MathUtils.hash(43)
        
        XCTAssertEqual(h1, h2)
        XCTAssertNotEqual(h1, h3)
    }
    
    func testHash2D() {
        let h1 = MathUtils.hash2D(10, 20)
        let h2 = MathUtils.hash2D(10, 20)
        let h3 = MathUtils.hash2D(20, 10)
        
        XCTAssertEqual(h1, h2)
        XCTAssertNotEqual(h1, h3)
    }
    
    func testNormalizeArray() {
        var array: [Float] = [0, 5, 10]
        MathUtils.normalizeArray(&array)
        
        XCTAssertEqual(array[0], 0, accuracy: 0.001)
        XCTAssertEqual(array[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(array[2], 1, accuracy: 0.001)
    }
    
    func testBilerp() {
        let result = MathUtils.bilerp(0, 1, 0, 1, 0.5, 0.5)
        XCTAssertEqual(result, 0.5, accuracy: 0.001)
    }
    
    func testFract() {
        XCTAssertEqual(MathUtils.fract(2.7), 0.7, accuracy: 0.001)
        XCTAssertEqual(MathUtils.fract(5.0), 0.0, accuracy: 0.001)
    }
    
    func testMod() {
        XCTAssertEqual(MathUtils.mod(-1, 3), 2)
        XCTAssertEqual(MathUtils.mod(5, 3), 2)
    }
}
