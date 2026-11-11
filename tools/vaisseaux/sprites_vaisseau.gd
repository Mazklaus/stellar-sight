extends SceneTree
## Tire les sprites 2D d'un vaisseau cuit (docs/vaisseaux-3d.md), vue de dessus, nez vers la droite :
##   <nom>_sprite.png         rendu éclairé, fond transparent (ce que le jeu affiche)
##   <nom>_sprite_masque.png  zone à teindre aux couleurs de l'empire (blanc = teinte)
##   <nom>_sprite_n.png       normales vues de dessus (x à droite, y en haut), pour de futures lumières 2D
##   <nom>_portrait.png       vue 3/4 avant en perspective, nez à droite (Chantier, fiches), et son masque
## Lancement (une fenêtre est nécessaire ; sur serveur, xvfb-run et --rendering-driver opengl3) :
##   godot --path . -s res://tools/vaisseaux/sprites_vaisseau.gd -- <vaisseau.glb> [dossier] [taille]
## Le masque est lu à côté du glb (<nom>_masque.png). Dossier par défaut : res://assets/ships,
## taille par défaut : 512 pixels pour la plus grande dimension.

const LUMIERE := Vector3(-35, -25, 0)  # soleil venu de l'avant gauche, un peu de haut


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage : -- <vaisseau.glb> [dossier] [taille]")
		quit(1)
		return
	var chemin := args[0]
	var dossier := ProjectSettings.globalize_path(args[1] if args.size() > 1 else "res://assets/ships")
	var taille := int(args[2]) if args.size() > 2 else 512
	var nom := chemin.get_file().get_basename()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(chemin, state) != OK:
		push_error("lecture impossible : " + chemin)
		quit(1)
		return

	var vue := SubViewport.new()
	vue.own_world_3d = true
	vue.transparent_bg = true
	vue.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vue)
	var vaisseau: Node3D = doc.generate_scene(state)
	vue.add_child(vaisseau)
	var maillages: Array[MeshInstance3D] = []
	for n in vaisseau.find_children("*", "MeshInstance3D", true, false):
		maillages.append(n as MeshInstance3D)
	if maillages.is_empty():
		push_error("aucun maillage dans " + chemin)
		quit(1)
		return
	await process_frame  # les transformations globales ne sont valables qu'une fois dans l'arbre
	var aabb := maillages[0].global_transform * maillages[0].get_aabb()
	for mi in maillages:
		aabb = aabb.merge(mi.global_transform * mi.get_aabb())

	# Cadrage : la longueur (axe Z) devient la largeur de l'image, marge de 4 %.
	var long := aabb.size.z * 1.04
	var large := aabb.size.x * 1.04
	vue.size = Vector2i(taille, maxi(16, int(ceil(taille * large / long))))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = long
	# Vue de dessus, l'avant (-Z) à droite de l'image.
	cam.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.LEFT), aabb.get_center() + Vector3(0, aabb.size.y + 10.0, 0))
	cam.far = aabb.size.y + 40.0
	vue.add_child(cam)
	cam.current = true

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.44, 0.52)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var monde := WorldEnvironment.new()
	monde.environment = env
	vue.add_child(monde)
	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = LUMIERE
	soleil.light_energy = 1.8
	vue.add_child(soleil)
	var appoint := DirectionalLight3D.new()
	appoint.rotation_degrees = Vector3(-60, 150, 0)
	appoint.light_energy = 0.5
	vue.add_child(appoint)

	DirAccess.make_dir_recursive_absolute(dossier)
	var base := dossier.path_join(nom)
	(await _capture(vue)).save_png(base + "_sprite.png")

	# Normales : matériau sans éclairage qui écrit la normale (avec la carte de relief) en couleur.
	var originaux := []
	for mi in maillages:
		var m := mi.get_active_material(0)
		originaux.append(m)
		mi.material_override = _passe_normales(m as BaseMaterial3D)
	soleil.visible = false
	appoint.visible = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	(await _capture(vue)).save_png(base + "_sprite_n.png")

	var chemin_masque := chemin.get_basename() + "_masque.png"
	var masque: ImageTexture = null
	if FileAccess.file_exists(chemin_masque):
		masque = ImageTexture.create_from_image(Image.load_from_file(chemin_masque))
		for mi in maillages:
			mi.material_override = _passe_masque(masque)
		(await _capture(vue)).save_png(base + "_sprite_masque.png")
	else:
		print("pas de masque à côté du glb : sprite sans teinte d'empire")
	print("sprites : ", base, "_sprite*.png (", vue.size.x, " x ", vue.size.y, ")")

	# Portrait 3/4 avant, en perspective, nez vers la droite : illustration du Chantier et des fiches.
	for mi in maillages:
		mi.material_override = null
	soleil.visible = true
	appoint.visible = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vue.size = Vector2i(taille * 2, taille * 2)
	var rayon := aabb.size.length() * 0.5
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = 30.0
	cam.far = rayon * 20.0
	var dist := rayon / sin(deg_to_rad(cam.fov * 0.5)) * 1.05
	var pos := aabb.get_center() + Vector3(1.0, 0.6, -0.55).normalized() * dist
	cam.transform = Transform3D(Basis.looking_at(aabb.get_center() - pos, Vector3.UP), pos)
	soleil.rotation_degrees = Vector3(-40, 30, 0)
	var portrait := await _capture(vue)
	var cadre := portrait.get_used_rect().grow(int(taille * 0.04)).intersection(Rect2i(Vector2i.ZERO, portrait.get_size()))
	portrait.get_region(cadre).save_png(base + "_portrait.png")
	if masque:
		for mi in maillages:
			mi.material_override = _passe_masque(masque)
		soleil.visible = false
		appoint.visible = false
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		(await _capture(vue)).get_region(cadre).save_png(base + "_portrait_masque.png")
	print("portrait : ", base, "_portrait.png (", cadre.size.x, " x ", cadre.size.y, ")")
	quit()


func _capture(vue: SubViewport) -> Image:
	for i in 4:
		await process_frame
	return vue.get_texture().get_image()


func _passe_normales(base: BaseMaterial3D) -> ShaderMaterial:
	var s := Shader.new()
	# La normale perturbée par la carte de relief est recalculée à la main, puis écrite en couleur.
	# La sortie de la vue passe en sRGB : on applique l'inverse pour garder des valeurs linéaires.
	s.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D relief : hint_normal;
uniform bool avec_relief;
void fragment() {
	vec3 n = NORMAL;
	if (avec_relief) {
		vec3 t = texture(relief, UV).rgb * 2.0 - 1.0;
		n = normalize(TANGENT * t.x + BINORMAL * t.y + NORMAL * t.z);
	}
	// Espace vue : x à droite, y en haut, z vers la caméra, comme une carte de normales 2D.
	vec3 c = n * 0.5 + 0.5;
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
"""
	var m := ShaderMaterial.new()
	m.shader = s
	var relief: Texture2D = base.normal_texture if base and base.normal_enabled else null
	m.set_shader_parameter("avec_relief", relief != null)
	if relief:
		m.set_shader_parameter("relief", relief)
	return m


func _passe_masque(masque: Texture2D) -> ShaderMaterial:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D masque : source_color;
void fragment() {
	ALBEDO = vec3(texture(masque, UV).r);
}
"""
	var m := ShaderMaterial.new()
	m.shader = s
	m.set_shader_parameter("masque", masque)
	return m
