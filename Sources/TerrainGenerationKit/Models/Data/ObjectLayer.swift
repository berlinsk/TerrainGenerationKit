import Foundation
import simd

public struct ObjectLayer: Codable, Sendable {
    
    public var objects: [MapObject]
    public var width: Int
    public var height: Int
    
    public init(width: Int, height: Int) {
        self.objects = []
        self.width = width
        self.height = height
    }
    
    public mutating func add(_ object: MapObject) {
        objects.append(object)
    }
    
    public func objectsIn(rect: (min: SIMD2<Float>, max: SIMD2<Float>)) -> [MapObject] {
        objects.filter { obj in
            obj.position.x >= rect.min.x &&
            obj.position.x <= rect.max.x &&
            obj.position.y >= rect.min.y &&
            obj.position.y <= rect.max.y
        }
    }
    
    public func objectsOfType(_ type: MapObjectType) -> [MapObject] {
        objects.filter { $0.type == type }
    }
    
    public var objectCount: Int {
        objects.count
    }
    
    public var statistics: [MapObjectType: Int] {
        var stats: [MapObjectType: Int] = [:]
        for obj in objects {
            stats[obj.type, default: 0] += 1
        }
        return stats
    }
}
