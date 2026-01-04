import Foundation
import simd

public struct ObjectGPUData {
    
    public var position: SIMD2<Float>
    public var size: SIMD2<Float>
    public var color: SIMD4<Float>
    public var rotation: Float
    public var type: Int32
    public var padding: SIMD2<Float>
    
    public init(
        position: SIMD2<Float>,
        size: SIMD2<Float>,
        color: SIMD4<Float>,
        rotation: Float,
        type: Int32
    ) {
        self.position = position
        self.size = size
        self.color = color
        self.rotation = rotation
        self.type = type
        self.padding = .zero
    }
    
    public static func from(_ object: MapObject) -> ObjectGPUData {
        ObjectGPUData(
            position: object.position,
            size: object.worldSize,
            color: object.type.color,
            rotation: object.rotation,
            type: Int32(object.type.rawValue)
        )
    }
}
