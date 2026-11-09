shader_type canvas_item;
// Planète éclairée par son étoile, dessinée sur un rectangle (ColorRect).
// Purement visuel : les paramètres viennent de la vue système selon le type de planète.

// Direction vers l'étoile, en coordonnées écran (y vers le bas), z vers le spectateur.
uniform vec3 light_dir = vec3(-1.0, 0.0, 0.35);
uniform vec4 c_deep : source_color = vec4(0.05, 0.12, 0.35, 1.0);
uniform vec4 c_shallow : source_color = vec4(0.1, 0.35, 0.6, 1.0);
uniform vec4 c_low : source_color = vec4(0.25, 0.45, 0.2, 1.0);
uniform vec4 c_high : source_color = vec4(0.55, 0.5, 0.35, 1.0);
uniform vec4 atmo : source_color = vec4(0.4, 0.65, 1.0, 1.0);
uniform float atmo_strength = 0.8;
// 0 = relief (continents, déserts…), 1 = bandes (géante gazeuse), 2 = cratères (monde stérile).
uniform int mode = 0;
uniform float sea_level = 0.5;
uniform float ice = 0.0;
uniform float clouds = 0.0;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float seed = 0.0;
uniform float spin = 0.03;
uniform float relief_scale = 2.2;
// Rayon de la planète dans le rectangle (le reste accueille le halo d'atmosphère).
uniform float body = 0.78;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 4.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 q = (UV * 2.0 - 1.0) / body;
	float d2 = dot(q, q);
	vec3 L = normalize(light_dir);
	float aa = fwidth(sqrt(d2)) * 1.5;

	// Halo d'atmosphère autour du disque, plus vif côté jour.
	float d = sqrt(d2);
	float halo_side = clamp(dot(normalize(vec3(q, 0.0001)), L) * 0.7 + 0.45, 0.0, 1.0);
	float halo = pow(max(0.0, 1.0 - (d - 1.0) / (1.0 / body - 1.0)), 2.5) * step(1.0, d);
	vec4 outside = vec4(atmo.rgb, halo * atmo_strength * 0.55 * halo_side);

	if (d2 >= 1.0) {
		COLOR = outside;
	} else {
		vec3 n = vec3(q.x, q.y, sqrt(1.0 - d2));
		float a = TIME * spin + seed * 6.2831;
		// Rotation autour de l'axe vertical : la surface défile.
		vec3 s = vec3(n.x * cos(a) - n.z * sin(a), n.y, n.x * sin(a) + n.z * cos(a));
		vec3 sp = s + vec3(seed * 13.1, seed * 7.3, seed * 3.7);
		vec3 col;
		float spec_mask = 0.0;

		if (mode == 1) {
			float turb = fbm(sp * vec3(2.0, 6.0, 2.0)) * 0.9;
			float band = sin((s.y + turb * 0.25) * 18.0 + seed * 10.0) * 0.5 + 0.5;
			float band2 = sin((s.y + turb * 0.12) * 7.0 + seed * 4.0) * 0.5 + 0.5;
			col = mix(c_deep.rgb, c_shallow.rgb, band);
			col = mix(col, c_low.rgb, band2 * 0.55);
			// Grande tempête ovale.
			vec2 st = vec2(atan(s.x, s.z) - 0.8, (s.y - 0.28) * 3.2);
			float storm = smoothstep(0.42, 0.15, length(st));
			col = mix(col, c_high.rgb, storm * 0.85);
		} else if (mode == 2) {
			float h = fbm(sp * relief_scale * 1.6);
			float crater = abs(noise3(sp * 6.0) - 0.5) * 2.0;
			col = mix(c_deep.rgb, c_shallow.rgb, smoothstep(0.25, 0.75, h));
			col = mix(col, c_low.rgb, smoothstep(0.85, 1.0, 1.0 - crater) * 0.6);
			col = mix(col, c_high.rgb, smoothstep(0.62, 0.8, h) * 0.5);
		} else {
			float h = fbm(sp * relief_scale);
			if (h < sea_level) {
				col = mix(c_deep.rgb, c_shallow.rgb, smoothstep(sea_level - 0.25, sea_level, h));
				spec_mask = 1.0;
			} else {
				col = mix(c_low.rgb, c_high.rgb, smoothstep(sea_level, sea_level + 0.3, h));
			}
		}

		// Calottes glaciaires.
		if (ice > 0.0) {
			float cap = smoothstep(1.0 - ice - 0.05, 1.0 - ice + 0.05, abs(s.y) + (fbm(sp * 4.0) - 0.5) * 0.25);
			col = mix(col, vec3(0.92, 0.96, 1.0), cap);
			spec_mask *= 1.0 - cap;
		}

		// Nuages, qui tournent un peu plus vite que le sol.
		if (clouds > 0.0) {
			float b = TIME * spin * 0.4;
			vec3 cs = vec3(s.x * cos(b) - s.z * sin(b), s.y, s.x * sin(b) + s.z * cos(b));
			float cl = smoothstep(0.5, 0.75, fbm(cs * 3.0 + vec3(seed * 5.0, 0.0, 2.0)));
			col = mix(col, cloud_color.rgb, cl * clouds);
			spec_mask *= 1.0 - cl;
		}

		float ndl = dot(n, L);
		float lit = smoothstep(-0.18, 0.55, ndl);
		vec3 h_vec = normalize(L + vec3(0.0, 0.0, 1.0));
		float spec = pow(max(0.0, dot(n, h_vec)), 40.0) * spec_mask * 0.5;
		vec3 shaded = col * (0.05 + 0.95 * lit) + vec3(spec) * lit;
		// Liseré d'atmosphère sur le bord éclairé.
		float fres = pow(1.0 - n.z, 2.5);
		shaded += atmo.rgb * fres * atmo_strength * (0.15 + 0.85 * lit);
		float edge = 1.0 - smoothstep(1.0 - aa, 1.0, d);
		COLOR = mix(outside, vec4(shaded, 1.0), edge);
	}
}
