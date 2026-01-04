#include <metal_stdlib>
using namespace metal;

uint pcg_hash(uint input) {
    uint state = input * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float random_float(uint seed) {
    return float(pcg_hash(seed)) / float(0xFFFFFFFFu);
}

float2 random_float2(uint seed) {
    return float2(
        random_float(seed),
        random_float(seed + 1u)
    );
}

struct PoissonParams {
    uint width;
    uint height;
    float minDistance;
    float cellSize;
    uint gridWidth;
    uint gridHeight;
    uint seed;
    uint maxAttempts;
};

kernel void poissonDiskSample(
    device float2* candidates [[buffer(0)]],
    device atomic_uint* candidateCount [[buffer(1)]],
    device int* grid [[buffer(2)]],
    constant PoissonParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint x = gid.x;
    uint y = gid.y;
    
    if (x >= params.gridWidth || y >= params.gridHeight) {
        return;
    }
    
    uint cellSeed = params.seed + y * params.gridWidth + x;
    
    float2 cellOrigin = float2(float(x), float(y)) * params.cellSize;
    float2 jitter = random_float2(cellSeed) * params.cellSize;
    float2 point = cellOrigin + jitter;
    
    if (point.x < 0 || point.x >= float(params.width) ||
        point.y < 0 || point.y >= float(params.height)) {
        return;
    }
    
    int cellX = int(point.x / params.cellSize);
    int cellY = int(point.y / params.cellSize);
    
    bool valid = true;
    float minDistSq = params.minDistance * params.minDistance;
    
    for (int dy = -2; dy <= 2 && valid; dy++) {
        for (int dx = -2; dx <= 2 && valid; dx++) {
            int nx = cellX + dx;
            int ny = cellY + dy;
            
            if (nx < 0 || nx >= int(params.gridWidth) ||
                ny < 0 || ny >= int(params.gridHeight)) {
                continue;
            }
            
            int neighborIdx = ny * int(params.gridWidth) + nx;
            int neighborPointIdx = grid[neighborIdx];
            
            if (neighborPointIdx >= 0) {
                uint nSeed = params.seed + uint(ny) * params.gridWidth + uint(nx);
                float2 nCellOrigin = float2(float(nx), float(ny)) * params.cellSize;
                float2 nJitter = random_float2(nSeed) * params.cellSize;
                float2 neighborPoint = nCellOrigin + nJitter;
                
                float distSq = length_squared(point - neighborPoint);
                if (distSq < minDistSq && !(dx == 0 && dy == 0)) {
                    valid = false;
                }
            }
        }
    }
    
    if (valid) {
        uint idx = atomic_fetch_add_explicit(candidateCount, 1, memory_order_relaxed);
        if (idx < params.width * params.height / 4) {
            candidates[idx] = point;
            grid[cellY * int(params.gridWidth) + cellX] = int(idx);
        }
    }
}

struct ObjectPlacementParams {
    uint width;
    uint height;
    float seaLevel;
    float treeDensity;
    float rockDensity;
    float vegetationDensity;
    float structureDensity;
    uint seed;
};

struct PlacedObject {
    float2 position;
    float height;
    float scale;
    float rotation;
    uint type;
    uint variation;
    uint _padding1;
    uint _padding2;
};

bool isCompatible(uint objectType, uint biome, float height, float slope) {
    if (biome <= 4) {
        return false;
    }
    
    switch (objectType) {
        case 0:
            return (biome == 11 || biome == 12 || biome == 13) && height > 0.4 && height < 0.85;
        case 1:
            return (biome == 6 || biome == 7) && height > 0.35 && height < 0.7;
        case 2:
            return (biome == 5 || biome == 10) && height > 0.35 && height < 0.45;
        case 3:
            return biome == 9 && height > 0.35 && height < 0.6;
        case 4:
            return (biome >= 5 && biome <= 8) && height > 0.35 && height < 0.75;
        case 5:
            return (biome == 6 || biome == 7 || biome == 10) && height > 0.35 && height < 0.65;
        case 6:
            return (biome >= 5 && biome <= 12) && height > 0.35 && height < 0.7;
        case 7:
            return height > 0.5 && height < 0.95 && slope > 0.1;
        case 8:
            return (biome == 14 || biome == 15) && height > 0.6;
        default:
            return false;
    }
}

float getDensityForObjectType(uint objType, constant ObjectPlacementParams& params) {
    switch (objType) {
        case 0:
        case 1:
        case 2:
            return params.treeDensity * 0.15;
        case 3:
            return params.vegetationDensity * 0.05;
        case 4:
            return params.vegetationDensity * 0.25;
        case 5:
            return params.vegetationDensity * 0.3;
        case 6:
            return params.vegetationDensity * 0.5;
        case 7:
            return params.rockDensity * 0.08;
        case 8:
            return params.rockDensity * 0.03;
        default:
            return 0.01;
    }
}

kernel void placeObjects(
    device const float2* candidates [[buffer(0)]],
    device const uint& candidateCount [[buffer(1)]],
    device const float* heightmap [[buffer(2)]],
    device const uchar* biomeMap [[buffer(3)]],
    device PlacedObject* objects [[buffer(4)]],
    device atomic_uint* objectCount [[buffer(5)]],
    constant ObjectPlacementParams& params [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= candidateCount) {
        return;
    }
    
    float2 point = candidates[gid];
    uint x = uint(point.x);
    uint y = uint(point.y);
    
    if (x >= params.width || y >= params.height) {
        return;
    }
    
    uint idx = y * params.width + x;
    float height = heightmap[idx];
    uint biome = uint(biomeMap[idx]);
    
    if (height < params.seaLevel || biome <= 4) {
        return;
    }
    
    float slope = 0.0;
    if (x > 0 && x < params.width - 1 && y > 0 && y < params.height - 1) {
        float hL = heightmap[idx - 1];
        float hR = heightmap[idx + 1];
        float hU = heightmap[idx - params.width];
        float hD = heightmap[idx + params.width];
        slope = max(abs(hR - hL), abs(hD - hU)) * 2.0;
    }
    
    uint pointSeed = params.seed + gid * 7919u;
    
    for (uint objType = 0; objType < 9; objType++) {
        if (!isCompatible(objType, biome, height, slope)) {
            continue;
        }
        
        float density = getDensityForObjectType(objType, params);
        float roll = random_float(pointSeed + objType * 1000u);
        
        if (roll < density) {
            uint outIdx = atomic_fetch_add_explicit(objectCount, 1, memory_order_relaxed);
            
            if (outIdx < params.width * params.height / 16) {
                PlacedObject obj;
                obj.position = point;
                obj.height = height;
                obj.scale = 0.7 + random_float(pointSeed + 100u) * 0.6;
                obj.rotation = random_float(pointSeed + 200u) * 6.28318;
                obj.type = objType;
                obj.variation = pcg_hash(pointSeed + 300u) % 4u;
                objects[outIdx] = obj;
            }
            break;
        }
    }
}

struct JFAParams {
    uint width;
    uint height;
    int step;
};

kernel void jumpFloodInit(
    device const float* roadMask [[buffer(0)]],
    device int2* seedBuffer [[buffer(1)]],
    constant JFAParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }
    
    uint idx = gid.y * params.width + gid.x;
    
    if (roadMask[idx] > 0.5) {
        seedBuffer[idx] = int2(int(gid.x), int(gid.y));
    } else {
        seedBuffer[idx] = int2(-1, -1);
    }
}

kernel void jumpFloodStep(
    device int2* seedBufferIn [[buffer(0)]],
    device int2* seedBufferOut [[buffer(1)]],
    constant JFAParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }
    
    uint idx = gid.y * params.width + gid.x;
    int2 bestSeed = seedBufferIn[idx];
    float bestDist = 1e10;
    
    if (bestSeed.x >= 0) {
        float dx = float(gid.x) - float(bestSeed.x);
        float dy = float(gid.y) - float(bestSeed.y);
        bestDist = dx * dx + dy * dy;
    }
    
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int nx = int(gid.x) + dx * params.step;
            int ny = int(gid.y) + dy * params.step;
            
            if (nx < 0 || nx >= int(params.width) ||
                ny < 0 || ny >= int(params.height)) {
                continue;
            }
            
            uint nidx = uint(ny) * params.width + uint(nx);
            int2 neighborSeed = seedBufferIn[nidx];
            
            if (neighborSeed.x >= 0) {
                float ndx = float(gid.x) - float(neighborSeed.x);
                float ndy = float(gid.y) - float(neighborSeed.y);
                float dist = ndx * ndx + ndy * ndy;
                
                if (dist < bestDist) {
                    bestDist = dist;
                    bestSeed = neighborSeed;
                }
            }
        }
    }
    
    seedBufferOut[idx] = bestSeed;
}

kernel void jumpFloodFinalize(
    device const int2* seedBuffer [[buffer(0)]],
    device float* sdfBuffer [[buffer(1)]],
    constant JFAParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }
    
    uint idx = gid.y * params.width + gid.x;
    int2 seed = seedBuffer[idx];
    
    if (seed.x >= 0) {
        float dx = float(gid.x) - float(seed.x);
        float dy = float(gid.y) - float(seed.y);
        sdfBuffer[idx] = sqrt(dx * dx + dy * dy);
    } else {
        sdfBuffer[idx] = 1000.0;
    }
}
