#version 440
// Barre de progression du lecteur (SeekBar) en une passe : partie jouee
// ondulee (sinus anime par `phase`), reste du morceau en trait droit, bouts
// arrondis, espace autour de la poignee.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // taille de l'element (pixels logiques)
    float frac;     // part jouee (0..1)
    float th;       // epaisseur du trait
    float amp;      // amplitude de l'ondulation (0 : droit)
    float wl;       // longueur d'onde
    float phase;
    float gap;      // espace de chaque cote de la poignee
    vec4 played;    // couleurs premultipliees
    vec4 rest;
};

const float TAU = 6.2831853;

float waveY(float x, float mid)
{
    return mid + amp * sin(x / wl * TAU - phase);
}

void main()
{
    vec2 p = qt_TexCoord0 * size;
    float mid = size.y * 0.5;
    float r = th * 0.5;
    float x0 = r;
    float x1 = size.x - r;
    float px = clamp(frac, 0.0, 1.0) * size.x;

    // partie jouee : de x0 a xa
    float aPlayed = 0.0;
    float xa = px - gap - r;
    if (frac > 0.0 && xa >= x0) {
        float xc = clamp(p.x, x0, xa);
        float y = waveY(xc, mid);
        float d;
        if (p.x == xc) {
            // distance verticale corrigee par la pente
            float s = amp * TAU / wl * cos(xc / wl * TAU - phase);
            d = abs(p.y - y) / sqrt(1.0 + s * s);
        } else {
            d = length(p - vec2(xc, y));
        }
        aPlayed = clamp(r - d + 0.5, 0.0, 1.0);
    }

    // reste : de xb a x1, droit
    float aRest = 0.0;
    float xb = frac > 0.0 ? px + gap + r : x0;
    if (xb <= x1) {
        float xc = clamp(p.x, xb, x1);
        float d = length(p - vec2(xc, mid));
        aRest = clamp(r - d + 0.5, 0.0, 1.0);
    }

    fragColor = (played * aPlayed + rest * aRest * (1.0 - aPlayed)) * qt_Opacity;
}
