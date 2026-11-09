shader_type canvas_item;
// Fond de la vue système : champ d'étoiles scintillantes et nébuleuse teintée par l'étoile.

uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform vec2 size = vec2(1600.0, 900.0);
uniform float seed = 0.0;
// Position de l'étoile (en pixels) : la nébuleuse s'éclaire autour d'elle.
uniform vec2 focus = vec2(600.0, 450.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.02 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

float stars(vec2 px, float cell, float density) {
	vec2 g = floor(px / cell);
	vec2 f = px / cell - g;
	float h = hash(g);
	if (h > density) {
		return 0.0;
	}
	vec2 pos = vec2(hash(g + 3.1), hash(g + 7.7));
	float d = length(f - pos) * cell;
	float tw = 0.7 + 0.3 * sin(TIME * (1.0 + h * 3.0) + h * 40.0);
	return smoothstep(1.6, 0.0, d) * tw * (0.4 + 0.6 * hash(g + 1.3));
}

void fragment() {
	vec2 px = UV * size;
	vec2 uv = px / size.y;
	vec3 bg = vec3(0.012, 0.016, 0.035);
	float n = fbm(uv * 2.2 + vec2(seed, seed * 0.5) + vec2(TIME * 0.004, 0.0));
	float n2 = fbm(uv * 4.5 - vec2(seed * 0.3, 1.0));
	float neb = smoothstep(0.42, 0.85, n) * (0.55 + 0.45 * n2);
	vec3 neb_col = mix(vec3(0.25, 0.12, 0.45), tint.rgb, 0.55);
	float near = exp(-length(px - focus) / (size.y * 0.55));
	vec3 col = bg + neb_col * neb * (0.10 + 0.25 * near);
	col += tint.rgb * near * 0.06;
	col += vec3(stars(px, 7.0, 0.05)) * 0.6;
	col += vec3(stars(px + 311.0, 23.0, 0.25)) * 0.9;
	col += mix(vec3(0.8, 0.9, 1.0), tint.rgb, 0.3) * stars(px + 97.0, 61.0, 0.35);
	// Vignette.
	float v = smoothstep(1.25, 0.35, length(UV - 0.5) * 1.6);
	COLOR = vec4(col * (0.55 + 0.45 * v), 1.0);
}
