import Foundation
import simd

extension SIMD2 where Scalar == Float {
    
    public var length: Float {
        sqrt(x * x + y * y)
    }
    
    public var lengthSquared: Float {
        x * x + y * y
    }
    
    public var normalized: SIMD2<Float> {
        let len = length
        if len > 0 {
            return self / len
        }
        return .zero
    }
    
    public func distance(to other: SIMD2<Float>) -> Float {
        (self - other).length
    }
    
    public func dot(_ other: SIMD2<Float>) -> Float {
        x * other.x + y * other.y
    }
    
    public func rotated(by angle: Float) -> SIMD2<Float> {
        let c = cos(angle)
        let s = sin(angle)
        return SIMD2(x * c - y * s, x * s + y * c)
    }
}

extension SIMD4 where Scalar == Float {
    
    public var rgb: SIMD3<Float> {
        SIMD3(x, y, z)
    }
    
    public init(rgb: SIMD3<Float>, alpha: Float = 1.0) {
        self.init(rgb.x, rgb.y, rgb.z, alpha)
    }
    
    public func mixed(with other: SIMD4<Float>, factor: Float) -> SIMD4<Float> {
        self * (1 - factor) + other * factor
    }
}
