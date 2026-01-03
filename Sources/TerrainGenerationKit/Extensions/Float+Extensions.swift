import Foundation

extension Float {
    
    public func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
    
    public func mapped(from: ClosedRange<Float>, to: ClosedRange<Float>) -> Float {
        let normalized = (self - from.lowerBound) / (from.upperBound - from.lowerBound)
        return to.lowerBound + normalized * (to.upperBound - to.lowerBound)
    }
    
    public var smoothstepValue: Float {
        let t = clamped(to: 0...1)
        return t * t * (3 - 2 * t)
    }
    
    public var smootherstepValue: Float {
        let t = clamped(to: 0...1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
}

extension Array where Element == Float {
    
    public mutating func normalize() {
        guard !isEmpty else {
            return
        }
        
        let minVal = self.min() ?? 0
        let maxVal = self.max() ?? 1
        let range = maxVal - minVal
        
        guard range > 0 else {
            return
        }
        
        for i in indices {
            self[i] = (self[i] - minVal) / range
        }
    }
    
    public func normalized() -> [Float] {
        var copy = self
        copy.normalize()
        return copy
    }
    
    public func average() -> Float {
        guard !isEmpty else {
            return 0
        }
        return reduce(0, +) / Float(count)
    }
}
