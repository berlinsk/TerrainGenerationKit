import Foundation

public enum GenerationStage: String, Sendable {
    case idle = "Idle"
    case heightmap = "Generating Heightmap"
    case erosion = "Simulating Erosion"
    case climate = "Calculating Climate"
    case biomes = "Assigning Biomes"
    case water = "Creating Rivers & Lakes"
    case cities = "Building Cities"
    case roads = "Generating Roads"
    case objects = "Placing Objects"
    case postProcessing = "Post Processing"
    case rendering = "Preparing Render"
    case complete = "Complete"
}
