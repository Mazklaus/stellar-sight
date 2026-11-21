shader_type canvas_item;
// Portrait vivant (essai « portraits animés ») : une illustration fixe (Midjourney ou autre) prend vie
// sans aucun découpage. Tout se fait en déformant la lecture de l'image :
//  - respiration : le buste se soulève lentement, la tête suit (le bas du cadre reste ancré) ;
//  - regard : la tête dérive un peu vers des cibles tirées au hasard, puis revient ;
//  - clignement : la paupière est « peinte » avec la peau juste au-dessus de l'œil (il faut la position
//    des yeux, donnée par data/portrait_motion.json ; sans elle, pas de clignement) ;
//  - lueur des yeux : pulsation douce (yeux luisants des Midjourney de science-fiction) ;
//  - lumière : léger vacillement (bougies, braises) et poussières qui flottent devant le fond.
// Les coordonnées sont celles de l'image (0..1), quelle que soit la façon dont le cadre la recadre.

uniform float seed = 0.0;
uniform float speed = 1.0;
// Respiration : amplitude (part de la hauteur), période en secondes, hauteur des épaules (0 = haut).
uniform float breath_amp = 0.006;
uniform float breath_period = 4.6;
uniform float shoulders = 0.45;
// Tête : centre et rayon (unités de l'image), amplitude du regard.
uniform vec2 head = vec2(0.5, 0.35);
uniform float head_radius = 0.16;
uniform float gaze_amp = 0.0035;
// Yeux : centres, demi-taille d'un œil (largeur, hauteur) ; eyes_on = 0 pour ne pas cligner.
uniform vec2 eye_l = vec2(0.44, 0.36);
uniform vec2 eye_r = vec2(0.57, 0.37);
uniform vec2 eye_size = vec2(0.026, 0.010);
uniform float eyes_on = 0.0;
uniform float blink_every = 4.5;
// Lueur des yeux (0 = aucune).
uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float glow = 0.0;
// Lumière vacillante et poussières.
uniform float flicker = 0.0;
uniform vec4 mote_color : source_color = vec4(1.0, 0.75, 0.45, 1.0);
uniform float motes = 0.0;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

float hash11(float n) { return fract(sin(n * 127.1 + seed * 31.7) * 43758.5453); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453); }

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), u) * 2.0 - 1.0;
}

// Fermeture de la paupière à l'instant t (0 ouvert, 1 fermé) : un clignement par intervalle,
// à un moment tiré au hasard, parfois double.
float blink(float t) {
	float slot = floor(t / blink_every);
	float local = t - slot * blink_every;
	float at = 0.4 + hash11(slot + 3.0) * (blink_every - 1.2);
	float d = local - at;
	float c = 1.0 - smoothstep(0.0, 0.075, abs(d - 0.075));
	if (hash11(slot + 9.0) > 0.78) {
		c = max(c, 1.0 - smoothstep(0.0, 0.07, abs(d - 0.36)));
	}
	return c;
}

vec4 eyelid(sampler2D tex, vec2 uv, vec2 eye, float closed, vec4 col) {
	vec2 p = (uv - eye) / eye_size;
	float r = length(p);
	if (r > 1.6) {
		return col;
	}
	// Bord de la paupière : descend du haut de l'œil (-1) au bas (+1).
	float lid = mix(-1.25, 1.05, closed);
	float inside = 1.0 - smoothstep(0.85, 1.35, r);
	float cover = smoothstep(lid + 0.18, lid - 0.12, p.y) * inside;
	// Peau de la paupière : lue au-dessus de l'œil, étirée vers le bas avec la fermeture.
	vec2 src = vec2(uv.x, eye.y - eye_size.y * (2.1 - (p.y + 1.0) * 0.25));
	vec4 skin = texture(tex, src);
	skin.rgb *= 0.92 - 0.06 * (p.y + 1.0) * 0.5;
	vec4 outc = mix(col, skin, cover * step(0.02, closed));
	// Trait de cils au bord.
	float lash = (1.0 - smoothstep(0.0, 0.16, abs(p.y - lid))) * inside * smoothstep(0.05, 0.25, closed);
	outc.rgb *= 1.0 - 0.45 * lash;
	return outc;
}

void fragment() {
	float t = TIME * speed + seed * 13.0;
	vec2 uv = UV;
	// Respiration : sinus adouci (inspiration un peu plus longue que l'expiration).
	float ph = fract(t / breath_period);
	float b = sin(ph * 6.2831853 - 0.6 * sin(ph * 6.2831853));
	// Champ vertical : 0 au bas du cadre, 1 à hauteur d'épaules et au-dessus.
	float lift = 1.0 - smoothstep(shoulders, 1.02, uv.y);
	// Le buste s'élargit à peine sur les côtés (cage thoracique).
	float chest = smoothstep(shoulders - 0.05, shoulders + 0.25, uv.y) * (1.0 - smoothstep(0.65, 1.0, uv.y));
	uv.y += breath_amp * (b * 0.5 + 0.5) * lift;
	uv.x -= (uv.x - head.x) * breath_amp * 0.5 * (b * 0.5 + 0.5) * chest;
	// Regard : la tête dérive vers des cibles lentes (bruit), avec une petite inclinaison.
	vec2 dh = uv - head;
	float hw = 1.0 - smoothstep(head_radius * 0.55, head_radius * 1.25, length(dh * vec2(1.0, 0.8)));
	vec2 gaze = vec2(noise1(t * 0.23), noise1(t * 0.19 + 11.0) * 0.6) * gaze_amp;
	float tilt = noise1(t * 0.13 + 5.0) * 0.012;
	vec2 rot = vec2(dh.x * cos(tilt) - dh.y * sin(tilt), dh.x * sin(tilt) + dh.y * cos(tilt));
	uv = mix(uv, head + rot - gaze, hw);
	vec4 col = texture(TEXTURE, uv);
	// Yeux : uv est déjà dans l'image déformée, les yeux suivent donc la tête d'eux-mêmes.
	float closed = blink(t) * eyes_on;
	if (eyes_on > 0.5) {
		col = eyelid(TEXTURE, uv, eye_l, closed, col);
		col = eyelid(TEXTURE, uv, eye_r, closed, col);
	}
	// Lueur des yeux : halo qui pulse, éteint quand l'œil est fermé.
	if (glow > 0.0) {
		float pulse = 0.75 + 0.25 * sin(t * 1.7) + 0.08 * noise1(t * 6.0);
		vec2 ql = (uv - eye_l) / (eye_size * 2.2);
		vec2 qr = (uv - eye_r) / (eye_size * 2.2);
		float h = exp(-dot(ql, ql) * 2.5) + exp(-dot(qr, qr) * 2.5);
		col.rgb += glow_color.rgb * glow * pulse * h * (1.0 - closed);
	}
	// Lumière vacillante.
	if (flicker > 0.0) {
		col.rgb *= 1.0 + flicker * (noise1(t * 3.1) * 0.6 + noise1(t * 7.7) * 0.4);
	}
	// Poussières : quelques grains qui montent lentement et scintillent.
	if (motes > 0.0) {
		vec2 g = UV * vec2(9.0, 12.0);
		g.y += t * 0.18;
		g.x += sin(g.y * 0.7 + seed) * 0.3;
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float hv = hash21(cell);
		if (hv > 0.72) {
			vec2 pos = vec2(hash21(cell + 1.3), hash21(cell + 7.1));
			float d = length(f - pos);
			float tw = 0.5 + 0.5 * sin(t * (1.0 + hv * 3.0) + hv * 40.0);
			col.rgb += mote_color.rgb * motes * tw * (1.0 - smoothstep(0.0, 0.07, d));
		}
	}
	COLOR = col * vcol;
}
