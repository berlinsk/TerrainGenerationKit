import Foundation
import simd

public enum MathUtils {
    
    @inlinable
    public static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + t * (b - a)
    }
    
    @inlinable
    public static func bilerp(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ tx: Float, _ ty: Float) -> Float {
        let ab = lerp(a, b, tx)
        let cd = lerp(c, d, tx)
        return lerp(ab, cd, ty)
    }
    
    @inlinable
    public static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3 - 2 * t)
    }
    
    @inlinable
    public static func smootherstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
    
    @inlinable
    public static func quintic(_ t: Float) -> Float {
        t * t * t * (t * (t * 6 - 15) + 10)
    }
    
    @inlinable
    public static func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
        Swift.min(Swift.max(value, min), max)
    }
    
    @inlinable
    public static func remap(_ value: Float, _ fromLow: Float, _ fromHigh: Float, _ toLow: Float, _ toHigh: Float) -> Float {
        let normalized = (value - fromLow) / (fromHigh - fromLow)
        return toLow + normalized * (toHigh - toLow)
    }
    
    @inlinable
    public static func fract(_ x: Float) -> Float {
        x - floor(x)
    }
    
    @inlinable
    public static func fastFloor(_ x: Float) -> Int {
        x > 0 ? Int(x) : Int(x) - 1
    }
    
    @inlinable
    public static func mod(_ a: Int, _ b: Int) -> Int {
        ((a % b) + b) % b
    }
    
    @inlinable
    public static func mod(_ a: Float, _ b: Float) -> Float {
        a.truncatingRemainder(dividingBy: b)
    }
}

extension MathUtils {
    
    @inlinable
    public static func dot2D(_ grad: SIMD2<Float>, _ x: Float, _ y: Float) -> Float {
        grad.x * x + grad.y * y
    }
    
    @inlinable
    public static func distance2D(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        simd_distance(a, b)
    }
    
    @inlinable
    public static func distanceSquared2D(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
    
    @inlinable
    public static func normalize2D(_ v: SIMD2<Float>) -> SIMD2<Float> {
        let len = sqrt(v.x * v.x + v.y * v.y)
        if len > 0 {
            return v / len
        }
        return .zero
    }
    
    @inlinable
    public static func perpendicular(_ v: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(-v.y, v.x)
    }
    
    @inlinable
    public static func rotate(_ v: SIMD2<Float>, by angle: Float) -> SIMD2<Float> {
        let c = cos(angle)
        let s = sin(angle)
        return SIMD2(v.x * c - v.y * s, v.x * s + v.y * c)
    }
}

extension MathUtils {
    
    @inlinable
    public static func easeIn(_ t: Float) -> Float {
        t * t
    }
    
    @inlinable
    public static func easeOut(_ t: Float) -> Float {
        1 - (1 - t) * (1 - t)
    }
    
    @inlinable
    public static func easeInOut(_ t: Float) -> Float {
        if t < 0.5 {
            return 2 * t * t
        }
        return 1 - pow(-2 * t + 2, 2) / 2
    }
    
    @inlinable
    public static func exponential(_ x: Float, _ power: Float) -> Float {
        pow(x, power)
    }
    
    @inlinable
    public static func sigmoid(_ x: Float, _ k: Float = 1) -> Float {
        1 / (1 + exp(-k * x))
    }
    
    @inlinable
    public static func bias(_ x: Float, _ b: Float) -> Float {
        pow(x, log(b) / log(0.5))
    }
    
    @inlinable
    public static func gain(_ x: Float, _ g: Float) -> Float {
        if x < 0.5 {
            return bias(2 * x, 1 - g) / 2
        }
        return 1 - bias(2 - 2 * x, 1 - g) / 2
    }
}

extension MathUtils {
    
    @inlinable
    public static func hash(_ x: Int) -> Int {
        var h = x
        h = ((h >> 16) ^ h) &* 0x45d9f3b
        h = ((h >> 16) ^ h) &* 0x45d9f3b
        h = (h >> 16) ^ h
        return h
    }
    
    @inlinable
    public static func hash2D(_ x: Int, _ y: Int) -> Int {
        hash(x &+ hash(y))
    }
    
    @inlinable
    public static func hashToFloat(_ x: Int, _ y: Int) -> Float {
        let h = hash2D(x, y)
        return Float(h & 0x7FFFFFFF) / Float(0x7FFFFFFF)
    }
    
    public static let gradients2D: [SIMD2<Float>] = {
        var grads = [SIMD2<Float>]()
        for i in 0..<16 {
            let angle = Float(i) * Float.pi / 8
            grads.append(SIMD2(cos(angle), sin(angle)))
        }
        return grads
    }()
    
    @inlinable
    public static func hashToGradient(_ x: Int, _ y: Int) -> SIMD2<Float> {
        let h = hash2D(x, y) & 15
        return gradients2D[h]
    }
}

extension MathUtils {
    
    @inlinable
    public static func ridged(_ value: Float) -> Float {
        1 - abs(value)
    }
    
    @inlinable
    public static func billow(_ value: Float) -> Float {
        abs(value) * 2 - 1
    }
    
    @inlinable
    public static func terrace(_ value: Float, steps: Int) -> Float {
        let s = Float(steps)
        return floor(value * s) / s
    }
    
    @inlinable
    public static func smoothTerrace(_ value: Float, steps: Int, sharpness: Float) -> Float {
        let s = Float(steps)
        let terraced = floor(value * s) / s
        let t = fract(value * s)
        let smoothT = smoothstep(0, 1, pow(t, sharpness))
        return lerp(terraced, terraced + 1 / s, smoothT)
    }
    
    @inlinable
    public static func temperatureFromHeight(_ height: Float, baseTemp: Float = 0.5) -> Float {
        clamp(baseTemp - height * 0.4, 0, 1)
    }
    
    @inlinable
    public static func temperatureFromLatitude(_ y: Float, height: Float) -> Float {
        let equatorDistance = abs(y - 0.5) * 2
        let latitudeTemp = 1 - equatorDistance
        let heightPenalty = height * 0.4
        return clamp(latitudeTemp - heightPenalty, 0, 1)
    }
}

extension MathUtils {
    
    public static func normalizeArray(_ array: inout [Float]) {
        guard !array.isEmpty else {
            return
        }
        
        var minVal = Float.greatestFiniteMagnitude
        var maxVal = -Float.greatestFiniteMagnitude
        
        for value in array {
            minVal = min(minVal, value)
            maxVal = max(maxVal, value)
        }
        
        let range = maxVal - minVal
        guard range > 0 else {
            return
        }
        
        for i in 0..<array.count {
            array[i] = (array[i] - minVal) / range
        }
    }
    
    public static func applyContrast(_ array: inout [Float], strength: Float) {
        for i in 0..<array.count {
            let centered = array[i] - 0.5
            array[i] = clamp(centered * strength + 0.5, 0, 1)
        }
    }
    
    public static func gaussianBlur(_ array: inout [Float], width: Int, height: Int, radius: Int = 1) {
        guard radius > 0 else {
            return
        }
        
        var temp = [Float](repeating: 0, count: array.count)
        
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                var count: Float = 0
                
                for dx in -radius...radius {
                    let nx = x + dx
                    if nx >= 0 && nx < width {
                        let weight = 1 - Float(abs(dx)) / Float(radius + 1)
                        sum += array[y * width + nx] * weight
                        count += weight
                    }
                }
                temp[y * width + x] = sum / count
            }
        }
        
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                var count: Float = 0
                
                for dy in -radius...radius {
                    let ny = y + dy
                    if ny >= 0 && ny < height {
                        let weight = 1 - Float(abs(dy)) / Float(radius + 1)
                        sum += temp[ny * width + x] * weight
                        count += weight
                    }
                }
                array[y * width + x] = sum / count
            }
        }
    }
}
