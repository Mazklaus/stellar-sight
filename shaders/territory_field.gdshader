shader_type canvas_item;
render_mode blend_disabled, unshaded;
// Champ des territoires (refonte, B5a), calculé une fois par changement de carte dans une image hors écran.
// Chaque « site » est un système connu ou un point d'une voie de saut : position, portée, empire.
// Pour chaque point de la galaxie : la couleur de l'empire le plus proche, et dans l'alpha la distance
// (signée, lissée) au bord de son territoire. Le lissage vient d'un minimum doux entre les sites : les
// creux entre deux systèmes voisins se comblent, comme sur la carte de Stellaris.

uniform sampler2D sites : filter_nearest;  // x, y, portée, empire (-1 : sans maître)
uniform sampler2D tints : filter_nearest;  // couleur du site
uniform int count = 0;
uniform float extent = 2000.0;  // demi-côté de l'image, en unités du monde
uniform float soft = 0.045;     // raideur du minimum doux (plus petit = plus rond)
uniform float gap = 5.0;        // demi-écart entre deux territoires voisins
uniform float band = 40.0;      // distance représentée par la moitié de l'alpha

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * extent;
	float best = 1.0e9;
	float own = -1.0;
	int at = 0;
	for (int i = 0; i < count; i++) {
		vec4 s = texelFetch(sites, ivec2(i, 0), 0);
		float d = distance(p, s.xy) - s.z;
		if (d < best) {
			best = d;
			own = s.w;
			at = i;
		}
	}
	float mine = 0.0;
	float theirs = 0.0;
	for (int i = 0; i < count; i++) {
		vec4 s = texelFetch(sites, ivec2(i, 0), 0);
		float e = exp(-soft * (distance(p, s.xy) - s.z - best));
		if (abs(s.w - own) < 0.5) {
			mine += e;
		} else {
			theirs += e;
		}
	}
	float d_mine = best - log(max(mine, 1.0e-6)) / soft;
	float d_theirs = theirs > 1.0e-9 ? best - log(theirs) / soft : 1.0e9;
	float inside = min(-d_mine, (d_theirs - d_mine) * 0.5 - gap);
	if (own < -0.5 || count == 0) {
		inside = -band;
	}
	vec3 tint = count > 0 ? texelFetch(tints, ivec2(at, 0), 0).rgb : vec3(0.0);
	COLOR = vec4(tint, clamp(0.5 + inside / (2.0 * band), 0.0, 1.0));
}
