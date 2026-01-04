import Foundation

public struct WaterData: Codable, Sendable {
    
    public var riverMask: [Float]
    public var lakeMask: [Float]
    public var flowDirectionX: [Float]
    public var flowDirectionY: [Float]
    public var waterDepth: [Float]
    public var width: Int
    public var height: Int
    
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        let count = width * height
        self.riverMask = [Float](repeating: 0, count: count)
        self.lakeMask = [Float](repeating: 0, count: count)
        self.flowDirectionX = [Float](repeating: 0, count: count)
        self.flowDirectionY = [Float](repeating: 0, count: count)
        self.waterDepth = [Float](repeating: 0, count: count)
    }
    
    public func isRiver(at x: Int, y: Int) -> Bool {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return false
        }
        return riverMask[y * width + x] > 0.5
    }
    
    public func isLake(at x: Int, y: Int) -> Bool {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return false
        }
        return lakeMask[y * width + x] > 0.5
    }
    
    public func combinedWaterMask() -> [Float] {
        var combined = [Float](repeating: 0, count: width * height)
        for i in 0..<combined.count {
            combined[i] = max(riverMask[i], lakeMask[i])
        }
        return combined
    }
}
