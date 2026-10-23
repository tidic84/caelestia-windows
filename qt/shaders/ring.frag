#version 440
// Anneau de spectre autour de la pochette festonnee (onglet Media) : 72
// barres arrondies partant du cercle `r0`, graves en bas, symetrique.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // taille de l'element (pixels logiques)
    float r0;       // rayon du pied des barres
    float maxLen;   // longueur ajoutee au niveau 1
    // 24 niveaux (0..1), quatre par vec4
    vec4 l0;
    vec4 l1;
    vec4 l2;
    vec4 l3;
    vec4 l4;
    vec4 l5;
    vec4 color;     // couleur premultipliee
};

const float PI = 3.14159265;
const float N = 72.0;
const float W = 4.0;

float level(int b)
{
    vec4 v = b < 4 ? l0 : b < 8 ? l1 : b < 12 ? l2 : b < 16 ? l3 : b < 20 ? l4 : l5;
    int i = b - (b / 4) * 4;
    return i == 0 ? v.x : i == 1 ? v.y : i == 2 ? v.z : v.w;
}

void main()
{
    vec2 p = qt_TexCoord0 * size - size * 0.5;
    float r = length(p);
    // 0 en haut, sens horaire, 0..1
    float t = atan(p.x, -p.y) / (2.0 * PI) + 0.5;
    float i = floor(t * N + 0.5);
    float tc = i / N;
    // aigus en haut (t = 0,5), graves en bas
    int band = int(clamp((1.0 - abs(tc - 0.5) * 2.0) * 23.0 + 0.5, 0.0, 23.0));
    float lv = level(band);
    float len = 3.0 + lv * maxLen;
    float dx = (t * N - i) / N * 2.0 * PI * r;
    float ry = r - r0;
    float d = ry < 0.0 ? length(vec2(dx, ry)) : ry > len ? length(vec2(dx, ry - len)) : abs(dx);
    float a = clamp(W * 0.5 - d + 0.5, 0.0, 1.0) * (0.55 + lv * 0.45);
    fragColor = color * (a * qt_Opacity);
}
