import Foundation
import simd

public final class FractalNoise: @unchecked Sendable {
    
    public enum NoiseType {
        case perlin
        case simplex
        case openSimplex
        case voronoi
        case ridged
        case billow
    }
    
    private let seed: UInt64
    private let permutation: [Int]
    private let gradients2D: [SIMD2<Float>]
    
    private static let F2: Float = 0.5 * (sqrt(3.0) - 1.0)
    private static let G2: Float = (3.0 - sqrt(3.0)) / 6.0
    
    public init(seed: UInt64) {
        self.seed = seed
        
        var perm = Array(0..<256)
        var rng = SeededRandom(seed: seed)
        perm.shuffle(using: &rng)
        self.permutation = perm + perm
        
        var grads: [SIMD2<Float>] = []
        for i in 0..<256 {
            let angle = Float(i) / 256.0 * Float.pi * 2.0
            grads.append(SIMD2<Float>(cos(angle), sin(angle)))
        }
        self.gradients2D = grads
    }
    
    public func generateNoiseMap(width: Int, height: Int, parameters: NoiseParameters) -> [Float] {
        var result = [Float](repeating: 0, count: width * height)
        
        let type: NoiseType
        switch parameters.type {
        case .simplex:
            type = .simplex
        case .perlin:
            type = .perlin
        case .openSimplex:
            type = .openSimplex
        case .voronoi:
            type = .voronoi
        case .ridged:
            type = .ridged
        case .billow:
            type = .billow
        }
        
        result.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: height) { y in
                for x in 0..<width {
                    let value = fbm(
                        x: Float(x),
                        y: Float(y),
                        type: type,
                        octaves: parameters.octaves,
                        frequency: parameters.frequency,
                        persistence: parameters.persistence,
                        lacunarity: parameters.lacunarity,
                        amplitude: parameters.amplitude
                    )
                    buf[y * width + x] = value
                }
            }
        }

        MathUtils.normalizeArray(&result)
        return result
    }
    
    public func fbm(
        x: Float,
        y: Float,
        type: NoiseType,
        octaves: Int,
        frequency: Float,
        persistence: Float,
        lacunarity: Float,
        amplitude: Float
    ) -> Float {
        var total: Float = 0
        var freq = frequency
        var amp = amplitude
        var maxValue: Float = 0
        
        for _ in 0..<octaves {
            let noiseValue: Float
            switch type {
            case .perlin:
                noiseValue = perlinNoise(x: x * freq, y: y * freq)
            case .simplex:
                noiseValue = simplexNoise(x: x * freq, y: y * freq)
            case .openSimplex:
                noiseValue = openSimplexNoise(x: x * freq, y: y * freq)
            case .voronoi:
                noiseValue = voronoiNoise(x: x * freq, y: y * freq)
            case .ridged:
                noiseValue = ridgedNoise(x: x * freq, y: y * freq)
            case .billow:
                noiseValue = billowNoise(x: x * freq, y: y * freq)
            }
            total += noiseValue * amp
            maxValue += amp
            amp *= persistence
            freq *= lacunarity
        }
        return total / maxValue
    }
    
    public func domainWarp(
        x: Float,
        y: Float,
        type: NoiseType,
        octaves: Int,
        frequency: Float,
        warpStrength: Float
    ) -> (Float, Float) {
        let warpX = fbm(
            x: x, y: y, type: type, octaves: octaves,
            frequency: frequency, persistence: 0.5, lacunarity: 2.0, amplitude: 1.0
        )
        let warpY = fbm(
            x: x + 5.2, y: y + 1.3, type: type, octaves: octaves,
            frequency: frequency, persistence: 0.5, lacunarity: 2.0, amplitude: 1.0
        )
        return (x + warpX * warpStrength, y + warpY * warpStrength)
    }
    
    private func perlinNoise(x: Float, y: Float) -> Float {
        let xi = Int(floor(x)) & 255
        let yi = Int(floor(y)) & 255
        let xf = x - floor(x)
        let yf = y - floor(y)
        let u = fade(xf)
        let v = fade(yf)
        
        let aa = permutation[permutation[xi] + yi]
        let ab = permutation[permutation[xi] + yi + 1]
        let ba = permutation[permutation[xi + 1] + yi]
        let bb = permutation[permutation[xi + 1] + yi + 1]
        
        let x1 = lerp(grad2D(hash: aa, x: xf, y: yf), grad2D(hash: ba, x: xf - 1, y: yf), u)
        let x2 = lerp(grad2D(hash: ab, x: xf, y: yf - 1), grad2D(hash: bb, x: xf - 1, y: yf - 1), u)
        return lerp(x1, x2, v)
    }
    
    private func simplexNoise(x: Float, y: Float) -> Float {
        let s = (x + y) * Self.F2
        let i = Int(floor(x + s))
        let j = Int(floor(y + s))
        let t = Float(i + j) * Self.G2
        let X0 = Float(i) - t
        let Y0 = Float(j) - t
        let x0 = x - X0
        let y0 = y - Y0
        
        let i1: Int
        let j1: Int
        if x0 > y0 {
            i1 = 1
            j1 = 0
        } else {
            i1 = 0
            j1 = 1
        }
        
        let x1 = x0 - Float(i1) + Self.G2
        let y1 = y0 - Float(j1) + Self.G2
        let x2 = x0 - 1.0 + 2.0 * Self.G2
        let y2 = y0 - 1.0 + 2.0 * Self.G2
        
        let ii = i & 255
        let jj = j & 255
        
        var n0: Float = 0
        var n1: Float = 0
        var n2: Float = 0
        
        var t0 = 0.5 - x0 * x0 - y0 * y0
        if t0 >= 0 {
            t0 *= t0
            let gi0 = permutation[ii + permutation[jj]] & 7
            n0 = t0 * t0 * dot2D(gi: gi0, x: x0, y: y0)
        }
        
        var t1 = 0.5 - x1 * x1 - y1 * y1
        if t1 >= 0 {
            t1 *= t1
            let gi1 = permutation[ii + i1 + permutation[jj + j1]] & 7
            n1 = t1 * t1 * dot2D(gi: gi1, x: x1, y: y1)
        }
        
        var t2 = 0.5 - x2 * x2 - y2 * y2
        if t2 >= 0 {
            t2 *= t2
            let gi2 = permutation[ii + 1 + permutation[jj + 1]] & 7
            n2 = t2 * t2 * dot2D(gi: gi2, x: x2, y: y2)
        }
        
        return 70.0 * (n0 + n1 + n2)
    }
    
    private func openSimplexNoise(x: Float, y: Float) -> Float {
        let stretchConstant: Float = -0.211324865405187
        let squishConstant: Float = 0.366025403784439
        
        let stretchOffset = (x + y) * stretchConstant
        let xs = x + stretchOffset
        let ys = y + stretchOffset
        let xsb = Int(floor(xs))
        let ysb = Int(floor(ys))
        let squishOffset = Float(xsb + ysb) * squishConstant
        let xb = Float(xsb) + squishOffset
        let yb = Float(ysb) + squishOffset
        let xins = xs - Float(xsb)
        let yins = ys - Float(ysb)
        let dx0 = x - xb
        let dy0 = y - yb
        
        var value: Float = 0
        
        var attn0 = 2.0 - dx0 * dx0 - dy0 * dy0
        if attn0 > 0 {
            attn0 *= attn0
            value += attn0 * attn0 * extrapolate(xsb: xsb, ysb: ysb, dx: dx0, dy: dy0)
        }
        
        let dx1 = dx0 - 1 - squishConstant
        let dy1 = dy0 - squishConstant
        var attn1 = 2.0 - dx1 * dx1 - dy1 * dy1
        if attn1 > 0 {
            attn1 *= attn1
            value += attn1 * attn1 * extrapolate(xsb: xsb + 1, ysb: ysb, dx: dx1, dy: dy1)
        }
        
        let dx2 = dx0 - squishConstant
        let dy2 = dy0 - 1 - squishConstant
        var attn2 = 2.0 - dx2 * dx2 - dy2 * dy2
        if attn2 > 0 {
            attn2 *= attn2
            value += attn2 * attn2 * extrapolate(xsb: xsb, ysb: ysb + 1, dx: dx2, dy: dy2)
        }
        
        if xins + yins > 1 {
            let dx3 = dx0 - 1 - 2 * squishConstant
            let dy3 = dy0 - 1 - 2 * squishConstant
            var attn3 = 2.0 - dx3 * dx3 - dy3 * dy3
            if attn3 > 0 {
                attn3 *= attn3
                value += attn3 * attn3 * extrapolate(xsb: xsb + 1, ysb: ysb + 1, dx: dx3, dy: dy3)
            }
        }
        return value / 47.0
    }
    
    private func extrapolate(xsb: Int, ysb: Int, dx: Float, dy: Float) -> Float {
        let index = permutation[(permutation[xsb & 255] + ysb) & 255] & 7
        let grad = gradients2D[index]
        return grad.x * dx + grad.y * dy
    }
    
    private func voronoiNoise(x: Float, y: Float) -> Float {
        let xi = Int(floor(x))
        let yi = Int(floor(y))
        var minDist: Float = Float.greatestFiniteMagnitude
        
        for dy in -1...1 {
            for dx in -1...1 {
                let cellX = xi + dx
                let cellY = yi + dy
                let hash = permutation[(permutation[cellX & 255] + cellY) & 255]
                let px = Float(cellX) + Float(hash & 0xFF) / 255.0
                let py = Float(cellY) + Float((hash >> 8) & 0xFF) / 255.0
                let distX = x - px
                let distY = y - py
                let dist = distX * distX + distY * distY
                if dist < minDist {
                    minDist = dist
                }
            }
        }
        return sqrt(minDist) * 2.0 - 1.0
    }
    
    private func ridgedNoise(x: Float, y: Float) -> Float {
        1.0 - abs(simplexNoise(x: x, y: y))
    }
    
    private func billowNoise(x: Float, y: Float) -> Float {
        abs(simplexNoise(x: x, y: y)) * 2.0 - 1.0
    }
    
    private func fade(_ t: Float) -> Float {
        t * t * t * (t * (t * 6 - 15) + 10)
    }
    
    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + t * (b - a)
    }
    
    private func grad2D(hash: Int, x: Float, y: Float) -> Float {
        let h = hash & 3
        switch h {
        case 0:
            return x + y
        case 1:
            return -x + y
        case 2:
            return x - y
        default:
            return -x - y
        }
    }
    
    private func dot2D(gi: Int, x: Float, y: Float) -> Float {
        let grad: [SIMD2<Float>] = [
            SIMD2(1, 1), SIMD2(-1, 1), SIMD2(1, -1), SIMD2(-1, -1),
            SIMD2(1, 0), SIMD2(-1, 0), SIMD2(0, 1), SIMD2(0, -1)
        ]
        let g = grad[gi & 7]
        return g.x * x + g.y * y
    }
}
