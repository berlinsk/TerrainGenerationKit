import Foundation

public enum GradientMaskType: Sendable {
    case radial(falloff: Float)
    case horizontal(falloff: Float)
    case vertical(falloff: Float)
    case island(coastWidth: Float)
}
