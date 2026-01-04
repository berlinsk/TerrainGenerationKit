import Foundation

public enum BuildingType: Int, Codable, CaseIterable, Sendable {
    case residential = 0
    case commercial = 1
    case industrial = 2
    case civic = 3
    case military = 4
    case market = 5
}
