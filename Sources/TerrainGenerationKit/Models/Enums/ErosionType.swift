import Foundation

public enum ErosionType: String, CaseIterable, Codable, Sendable {
    case none = "None"
    case thermal = "Thermal"
    case hydraulic = "Hydraulic"
    case combined = "Combined"
}
