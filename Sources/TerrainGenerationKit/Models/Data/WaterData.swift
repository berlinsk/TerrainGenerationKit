import Foundation

public struct WaterData: Codable, Sendable {
    
    public var riverMask: [Float]
    public var lakeMask: [Float]
    public var flowDirection: [Int]
    public var waterLevel: [Float]
    
    public init(width: Int, height: Int) {
        let size = width * height
        self.riverMask = [Float](repeating: 0, count: size)
        self.lakeMask = [Float](repeating: 0, count: size)
        self.flowDirection = [Int](repeating: -1, count: size)
        self.waterLevel = [Float](repeating: 0, count: size)
    }
    
    public func isWater(at index: Int) -> Bool {
        riverMask[index] > 0.5 || lakeMask[index] > 0.5
    }
    
    public func isRiver(at index: Int) -> Bool {
        riverMask[index] > 0.5
    }
    
    public func isLake(at index: Int) -> Bool {
        lakeMask[index] > 0.5
    }
}
