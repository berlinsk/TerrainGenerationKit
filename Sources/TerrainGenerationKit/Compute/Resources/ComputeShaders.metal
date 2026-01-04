#include <metal_stdlib>
using namespace metal;

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
