#include <metal_stdlib>
using namespace metal;

struct FlowDirParams {
    uint width;
    uint height;
    float seaLevel;
};

struct FlowAccumParams {
    uint width;
    uint height;
};

struct RiverScoreParams {
    uint width;
    uint height;
    float seaLevel;
    float maxAccum;
};

struct GPURiverSource {
    uint x;
    uint y;
};

struct TraceRiverParams {
    uint width;
    uint height;
    uint riverCount;
    float riverStartWidth;
    float riverWidthGrowth;
    float riverMaxWidth;
    float meandering;
    float seaLevel;
    uint baseSeed;
};

struct WidenParams {
    uint width;
    uint height;
    float maxFlow;
};

struct SmoothRiverParams {
    uint width;
    uint height;
};

struct DeltaParams {
    uint width;
    uint height;
    float seaLevel;
    uint deltaSize;
};

struct DepressionParams {
    uint width;
    uint height;
    float seaLevel;
    float lakeThreshold;
};

struct LakeFloodParams {
    uint width;
    uint height;
};

struct LakeFinalizeParams {
    uint width;
    uint height;
    uint lakeMinSize;
};

struct FlowXYParams {
    uint width;
    uint height;
};

constant int2 waterNeighborOffsets[8] = {
    int2(0, -1), int2(1, -1), int2(1, 0), int2(1, 1),
    int2(0, 1), int2(-1, 1), int2(-1, 0), int2(-1, -1)
};

constant float waterNeighborDists[8] = {
    1.0, 1.41421356, 1.0, 1.41421356,
    1.0, 1.41421356, 1.0, 1.41421356
};

static uint waterPcgHash(uint input) {
    uint state = input * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

static float waterRandomFloat(thread uint& state) {
    state = waterPcgHash(state);
    return float(state) / 4294967295.0;
}

kernel void computeFlowDirections(
    device const float* heightmap [[buffer(0)]],
    device int* directions [[buffer(1)]],
    constant FlowDirParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    float h = heightmap[idx];

    if (h < params.seaLevel) {
        directions[idx] = -1;
        return;
    }

    int bestDir = -1;
    float bestSlope = 0;

    for (int d = 0; d < 8; d++) {
        int nx = int(gid.x) + waterNeighborOffsets[d].x;
        int ny = int(gid.y) + waterNeighborOffsets[d].y;

        if (nx >= 0 && nx < int(params.width) && ny >= 0 && ny < int(params.height)) {
            uint nidx = uint(ny) * params.width + uint(nx);
            float slope = (h - heightmap[nidx]) / waterNeighborDists[d];

            if (slope > bestSlope) {
                bestSlope = slope;
                bestDir = d;
            }
        }
    }

    directions[idx] = bestDir;
}

kernel void relaxFlowAccumulation(
    device const int* directions [[buffer(0)]],
    device const float* accumIn [[buffer(1)]],
    device float* accumOut [[buffer(2)]],
    device atomic_uint* changedCount [[buffer(3)]],
    constant FlowAccumParams& params [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    float incoming = 1.0;

    for (int d = 0; d < 8; d++) {
        int nx = int(gid.x) + waterNeighborOffsets[d].x;
        int ny = int(gid.y) + waterNeighborOffsets[d].y;

        if (nx >= 0 && nx < int(params.width) && ny >= 0 && ny < int(params.height)) {
            uint nidx = uint(ny) * params.width + uint(nx);
            if (directions[nidx] == (d + 4) % 8) {
                incoming += accumIn[nidx];
            }
        }
    }

    accumOut[idx] = incoming;

    if (abs(incoming - accumIn[idx]) > 0.5) {
        atomic_fetch_add_explicit(changedCount, 1, memory_order_relaxed);
    }
}

kernel void computeRiverScores(
    device const float* heightmap [[buffer(0)]],
    device const float* accumulation [[buffer(1)]],
    device float* scores [[buffer(2)]],
    constant RiverScoreParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    float h = heightmap[idx];
    float minHeight = params.seaLevel + 0.15;

    if (h < minHeight || h > 0.9) {
        scores[idx] = 0;
        return;
    }

    float heightScore = (h - params.seaLevel) / (1.0 - params.seaLevel);
    float flowScore = min(accumulation[idx] / 100.0, 1.0);
    scores[idx] = heightScore * 0.7 + flowScore * 0.3;
}

kernel void traceRiversKernel(
    device const int* directions [[buffer(0)]],
    device const float* heightmap [[buffer(1)]],
    device float* riverMask [[buffer(2)]],
    device float* waterDepth [[buffer(3)]],
    device const GPURiverSource* sources [[buffer(4)]],
    constant TraceRiverParams& params [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= params.riverCount) {
        return;
    }

    int x = int(sources[gid].x);
    int y = int(sources[gid].y);
    float riverWidth = params.riverStartWidth;
    uint rngState = waterPcgHash(params.baseSeed ^ waterPcgHash(gid + 1));

    uint maxSteps = params.width + params.height;
    int prevX = -1;
    int prevY = -1;

    for (uint step = 0; step < maxSteps; step++) {
        if (x < 0 || x >= int(params.width) || y < 0 || y >= int(params.height)) {
            break;
        }

        uint idx = uint(y) * params.width + uint(x);

        if (heightmap[idx] < params.seaLevel) {
            break;
        }

        if (x == prevX && y == prevY) {
            break;
        }

        riverMask[idx] = 1.0;
        waterDepth[idx] = riverWidth;
        riverWidth = min(riverWidth + params.riverWidthGrowth, params.riverMaxWidth);

        prevX = x;
        prevY = y;

        int dir = directions[idx];

        if (dir < 0) {
            bool found = false;
            for (int d = 0; d < 8; d++) {
                int nx = x + waterNeighborOffsets[d].x;
                int ny = y + waterNeighborOffsets[d].y;
                if (nx >= 0 && nx < int(params.width) && ny >= 0 && ny < int(params.height)) {
                    if (heightmap[uint(ny) * params.width + uint(nx)] < heightmap[idx]) {
                        x = nx;
                        y = ny;
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                break;
            }
        } else {
            x += waterNeighborOffsets[dir].x;
            y += waterNeighborOffsets[dir].y;
        }

        if (waterRandomFloat(rngState) < params.meandering && dir >= 0) {
            int perpDx = 0;
            int perpDy = 0;
            if (dir == 0 || dir == 4) {
                perpDx = waterRandomFloat(rngState) > 0.5 ? 1 : -1;
            } else if (dir == 2 || dir == 6) {
                perpDy = waterRandomFloat(rngState) > 0.5 ? 1 : -1;
            }
            int mx = x + perpDx;
            int my = y + perpDy;
            if (mx >= 0 && mx < int(params.width) && my >= 0 && my < int(params.height)) {
                uint midx = uint(my) * params.width + uint(mx);
                riverMask[midx] = max(riverMask[midx], 0.5f);
            }
        }
    }
}

kernel void widenRiversKernel(
    device const float* riverMask [[buffer(0)]],
    device const float* flowAccum [[buffer(1)]],
    device float* output [[buffer(2)]],
    constant WidenParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    float maxVal = riverMask[idx];

    for (int dy = -3; dy <= 3; dy++) {
        for (int dx = -3; dx <= 3; dx++) {
            int nx = int(gid.x) + dx;
            int ny = int(gid.y) + dy;

            if (nx >= 0 && nx < int(params.width) && ny >= 0 && ny < int(params.height)) {
                uint nidx = uint(ny) * params.width + uint(nx);

                if (riverMask[nidx] > 0) {
                    float flowRatio = flowAccum[nidx] / params.maxFlow;
                    int extraWidth = int(flowRatio * 3.0);
                    float dist = sqrt(float(dx * dx + dy * dy));

                    if (dist <= float(extraWidth)) {
                        float strength = 1.0 - dist / float(extraWidth + 1);
                        maxVal = max(maxVal, riverMask[nidx] * strength);
                    }
                }
            }
        }
    }

    output[idx] = maxVal;
}

kernel void smoothRiversKernel(
    device const float* riverMask [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant SmoothRiverParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;

    if (gid.x < 1 || gid.x >= params.width - 1 || gid.y < 1 || gid.y >= params.height - 1) {
        output[idx] = riverMask[idx];
        return;
    }

    if (riverMask[idx] <= 0) {
        output[idx] = 0;
        return;
    }

    float sum = riverMask[idx] * 4.0;
    float count = 4.0;

    for (int d = 0; d < 8; d++) {
        int nx = int(gid.x) + waterNeighborOffsets[d].x;
        int ny = int(gid.y) + waterNeighborOffsets[d].y;
        uint nidx = uint(ny) * params.width + uint(nx);

        float w = (abs(waterNeighborOffsets[d].x) + abs(waterNeighborOffsets[d].y) == 1)
            ? 2.0 : 1.0;
        sum += riverMask[nidx] * w;
        count += w;
    }

    output[idx] = sum / count;
}

kernel void riverDeltasKernel(
    device const float* heightmap [[buffer(0)]],
    device float* riverMask [[buffer(1)]],
    constant DeltaParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    if (heightmap[idx] >= params.seaLevel + 0.02) {
        return;
    }

    int ds = int(params.deltaSize);

    for (int dy = -ds; dy <= ds; dy++) {
        for (int dx = -ds; dx <= ds; dx++) {
            int nx = int(gid.x) + dx;
            int ny = int(gid.y) + dy;
            if (nx < 0 || nx >= int(params.width) || ny < 0 || ny >= int(params.height)) {
                continue;
            }

            uint nidx = uint(ny) * params.width + uint(nx);
            if (riverMask[nidx] <= 0.5 || heightmap[nidx] < params.seaLevel) {
                continue;
            }

            bool isMouth = false;
            for (int cd = 0; cd < 8; cd += 2) {
                int mx = nx + waterNeighborOffsets[cd].x;
                int my = ny + waterNeighborOffsets[cd].y;
                if (mx >= 0 && mx < int(params.width) && my >= 0 && my < int(params.height)) {
                    if (heightmap[uint(my) * params.width + uint(mx)] < params.seaLevel) {
                        isMouth = true;
                        break;
                    }
                }
            }

            if (isMouth) {
                float dist = sqrt(float(dx * dx + dy * dy));
                if (dist <= float(ds)) {
                    float strength = 1.0 - dist / float(ds + 1);
                    riverMask[idx] = max(riverMask[idx], strength * 0.6);
                    return;
                }
            }
        }
    }
}

kernel void detectDepressions(
    device const float* heightmap [[buffer(0)]],
    device const float* riverMask [[buffer(1)]],
    device uint* lakeIds [[buffer(2)]],
    device float* waterLevels [[buffer(3)]],
    device atomic_uint* depressionCount [[buffer(4)]],
    constant DepressionParams& params [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x < 1 || gid.x >= params.width - 1 || gid.y < 1 || gid.y >= params.height - 1) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    float h = heightmap[idx];

    if (h < params.seaLevel || riverMask[idx] > 0.5) {
        return;
    }

    bool isMinimum = true;
    float minNeighbor = 1e10;

    for (int d = 0; d < 8; d++) {
        int nx = int(gid.x) + waterNeighborOffsets[d].x;
        int ny = int(gid.y) + waterNeighborOffsets[d].y;
        uint nidx = uint(ny) * params.width + uint(nx);
        float nh = heightmap[nidx];

        if (nh < h) {
            isMinimum = false;
            break;
        }
        minNeighbor = min(minNeighbor, nh);
    }

    if (!isMinimum || minNeighbor <= h) {
        return;
    }

    float depth = minNeighbor - h;
    if (depth <= params.lakeThreshold * 0.1) {
        return;
    }

    uint id = atomic_fetch_add_explicit(depressionCount, 1, memory_order_relaxed) + 1;
    lakeIds[idx] = id;
    waterLevels[idx] = h + depth * 0.5;
}

kernel void lakeFloodFillPass(
    device const float* heightmap [[buffer(0)]],
    device const uint* lakeIdsIn [[buffer(1)]],
    device uint* lakeIdsOut [[buffer(2)]],
    device const float* waterLevelsIn [[buffer(3)]],
    device float* waterLevelsOut [[buffer(4)]],
    device atomic_uint* changedCount [[buffer(5)]],
    constant LakeFloodParams& params [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;

    lakeIdsOut[idx] = lakeIdsIn[idx];
    waterLevelsOut[idx] = waterLevelsIn[idx];

    if (lakeIdsIn[idx] > 0) {
        return;
    }

    for (int d = 0; d < 4; d++) {
        int nx = int(gid.x) + waterNeighborOffsets[d * 2].x;
        int ny = int(gid.y) + waterNeighborOffsets[d * 2].y;

        if (nx >= 0 && nx < int(params.width) && ny >= 0 && ny < int(params.height)) {
            uint nidx = uint(ny) * params.width + uint(nx);

            if (lakeIdsIn[nidx] > 0 && heightmap[idx] <= waterLevelsIn[nidx]) {
                lakeIdsOut[idx] = lakeIdsIn[nidx];
                waterLevelsOut[idx] = waterLevelsIn[nidx];
                atomic_fetch_add_explicit(changedCount, 1, memory_order_relaxed);
                return;
            }
        }
    }
}

kernel void countLakePixels(
    device const uint* lakeIds [[buffer(0)]],
    device atomic_uint* lakeSizes [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    uint id = lakeIds[gid];
    if (id > 0) {
        atomic_fetch_add_explicit(&lakeSizes[id], 1, memory_order_relaxed);
    }
}

kernel void finalizeLakes(
    device const uint* lakeIds [[buffer(0)]],
    device const float* waterLevels [[buffer(1)]],
    device const float* heightmap [[buffer(2)]],
    device const uint* lakeSizes [[buffer(3)]],
    device float* lakeMask [[buffer(4)]],
    device float* waterDepth [[buffer(5)]],
    constant LakeFinalizeParams& params [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    uint id = lakeIds[idx];

    if (id > 0 && lakeSizes[id] >= params.lakeMinSize) {
        lakeMask[idx] = 1.0;
        waterDepth[idx] = max(waterDepth[idx], waterLevels[idx] - heightmap[idx]);
    }
}

kernel void assignFlowXY(
    device const int* directions [[buffer(0)]],
    device float* flowDirX [[buffer(1)]],
    device float* flowDirY [[buffer(2)]],
    constant FlowXYParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    int dir = directions[idx];

    if (dir >= 0 && dir < 8) {
        flowDirX[idx] = float(waterNeighborOffsets[dir].x);
        flowDirY[idx] = float(waterNeighborOffsets[dir].y);
    } else {
        flowDirX[idx] = 0;
        flowDirY[idx] = 0;
    }
}
