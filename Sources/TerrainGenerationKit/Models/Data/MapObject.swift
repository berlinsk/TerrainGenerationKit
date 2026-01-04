import Foundation
import simd

public struct MapObject: Codable, Sendable, Identifiable {
    
    public let id: UUID
    public var type: MapObjectType
    public var position: SIMD2<Float>
    public var height: Float
    public var scale: Float
    public var rotation: Float
    public var variation: Int
    
    public init(
        id: UUID = UUID(),
        type: MapObjectType,
        position: SIMD2<Float>,
        height: Float = 0,
        scale: Float = 1.0,
        rotation: Float = 0,
        variation: Int = 0
    ) {
        self.id = id
        self.type = type
        self.position = position
        self.height = height
        self.scale = scale
        self.rotation = rotation
        self.variation = variation
    }
    
    public var worldSize: SIMD2<Float> {
        type.baseSize * scale
    }
    
    public var boundingBox: (min: SIMD2<Float>, max: SIMD2<Float>) {
        let halfSize = worldSize * 0.5
        return (position - halfSize, position + halfSize)
    }
}
