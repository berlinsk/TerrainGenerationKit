import CoreGraphics

public protocol MapTextureGeneratorProtocol: Sendable {
    func generateTexture(from mapData: MapData, mode: MapRenderMode) -> CGImage?
}
