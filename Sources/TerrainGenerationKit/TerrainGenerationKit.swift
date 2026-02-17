import Foundation
import simd

public enum TerrainGenerationKit {
    public static let version = "1.0.0"
    
    public static func createGenerator() -> MapGenerator {
        return MapGenerator()
    }

    public static func createTextureGenerator() -> any MapTextureGeneratorProtocol {
        return MapTextureGenerator()
    }
}
