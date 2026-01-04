import Foundation
import simd

public struct Road: Codable, Identifiable, Sendable {
    
    public let id: UUID
    public var path: [SIMD2<Int>]
    public var fromCityId: UUID
    public var toCityId: UUID
    public var hasBridge: Bool
    
    public init(from: UUID, to: UUID, path: [SIMD2<Int>]) {
        self.id = UUID()
        self.fromCityId = from
        self.toCityId = to
        self.path = path
        self.hasBridge = false
    }
}
