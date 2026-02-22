#include <metal_stdlib>
using namespace metal;

struct BlendParams {
    uint count;
    uint layerCount;
    float weight0;
    float weight1;
    float weight2;
    float invTotalWeight;
};

kernel void blendNoiseLayers(
    device const float* layer0 [[buffer(0)]],
    device const float* layer1 [[buffer(1)]],
    device const float* layer2 [[buffer(2)]],
    device float* output [[buffer(3)]],
    constant BlendParams& params [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= params.count) {
        return;
    }

    float sum = layer0[gid] * params.weight0;

    if (params.layerCount >= 2) {
        sum += layer1[gid] * params.weight1;
    }

    if (params.layerCount >= 3) {
        sum += layer2[gid] * params.weight2;
    }

    output[gid] = sum * params.invTotalWeight;
}

struct NormalizeParams {
    uint count;
    float minVal;
    float invRange;
};

kernel void normalizeArray(
    device float* data [[buffer(0)]],
    constant NormalizeParams& params [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= params.count) {
        return;
    }

    data[gid] = (data[gid] - params.minVal) * params.invRange;
}

struct ContrastParams {
    uint count;
    float strength;
};

kernel void applyContrast(
    device float* data [[buffer(0)]],
    constant ContrastParams& params [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= params.count) {
        return;
    }

    float v = (data[gid] - 0.5) * params.strength + 0.5;
    data[gid] = clamp(v, 0.0, 1.0);
}

struct TerraceParams {
    uint count;
    float steps;
    float sharpness;
};

float smootherstep(float edge0, float edge1, float x) {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

kernel void applyTerracing(
    device float* data [[buffer(0)]],
    constant TerraceParams& params [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= params.count) {
        return;
    }

    float value = data[gid];
    float s = params.steps;
    float terraced = floor(value * s) / s;
    float t = fract(value * s);
    float smoothT = smoothstep(0.0, 1.0, pow(t, params.sharpness));
    data[gid] = mix(terraced, terraced + 1.0 / s, smoothT);
}

struct MaskParams {
    uint width;
    uint height;
    float param0;
    float param1;
};

kernel void applyRadialMask(
    device float* heightmap [[buffer(0)]],
    constant MaskParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    float centerX = float(params.width) / 2.0;
    float centerY = float(params.height) / 2.0;
    float maxDist = sqrt(centerX * centerX + centerY * centerY);
    float dx = float(gid.x) - centerX;
    float dy = float(gid.y) - centerY;
    float dist = sqrt(dx * dx + dy * dy);
    float falloff = params.param0;
    float base = max(0.0, 1.0 - dist / maxDist);
    float mask = pow(base, falloff);

    float blend = params.param1;
    heightmap[idx] = heightmap[idx] * (1.0 - blend) + mask * blend;
}

kernel void applyIslandMask(
    device float* heightmap [[buffer(0)]],
    constant MaskParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    float centerX = float(params.width) / 2.0;
    float centerY = float(params.height) / 2.0;
    float maxDist = min(centerX, centerY);
    float coastWidth = params.param0;

    float dx = float(gid.x) - centerX;
    float dy = float(gid.y) - centerY;
    float dist = max(abs(dx), abs(dy));

    float mask;
    if (dist < maxDist - coastWidth) {
        mask = 1.0;
    } else if (dist < maxDist) {
        float t = (maxDist - dist) / coastWidth;
        mask = smootherstep(0.0, 1.0, t);
    } else {
        mask = 0.0;
    }

    heightmap[idx] = heightmap[idx] * mask;
}

kernel void applyPangaeaMask(
    device float* heightmap [[buffer(0)]],
    constant MaskParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;
    float centerX = float(params.width) / 2.0;
    float centerY = float(params.height) / 2.0;
    float maxDist = min(centerX, centerY) * 0.8;

    float dx = float(gid.x) - centerX;
    float dy = float(gid.y) - centerY;
    float dist = sqrt(dx * dx + dy * dy);

    float landMask;
    if (dist < maxDist * 0.6) {
        landMask = 1.0;
    } else if (dist < maxDist) {
        float t = (dist - maxDist * 0.6) / (maxDist * 0.4);
        landMask = 1.0 - smootherstep(0.0, 1.0, t);
    } else {
        landMask = 0.0;
    }

    heightmap[idx] = heightmap[idx] * 0.5 + landMask * 0.5;
}

struct SmoothParams {
    uint width;
    uint height;
    float strength;
};

kernel void smoothPass(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant SmoothParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;

    if (gid.x == 0 || gid.x >= params.width - 1 || gid.y == 0 || gid.y >= params.height - 1) {
        output[idx] = input[idx];
        return;
    }

    float sum = input[idx];
    float count = 1.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }
            sum += input[(gid.y + dy) * params.width + (gid.x + dx)];
            count += 1.0;
        }
    }

    float avg = sum / count;
    output[idx] = mix(input[idx], avg, params.strength);
}

struct BlurParams {
    uint width;
    uint height;
    int radius;
};

kernel void gaussianBlurH(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant BlurParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    float sum = 0.0;
    float totalWeight = 0.0;

    for (int dx = -params.radius; dx <= params.radius; dx++) {
        int nx = int(gid.x) + dx;
        if (nx >= 0 && nx < int(params.width)) {
            float weight = 1.0 - float(abs(dx)) / float(params.radius + 1);
            sum += input[gid.y * params.width + uint(nx)] * weight;
            totalWeight += weight;
        }
    }

    output[gid.y * params.width + gid.x] = sum / totalWeight;
}

kernel void gaussianBlurV(
    device const float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    constant BlurParams& params [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    float sum = 0.0;
    float totalWeight = 0.0;

    for (int dy = -params.radius; dy <= params.radius; dy++) {
        int ny = int(gid.y) + dy;
        if (ny >= 0 && ny < int(params.height)) {
            float weight = 1.0 - float(abs(dy)) / float(params.radius + 1);
            sum += input[uint(ny) * params.width + gid.x] * weight;
            totalWeight += weight;
        }
    }

    output[gid.y * params.width + gid.x] = sum / totalWeight;
}

kernel void applyContinentalBlend(
    device float* heightmap [[buffer(0)]],
    device const float* mask [[buffer(1)]],
    constant uint& count [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }

    heightmap[gid] = heightmap[gid] * 0.7 + mask[gid] * 0.3;
}
