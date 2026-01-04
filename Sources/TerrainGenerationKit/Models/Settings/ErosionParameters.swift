import Foundation

public struct ErosionParameters: Codable, Sendable, Equatable {
    
    public var type: ErosionType
    public var iterations: Int
    public var erosionStrength: Float
    public var depositionRate: Float
    public var evaporationRate: Float
    public var sedimentCapacity: Float
    public var thermalTalusAngle: Float
    public var gravity: Float
    public var inertia: Float
    public var minSlope: Float
    public var dropletLifetime: Int
    
    public init(
        type: ErosionType = .hydraulic,
        iterations: Int = 50000,
        erosionStrength: Float = 0.3,
        depositionRate: Float = 0.3,
        evaporationRate: Float = 0.02,
        sedimentCapacity: Float = 4.0,
        thermalTalusAngle: Float = 0.6,
        gravity: Float = 4.0,
        inertia: Float = 0.05,
        minSlope: Float = 0.01,
        dropletLifetime: Int = 30
    ) {
        self.type = type
        self.iterations = iterations
        self.erosionStrength = erosionStrength
        self.depositionRate = depositionRate
        self.evaporationRate = evaporationRate
        self.sedimentCapacity = sedimentCapacity
        self.thermalTalusAngle = thermalTalusAngle
        self.gravity = gravity
        self.inertia = inertia
        self.minSlope = minSlope
        self.dropletLifetime = dropletLifetime
    }
    
    public static let `default` = ErosionParameters()
    
    public static let none = ErosionParameters(type: .none, iterations: 0)
}
