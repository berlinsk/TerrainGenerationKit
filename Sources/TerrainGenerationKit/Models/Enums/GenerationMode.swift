import Foundation

public enum GenerationMode: String, CaseIterable, Codable, Sendable {
    case continental = "Continental"
    case archipelago = "Archipelago"
    case pangaea = "Pangaea"
    case fractal = "Fractal Islands"
    case custom = "Custom"
}
