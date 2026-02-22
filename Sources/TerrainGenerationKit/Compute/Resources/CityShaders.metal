#include <metal_stdlib>
using namespace metal;

struct DistanceInitParams {
    uint width;
    uint height;
    uint type;
    uint maxDistance;
    float seaLevel;
};

struct DistanceRelaxParams {
    uint width;
    uint height;
    uint maxDistance;
};

struct CostMapParams {
    uint width;
    uint height;
    float seaLevel;
};

struct DownsampleParams {
    uint fullWidth;
    uint fullHeight;
    uint coarseWidth;
    uint coarseHeight;
    uint scale;
};

struct BoundedPathParams {
    uint mapWidth;
    uint mapHeight;
    uint bboxMinX;
    uint bboxMinY;
    uint bboxWidth;
    uint bboxHeight;
    uint sourceX;
    uint sourceY;
    float roadDiscount;
};

constant int2 pathNeighborOffsets[8] = {
    int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1),
    int2(-1, -1), int2(1, -1), int2(-1, 1), int2(1, 1)
};

constant float pathNeighborDists[8] = {
    1.0, 1.0, 1.0, 1.0,
    1.414214, 1.414214, 1.414214, 1.414214
};

struct CityScoreParams {
    uint width;
    uint height;
    float seaLevel;
    float preferRivers;
    float preferCoast;
    float avoidMountains;
};

kernel void initDistanceMap(
    device const float* heightmap [[buffer(0)]],
    device const float* riverMask [[buffer(1)]],
    device int* distances [[buffer(2)]],
    constant DistanceInitParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }
    uint idx = gid.y * params.width + gid.x;

    bool isSeed;
    if (params.type == 0) {
        isSeed = riverMask[idx] > 0.5;
    } else {
        isSeed = heightmap[idx] < params.seaLevel;
    }

    if (isSeed) {
        distances[idx] = 0;
    } else {
        distances[idx] = int(params.maxDistance) + 1;
    }
}

kernel void wavefrontDistancePass(
    device const int* distIn [[buffer(0)]],
    device int* distOut [[buffer(1)]],
    device atomic_uint* changedCount [[buffer(2)]],
    constant DistanceRelaxParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }
    uint idx = gid.y * params.width + gid.x;

    int current = distIn[idx];
    int best = current;

    if (gid.x > 0) {
        best = min(best, distIn[idx - 1] + 1);
    }
    if (gid.x < params.width - 1) {
        best = min(best, distIn[idx + 1] + 1);
    }
    if (gid.y > 0) {
        best = min(best, distIn[idx - params.width] + 1);
    }
    if (gid.y < params.height - 1) {
        best = min(best, distIn[idx + params.width] + 1);
    }

    best = min(best, int(params.maxDistance) + 1);
    distOut[idx] = best;

    if (best < current) {
        atomic_fetch_add_explicit(changedCount, 1, memory_order_relaxed);
    }
}

kernel void buildTerrainCostKernel(
    device const float* heightmap [[buffer(0)]],
    device const uchar* biomeMap [[buffer(1)]],
    device const float* riverMask [[buffer(2)]],
    device const float* lakeMask [[buffer(3)]],
    device float* costMap [[buffer(4)]],
    constant CostMapParams& params [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }
    uint idx = gid.y * params.width + gid.x;

    float h = heightmap[idx];
    int biome = int(biomeMap[idx]);
    float cost = 1.0;

    if (riverMask[idx] > 0.5) {
        cost = 300.0;
    } else if (lakeMask[idx] > 0.5) {
        cost = 500.0;
    } else if (h < params.seaLevel) {
        float depth = params.seaLevel - h;
        if (depth > 0.15) {
            cost = 10000.0;
        } else {
            cost = 500.0;
        }
    } else {
        switch (biome) {
            case 0:
                cost = 10000.0;
                break;
            case 1:
                cost = 10000.0;
                break;
            case 2:
                cost = 500.0;
                break;
            case 3:
                cost = 2.0;
                break;
            case 4:
                cost = 4.0;
                break;
            case 5:
                cost = 1.5;
                break;
            case 6:
                cost = 1.0;
                break;
            case 7:
                cost = 8.0;
                break;
            case 8:
                cost = 12.0;
                break;
            case 9:
                cost = 9.6;
                break;
            case 10:
                cost = 8.4;
                break;
            case 11:
                cost = 12.0;
                break;
            case 12:
                cost = 80.0;
                break;
            case 13:
                cost = 120.0;
                break;
            case 14:
                cost = 25.0;
                break;
            case 15:
                cost = 500.0;
                break;
            case 16:
                cost = 500.0;
                break;
            default:
                cost = 1.0;
                break;
        }

        if (h > 0.7) {
            cost += (h - 0.7) * 120.0;
        } else if (h > 0.55) {
            cost += (h - 0.55) * 15.0;
        }

        float slope = 0;
        if (gid.x > 0) {
            slope = max(slope, abs(h - heightmap[idx - 1]));
        }
        if (gid.x < params.width - 1) {
            slope = max(slope, abs(h - heightmap[idx + 1]));
        }
        if (gid.y > 0) {
            slope = max(slope, abs(h - heightmap[idx - params.width]));
        }
        if (gid.y < params.height - 1) {
            slope = max(slope, abs(h - heightmap[idx + params.width]));
        }

        cost += slope * 20.0;
    }

    costMap[idx] = cost;
}

kernel void scoreCityLocationsKernel(
    device const float* heightmap [[buffer(0)]],
    device const uchar* biomeMap [[buffer(1)]],
    device const int* riverDistMap [[buffer(2)]],
    device const int* coastDistMap [[buffer(3)]],
    device float* scores [[buffer(4)]],
    constant CityScoreParams& params [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }
    uint idx = gid.y * params.width + gid.x;

    float h = heightmap[idx];
    int biome = int(biomeMap[idx]);

    bool isWater = (biome == 0 || biome == 1 || biome == 2 ||
                    biome == 15 || biome == 16);
    if (isWater || h < params.seaLevel || h > 0.72) {
        scores[idx] = 0;
        return;
    }

    float score = 0.5;

    float totalDiff = 0;
    if (gid.x >= 2 && gid.x < params.width - 2 &&
        gid.y >= 2 && gid.y < params.height - 2) {
        totalDiff += abs(heightmap[(gid.y - 2) * params.width + gid.x] - h);
        totalDiff += abs(heightmap[(gid.y + 2) * params.width + gid.x] - h);
        totalDiff += abs(heightmap[gid.y * params.width + (gid.x - 2)] - h);
        totalDiff += abs(heightmap[gid.y * params.width + (gid.x + 2)] - h);
    }
    float flatness = max(0.0, 1.0 - totalDiff * 2.5);
    score += flatness * 0.3;

    int riverDist = riverDistMap[idx];
    if (riverDist > 2 && riverDist < 18) {
        score += (1.0 - float(riverDist) / 18.0) * params.preferRivers * 0.4;
    }

    int coastDist = coastDistMap[idx];
    if (coastDist > 5 && coastDist < 25) {
        score += (1.0 - float(coastDist) / 25.0) * params.preferCoast * 0.35;
    }

    if (h > 0.6) {
        score -= (h - 0.6) * params.avoidMountains * 2.5;
    }

    switch (biome) {
        case 6:
        case 7:
            score += 0.15;
            break;
        case 5:
            score += 0.1;
            break;
        case 3:
            score += 0.08;
            break;
        case 10:
        case 9:
            score -= 0.1;
            break;
        case 4:
            score -= 0.12;
            break;
        case 12:
        case 13:
            score -= 0.5;
            break;
        default:
            break;
    }

    if (score > 0.35) {
        scores[idx] = score;
    } else {
        scores[idx] = 0;
    }
}

kernel void downsampleCostMap(
    device const float* fullCostMap [[buffer(0)]],
    device float* coarseCostMap [[buffer(1)]],
    constant DownsampleParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.coarseWidth || gid.y >= params.coarseHeight) {
        return;
    }

    float sum = 0.0;
    uint count = 0;
    uint startX = gid.x * params.scale;
    uint startY = gid.y * params.scale;

    for (uint dy = 0; dy < params.scale; dy++) {
        for (uint dx = 0; dx < params.scale; dx++) {
            uint fx = startX + dx;
            uint fy = startY + dy;

            if (fx < params.fullWidth && fy < params.fullHeight) {
                sum += fullCostMap[fy * params.fullWidth + fx];
                count++;
            }
        }
    }

    float avg = sum / max(float(count), 1.0);
    coarseCostMap[gid.y * params.coarseWidth + gid.x] = avg;
}

kernel void initBoundedDistance(
    device float* dist [[buffer(0)]],
    constant BoundedPathParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.bboxWidth || gid.y >= params.bboxHeight) {
        return;
    }

    uint wx = gid.x + params.bboxMinX;
    uint wy = gid.y + params.bboxMinY;

    if (wx >= params.mapWidth || wy >= params.mapHeight) {
        return;
    }

    uint idx = wy * params.mapWidth + wx;

    if (wx == params.sourceX && wy == params.sourceY) {
        dist[idx] = 0.0;
    } else {
        dist[idx] = 1e30;
    }
}

kernel void propagateBoundedDistance(
    device const float* costMap [[buffer(0)]],
    device const float* distIn [[buffer(1)]],
    device float* distOut [[buffer(2)]],
    device const float* roadMask [[buffer(3)]],
    device atomic_uint* changedCount [[buffer(4)]],
    constant BoundedPathParams& params [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.bboxWidth || gid.y >= params.bboxHeight) {
        return;
    }

    uint wx = gid.x + params.bboxMinX;
    uint wy = gid.y + params.bboxMinY;

    if (wx >= params.mapWidth || wy >= params.mapHeight) {
        return;
    }

    uint idx = wy * params.mapWidth + wx;
    float myCost = costMap[idx];

    if (myCost >= 5000.0) {
        distOut[idx] = distIn[idx];
        return;
    }

    float current = distIn[idx];
    float best = current;

    for (int d = 0; d < 8; d++) {
        int nx = int(wx) + pathNeighborOffsets[d].x;
        int ny = int(wy) + pathNeighborOffsets[d].y;

        if (nx < 0 || nx >= int(params.mapWidth)) {
            continue;
        }
        if (ny < 0 || ny >= int(params.mapHeight)) {
            continue;
        }

        if (uint(nx) < params.bboxMinX || uint(nx) >= params.bboxMinX + params.bboxWidth) {
            continue;
        }
        if (uint(ny) < params.bboxMinY || uint(ny) >= params.bboxMinY + params.bboxHeight) {
            continue;
        }

        uint nidx = uint(ny) * params.mapWidth + uint(nx);
        float neighborDist = distIn[nidx];

        if (neighborDist >= 1e29) {
            continue;
        }

        float moveCost = myCost * pathNeighborDists[d];

        if (roadMask[idx] > 0.5) {
            moveCost *= params.roadDiscount;
        }

        float candidate = neighborDist + moveCost;
        if (candidate < best) {
            best = candidate;
        }
    }

    distOut[idx] = best;

    if (best < current - 0.001) {
        atomic_fetch_add_explicit(changedCount, 1, memory_order_relaxed);
    }
}
