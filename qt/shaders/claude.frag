#version 440
// Animation « Claude travaille » (docs/design/claude-code, variante L4) :
// 4 noeuds orange en orbite avec trainee, qui spiralent vers le centre et
// fusionnent en etoile a 10 rayons, puis se separent. Boucle de 5 s, tout
// est calcule ici a partir de `t` : un seul appel de dessin, aucun JS.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;  // taille de l'element (pixels logiques)
    float t;    // secondes dans la boucle (0..5)
    float px;   // un pixel physique en pixels logiques (anticrenelage)
};

const float TAU = 6.283185307;
const float PERIOD = 5.0;
// un quart de tour par seconde : 5 s = 5 quarts, et les 4 noeuds sont
// symetriques par quart de tour, donc la boucle se raccorde sans saut
const float SPEED = 1.5707963;
// teintes un peu sourdes : l'ilot est sombre, des lueurs vives y eblouissent
const vec3 HOT = vec3(0.941, 0.639, 0.443);  // #f0a371
const vec3 DEEP = vec3(0.878, 0.380, 0.180); // #e0612e
const vec3 CORE = vec3(0.976, 0.855, 0.769); // #f9dac4
const float GLOW = 0.4;                      // force des halos

float seg(float x, float a, float b) { return clamp((x - a) / (b - a), 0.0, 1.0); }
float io(float x) { return x < 0.5 ? 4.0 * x * x * x : 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0; }
float outBack(float x) { float y = x - 1.0; return 1.0 + 2.4 * y * y * y + 1.4 * y * y; }

// rayon (1 : orbite, 0 : au centre) et angle des noeuds a l'instant u
vec2 phase(float u)
{
    u = mod(u, PERIOD);
    float kin = seg(u, 1.7, 2.4), kout = seg(u, 3.9, 4.5);
    float r = 1.0;
    if (u >= 1.7 && u < 2.4) r = 1.0 - kin * kin * kin;
    else if (u >= 2.4 && u < 3.9) r = 0.0;
    else if (u >= 3.9 && u < 4.5) r = outBack(kout);
    // un tour complet de plus par boucle (moitie en entrant, moitie en sortant)
    return vec2(r, u * SPEED + (io(kin) + io(kout)) * 0.5 * TAU);
}

float capsule(vec2 p, vec2 a, vec2 b)
{
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    return length(pa - ba * h);
}

void main()
{
    float s = min(size.x, size.y);
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    bool small = s < 40.0;
    float R = s * (small ? 0.36 : 0.32);
    float nodeR = max(small ? 1.8 : 2.2, s * 0.065);
    float aa = max(px, 0.35);

    vec3 col = vec3(0.0);
    float alpha = 0.0;

    // ---- noeuds et trainees (echos aux instants passes)
    const int TRAIL = 7;
    for (int i = 0; i < 4; ++i) {
        for (int k = TRAIL; k >= 0; --k) {
            vec2 ph = phase(t - float(k) * 0.018);
            if (ph.x < 0.04)
                continue;
            float a = ph.y + float(i) * TAU / 4.0;
            vec2 c = vec2(cos(a), sin(a)) * ph.x * R;
            float f = 1.0 - float(k) / float(TRAIL + 1);
            float rad = nodeR * (k > 0 ? 0.25 + 0.6 * f : 1.0) * clamp(ph.x * 1.6, 0.35, 1.0);
            float d = length(p - c);
            float cov = clamp((rad - d) / aa + 0.5, 0.0, 1.0);
            float w = k > 0 ? f * f * 0.4 : 1.0;
            col += (k > 0 ? DEEP : HOT) * cov * w;
            alpha += cov * w;
            if (k == 0) {
                // halo de la tete
                float g = exp(-max(d - rad, 0.0) / (s * 0.07)) * 0.45 * GLOW;
                col += DEEP * g;
                alpha += g;
            }
        }
    }

    // ---- etoile
    float u = mod(t, PERIOD);
    const float S0 = 2.35, END = 3.9;
    bool live = u >= S0 - 0.05 && u < END + 0.55;
    if (live) {
        float breathe = 0.9 + 0.1 * sin((u - S0) * 4.2);
        float rot = radians(u * 26.0);
        float Rin = R * 0.12, Rout = R * 1.08 * breathe;
        float w = max(small ? 1.7 : 2.2, s * 0.078) * 0.5;
        for (int i = 0; i < 10; ++i) {
            float open = outBack(seg(u, S0 + float(i) * 0.035, S0 + 0.4 + float(i) * 0.035));
            float close = io(seg(u, END - 0.05 + float(i) * 0.02, END + 0.3 + float(i) * 0.02));
            float v = u < S0 ? 0.0 : clamp(open, 0.0, 1.3) * (1.0 - close);
            if (v <= 0.01)
                continue;
            float a = rot + float(i) / 10.0 * TAU;
            vec2 dir = vec2(cos(a), sin(a));
            float L = Rin + (Rout - Rin) * (i % 2 == 1 ? 0.7 : 1.0) * v;
            float d = capsule(p, dir * Rin, dir * L) - w;
            float cov = clamp(-d / aa + 0.5, 0.0, 1.0);
            // degrade : blanc chaud au centre, orange au bout
            float r = length(p) / max(Rout, 1e-3);
            vec3 c = r < 0.3 ? mix(CORE, HOT, r / 0.3) : mix(HOT, DEEP, clamp((r - 0.3) / 0.7, 0.0, 1.0));
            float g = exp(-max(d, 0.0) / (s * 0.07)) * 0.35 * GLOW * v;
            col += c * cov + DEEP * g;
            alpha += cov + g;
        }
        // coeur
        float core = clamp(seg(u, S0 - 0.05, S0 + 0.1) * (1.0 - seg(u, END + 0.2, END + 0.5)), 0.0, 1.0);
        if (core > 0.0) {
            float d = length(p) - Rin * 1.15;
            float cov = clamp(-d / aa + 0.5, 0.0, 1.0) * core;
            float g = exp(-max(d, 0.0) / (s * 0.08)) * 0.5 * GLOW * core;
            col += CORE * cov + DEEP * g;
            alpha += cov + g;
        }
        // onde de choc a l'impact
        if (u >= S0 && u < S0 + 0.6) {
            float k = io(seg(u, S0, S0 + 0.6));
            float d = abs(length(p) - R * (0.3 + 1.1 * k)) - max(0.8, s * 0.018) * 0.5;
            float cov = clamp(-d / aa + 0.5, 0.0, 1.0) * (1.0 - k) * 0.45;
            col += HOT * cov;
            alpha += cov;
        }
    }

    // les lueurs s'additionnent ; sortie premultipliee
    alpha = clamp(alpha, 0.0, 1.0);
    col = min(col * 0.88, vec3(alpha));
    fragColor = vec4(col, alpha) * qt_Opacity;
}
