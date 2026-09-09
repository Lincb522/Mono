#include <metal_stdlib>
using namespace metal;

static float shibaSmooth(float value) {
    float x = clamp(value, 0.0f, 1.0f);
    return x * x * x * (x * (x * 6.0f - 15.0f) + 10.0f);
}

// The same continuous deformation as the revised web preview.
// Weights are tied to the ORIGINAL image position, not separate body layers.
static float2 shibaForward(
    float2 source, float tilt, float nod, float breath, float blink, float tail
) {
    float x = source.x;
    float y = source.y;
    float head = 1.0f - shibaSmooth((y - 0.435f) / 0.30f);
    float foot = 1.0f - shibaSmooth((y - 0.79f) / 0.115f);
    float tailWeight = shibaSmooth((x - 0.69f) / 0.095f)
        * shibaSmooth((y - 0.535f) / 0.115f)
        * (1.0f - shibaSmooth((y - 0.84f) / 0.07f));

    float eyeY = 1.0f - shibaSmooth((abs(y - 0.364f) - 0.026f) / 0.038f);
    float left = 1.0f - shibaSmooth((abs(x - 0.39f) - 0.026f) / 0.04f);
    float right = 1.0f - shibaSmooth((abs(x - 0.596f) - 0.026f) / 0.04f);
    y -= 0.86f * blink * (y - 0.364f) * max(left, right) * eyeY;

    float dx = x - 0.493f;
    float dy = y - 0.575f;
    float c = cos(tilt), s = sin(tilt);
    x += head * (dx * c - dy * s - dx);
    y += head * (dx * s + dy * c - dy);
    y += head * nod * (0.016f - (y - 0.56f) * 0.066f);
    x += (x - 0.493f) * 0.012f * breath * foot;
    y -= 0.008f * breath * foot;

    float tx = x - 0.73f, ty = y - 0.80f;
    float tc = cos(tail), ts = sin(tail);
    x += tailWeight * (tx * tc - ty * ts - tx);
    y += tailWeight * (tx * ts + ty * tc - ty);
    return float2(x, y);
}

// SwiftUI distortionEffect asks for destination -> source coordinates.
// Invert the rigid head region analytically. The eyelid map is monotonic and
// uses bisection so a nearly closed eye cannot make a Newton step overshoot.
// The gently blended neck/body region uses bounded Newton iterations.
[[ stitchable ]] float2 shibaDeform(
    float2 position, float2 size,
    float tilt, float nod, float breath, float blink, float tail
) {
    float2 safeSize = max(size, float2(1.0f));
    float2 target = position / safeSize;

    float hx = 0.493f + (target.x - 0.493f) / (1.0f + 0.012f * breath);
    float hy = (target.y + 0.008f * breath - 0.05296f * nod) / (1.0f - 0.066f * nod);
    float c = cos(tilt), s = sin(tilt);
    float2 headSource = float2(
        0.493f + (hx - 0.493f) * c + (hy - 0.575f) * s,
        0.575f - (hx - 0.493f) * s + (hy - 0.575f) * c
    );

    if (headSource.y <= 0.435f) {
        float left = 1.0f - shibaSmooth((abs(headSource.x - 0.39f) - 0.026f) / 0.04f);
        float right = 1.0f - shibaSmooth((abs(headSource.x - 0.596f) - 0.026f) / 0.04f);
        float eyeX = max(left, right);
        if (blink > 0.00001f && eyeX > 0.0f && abs(headSource.y - 0.364f) < 0.064f) {
            float low = headSource.y - 0.065f;
            float high = headSource.y + 0.065f;
            for (int i = 0; i < 15; ++i) {
                float middle = (low + high) * 0.5f;
                float eyeY = 1.0f - shibaSmooth((abs(middle - 0.364f) - 0.026f) / 0.038f);
                float warped = middle - 0.86f * blink * (middle - 0.364f) * eyeX * eyeY;
                if (warped < headSource.y) { low = middle; }
                else { high = middle; }
            }
            headSource.y = (low + high) * 0.5f;
        }
        return headSource * safeSize;
    }

    float2 source = target;
    constexpr float epsilon = 0.0001f;

    for (int iteration = 0; iteration < 8; ++iteration) {
        float2 projected = shibaForward(source, tilt, nod, breath, blink, tail);
        float2 error = projected - target;
        if (dot(error, error) < 1e-12f) { break; }
        float2 jx = (shibaForward(source + float2(epsilon, 0.0f), tilt, nod, breath, blink, tail) - projected) / epsilon;
        float2 jy = (shibaForward(source + float2(0.0f, epsilon), tilt, nod, breath, blink, tail) - projected) / epsilon;
        float determinant = jx.x * jy.y - jy.x * jx.y;
        float2 correction = error;
        if (abs(determinant) > 0.02f) {
            correction = float2(
                (jy.y * error.x - jy.x * error.y) / determinant,
                (-jx.y * error.x + jx.x * error.y) / determinant
            );
        }
        source -= clamp(correction, float2(-0.08f), float2(0.08f));
    }
    return source * safeSize;
}
