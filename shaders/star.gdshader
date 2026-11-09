shader_type canvas_item;
// Étoile au centre de la vue système : cœur, couronne animée et halo.
// mode : 0 = étoile, 1 = étoile à neutrons (faisceaux tournants), 2 = trou noir (disque d'accrétion).

uniform vec4 star_color : source_color = vec4(1.0, 0.9, 0.55, 1.0);
uniform int mode = 0;
// Rayon du cœur, en fraction de la demi-taille du rectangle.
uniform float core = 0.2;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	vec3 c = star_color.rgb;
	vec4 col = vec4(0.0);

	if (mode == 2) {
		// Trou noir : anneau incliné, lueur, horizon noir.
		vec2 e = vec2(p.x, p.y * 3.2);
		float ring_r = length(e);
		float disk = smoothstep(core * 3.2, core * 1.4, ring_r) * smoothstep(core * 1.0, core * 1.5, ring_r);
		float swirl = fbm(vec2(atan(e.y, e.x) * 3.0 - TIME * 0.8, ring_r * 8.0));
		vec3 hot = mix(c, vec3(1.0, 0.85, 0.6), swirl);
		float glow = exp(-r * 5.0) * 0.6;
		float lens = smoothstep(core * 1.6, core * 1.05, r) * smoothstep(core * 0.9, core * 1.05, r);
		col.rgb = hot * (disk * (0.6 + swirl) + glow) + vec3(1.0, 0.9, 0.8) * lens * 0.9;
		col.a = clamp(disk + glow + lens, 0.0, 1.0);
		// L'horizon masque la moitié arrière du disque.
		float horizon = smoothstep(core, core * 0.92, r);
		bool back = p.y < 0.0;
		if (back) {
			col = mix(col, vec4(0.0, 0.0, 0.0, 1.0), horizon);
		} else {
			float front_disk = disk * step(abs(p.y), core * 0.35);
			col = mix(col, vec4(0.0, 0.0, 0.0, 1.0), horizon * (1.0 - front_disk));
		}
	} else {
		float corona_n = fbm(vec2(ang * 3.0 + TIME * 0.05, r * 4.0 - TIME * 0.35));
		float corona = exp(-(r - core) * (mode == 1 ? 9.0 : 5.0) / (0.6 + corona_n * 0.8));
		float glow = exp(-r * 3.2) * 0.55;
		float rays = pow(max(0.0, sin(ang * 6.0 + corona_n * 2.0)), 18.0) * exp(-r * 4.0) * 0.4;
		vec3 base = c * (corona * 0.9 + glow + rays);
		float a = clamp(corona * 0.9 + glow + rays, 0.0, 1.0);
		if (mode == 1) {
			float beam_ang = TIME * 1.6;
			vec2 dir = vec2(cos(beam_ang), sin(beam_ang) * 0.35);
			float along = abs(dot(p, normalize(dir)));
			float across = length(p - dot(p, normalize(dir)) * normalize(dir));
			float beam = exp(-across * 40.0) * smoothstep(1.0, 0.1, along);
			base += c * beam * 1.4;
			a = clamp(a + beam, 0.0, 1.0);
		}
		// Surface : granulation sur le disque.
		float surf = smoothstep(core, core - 0.01, r);
		float gran = fbm(p * 22.0 + vec2(TIME * 0.2, -TIME * 0.15));
		float limb = sqrt(max(0.0, 1.0 - (r / core) * (r / core)));
		vec3 disc = mix(c, vec3(1.0), 0.55 + 0.25 * gran) * (0.65 + 0.35 * limb);
		col = vec4(mix(base, disc, surf), max(a, surf));
	}
	COLOR = col;
}
