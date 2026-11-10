extends SceneTree
## Planche de contrôle d'un vaisseau cuit (docs/vaisseaux-3d.md) : vue de dessus (l'avant, -Z,
## en haut de l'image), vue de profil (l'avant à droite) et vue 3/4, points d'attache en sphères
## (jaune = slot_, cyan = fx_, blanc = centre), masque d'empire teinté si le fichier existe.
## Lancement (une fenêtre est nécessaire ; sur serveur, xvfb-run et --rendering-driver opengl3) :
##   godot --path . -s res://tools/vaisseaux/apercu_vaisseau.gd -- <vaisseau.glb> <planche.png>

const TEINTE := Color(0.25, 0.55, 1.0)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage : -- <vaisseau.glb> <planche.png>")
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(args[0], state) != OK:
		push_error("lecture impossible : " + args[0])
		quit(1)
		return
	var vaisseau: Node3D = doc.generate_scene(state)
	root.add_child(vaisseau)
	_teinter(vaisseau, args[0].get_basename() + "_masque.png")
	var aabb := AABB()
	var premier := true
	for n in vaisseau.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
		aabb = b if premier else aabb.merge(b)
		premier = false
	var rayon := aabb.size.length() * 0.012
	for n in vaisseau.find_children("*", "Node3D", true, false):
		if n is MeshInstance3D:
			continue
		var bille := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = rayon
		sphere.height = rayon * 2
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.albedo_color = Color.YELLOW if n.name.begins_with("slot_") else (Color.CYAN if n.name.begins_with("fx_") else Color.WHITE)
		sphere.material = mat
		bille.mesh = sphere
		n.add_child(bille)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.47, 0.55)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var monde := WorldEnvironment.new()
	monde.environment = env
	root.add_child(monde)
	var soleil := DirectionalLight3D.new()
	soleil.rotation_degrees = Vector3(-50, -35, 0)
	soleil.light_energy = 2.0
	root.add_child(soleil)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var taille := maxf(aabb.size.x, aabb.size.z) * 1.15
	var vues := []
	# Dessus : -Z (l'avant) en haut de l'image.
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = taille
	cam.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0, 10, 0))
	vues.append(await _capture())
	# Profil : caméra à droite du vaisseau (+X), l'avant (-Z) à droite de l'image.
	cam.transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), Vector3(10, 0, 0))
	vues.append(await _capture())
	# 3/4 avant en perspective.
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 35
	var pos := Vector3(1.0, 0.7, -1.2).normalized() * taille * 1.9
	cam.transform = Transform3D(Basis.looking_at(-pos, Vector3.UP), pos)
	vues.append(await _capture())

	var w: int = vues[0].get_width()
	var h: int = vues[0].get_height()
	var planche := Image.create(w * 3, h, false, Image.FORMAT_RGBA8)
	for i in vues.size():
		planche.blit_rect(vues[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	planche.save_png(args[1])
	print("planche : ", args[1])
	quit()


func _capture() -> Image:
	for i in 4:
		await process_frame
	return root.get_texture().get_image()


func _teinter(vaisseau: Node, chemin_masque: String) -> void:
	# Aperçu simple du masque : la zone peinte prend une teinte d'empire bleue.
	if not FileAccess.file_exists(chemin_masque):
		return
	var masque := ImageTexture.create_from_image(Image.load_from_file(chemin_masque))
	for n in vaisseau.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var base := mi.get_active_material(0) as StandardMaterial3D
		if base == null:
			continue
		base.next_pass = _passe_teinte(masque)


func _passe_teinte(masque: Texture2D) -> ShaderMaterial:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never;
uniform sampler2D masque;
uniform vec3 teinte;
void fragment() {
	float m = texture(masque, UV).r;
	ALBEDO = mix(vec3(1.0), teinte * 1.6, m * 0.6);
}
"""
	var m := ShaderMaterial.new()
	m.shader = s
	m.set_shader_parameter("masque", masque)
	m.set_shader_parameter("teinte", Vector3(TEINTE.r, TEINTE.g, TEINTE.b))
	return m
