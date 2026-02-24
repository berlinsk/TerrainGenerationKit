#include <metal_stdlib>
using namespace metal;

struct BiomeClassifyParams {
    uint width;
    uint height;
    float seaLevel;
    float snowLevel;
    float beachWidth;
    float desertThreshold;
    uint enabledBitmask;
};

struct BiomeSmoothParams {
    uint width;
    uint height;
};

constant int BIOME_DEEP_OCEAN     = 0;
constant int BIOME_OCEAN          = 1;
constant int BIOME_SHALLOW_WATER  = 2;
constant int BIOME_BEACH          = 3;
constant int BIOME_DESERT         = 4;
constant int BIOME_SAVANNA        = 5;
constant int BIOME_GRASSLAND      = 6;
constant int BIOME_FOREST         = 7;
constant int BIOME_RAINFOREST     = 8;
constant int BIOME_TAIGA          = 9;
constant int BIOME_TUNDRA         = 10;
constant int BIOME_SNOW           = 11;
constant int BIOME_MOUNTAIN       = 12;
constant int BIOME_SNOWY_MOUNTAIN = 13;
constant int BIOME_MARSH          = 14;
constant int BIOME_RIVER          = 15;
constant int BIOME_LAKE           = 16;

static bool biomeIsWater(int b) {
    return b == BIOME_DEEP_OCEAN || b == BIOME_OCEAN ||
           b == BIOME_SHALLOW_WATER || b == BIOME_RIVER || b == BIOME_LAKE;
}

static bool biomeEnabled(int b, uint mask) {
    return (mask >> uint(b)) & 1u;
}

static int classifyBiome(
    float h, float temp, float humidity,
    bool isRiver, bool isLake,
    float seaLevel, float snowLevel,
    float beachWidth, float desertThreshold
) {
    if (isRiver) return BIOME_RIVER;
    if (isLake) return BIOME_LAKE;

    if (h < seaLevel - 0.15) return BIOME_DEEP_OCEAN;
    if (h < seaLevel - 0.05) return BIOME_OCEAN;
    if (h < seaLevel) return BIOME_SHALLOW_WATER;
    if (h < seaLevel + beachWidth) return BIOME_BEACH;

    if (h > snowLevel) {
        return temp < 0.3 ? BIOME_SNOWY_MOUNTAIN : BIOME_MOUNTAIN;
    }
    if (h > snowLevel - 0.1) {
        return temp < 0.2 ? BIOME_SNOWY_MOUNTAIN : BIOME_MOUNTAIN;
    }

    if (temp < 0.15) return BIOME_SNOW;
    if (temp < 0.25) return humidity > 0.4 ? BIOME_TUNDRA : BIOME_SNOW;
    if (temp < 0.4) return humidity > 0.5 ? BIOME_TAIGA : BIOME_TUNDRA;

    if (humidity > 0.8 && h < seaLevel + 0.1) return BIOME_MARSH;

    if (temp < 0.65) {
        if (humidity < 0.3) return BIOME_GRASSLAND;
        if (humidity < 0.6) return BIOME_FOREST;
        return BIOME_RAINFOREST;
    }

    if (humidity < desertThreshold) return BIOME_DESERT;
    if (humidity < 0.5) return BIOME_SAVANNA;
    if (humidity < 0.7) return BIOME_GRASSLAND;
    return BIOME_RAINFOREST;
}

constant int biomeAlternatives[17][3] = {
    { BIOME_OCEAN, BIOME_SHALLOW_WATER, BIOME_LAKE },
    { BIOME_SHALLOW_WATER, BIOME_DEEP_OCEAN, BIOME_LAKE },
    { BIOME_OCEAN, BIOME_LAKE, BIOME_BEACH },
    { BIOME_DESERT, BIOME_SAVANNA, BIOME_GRASSLAND },
    { BIOME_SAVANNA, BIOME_BEACH, BIOME_TUNDRA },
    { BIOME_GRASSLAND, BIOME_DESERT, BIOME_BEACH },
    { BIOME_SAVANNA, BIOME_FOREST, BIOME_TUNDRA },
    { BIOME_TAIGA, BIOME_RAINFOREST, BIOME_GRASSLAND },
    { BIOME_FOREST, BIOME_MARSH, BIOME_GRASSLAND },
    { BIOME_FOREST, BIOME_TUNDRA, BIOME_SNOW },
    { BIOME_TAIGA, BIOME_SNOW, BIOME_GRASSLAND },
    { BIOME_TUNDRA, BIOME_SNOWY_MOUNTAIN, BIOME_TAIGA },
    { BIOME_SNOWY_MOUNTAIN, BIOME_TUNDRA, BIOME_GRASSLAND },
    { BIOME_MOUNTAIN, BIOME_SNOW, BIOME_TUNDRA },
    { BIOME_LAKE, BIOME_RAINFOREST, BIOME_GRASSLAND },
    { BIOME_LAKE, BIOME_SHALLOW_WATER, BIOME_MARSH },
    { BIOME_SHALLOW_WATER, BIOME_RIVER, BIOME_OCEAN }
};

static int findAlternative(int biome, uint mask) {
    if (biome >= 0 && biome < 17) {
        for (int i = 0; i < 3; i++) {
            int alt = biomeAlternatives[biome][i];
            if (biomeEnabled(alt, mask)) return alt;
        }
    }
    for (int b = 0; b < 17; b++) {
        if (biomeEnabled(b, mask)) return b;
    }
    return BIOME_GRASSLAND;
}

kernel void classifyBiomesKernel(
    device const float* heightmap [[buffer(0)]],
    device const float* temperatureMap [[buffer(1)]],
    device const float* humidityMap [[buffer(2)]],
    device const float* riverMask [[buffer(3)]],
    device const float* lakeMask [[buffer(4)]],
    device uchar* biomeMap [[buffer(5)]],
    constant BiomeClassifyParams& params [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) return;

    uint idx = gid.y * params.width + gid.x;
    float h = heightmap[idx];
    float temp = temperatureMap[idx];
    float humidity = humidityMap[idx];
    bool isRiver = riverMask[idx] > 0.5;
    bool isLake = lakeMask[idx] > 0.5;

    int biome = classifyBiome(
        h, temp, humidity, isRiver, isLake,
        params.seaLevel, params.snowLevel,
        params.beachWidth, params.desertThreshold
    );

    if (!biomeEnabled(biome, params.enabledBitmask)) {
        biome = findAlternative(biome, params.enabledBitmask);
    }

    biomeMap[idx] = uchar(biome);
}

kernel void smoothBiomeTransitionsKernel(
    device const uchar* biomeIn [[buffer(0)]],
    device uchar* biomeOut [[buffer(1)]],
    constant BiomeSmoothParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) return;

    uint idx = gid.y * params.width + gid.x;

    if (gid.x < 1 || gid.x >= params.width - 1 || gid.y < 1 || gid.y >= params.height - 1) {
        biomeOut[idx] = biomeIn[idx];
        return;
    }

    int current = int(biomeIn[idx]);
    if (biomeIsWater(current)) {
        biomeOut[idx] = biomeIn[idx];
        return;
    }

    int counts[17] = {};
    counts[current] = 2;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            uint nidx = (gid.y + uint(dy)) * params.width + (gid.x + uint(dx));
            int neighbor = int(biomeIn[nidx]);
            if (!biomeIsWater(neighbor)) {
                counts[neighbor]++;
            }
        }
    }

    int bestBiome = current;
    int bestCount = counts[current];

    for (int b = 0; b < 17; b++) {
        if (counts[b] > bestCount) {
            bestCount = counts[b];
            bestBiome = b;
        }
    }

    if (bestCount >= 5 && bestBiome != current) {
        biomeOut[idx] = uchar(bestBiome);
    } else {
        biomeOut[idx] = biomeIn[idx];
    }
}
