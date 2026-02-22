#include <metal_stdlib>
using namespace metal;

struct NoiseParams {
    uint width;
    uint height;
    uint noiseType;
    uint octaves;
    float frequency;
    float persistence;
    float lacunarity;
    float amplitude;
};

constant float F2 = 0.36602540378443864;
constant float G2 = 0.21132486540518713;

constant float OPEN_SIMPLEX_STRETCH = -0.211324865405187;
constant float OPEN_SIMPLEX_SQUISH = 0.366025403784439;

float noiseFade(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float noiseGrad2D(int h, float x, float y) {
    int hash = h & 3;
    if (hash == 0) return x + y;
    if (hash == 1) return -x + y;
    if (hash == 2) return x - y;
    return -x - y;
}

float simplexDot2D(int gi, float x, float y) {
    switch (gi & 7) {
        case 0: return x + y;
        case 1: return -x + y;
        case 2: return x - y;
        case 3: return -x - y;
        case 4: return x;
        case 5: return -x;
        case 6: return y;
        case 7: return -y;
        default: return 0.0;
    }
}

float openSimplexExtrapolate(
    int xsb,
    int ysb,
    float dx,
    float dy,
    device const uint* perm,
    device const float2* grads
) {
    uint index = perm[(perm[xsb & 255] + ysb) & 255] & 7;
    float2 grad = grads[index];
    return grad.x * dx + grad.y * dy;
}

float perlinNoise(float x, float y, device const uint* perm) {
    int xi = int(floor(x)) & 255;
    int yi = int(floor(y)) & 255;
    float xf = x - floor(x);
    float yf = y - floor(y);
    float u = noiseFade(xf);
    float v = noiseFade(yf);

    int aa = perm[perm[xi] + yi];
    int ab = perm[perm[xi] + yi + 1];
    int ba = perm[perm[xi + 1] + yi];
    int bb = perm[perm[xi + 1] + yi + 1];

    float x1 = mix(noiseGrad2D(aa, xf, yf), noiseGrad2D(ba, xf - 1.0, yf), u);
    float x2 = mix(noiseGrad2D(ab, xf, yf - 1.0), noiseGrad2D(bb, xf - 1.0, yf - 1.0), u);
    return mix(x1, x2, v);
}

float simplexNoise(float x, float y, device const uint* perm) {
    float s = (x + y) * F2;
    int i = int(floor(x + s));
    int j = int(floor(y + s));
    float t = float(i + j) * G2;
    float X0 = float(i) - t;
    float Y0 = float(j) - t;
    float x0 = x - X0;
    float y0 = y - Y0;

    int i1, j1;
    if (x0 > y0) {
        i1 = 1;
        j1 = 0;
    } else {
        i1 = 0;
        j1 = 1;
    }

    float x1 = x0 - float(i1) + G2;
    float y1 = y0 - float(j1) + G2;
    float x2 = x0 - 1.0 + 2.0 * G2;
    float y2 = y0 - 1.0 + 2.0 * G2;

    int ii = i & 255;
    int jj = j & 255;

    float n0 = 0.0;
    float n1 = 0.0;
    float n2 = 0.0;

    float t0 = 0.5 - x0 * x0 - y0 * y0;
    if (t0 >= 0.0) {
        t0 *= t0;
        int gi0 = perm[ii + perm[jj]] & 7;
        n0 = t0 * t0 * simplexDot2D(gi0, x0, y0);
    }

    float t1 = 0.5 - x1 * x1 - y1 * y1;
    if (t1 >= 0.0) {
        t1 *= t1;
        int gi1 = perm[ii + i1 + perm[jj + j1]] & 7;
        n1 = t1 * t1 * simplexDot2D(gi1, x1, y1);
    }

    float t2 = 0.5 - x2 * x2 - y2 * y2;
    if (t2 >= 0.0) {
        t2 *= t2;
        int gi2 = perm[ii + 1 + perm[jj + 1]] & 7;
        n2 = t2 * t2 * simplexDot2D(gi2, x2, y2);
    }

    return 70.0 * (n0 + n1 + n2);
}

float openSimplexNoise(
    float x,
    float y,
    device const uint* perm,
    device const float2* grads
) {
    float stretchOffset = (x + y) * OPEN_SIMPLEX_STRETCH;
    float xs = x + stretchOffset;
    float ys = y + stretchOffset;
    int xsb = int(floor(xs));
    int ysb = int(floor(ys));
    float squishOffset = float(xsb + ysb) * OPEN_SIMPLEX_SQUISH;
    float xb = float(xsb) + squishOffset;
    float yb = float(ysb) + squishOffset;
    float xins = xs - float(xsb);
    float yins = ys - float(ysb);
    float dx0 = x - xb;
    float dy0 = y - yb;

    float value = 0.0;

    float attn0 = 2.0 - dx0 * dx0 - dy0 * dy0;
    if (attn0 > 0.0) {
        attn0 *= attn0;
        value += attn0 * attn0 * openSimplexExtrapolate(xsb, ysb, dx0, dy0, perm, grads);
    }

    float dx1 = dx0 - 1.0 - OPEN_SIMPLEX_SQUISH;
    float dy1 = dy0 - OPEN_SIMPLEX_SQUISH;
    float attn1 = 2.0 - dx1 * dx1 - dy1 * dy1;
    if (attn1 > 0.0) {
        attn1 *= attn1;
        value += attn1 * attn1 * openSimplexExtrapolate(xsb + 1, ysb, dx1, dy1, perm, grads);
    }

    float dx2 = dx0 - OPEN_SIMPLEX_SQUISH;
    float dy2 = dy0 - 1.0 - OPEN_SIMPLEX_SQUISH;
    float attn2 = 2.0 - dx2 * dx2 - dy2 * dy2;
    if (attn2 > 0.0) {
        attn2 *= attn2;
        value += attn2 * attn2 * openSimplexExtrapolate(xsb, ysb + 1, dx2, dy2, perm, grads);
    }

    if (xins + yins > 1.0) {
        float dx3 = dx0 - 1.0 - 2.0 * OPEN_SIMPLEX_SQUISH;
        float dy3 = dy0 - 1.0 - 2.0 * OPEN_SIMPLEX_SQUISH;
        float attn3 = 2.0 - dx3 * dx3 - dy3 * dy3;
        if (attn3 > 0.0) {
            attn3 *= attn3;
            value += attn3 * attn3 * openSimplexExtrapolate(xsb + 1, ysb + 1, dx3, dy3, perm, grads);
        }
    }

    return value / 47.0;
}

float voronoiNoise(float x, float y, device const uint* perm) {
    int xi = int(floor(x));
    int yi = int(floor(y));
    float minDist = 3.402823e+38;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int cellX = xi + dx;
            int cellY = yi + dy;
            int hash = perm[(perm[cellX & 255] + cellY) & 255];
            float px = float(cellX) + float(hash & 0xFF) / 255.0;
            float py = float(cellY) + float((hash >> 8) & 0xFF) / 255.0;
            float distX = x - px;
            float distY = y - py;
            float dist = distX * distX + distY * distY;
            if (dist < minDist) {
                minDist = dist;
            }
        }
    }

    return sqrt(minDist) * 2.0 - 1.0;
}

float sampleNoise(
    float x,
    float y,
    uint noiseType,
    device const uint* perm,
    device const float2* grads
) {
    switch (noiseType) {
        case 0:
            return perlinNoise(x, y, perm);
        case 1:
            return simplexNoise(x, y, perm);
        case 2:
            return openSimplexNoise(x, y, perm, grads);
        case 3:
            return voronoiNoise(x, y, perm);
        case 4:
            return 1.0 - abs(simplexNoise(x, y, perm));
        case 5:
            return abs(simplexNoise(x, y, perm)) * 2.0 - 1.0;
        default:
            return 0.0;
    }
}

float fbm(
    float x,
    float y,
    uint noiseType,
    uint octaves,
    float frequency,
    float persistence,
    float lacunarity,
    float amplitude,
    device const uint* perm,
    device const float2* grads
) {
    float total = 0.0;
    float freq = frequency;
    float amp = amplitude;
    float maxValue = 0.0;

    for (uint o = 0; o < octaves; o++) {
        float noiseValue = sampleNoise(x * freq, y * freq, noiseType, perm, grads);
        total += noiseValue * amp;
        maxValue += amp;
        amp *= persistence;
        freq *= lacunarity;
    }

    return total / maxValue;
}

kernel void generateNoise(
    device float* output [[buffer(0)]],
    device const uint* perm [[buffer(1)]],
    device const float2* grads [[buffer(2)]],
    constant NoiseParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint idx = gid.y * params.width + gid.x;

    output[idx] = fbm(
        float(gid.x),
        float(gid.y),
        params.noiseType,
        params.octaves,
        params.frequency,
        params.persistence,
        params.lacunarity,
        params.amplitude,
        perm,
        grads
    );
}
