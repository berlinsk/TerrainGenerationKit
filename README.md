# TerrainGenerationKit

Swift package for procedural terrain generation. Takes a settings struct, returns a fully populated map with heightmap, biomes, water, cities and objects

iOS 15+ - macOS 12+

<img width="1019" height="686" alt="biome" src="https://github.com/user-attachments/assets/55ec331b-9b57-4549-ab49-eb90a9f55993" />

---

## What it generates

- heightmap from fractal noise(simplex, perlin, ridged, worley) with up to 3 weighted layers
- 17 biome types per cell based on height, temperature and humidity
- hydraulic and thermal erosion
- river and lake network from flow simulation
- city and road network
- object scatter(trees, rocks, vegetation, structures)

All output is in a single `MapData` struct with flat arrays: `heightmap`, `biomeMap`, `temperatureMap`, `humidityMap`, `steepnessMap`, `waterData`, `cityNetwork`, `objectLayer`

---

## Installation

**Xcode**: File -> Add Package Dependencies -> paste the repo URL -> select version

**Package.swift**:

```swift
dependencies: [
    .package(url: "https://github.com/berlinsk/TerrainGenerationKit.git", from: "1.0.3")
],
targets: [
    .target(name: "!!!!fill in yourtarget!!!!", dependencies: ["TerrainGenerationKit"])
]
```

---

## Usage

### Generate a map

```swift
let generator = TerrainGenerationKit.createGenerator()

let map = try await generator.generate(settings: .continental) { progress in
    print(progress.stage, progress.progress)
}
```

### Settings

```swift
var settings = GenerationSettings()
settings.seed = 42
settings.width = 1024
settings.height = 1024
settings.biome.seaLevel = 0.4
settings.erosion.iterations = 80000
settings.water.riverCount = 8
settings.cities.cityCount = 12
```

Built-in presets: `.continental`, `.archipelago`, `.desert`, `.tundra`, `.volcanic`

---

## 2D rendering

Converts `MapData` to a `CGImage`. GPU path uses a Metal compute shader, falls back to CPU

```swift
let textureGenerator = TerrainGenerationKit.createTextureGenerator()
let image: CGImage? = textureGenerator.generateTexture(from: map, mode: .biome)
```
---

## 3D mesh

Builds a vertex/normal/uv/index mesh from the heightmap. Normals computed per-vertex from the heightmap gradient. GPU path via Metal, CPU fallback included

```swift
let meshGenerator = TerrainGenerationKit.createMeshGenerator()
let mesh = meshGenerator.generateMesh(from: map, settings: TerrainMeshSettings(
    heightScale: 50.0,
    resolution: .full  // .full, .half, .quarter
))
// mesh.vertices, mesh.normals, mesh.uvs, mesh.indices
```

`TerrainMeshData` is ready to pass into SceneKit, RealityKit or any renderer that accepts raw mesh data

<!-- screenshot: 3D biome view -->
<!-- screenshot: 3D composite view -->

---

## Demo

---

**biome**(2D/3D projection) - 17 biome types, shaded by height
<img width="689" height="686" alt="image" src="https://github.com/user-attachments/assets/9cb2beff-0373-4669-ba64-300de038edd9" />
<img width="1019" height="686" alt="biome" src="https://github.com/user-attachments/assets/55ec331b-9b57-4549-ab49-eb90a9f55993" />

**heightmap**(2D/3D projection) - normalized heightmap after noise, erosion and post-processing
<img width="689" height="686" alt="image" src="https://github.com/user-attachments/assets/8511953a-8f02-4797-a461-a65bbdf7ba9a" />
<img width="1019" height="686" alt="heightmap" src="https://github.com/user-attachments/assets/b2538a84-e1a4-461c-b79a-e546311f834a" />

**temperature**(2D/3D projection) - heatmap gradient from cold to hot
<img width="689" height="686" alt="image" src="https://github.com/user-attachments/assets/cc403852-545b-449f-b61f-cfe84e1d0a7e" />
<img width="1019" height="686" alt="temperature" src="https://github.com/user-attachments/assets/f5854b5e-4810-4cbf-b28a-5d9506bcf8c5" />

**humidity**(2D/3D projection) - humidity distribution across the map
<img width="689" height="686" alt="image" src="https://github.com/user-attachments/assets/681808ad-9332-482e-90d9-e83f9ea2df65" />
<img width="1019" height="686" alt="humidity" src="https://github.com/user-attachments/assets/3b0b4286-f708-4fab-a19d-d952722bd0b3" />

**water**(2D/3D projection) - rivers, lakes and ocean by seaLevel
<img width="689" height="686" alt="image" src="https://github.com/user-attachments/assets/b8fbd339-64fc-47a0-86f9-b74cebe36f4d" />
<img width="1019" height="686" alt="water" src="https://github.com/user-attachments/assets/e525765e-49e4-4743-9b7c-1803fcf25fd7" />

**waterDepth**(2D/3D projection) - water depth, distinguishes shallow and deep areas
<img width="689" height="686" alt="image" src="https://github.com/user-attachments/assets/2d537faa-8dd3-44ef-aec9-102d2121dc9d" />
<img width="1019" height="686" alt="waterDepth" src="https://github.com/user-attachments/assets/9df2700f-bd1e-4a35-ae45-25f5b6b8c5da" />

**flowDirection**(2D/3D projection) - flow vector field used to build the river network
<img width="689" height="686" alt="image" src="https://github.com/user-attachments/assets/88c85a66-e8da-4d30-873a-544b62388ca5" />
<img width="1019" height="686" alt="flowDirection" src="https://github.com/user-attachments/assets/216746f2-22e2-41f4-9a10-5f13b78a7efa" />

**cities**(2D/3D projection) - city zones, walls and road network
<img width="689" height="686" alt="image" src="https://github.com/user-attachments/assets/504a84ea-8d57-4834-8648-b7dd39ccac3a" />
<img width="1019" height="686" alt="cities" src="https://github.com/user-attachments/assets/1f8d35c6-5eaf-4b4f-a35e-976a13a8e80d" />

**composite**(2D/3D projection) - biomes + rivers + roads + cities combined
<img width="689" height="686" alt="image" src="https://github.com/user-attachments/assets/2b684d71-e4c6-4507-b9e1-ab08f9216edc" />
<img width="1019" height="686" alt="composite" src="https://github.com/user-attachments/assets/6c27f328-bb5b-400b-a11b-d0883f6dc209" />

---

## Changelog

### 1.0.3
Added `MapTextureGenerator` and `TerrainMeshGenerator` with Metal compute shaders and CPU fallbacks. Factory methods `createTextureGenerator()` and `createMeshGenerator()` added to `TerrainGenerationKit`

### 1.0.2
Fixed road pathfinding: roads now correctly reach city centers, blind branches from incomplete hierarchical paths removed

### 1.0.1
Fixed `steepnessMap` and `waterDepth` not being normalized to 0-1 range(values could exceed 1.0, breaking any rendering or logic that expects normalized input)

### 1.0.0
Initial release. Full generation pipeline: fractal noise(simplex, perlin, ridged, worley), biome classification, hydraulic and thermal erosion, water flow simulation with rivers and lakes, city and road generation, object scatter. GPU compute engine with JFA for road SDF and poisson disk sampling for object placement
