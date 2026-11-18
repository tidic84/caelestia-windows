#version 440
// Sphere d'Akira (approche en un seul passage de la maquette Three.js
// AkiraVoice/mockup/sphere-jarvis.html) : des rubans lumineux sur trois
// coques transparentes (lignes de niveau d'un bruit 3D, avec des trous),
// un coeur chaud, des ondes quand Akira parle et un halo qui imite le bloom.
// Tout part de `t` : aucun JS par image, un seul appel de dessin.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;     // taille de l'element (pixels logiques)
    float t;       // secondes
    float energy;  // eclat : 0.35 veille, 0.7 ecoute, 0.85 reflexion, 1 parole
    float wave;    // ondes concentriques du coeur (0..1, parole)
    float spin;    // vitesse de rotation (1 : normale)
};

const vec3 HALO = vec3(1.0, 0.28, 0.05);
const vec3 CORE = vec3(1.0, 0.66, 0.32);

float hash(vec3 p)
{
    p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// bruit de valeur 3D, lisse
float noise(vec3 x)
{
    vec3 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
                   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
                   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

mat3 rot(float a, float b)
{
    float ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b);
    // autour de y (a), puis inclinaison autour de x (b)
    return mat3(ca, 0.0, -sa, 0.0, 1.0, 0.0, sa, 0.0, ca) * mat3(1.0, 0.0, 0.0, 0.0, cb, sb, 0.0, -sb, cb);
}

// rubans d'une coque au point q (sphere unite) : lignes de niveau d'un
// bruit, trouees par un second bruit, avec des impulsions qui circulent
float ribbons(vec3 q, float freq, float bands, float seed, float hole)
{
    float n = noise(q * freq + seed) * 0.7 + noise(q * freq * 2.3 - seed) * 0.3;
    float x = n * bands;
    float d = abs(fract(x + 0.5) - 0.5);
    float w = d / max(fwidth(x), 1e-4);
    float line = exp(-w * w * 0.45) + 0.22 * exp(-w * 0.45);
    float mask = smoothstep(hole - 0.08, hole + 0.08, noise(q * 1.7 + seed * 3.1));
    float pulse = pow(noise(q * 5.0 + vec3(0.0, 0.0, t * 1.4 + seed)), 4.0) * 3.5;
    return line * mask * (0.55 + pulse);
}

void main()
{
    float s = min(size.x, size.y);
    float R = s * 0.40;
    vec2 p = (qt_TexCoord0 - 0.5) * size / R;
    float r = length(p);
    float aa = 1.5 / R;
    // moins de rubans en petit : ils resteraient sous le pixel
    float detail = clamp(s / 220.0, 0.25, 1.0);
    float a = t * 0.16 * spin;

    vec3 col = vec3(0.0);
    for (int k = 0; k < 3; ++k) {
        float Rs = k == 0 ? 1.0 : k == 1 ? 0.9 : 0.55;
        float inside = smoothstep(Rs, Rs - aa, r);
        float z = sqrt(max(Rs * Rs - r * r, 0.0));
        mat3 m = rot(a * (k == 1 ? -1.3 : 1.0 + 0.6 * float(k)) + float(k) * 1.7, 0.35 + 0.25 * float(k));
        float freq = (k == 2 ? 2.6 : 1.9) + 0.3 * float(k);
        float bands = mix(2.5, k == 2 ? 6.0 : 8.0, detail);
        float hole = k == 0 ? 0.42 : 0.5;
        float gain = k == 2 ? 0.9 : k == 0 ? 1.0 : 0.75;
        // face avant, puis face arriere (plus sombre) : coques transparentes
        for (int side = 0; side < 2; ++side) {
            float sg = side == 0 ? 1.0 : -1.0;
            vec3 q = m * (vec3(p, z * sg) / Rs);
            float I = ribbons(q, freq, bands, float(k) * 7.3 + 1.0, hole);
            // bord de la coque : les rubans s'y tassent, on les attenue
            float limb = smoothstep(0.0, 0.35, z / Rs);
            float back = side == 0 ? 1.0 : 0.38;
            float heat = clamp(1.0 - r * 0.9, 0.0, 1.0) * (k == 2 ? 1.0 : 0.55);
            col += mix(HALO, CORE, heat) * I * inside * limb * back * gain;
        }
    }
    col *= 0.55 * (0.25 + 0.75 * energy);

    // coeur et ondes qui en partent quand Akira parle
    float core = exp(-r * r * 10.0) * (0.25 + 0.75 * energy);
    float rings = wave * pow(max(0.0, 0.5 + 0.5 * sin(r * 16.0 - t * 7.0)), 5.0) * smoothstep(1.0, 0.15, r);
    col += CORE * (core * 0.85 + rings * 0.55) + HALO * rings * 0.25;
    // halo autour de la sphere (bloom)
    col += HALO * exp(-max(r - 0.9, 0.0) * 5.0) * smoothstep(0.55, 1.0, r) * 0.16 * (0.4 + 0.6 * energy);

    // lueurs additives : sortie premultipliee, alpha = canal le plus fort
    col = min(col, vec3(1.0));
    float alpha = max(col.r, max(col.g, col.b));
    // rien au-dela du halo : le carre de l'element ne se voit pas
    alpha *= smoothstep(1.25, 1.05, r);
    col = min(col, vec3(alpha));
    fragColor = vec4(col, alpha) * qt_Opacity;
}
