#version 440
// Rounded rectangle (per-corner radii) with an optional inside border,
// drawn from its signed distance, edged the way Omacale's blob.frag shades
// its drawers: smoothstep(-fwidth, fwidth) centred on the true edge.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec4 radii;        // top-left, top-right, bottom-right, bottom-left
    vec4 fillColor;    // straight (non-premultiplied) RGBA
    vec4 borderColor;
    float borderWidth;
};

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * itemSize;
    float r = p.x < 0.0 ? (p.y < 0.0 ? radii.x : radii.w)
                        : (p.y < 0.0 ? radii.y : radii.z);
    float d = sdRoundBox(p, itemSize * 0.5, r);

    // Omacale's blob.frag edge: smoothstep across +-fwidth, a ramp about
    // two pixels wide (wider on diagonals), instead of a hard one-pixel
    // linear ramp that stair-steps on small curves.
    float fw = max(fwidth(d), 1e-4);
    float outer = 1.0 - smoothstep(-fw, fw, d);
    float inner = borderWidth > 0.0 ? 1.0 - smoothstep(-fw, fw, d + borderWidth) : outer;

    vec4 f = vec4(fillColor.rgb * fillColor.a, fillColor.a);
    vec4 b = vec4(borderColor.rgb * borderColor.a, borderColor.a);
    fragColor = (f * inner + b * (outer - inner)) * qt_Opacity;
}
