#version 440
// Visualiseur de l'onglet Media (VizBars, mirror) en une passe : 48 barres
// arrondies, graves au centre, degrade de toute la hauteur. Remplace 48
// Rectangle dont chacun recalculait son Gradient en JS a chaque trame.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // taille de l'element (pixels logiques)
    float gap;      // espace entre deux barres
    // 24 niveaux (0..1), quatre par vec4
    vec4 l0;
    vec4 l1;
    vec4 l2;
    vec4 l3;
    vec4 l4;
    vec4 l5;
    // degrade (non premultiplie) : haut, 40 %, 70 %, bas
    vec4 c0;
    vec4 c1;
    vec4 c2;
    vec4 c3;
};

float level(int b)
{
    vec4 v = b < 4 ? l0 : b < 8 ? l1 : b < 12 ? l2 : b < 16 ? l3 : b < 20 ? l4 : l5;
    return v[b % 4];
}

void main()
{
    const float n = 48.0;
    vec2 p = qt_TexCoord0 * size;
    float bw = (size.x - gap * (n - 1.0)) / n;
    float cell = bw + gap;
    float i = clamp(floor(p.x / cell), 0.0, n - 1.0);
    int idx = int(i);
    int band = idx < 24 ? 23 - idx : idx - 24;
    float h = max(2.0, level(band) * size.y);

    // barre arrondie aux quatre coins (rayon 4 px au plus)
    vec2 hs = vec2(bw, h) * 0.5;
    vec2 c = vec2(i * cell + hs.x, size.y - hs.y);
    float r = min(min(hs.x, 4.0), hs.y);
    vec2 q = abs(p - c) - (hs - vec2(r));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    // bord adouci sur un pixel de l'ecran (quelle que soit la mise a l'echelle)
    float a = clamp(0.5 - d / max(fwidth(d), 1e-4), 0.0, 1.0);

    // interpolation premultipliee, comme le Gradient de Rectangle : la
    // couleur d'un arret transparent ne teinte pas le fondu
    vec4 p0 = vec4(c0.rgb * c0.a, c0.a);
    vec4 p1 = vec4(c1.rgb * c1.a, c1.a);
    vec4 p2 = vec4(c2.rgb * c2.a, c2.a);
    vec4 p3 = vec4(c3.rgb * c3.a, c3.a);
    float t = qt_TexCoord0.y;
    vec4 col = t < 0.4 ? mix(p0, p1, t / 0.4)
             : t < 0.7 ? mix(p1, p2, (t - 0.4) / 0.3)
             : mix(p2, p3, (t - 0.7) / 0.3);
    fragColor = col * (a * qt_Opacity);
}
