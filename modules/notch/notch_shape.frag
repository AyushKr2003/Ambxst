#version 440
// The default notch's silhouette from its signed distance: a body with
// rounded free corners, joined to the screen edge by two concave "ears"
// (a strip minus two circles). Edged like components/rounded_rect.frag,
// with Omacale blob.frag's smoothstep(-fwidth, fwidth). Drawn for a top
// notch; flip mirrors it.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float earSize;     // concave corner radius (0: no ears)
    float bodyRadius;  // radius of the body's free corners
    float flip;        // 1: bottom notch
    vec4 fillColor;    // straight RGBA
};

float sdBox(vec2 p, vec2 c, vec2 hs) {
    vec2 q = abs(p - c) - hs;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0));
}

float sdRoundBox(vec2 p, vec2 c, vec2 hs, float r) {
    vec2 q = abs(p - c) - hs + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 s = itemSize;
    vec2 p = qt_TexCoord0 * s;
    if (flip > 0.5) p.y = s.y - p.y;

    float c = earSize;
    float r = bodyRadius;

    // Body: x in [c, W-c], y in [0, H]; only its bottom corners are round,
    // so it is a rounded box running r past the top edge.
    vec2 bc = vec2(s.x * 0.5, (s.y - r) * 0.5);
    vec2 bh = vec2(s.x * 0.5 - c, (s.y + r) * 0.5);
    float d = sdRoundBox(p, bc, bh, r);

    if (c > 0.0) {
        float strip = sdBox(p, vec2(s.x * 0.5, c * 0.5 - c), vec2(s.x * 0.5, c * 1.5));
        float holeL = length(p - vec2(0.0, c)) - c;
        float holeR = length(p - vec2(s.x, c)) - c;
        d = min(d, max(strip, max(-holeL, -holeR)));
    }

    float fw = max(fwidth(d), 1e-4);
    float a = 1.0 - smoothstep(-fw, fw, d);
    fragColor = vec4(fillColor.rgb * fillColor.a, fillColor.a) * a * qt_Opacity;
}
