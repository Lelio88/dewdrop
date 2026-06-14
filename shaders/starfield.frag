#version 460 core

// DewDrop — décor "constellations".
// Ciel étoilé procédural : dégradé selon l'heure (uDaylight), étoiles
// scintillantes sur 3 couches, léger décalage de parallax (uParallax).
// Aucune texture : tout est généré, donc zéro asset.

#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;   // floats 0,1 — taille du canvas (px logiques)
uniform float uTime;        // float  2   — secondes écoulées
uniform float uDaylight;    // float  3   — 0 = nuit, 1 = plein jour
uniform vec2 uParallax;     // floats 4,5 — décalage gyroscope/pointeur

out vec4 fragColor;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Une couche d'étoiles sur une grille : voisinage 3x3, scintillement par cellule.
float starField(vec2 uv, float twinkleSpeed) {
    vec2 gv = fract(uv) - 0.5;
    vec2 id = floor(uv);
    float c = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offs = vec2(float(x), float(y));
            float n = hash21(id + offs);
            float present = step(0.55, n);          // ~45% des cellules ont une étoile
            float n2 = fract(n * 34.0);
            vec2 pos = offs + vec2(n, n2) - 0.5;     // position sous-cellule
            float d = length(gv - pos);
            float bright = smoothstep(0.06, 0.0, d);
            bright *= 0.55 + 0.45 * sin(uTime * twinkleSpeed + n * 6.2831);
            c += bright * present;
        }
    }
    return c;
}

void main() {
    vec2 fragCoord = FlutterFragCoord();
    vec2 uv = (fragCoord - 0.5 * uResolution) / uResolution.y;
    vec2 p = uv + uParallax;

    float t = clamp(uv.y * 0.6 + 0.5, 0.0, 1.0);

    // Palettes nuit / jour, interpolées par uDaylight.
    vec3 nightTop = vec3(0.03, 0.04, 0.12);
    vec3 nightBot = vec3(0.02, 0.02, 0.05);
    vec3 night = mix(nightBot, nightTop, t);

    vec3 dayTop = vec3(0.18, 0.34, 0.62);
    vec3 dayBot = vec3(0.62, 0.45, 0.38);   // horizon chaud (aube/crépuscule)
    vec3 day = mix(dayBot, dayTop, t);

    vec3 sky = mix(night, day, uDaylight);

    // Les étoiles s'effacent quand le jour se lève.
    float starVis = 1.0 - smoothstep(0.15, 0.6, uDaylight);
    float stars = 0.0;
    stars += starField(p * 9.0 + 7.0, 2.6);
    stars += starField(p * 18.0 + 41.0, 1.7) * 0.7;
    stars += starField(p * 34.0 + 88.0, 3.4) * 0.4;

    vec3 col = sky + stars * starVis * vec3(0.92, 0.96, 1.0);

    // Vignette douce pour concentrer le regard.
    float vig = smoothstep(1.2, 0.2, length(uv));
    col *= mix(0.85, 1.0, vig);

    fragColor = vec4(col, 1.0);
}
