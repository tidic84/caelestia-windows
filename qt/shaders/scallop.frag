#version 440
// Pochette festonnee (onglet Media, Reglages > Lecteur) : l'image remplit
// (cover) un disque au bord ondule de 12 festons, en une passe ; `dim`
// l'assombrit (pause).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // taille de l'element (pixels logiques)
    vec2 imgSize;   // taille de l'image
    float dim;      // assombrissement (pause), 0..1
};

layout(binding = 1) uniform sampler2D source;

void main()
{
    vec2 p = qt_TexCoord0 * size - size * 0.5;
    float c = min(size.x, size.y) * 0.5;
    float edge = c * (0.95 + 0.04 * cos(12.0 * atan(p.y, p.x)));
    float a = clamp(edge - length(p) + 0.5, 0.0, 1.0);

    float s = max(size.x / imgSize.x, size.y / imgSize.y);
    vec2 uv = (qt_TexCoord0 - 0.5) * size / (imgSize * s) + 0.5;
    vec4 t = texture(source, uv);
    fragColor = vec4(t.rgb * (1.0 - dim), t.a) * (a * qt_Opacity);
}
