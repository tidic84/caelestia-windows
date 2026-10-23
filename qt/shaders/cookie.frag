#version 440
// Fond du bouton lecture (PlayBtn) : forme « cookie » de Material 3
// Expressive. 5 bosses douces en pause (m = 0), 9 festons en lecture
// (m = 1) ; cookie = 0 donne un disque. La rotation est celle de l'element.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // taille de l'element (pixels logiques)
    float m;        // pause 0 .. lecture 1
    float cookie;   // 1 : festonne, 0 : rond
    vec4 fill;      // couleur premultipliee
};

void main()
{
    vec2 p = qt_TexCoord0 * size - size * 0.5;
    float r = length(p);
    float a = atan(p.y, p.x);
    float R = min(size.x, size.y) * 0.5 - 1.0;
    float k = cookie * ((1.0 - m) * 0.055 * cos(5.0 * a) + m * 0.07 * cos(9.0 * a));
    float edge = R * (1.0 - 0.07 * cookie + k);
    fragColor = fill * (clamp(edge - r + 0.5, 0.0, 1.0) * qt_Opacity);
}
