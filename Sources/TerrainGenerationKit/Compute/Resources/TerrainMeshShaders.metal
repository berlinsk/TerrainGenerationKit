#include <metal_stdlib>
using namespace metal;

struct MeshParams {
    uint mapWidth;
    uint mapHeight;
    uint meshWidth;
    uint meshHeight;
    uint step;
    float heightScale;
};

kernel void generateTerrainMesh(
    device const float* heightmap [[buffer(0)]],
    constant MeshParams& params [[buffer(1)]],
    device float3* vertices [[buffer(2)]],
    device float3* normals [[buffer(3)]],
    device float2* uvs [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.meshWidth || gid.y >= params.meshHeight) return;

    uint meshIdx = gid.y * params.meshWidth + gid.x;

    uint mapCol = min(gid.x * params.step, params.mapWidth - 1);
    uint mapRow = min(gid.y * params.step, params.mapHeight - 1);
    uint mapIdx = mapRow * params.mapWidth + mapCol;

    float h = heightmap[mapIdx];

    vertices[meshIdx] = float3(float(mapCol), h * params.heightScale, float(mapRow));
    uvs[meshIdx] = float2(
        float(mapCol) / float(params.mapWidth - 1),
        float(mapRow) / float(params.mapHeight - 1)
    );

    float hL = mapCol > 0 ? heightmap[mapRow * params.mapWidth + (mapCol - 1)] : h;
    float hR = mapCol < params.mapWidth - 1 ? heightmap[mapRow * params.mapWidth + (mapCol + 1)] : h;
    float hU = mapRow > 0 ? heightmap[(mapRow - 1) * params.mapWidth + mapCol] : h;
    float hD = mapRow < params.mapHeight - 1 ? heightmap[(mapRow + 1) * params.mapWidth + mapCol] : h;

    float3 tx = float3(2.0, (hR - hL) * params.heightScale, 0.0);
    float3 tz = float3(0.0, (hD - hU) * params.heightScale, 2.0);
    normals[meshIdx] = normalize(cross(tz, tx));
}
