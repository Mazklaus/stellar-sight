shader_type canvas_item;
render_mode unshaded;
// Sprite de vaisseau éclairé par l'étoile de l'arène (visuel des combats, prop. 12).
// La texture est une CanvasTexture : couleur teinte aux couleurs de l'empire + normales vues de dessus
// (x à droite, y en haut, z vers la caméra : tools/vaisseaux/sprites_vaisseau.gd).
// Un sprite retourné (échelle x négative, camp de droite) inverse la normale en x.

// Direction vers la lumière, en coordonnées écran (x à droite, y vers le bas), z vers le spectateur.
uniform vec3 light_dir = vec3(-0.6, -0.4, 0.7);
uniform vec4 light_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float power = 1.0;
uniform float ambient = 0.32;

varying float flip;

void vertex() {
	flip = determinant(mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy)) < 0.0 ? -1.0 : 1.0;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec3 n = texture(NORMAL_TEXTURE, UV).rgb * 2.0 - 1.0;
	n.x *= flip;
	n = normalize(n);
	vec3 l = normalize(vec3(light_dir.x, -light_dir.y, light_dir.z));
	float d = max(dot(n, l), 0.0);
	// Liseré sur les bords tournés vers l'étoile.
	float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.0) * d;
	vec3 lit = c.rgb * (ambient + (1.0 - ambient) * 1.35 * d * power * light_color.rgb);
	lit += light_color.rgb * rim * 0.35 * power * c.a;
	COLOR = vec4(lit, c.a);
}
