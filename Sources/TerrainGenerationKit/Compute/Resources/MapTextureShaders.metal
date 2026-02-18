#include <metal_stdlib>
using namespace metal;

struct MapTextureParams {
    uint width;
    uint height;
    uint renderMode;
    float seaLevel;
};

constant float3 kBiomeColors[17] = {
    float3(0.05, 0.15, 0.35),
    float3(0.10, 0.25, 0.50),
    float3(0.20, 0.45, 0.65),
    float3(0.85, 0.80, 0.60),
    float3(0.90, 0.80, 0.55),
    float3(0.70, 0.65, 0.35),
    float3(0.40, 0.65, 0.30),
    float3(0.20, 0.45, 0.20),
    float3(0.10, 0.35, 0.15),
    float3(0.25, 0.40, 0.35),
    float3(0.65, 0.70, 0.65),
    float3(0.95, 0.97, 1.00),
    float3(0.50, 0.48, 0.45),
    float3(0.85, 0.88, 0.92),
    float3(0.35, 0.45, 0.30),
    float3(0.25, 0.50, 0.70),
    float3(0.20, 0.45, 0.65),
};

static float3 heatmapColor(float v) {
    v = clamp(v, 0.0, 1.0);
    if (v < 0.5) {
        float t = v * 2.0;
        return float3(0.0, t, 1.0 - t);
    }
    float t = (v - 0.5) * 2.0;
    return float3(t, 1.0 - t, 0.0);
}

static float3 humidityColor(float v) {
    v = clamp(v, 0.0, 1.0);
    return float3(
        (1.0 - v) * (180.0 / 255.0) + (40.0 / 255.0),
        (1.0 - v) * (130.0 / 255.0) + (60.0 / 255.0),
        v * (200.0 / 255.0) + (55.0 / 255.0)
    );
}

kernel void generateMapTexture(
    device const float* heightmap [[buffer(0)]],
    device const uchar* biomeMap [[buffer(1)]],
    device const float* temperatureMap [[buffer(2)]],
    device const float* humidityMap [[buffer(3)]],
    device const float* riverMask [[buffer(4)]],
    device const float* lakeMask [[buffer(5)]],
    device const float* waterDepth [[buffer(6)]],
    device const float* flowDirX [[buffer(7)]],
    device const float* flowDirY [[buffer(8)]],
    device const float* steepnessMap [[buffer(9)]],
    device const uchar* cityMask [[buffer(10)]],
    device const uchar* wallMask [[buffer(11)]],
    device const float* roadSDF [[buffer(12)]],
    constant MapTextureParams& params [[buffer(13)]],
    device uchar4* outPixels [[buffer(14)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) return;

    uint idx = gid.y * params.width + gid.x;
    float h = heightmap[idx];
    float seaLevel = params.seaLevel;
    float3 color;

    switch (params.renderMode) {
        case 0: {
            color = float3(h);
            break;
        }
        case 1: {
            uint bi = min((uint)biomeMap[idx], 16u);
            float shade = 0.7 + 0.3 * h;
            color = kBiomeColors[bi] * shade;
            break;
        }
        case 2: {
            color = heatmapColor(temperatureMap[idx]);
            break;
        }
        case 3: {
            color = humidityColor(humidityMap[idx]);
            break;
        }
        case 4: {
            float rv = riverMask[idx];
            float lv = lakeMask[idx];
            if (rv > 0.3) {
                color = float3(50, 120, 200) / 255.0;
            } else if (lv > 0.3) {
                color = float3(40, 100, 180) / 255.0;
            } else if (h < seaLevel) {
                float d = (seaLevel - h) / seaLevel;
                color = float3(0,
                    (0.2 + d * 0.2) * (100.0 / 255.0),
                    (0.4 + d * 0.6) * (200.0 / 255.0) + (30.0 / 255.0));
            } else {
                float v = h * (200.0 / 255.0) + (30.0 / 255.0);
                color = float3(v);
            }
            break;
        }
        case 5: {
            float depth = waterDepth[idx];
            float rv = riverMask[idx];
            float lv = lakeMask[idx];
            if (depth > 0 || rv > 0.3 || lv > 0.3) {
                float intensity = 0.3 + depth * 0.7;
                color = float3(
                    (1.0 - intensity) * (150.0 / 255.0),
                    (1.0 - intensity) * (180.0 / 255.0) + (40.0 / 255.0),
                    intensity * (200.0 / 255.0) + (55.0 / 255.0));
            } else if (h < seaLevel) {
                float od = (seaLevel - h) / seaLevel;
                float intensity = 0.2 + od * 0.8;
                color = float3(
                    (1.0 - intensity) * (80.0 / 255.0),
                    (1.0 - intensity) * (100.0 / 255.0) + (10.0 / 255.0),
                    intensity * (220.0 / 255.0) + (35.0 / 255.0));
            } else {
                float v = h * (200.0 / 255.0) + (30.0 / 255.0);
                color = float3(v);
            }
            break;
        }
        case 6: {
            color = float3(flowDirX[idx] * 0.5 + 0.5, flowDirY[idx] * 0.5 + 0.5, 0.5);
            break;
        }
        case 7: {
            uchar wv = wallMask[idx];
            uchar cv = cityMask[idx];
            if (wv == 2) {
                color = float3(255, 200, 50) / 255.0;
            } else if (wv == 1) {
                color = float3(120, 100, 80) / 255.0;
            } else if (cv > 0) {
                color = float3(200, 140, 80) / 255.0;
            } else {
                float v = h * (200.0 / 255.0) + (30.0 / 255.0);
                color = float3(v);
            }
            break;
        }
        case 8: {
            float s = pow(steepnessMap[idx], 0.4);
            color = float3(s, s * 0.5, 0.0);
            break;
        }
        case 9: {
            uint bi = min((uint)biomeMap[idx], 16u);
            float4 c = float4(kBiomeColors[bi], 1.0);

            float rv = riverMask[idx];
            float lv = lakeMask[idx];
            if (rv > 0.3) c = mix(c, float4(0.2, 0.45, 0.7, 1.0), rv);
            if (lv > 0.3) c = mix(c, float4(0.15, 0.4, 0.65, 1.0), lv);

            float rd = roadSDF[idx];
            if (rd < 2.0) {
                float rf = max(0.0, 1.0 - rd / 2.0) * 0.8;
                c = mix(c, float4(0.55, 0.45, 0.35, 1.0), rf);
            }

            uchar wv = wallMask[idx];
            uchar cv = cityMask[idx];
            if (wv == 2) {
                c = float4(0.95, 0.8, 0.3, 1.0);
            } else if (wv == 1) {
                c = float4(0.5, 0.45, 0.35, 1.0);
            } else if (cv > 0) {
                c = mix(c, float4(0.75, 0.55, 0.35, 1.0), 0.6);
            }

            color = c.xyz * (0.65 + 0.35 * h);
            break;
        }
        default: {
            color = float3(h);
            break;
        }
    }

    outPixels[idx] = uchar4(
        uchar(clamp(color.x, 0.0, 1.0) * 255),
        uchar(clamp(color.y, 0.0, 1.0) * 255),
        uchar(clamp(color.z, 0.0, 1.0) * 255),
        255
    );
}
