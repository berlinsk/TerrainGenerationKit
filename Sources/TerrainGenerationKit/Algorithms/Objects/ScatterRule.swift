import Foundation

public struct ScatterRule: Sendable {
    
    public let objectType: MapObjectType
    public let baseDensity: Float
    public let clusterProbability: Float
    public let clusterSize: ClosedRange<Int>
    public let scaleRange: ClosedRange<Float>
    public let slopeRange: ClosedRange<Float>
    public let heightRange: ClosedRange<Float>
    public let preferEdges: Bool
    
    public init(
        objectType: MapObjectType,
        baseDensity: Float,
        clusterProbability: Float,
        clusterSize: ClosedRange<Int>,
        scaleRange: ClosedRange<Float>,
        slopeRange: ClosedRange<Float>,
        heightRange: ClosedRange<Float>,
        preferEdges: Bool
    ) {
        self.objectType = objectType
        self.baseDensity = baseDensity
        self.clusterProbability = clusterProbability
        self.clusterSize = clusterSize
        self.scaleRange = scaleRange
        self.slopeRange = slopeRange
        self.heightRange = heightRange
        self.preferEdges = preferEdges
    }
    
    public static func forType(_ type: MapObjectType) -> ScatterRule {
        switch type {
        case .pine:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.15,
                clusterProbability: 0.7,
                clusterSize: 3...8,
                scaleRange: 0.7...1.3,
                slopeRange: 0...0.3,
                heightRange: 0.4...0.85,
                preferEdges: false
            )
        case .oak:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.12,
                clusterProbability: 0.5,
                clusterSize: 2...5,
                scaleRange: 0.8...1.4,
                slopeRange: 0...0.25,
                heightRange: 0.35...0.7,
                preferEdges: false
            )
        case .palm:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.08,
                clusterProbability: 0.3,
                clusterSize: 1...3,
                scaleRange: 0.9...1.2,
                slopeRange: 0...0.15,
                heightRange: 0.35...0.45,
                preferEdges: true
            )
        case .cactus:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.05,
                clusterProbability: 0.2,
                clusterSize: 1...3,
                scaleRange: 0.6...1.5,
                slopeRange: 0...0.2,
                heightRange: 0.35...0.6,
                preferEdges: false
            )
        case .bush:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.25,
                clusterProbability: 0.6,
                clusterSize: 3...10,
                scaleRange: 0.5...1.2,
                slopeRange: 0...0.35,
                heightRange: 0.35...0.75,
                preferEdges: true
            )
        case .flower:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.3,
                clusterProbability: 0.8,
                clusterSize: 5...15,
                scaleRange: 0.4...1.0,
                slopeRange: 0...0.25,
                heightRange: 0.35...0.65,
                preferEdges: false
            )
        case .grass:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.5,
                clusterProbability: 0.9,
                clusterSize: 10...30,
                scaleRange: 0.3...1.0,
                slopeRange: 0...0.4,
                heightRange: 0.35...0.7,
                preferEdges: false
            )
        case .rock:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.08,
                clusterProbability: 0.4,
                clusterSize: 2...5,
                scaleRange: 0.5...2.0,
                slopeRange: 0.1...0.8,
                heightRange: 0.5...0.95,
                preferEdges: false
            )
        case .boulder:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.03,
                clusterProbability: 0.2,
                clusterSize: 1...3,
                scaleRange: 0.8...2.5,
                slopeRange: 0.15...0.6,
                heightRange: 0.6...0.95,
                preferEdges: false
            )
        case .ruin:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.002,
                clusterProbability: 0.1,
                clusterSize: 1...2,
                scaleRange: 0.8...1.5,
                slopeRange: 0...0.2,
                heightRange: 0.4...0.65,
                preferEdges: false
            )
        case .tower:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.001,
                clusterProbability: 0,
                clusterSize: 1...1,
                scaleRange: 0.9...1.2,
                slopeRange: 0...0.15,
                heightRange: 0.5...0.8,
                preferEdges: false
            )
        case .village:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.0005,
                clusterProbability: 0,
                clusterSize: 1...1,
                scaleRange: 0.8...1.3,
                slopeRange: 0...0.1,
                heightRange: 0.38...0.55,
                preferEdges: false
            )
        case .crystal:
            return ScatterRule(
                objectType: type,
                baseDensity: 0.005,
                clusterProbability: 0.5,
                clusterSize: 2...5,
                scaleRange: 0.3...1.5,
                slopeRange: 0.2...0.7,
                heightRange: 0.7...0.95,
                preferEdges: false
            )
        }
    }
}
