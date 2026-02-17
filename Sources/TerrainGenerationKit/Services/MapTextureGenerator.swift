import CoreGraphics
import Foundation
import simd

public final class MapTextureGenerator: MapTextureGeneratorProtocol {

    public init() {}

    public func generateTexture(from mapData: MapData, mode: MapRenderMode) -> CGImage? {
        if let result = generateTextureGPU(mapData: mapData, mode: mode) {
            return result
        }
        return generateTextureCPU(mapData: mapData, mode: mode)
    }

    private func generateTextureGPU(mapData: MapData, mode: MapRenderMode) -> CGImage? {
        return nil
    }

    private func generateTextureCPU(mapData: MapData, mode: MapRenderMode) -> CGImage? {
        let width = mapData.width
        let height = mapData.height
        var pixels = [UInt8](repeating: 255, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let offset = idx * 4
                let (r, g, b) = colorForPixel(x: x, y: y, idx: idx, mapData: mapData, mode: mode)
                pixels[offset]     = r
                pixels[offset + 1] = g
                pixels[offset + 2] = b
                pixels[offset + 3] = 255
            }
        }

        if mode == .biome || mode == .composite {
            overlayObjects(pixels: &pixels, mapData: mapData, width: width, height: height)
        }

        if mode == .biome || mode == .composite || mode == .cities {
            overlayRoads(pixels: &pixels, mapData: mapData, width: width, height: height)
            overlayCities(pixels: &pixels, mapData: mapData, width: width, height: height)
        }

        return createCGImage(from: pixels, width: width, height: height)
    }

    private func colorForPixel(
        x: Int, y: Int, idx: Int,
        mapData: MapData, mode: MapRenderMode
    ) -> (UInt8, UInt8, UInt8) {
        switch mode {
        case .heightmap:
            let h = mapData.heightmap[idx]
            let v = UInt8(clamping: Int(h * 255))
            return (v, v, v)

        case .biome:
            let biome = BiomeType(rawValue: Int(mapData.biomeMap[idx])) ?? .ocean
            let color = biome.baseColor
            let h = mapData.heightmap[idx]
            let shade = 0.7 + 0.3 * h
            return (
                UInt8(clamping: Int(color.x * shade * 255)),
                UInt8(clamping: Int(color.y * shade * 255)),
                UInt8(clamping: Int(color.z * shade * 255))
            )

        case .temperature:
            return heatmapColor(value: mapData.temperatureMap[idx])

        case .humidity:
            return humidityColor(value: mapData.humidityMap[idx])

        case .water:
            let riverVal = mapData.waterData.riverMask[idx]
            let lakeVal = mapData.waterData.lakeMask[idx]
            let h = mapData.heightmap[idx]
            let seaLevel = mapData.metadata.settings.biome.seaLevel
            if riverVal > 0.3 {
                return (50, 120, 200)
            } else if lakeVal > 0.3 {
                return (40, 100, 180)
            } else if h < seaLevel {
                let depth = (seaLevel - h) / seaLevel
                let b = UInt8(clamping: Int((0.4 + depth * 0.6) * 200 + 30))
                let g = UInt8(clamping: Int((0.2 + depth * 0.2) * 100))
                return (0, g, b)
            } else {
                let v = UInt8(clamping: Int(h * 200 + 30))
                return (v, v, v)
            }

        case .waterDepth:
            let depth = mapData.waterData.waterDepth[idx]
            let riverVal = mapData.waterData.riverMask[idx]
            let lakeVal = mapData.waterData.lakeMask[idx]
            let h = mapData.heightmap[idx]
            let seaLevel = mapData.metadata.settings.biome.seaLevel
            if depth > 0 || riverVal > 0.3 || lakeVal > 0.3 {
                let intensity = 0.3 + depth * 0.7
                let r = UInt8(clamping: Int((1.0 - intensity) * 150))
                let g = UInt8(clamping: Int((1.0 - intensity) * 180 + 40))
                let b = UInt8(clamping: Int(intensity * 200 + 55))
                return (r, g, b)
            } else if h < seaLevel {
                let oceanDepth = (seaLevel - h) / seaLevel
                let intensity = 0.2 + oceanDepth * 0.8
                let r = UInt8(clamping: Int((1.0 - intensity) * 80))
                let g = UInt8(clamping: Int((1.0 - intensity) * 100 + 10))
                let b = UInt8(clamping: Int(intensity * 220 + 35))
                return (r, g, b)
            } else {
                let v = UInt8(clamping: Int(h * 200 + 30))
                return (v, v, v)
            }

        case .flowDirection:
            let fx = mapData.waterData.flowDirectionX[idx]
            let fy = mapData.waterData.flowDirectionY[idx]
            let r = UInt8(clamping: Int((fx * 0.5 + 0.5) * 255))
            let g = UInt8(clamping: Int((fy * 0.5 + 0.5) * 255))
            return (r, g, 128)

        case .cities:
            let cityVal = mapData.cityNetwork.cityMask[idx]
            let wallVal = mapData.cityNetwork.wallMask[idx]
            if wallVal == 2 {
                return (255, 200, 50)
            } else if wallVal == 1 {
                return (120, 100, 80)
            } else if cityVal > 0 {
                return (200, 140, 80)
            } else {
                let h = mapData.heightmap[idx]
                let v = UInt8(clamping: Int(h * 200 + 30))
                return (v, v, v)
            }

        case .steepness:
            let s = mapData.steepnessMap[idx]
            let r = UInt8(clamping: Int(s * 255))
            let g = UInt8(clamping: Int(s * 128))
            return (r, g, 0)

        case .composite:
            let biome = BiomeType(rawValue: Int(mapData.biomeMap[idx])) ?? .ocean
            var color = biome.baseColor
            let h = mapData.heightmap[idx]

            let riverVal = mapData.waterData.riverMask[idx]
            let lakeVal = mapData.waterData.lakeMask[idx]
            if riverVal > 0.3 {
                color = color.mixed(with: SIMD4<Float>(0.2, 0.45, 0.7, 1.0), factor: riverVal)
            }
            if lakeVal > 0.3 {
                color = color.mixed(with: SIMD4<Float>(0.15, 0.4, 0.65, 1.0), factor: lakeVal)
            }

            let roadDist = mapData.cityNetwork.roadSDF[idx]
            if roadDist < 2.0 {
                let roadFactor = max(0, 1.0 - roadDist / 2.0)
                color = color.mixed(with: SIMD4<Float>(0.55, 0.45, 0.35, 1.0), factor: roadFactor * 0.8)
            }

            let cityVal = mapData.cityNetwork.cityMask[idx]
            let wallVal = mapData.cityNetwork.wallMask[idx]
            if wallVal == 2 {
                color = SIMD4<Float>(0.95, 0.8, 0.3, 1.0)
            } else if wallVal == 1 {
                color = SIMD4<Float>(0.5, 0.45, 0.35, 1.0)
            } else if cityVal > 0 {
                color = color.mixed(with: SIMD4<Float>(0.75, 0.55, 0.35, 1.0), factor: 0.6)
            }

            let shade: Float = 0.65 + 0.35 * h
            return (
                UInt8(clamping: Int(color.x * shade * 255)),
                UInt8(clamping: Int(color.y * shade * 255)),
                UInt8(clamping: Int(color.z * shade * 255))
            )
        }
    }

    private func overlayObjects(pixels: inout [UInt8], mapData: MapData, width: Int, height: Int) {
        for obj in mapData.objectLayer.objects {
            let x = Int(obj.position.x)
            let y = Int(obj.position.y)
            guard x >= 0, x < width, y >= 0, y < height else { continue }
            let color = obj.type.color
            let offset = (y * width + x) * 4
            pixels[offset]     = UInt8(clamping: Int(color.x * 255))
            pixels[offset + 1] = UInt8(clamping: Int(color.y * 255))
            pixels[offset + 2] = UInt8(clamping: Int(color.z * 255))
        }
    }

    private func overlayCities(pixels: inout [UInt8], mapData: MapData, width: Int, height: Int) {
        for city in mapData.cityNetwork.cities {
            let cx = city.center.x
            let cy = city.center.y
            for dy in -2...2 {
                for dx in -2...2 {
                    let px = cx + dx
                    let py = cy + dy
                    guard px >= 0, px < width, py >= 0, py < height else { continue }
                    let offset = (py * width + px) * 4
                    pixels[offset]     = 255
                    pixels[offset + 1] = 50
                    pixels[offset + 2] = 50
                }
            }
        }
    }

    private func overlayRoads(pixels: inout [UInt8], mapData: MapData, width: Int, height: Int) {
        for road in mapData.cityNetwork.roads {
            for point in road.path {
                guard point.x >= 0, point.x < width,
                      point.y >= 0, point.y < height else { continue }
                let offset = (point.y * width + point.x) * 4
                if road.hasBridge {
                    pixels[offset]     = 160
                    pixels[offset + 1] = 130
                    pixels[offset + 2] = 90
                } else {
                    pixels[offset]     = 140
                    pixels[offset + 1] = 110
                    pixels[offset + 2] = 80
                }
            }
        }
    }

    private func heatmapColor(value: Float) -> (UInt8, UInt8, UInt8) {
        let v = max(0, min(1, value))
        let r: Float
        let g: Float
        let b: Float
        if v < 0.5 {
            let t = v * 2.0
            r = 0; g = t; b = 1.0 - t
        } else {
            let t = (v - 0.5) * 2.0
            r = t; g = 1.0 - t; b = 0
        }
        return (
            UInt8(clamping: Int(r * 255)),
            UInt8(clamping: Int(g * 255)),
            UInt8(clamping: Int(b * 255))
        )
    }

    private func humidityColor(value: Float) -> (UInt8, UInt8, UInt8) {
        let v = max(0, min(1, value))
        return (
            UInt8(clamping: Int((1.0 - v) * 180 + 40)),
            UInt8(clamping: Int((1.0 - v) * 130 + 60)),
            UInt8(clamping: Int(v * 200 + 55))
        )
    }

    private func createCGImage(from pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
