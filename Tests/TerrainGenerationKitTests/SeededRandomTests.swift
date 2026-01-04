import XCTest
@testable import TerrainGenerationKit

final class SeededRandomTests: XCTestCase {
    
    func testDeterminism() {
        let rng1 = SeededRandom(seed: 12345)
        let rng2 = SeededRandom(seed: 12345)
        
        for _ in 0..<100 {
            XCTAssertEqual(rng1.nextFloat(), rng2.nextFloat())
        }
    }
    
    func testDifferentSeeds() {
        let rng1 = SeededRandom(seed: 12345)
        let rng2 = SeededRandom(seed: 54321)
        
        var same = true
        for _ in 0..<10 {
            if rng1.nextFloat() != rng2.nextFloat() {
                same = false
                break
            }
        }
        XCTAssertFalse(same)
    }
    
    func testFloatRange() {
        let rng = SeededRandom(seed: 42)
        
        for _ in 0..<1000 {
            let value = rng.nextFloat()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }
    
    func testIntRange() {
        let rng = SeededRandom(seed: 42)
        
        for _ in 0..<1000 {
            let value = rng.nextInt(in: 5...10)
            XCTAssertGreaterThanOrEqual(value, 5)
            XCTAssertLessThanOrEqual(value, 10)
        }
    }
    
    func testFloatInRange() {
        let rng = SeededRandom(seed: 42)
        
        for _ in 0..<1000 {
            let value = rng.nextFloat(in: 0.5...1.5)
            XCTAssertGreaterThanOrEqual(value, 0.5)
            XCTAssertLessThanOrEqual(value, 1.5)
        }
    }
    
    func testBool() {
        let rng = SeededRandom(seed: 42)
        var trueCount = 0
        var falseCount = 0
        
        for _ in 0..<1000 {
            if rng.nextBool() {
                trueCount += 1
            } else {
                falseCount += 1
            }
        }
        
        XCTAssertGreaterThan(trueCount, 400)
        XCTAssertGreaterThan(falseCount, 400)
    }
    
    func testFork() {
        let rng = SeededRandom(seed: 42)
        let forked = rng.fork()
        
        let v1 = rng.nextFloat()
        let v2 = forked.nextFloat()
        
        XCTAssertNotEqual(v1, v2)
    }
    
    func testGaussian() {
        let rng = SeededRandom(seed: 42)
        var values: [Float] = []
        
        for _ in 0..<1000 {
            values.append(rng.nextGaussian(mean: 0, stdDev: 1))
        }
        
        let mean = values.reduce(0, +) / Float(values.count)
        XCTAssertEqual(mean, 0, accuracy: 0.2)
    }
    
    func testShuffle() {
        let rng = SeededRandom(seed: 42)
        var array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let original = array
        
        rng.shuffle(&array)
        
        XCTAssertNotEqual(array, original)
        XCTAssertEqual(Set(array), Set(original))
    }
}
