shader_type canvas_item;
// Figurines de bataille au sol (visuel des combats, lot 3, prop. 33) : la base garde ses couleurs
// propres, le masque reçoit la couleur de l'empire (couleur de l'instance) ; tint : heure du jour.

uniform sampler2D mask_tex : filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
varying vec4 team;

void vertex() {
	team = COLOR;
}

void fragment() {
	vec4 b = texture(TEXTURE, UV);
	float m = texture(mask_tex, UV).r;
	vec3 base = b.rgb * tint.rgb;
	vec3 col = mix(base, base * team.rgb * 1.15, m);
	COLOR = vec4(col, b.a * team.a);
}
