#include <metal_stdlib>
using namespace metal;

struct TemperatureParams {
    uint width;
    uint height;
    float temperatureVariation;
};

struct HumidityParams {
    uint width;
    uint height;
    float humidityVariation;
};

kernel void generateTemperatureMap(
    device const float* heightmap [[buffer(0)]],
    device const float* noise [[buffer(1)]],
    device float* output [[buffer(2)]],
    constant TemperatureParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;

    float latitudeNormalized = float(gid.y) / float(params.height - 1);
    float equatorDistance = abs(latitudeNormalized - 0.5) * 2.0;
    float latitudeTemp = 1.0 - equatorDistance;
    float heightPenalty = heightmap[idx] * 0.4;

    float noiseInfluence = (noise[idx] - 0.5) * params.temperatureVariation;

    output[idx] = clamp(latitudeTemp - heightPenalty + noiseInfluence, 0.0f, 1.0f);
}

kernel void generateHumidityMap(
    device const float* heightmap [[buffer(0)]],
    device const float* noise [[buffer(1)]],
    device const float* waterDistance [[buffer(2)]],
    device float* output [[buffer(3)]],
    constant HumidityParams& params [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;

    float humidity = noise[idx];
    float distInfluence = max(0.0f, 1.0f - waterDistance[idx] / 50.0f);
    humidity = humidity * 0.6 + distInfluence * 0.4;

    float heightPen = max(0.0f, (heightmap[idx] - 0.6) * 0.5);
    humidity -= heightPen;

    humidity = 0.5 + (humidity - 0.5) * params.humidityVariation;

    output[idx] = clamp(humidity, 0.0f, 1.0f);
}
