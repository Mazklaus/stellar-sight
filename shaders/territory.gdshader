shader_type canvas_item;
render_mode unshaded;
// Affichage des territoires à partir du champ de territory_field.gdshader : aplat à la couleur de
// l'empire, plus dense vers le bord, et un liseré clair juste à l'intérieur de la limite.

uniform float band = 40.0;   // même valeur que dans le champ
uniform float px = 1.0;      // un pixel écran, en unités du monde
uniform float fill = 0.26;   // opacité de l'aplat
uniform float rim = 0.3;     // opacité ajoutée vers le bord
uniform float rim_width = 26.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float inside = (t.a - 0.5) * 2.0 * band;
	float aa = max(px, 2.0);
	float mask = smoothstep(-aa, aa, inside);
	float w = max(rim_width, px * 10.0);
	float edge = 1.0 - smoothstep(0.0, w, inside);
	float line_at = px * 1.6;
	float line = 1.0 - smoothstep(px * 0.5, px * 1.5, abs(inside - line_at));
	vec3 col = mix(t.rgb, min(t.rgb * 1.25 + 0.08, vec3(1.0)), line);
	float a = max((fill + rim * edge * edge) * mask, line * 0.8 * mask);
	COLOR = vec4(col, a);
}
