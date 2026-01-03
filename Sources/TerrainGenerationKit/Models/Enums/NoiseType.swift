import Foundation

public enum NoiseType: String, CaseIterable, Codable, Sendable {
    case perlin = "Perlin"
    case simplex = "Simplex"
    case openSimplex = "OpenSimplex"
    case ridged = "Ridged"
    case billow = "Billow"
    case voronoi = "Voronoi"
}
