#include <metal_stdlib>
using namespace metal;

struct HydraulicParams {
    uint width;
    uint height;
    uint dropletCount;
    uint dropletLifetime;
    uint brushRadius;
    float erosionStrength;
    float depositionRate;
    float evaporationRate;
    float sedimentCapacity;
    float gravity;
    float inertia;
    float minSlope;
    uint baseSeed;
};

struct ThermalParams {
    uint width;
    uint height;
    float talusAngle;
    float erosionRate;
};

uint pcgHash(uint input) {
    uint state = input * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float randomFloat(thread uint& state) {
    state = pcgHash(state);
    return float(state) / 4294967295.0;
}

void atomicAddFloat(device atomic_uint* addr, float value) {
    uint expected = atomic_load_explicit(addr, memory_order_relaxed);
    while (true) {
        float current = as_type<float>(expected);
        float desired = current + value;
        uint desiredBits = as_type<uint>(desired);
        if (atomic_compare_exchange_weak_explicit(
            addr, &expected, desiredBits,
            memory_order_relaxed, memory_order_relaxed
        )) {
            break;
        }
    }
}

float readHeight(device atomic_uint* heightmap, uint idx) {
    return as_type<float>(atomic_load_explicit(&heightmap[idx], memory_order_relaxed));
}

struct HeightGradient {
    float height;
    float2 gradient;
};

HeightGradient calcHeightAndGradient(
    device atomic_uint* heightmap,
    uint width,
    float posX,
    float posY
) {
    int coordX = int(posX);
    int coordY = int(posY);
    float x = posX - float(coordX);
    float y = posY - float(coordY);
    uint idx = uint(coordY) * width + uint(coordX);

    float hNW = readHeight(heightmap, idx);
    float hNE = readHeight(heightmap, idx + 1);
    float hSW = readHeight(heightmap, idx + width);
    float hSE = readHeight(heightmap, idx + width + 1);

    HeightGradient result;
    result.gradient.x = (hNE - hNW) * (1 - y) + (hSE - hSW) * y;
    result.gradient.y = (hSW - hNW) * (1 - x) + (hSE - hNE) * x;
    result.height = hNW * (1 - x) * (1 - y) +
                    hNE * x * (1 - y) +
                    hSW * (1 - x) * y +
                    hSE * x * y;
    return result;
}

float calcHeight(
    device atomic_uint* heightmap,
    uint width,
    float posX,
    float posY
) {
    int coordX = int(posX);
    int coordY = int(posY);
    float x = posX - float(coordX);
    float y = posY - float(coordY);
    uint idx = uint(coordY) * width + uint(coordX);

    float hNW = readHeight(heightmap, idx);
    float hNE = readHeight(heightmap, idx + 1);
    float hSW = readHeight(heightmap, idx + width);
    float hSE = readHeight(heightmap, idx + width + 1);

    return hNW * (1 - x) * (1 - y) +
           hNE * x * (1 - y) +
           hSW * (1 - x) * y +
           hSE * x * y;
}

kernel void hydraulicErosion(
    device atomic_uint* heightmap [[buffer(0)]],
    constant HydraulicParams& params [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= params.dropletCount) {
        return;
    }

    uint rngState = pcgHash(params.baseSeed ^ pcgHash(gid + 1));

    int br = int(params.brushRadius);
    float minX = float(br);
    float maxX = float(int(params.width) - br - 2);
    float minY = float(br);
    float maxY = float(int(params.height) - br - 2);

    float posX = minX + randomFloat(rngState) * (maxX - minX);
    float posY = minY + randomFloat(rngState) * (maxY - minY);
    float dirX = 0;
    float dirY = 0;
    float vel = 1;
    float water = 1;
    float sediment = 0;

    for (uint step = 0; step < params.dropletLifetime; step++) {
        int nodeX = int(posX);
        int nodeY = int(posY);
        float cellOffsetX = posX - float(nodeX);
        float cellOffsetY = posY - float(nodeY);
        uint dropletIdx = uint(nodeY) * params.width + uint(nodeX);

        HeightGradient hg = calcHeightAndGradient(heightmap, params.width, posX, posY);

        dirX = dirX * params.inertia - hg.gradient.x * (1 - params.inertia);
        dirY = dirY * params.inertia - hg.gradient.y * (1 - params.inertia);

        float len = sqrt(dirX * dirX + dirY * dirY);
        if (len > 0) {
            dirX /= len;
            dirY /= len;
        } else {
            float angle = randomFloat(rngState) * 6.28318530718;
            dirX = cos(angle);
            dirY = sin(angle);
        }

        float newPosX = posX + dirX;
        float newPosY = posY + dirY;

        if (newPosX < minX || newPosX >= maxX || newPosY < minY || newPosY >= maxY) {
            break;
        }

        float newHeight = calcHeight(heightmap, params.width, newPosX, newPosY);
        float deltaHeight = newHeight - hg.height;

        float sedCap = max(
            -deltaHeight * vel * water * params.sedimentCapacity,
            params.minSlope
        );

        if (sediment > sedCap || deltaHeight > 0) {
            float depositAmount;
            if (deltaHeight > 0) {
                depositAmount = min(deltaHeight, sediment);
            } else {
                depositAmount = (sediment - sedCap) * params.depositionRate;
            }

            sediment -= depositAmount;

            atomicAddFloat(&heightmap[dropletIdx], depositAmount * (1 - cellOffsetX) * (1 - cellOffsetY));
            atomicAddFloat(&heightmap[dropletIdx + 1], depositAmount * cellOffsetX * (1 - cellOffsetY));
            atomicAddFloat(&heightmap[dropletIdx + params.width], depositAmount * (1 - cellOffsetX) * cellOffsetY);
            atomicAddFloat(&heightmap[dropletIdx + params.width + 1], depositAmount * cellOffsetX * cellOffsetY);
        } else {
            float erodeAmount = min(
                (sedCap - sediment) * params.erosionStrength,
                -deltaHeight
            );

            float weightSum = 0;
            for (int dy = -br; dy <= br; dy++) {
                for (int dx = -br; dx <= br; dx++) {
                    int nx = nodeX + dx;
                    int ny = nodeY + dy;
                    if (nx >= 0 && nx < int(params.width) && ny >= 0 && ny < int(params.height)) {
                        float dist = sqrt(float(dx * dx + dy * dy));
                        if (dist <= float(br)) {
                            weightSum += 1.0 - dist / float(br);
                        }
                    }
                }
            }

            if (weightSum > 0) {
                for (int dy = -br; dy <= br; dy++) {
                    for (int dx = -br; dx <= br; dx++) {
                        int nx = nodeX + dx;
                        int ny = nodeY + dy;
                        if (nx >= 0 && nx < int(params.width) && ny >= 0 && ny < int(params.height)) {
                            float dist = sqrt(float(dx * dx + dy * dy));
                            if (dist <= float(br)) {
                                float weight = (1.0 - dist / float(br)) / weightSum;
                                uint nidx = uint(ny) * params.width + uint(nx);
                                float currentH = readHeight(heightmap, nidx);
                                float eroded = min(currentH, erodeAmount * weight);
                                atomicAddFloat(&heightmap[nidx], -eroded);
                                sediment += eroded;
                            }
                        }
                    }
                }
            }
        }

        vel = sqrt(max(0.0, vel * vel + deltaHeight * params.gravity));
        water *= (1 - params.evaporationRate);
        posX = newPosX;
        posY = newPosY;

        if (vel < 0.01 || water < 0.01) {
            break;
        }
    }
}

constant int2 thermalOffsets[8] = {
    int2(-1, -1), int2(0, -1), int2(1, -1),
    int2(-1,  0),              int2(1,  0),
    int2(-1,  1), int2(0,  1), int2(1,  1)
};

kernel void thermalErosionPass(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant ThermalParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;

    if (gid.x < 2 || gid.x >= params.width - 2 || gid.y < 2 || gid.y >= params.height - 2) {
        output[idx] = input[idx];
        return;
    }

    float h = input[idx];
    float change = 0;

    float myMaxDiff = 0;
    float myTotalDiff = 0;

    for (int n = 0; n < 8; n++) {
        int nx = int(gid.x) + thermalOffsets[n].x;
        int ny = int(gid.y) + thermalOffsets[n].y;
        uint nidx = uint(ny) * params.width + uint(nx);
        float diff = h - input[nidx];

        if (diff > params.talusAngle) {
            myTotalDiff += diff;
            myMaxDiff = max(myMaxDiff, diff);
        }
    }

    if (myTotalDiff > 0) {
        change -= (myMaxDiff - params.talusAngle) * params.erosionRate;
    }

    for (int n = 0; n < 8; n++) {
        int nx = int(gid.x) + thermalOffsets[n].x;
        int ny = int(gid.y) + thermalOffsets[n].y;
        uint nidx = uint(ny) * params.width + uint(nx);
        float nh = input[nidx];

        if (nh - h > params.talusAngle) {
            float nMaxDiff = 0;
            float nTotalDiff = 0;

            for (int m = 0; m < 8; m++) {
                int mx = nx + thermalOffsets[m].x;
                int my = ny + thermalOffsets[m].y;

                if (mx >= 0 && mx < int(params.width) && my >= 0 && my < int(params.height)) {
                    float mh = input[uint(my) * params.width + uint(mx)];
                    float diff = nh - mh;

                    if (diff > params.talusAngle) {
                        nTotalDiff += diff;
                        nMaxDiff = max(nMaxDiff, diff);
                    }
                }
            }

            if (nTotalDiff > 0) {
                float nRedistributed = (nMaxDiff - params.talusAngle) * params.erosionRate;
                float proportion = (nh - h) / nTotalDiff;
                change += nRedistributed * proportion;
            }
        }
    }

    output[idx] = h + change;
}
