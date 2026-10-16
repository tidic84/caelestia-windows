#version 440
// Image aux coins arrondis (object-fit: cover ou contain), en une passe :
// sans calque ni masque, comme border-radius + overflow: hidden.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // taille de l'element (pixels logiques)
    vec2 imgSize;   // taille de l'image
    float radius;
    float cover;    // 1 : remplir en rognant, 0 : tout montrer
    float zoom;     // agrandissement de l'image dans son cadre (survol des fonds)
};

layout(binding = 1) uniform sampler2D source;

void main()
{
    vec2 p = qt_TexCoord0 * size;
    vec2 h = size * 0.5;
    vec2 q = abs(p - h) - (h - vec2(radius));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float a = clamp(0.5 - d, 0.0, 1.0);

    float s = cover > 0.5 ? max(size.x / imgSize.x, size.y / imgSize.y)
                          : min(size.x / imgSize.x, size.y / imgSize.y);
    vec2 shown = size / (imgSize * s);
    vec2 uv = (qt_TexCoord0 - 0.5) * shown / max(zoom, 0.01) + 0.5;
    float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    fragColor = texture(source, uv) * (a * inside * qt_Opacity);
}
