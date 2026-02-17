import Foundation

public enum MapRenderMode: String, Sendable, CaseIterable {
    case biome
    case heightmap
    case temperature
    case humidity
    case water
    case waterDepth
    case flowDirection
    case cities
    case steepness
    case composite
}
