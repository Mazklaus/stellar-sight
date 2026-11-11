class_name BattleCinematic
extends Control
## Cinématique 3D d'une bataille (prototype), ouverte depuis la vue de replay : rejoue le même journal
## (report["units"], report["log"]) dans une scène 3D, dans l'esprit des batailles regardées d'Endless
## Space 2 : arrivée des flottes, échanges à longue puis moyenne portée, puis à courte portée les deux
## flottes se croisent avant de s'écarter, sous une caméra qui enchaîne les plans.
##
## Elle ne fait que relire, comme la vue de replay. Tout se calcule à partir du temps t (positions,
## tirs, plans de caméra), sans hasard non reproductible : revenir en arrière redonne la même image.
## Vaisseaux : le modèle 3D allégé du peuple et de la coque (res://assets/ships/<peuple>_<coque>.glb,
## voir docs/vaisseaux-3d.md), teint aux couleurs de l'empire, sinon une silhouette simple.

signal closed

const DAY_SECONDS := 3.0
const SPEEDS := [1.0, 2.0, 4.0]
const SHOT_SECONDS := 4.0     # durée d'un plan de caméra (en temps de bataille)
const MODEL_SCALE := 2.4      # les modèles sont à l'échelle du cahier des charges (frégate 1,6)
const LANE := 6.0             # écart entre deux vaisseaux d'un rang
const LINE_DEPTH := 7.0       # écart entre écran, ligne et arrière
const LINES := ["screen", "line", "rear"]
const FALLBACK_LENGTH := {"small": 1.0, "medium": 1.6, "large": 2.5, "titan": 5.0}
const WEAPON_COLORS := BattleReplayPanel.WEAPON_COLORS
const TRAVEL := {"beam": 0.12, "kinetic": 0.22, "missile": 0.42, "torpedo": 0.5, "artillery": 0.45,
		"fighters": 0.55, "bombers": 0.55, "stellar_lance": 0.15, "singularity": 0.5, "martyr": 0.3}
const SHOT_KINDS := ["ensemble", "poursuite", "flanc", "croisement"]

var report: Dictionary = {}
var playing := true
var t := 0.0
var overview := false           # vue d'ensemble fixe au lieu des plans de cinéma
var _speed_i := 0
var _state: GameState
var _left := {}
var _units: Array = []          # {node, side (-1 gauche, 1 droite), line, lane, lanes, size, dead_day, joined}
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _fx: MeshInstance3D         # traits des tirs, refaits à chaque image
var _flashes: MeshInstance3D    # éclairs d'impact et explosions
var _fx_mesh := ImmediateMesh.new()
var _flash_mesh := ImmediateMesh.new()
var _play_btn: Button
var _speed_btn: Button
var _cam_btn: Button
var _title: Label
var _sub: Label
var _shot_label: Label
var _shot_cache := {}           # indice de plan -> {kind, unit}
var _first_day := 0             # numéro du premier jour du journal (les renforts arrivent après)


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(_vp)

	_title = _label(Vector2(40, 30), 30, UiTheme.TEXT, UiTheme.title_font())
	_sub = _label(Vector2(40, 74), 16, UiTheme.WARN, UiTheme.body_font())
	_shot_label = _label(Vector2(40, 100), 12, UiTheme.TEXT_DIM, UiTheme.caps_font())
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_top = -72.0
	bar.offset_bottom = -28.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	_button(bar, "◀ JOUR", "Revenir au début du jour précédent", func() -> void: _seek_day(-1))
	_play_btn = _button(bar, "PAUSE", "Lecture ou pause  (Espace)", toggle_play)
	_speed_btn = _button(bar, "VITESSE ×1", "Changer la vitesse de lecture", _cycle_speed)
	_cam_btn = _button(bar, "VUE D'ENSEMBLE", "Basculer entre les plans de cinéma et une vue d'ensemble fixe  (C)", toggle_overview)
	_button(bar, "JOUR ▶", "Passer au jour suivant", func() -> void: _seek_day(1))
	_button(bar, "VUE 2D", "Revenir à la vue de bataille en 2D  (Échap)", hide_cinematic)


func _label(at: Vector2, fsize: int, col: Color, font: Font) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _button(parent: Control, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(130, 38)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# --- Ouverture -----------------------------------------------------------------------------------

## left : empires du camp de gauche (comme dans la vue de replay).
func show_cinematic(state: GameState, r: Dictionary, left: Dictionary) -> void:
	if not BattleReplayPanel.has_log(r):
		return
	_state = state
	report = r
	_left = left
	t = 0.0
	playing = true
	_speed_i = 0
	_shot_cache.clear()
	_first_day = int(r["log"][0].get("day", 0))
	_build_world()
	_title.text = "Bataille de %s" % String(r.get("system_name", "?"))
	_refresh_buttons()
	visible = true
	_update(0.0)


func hide_cinematic() -> void:
	if visible:
		visible = false
		_clear_world()
		closed.emit()


func close_silently() -> void:
	visible = false
	_clear_world()
	_state = null
	report = {}


func toggle_play() -> void:
	if t >= day_count() * DAY_SECONDS:
		t = 0.0
	playing = not playing
	_refresh_buttons()


func toggle_overview() -> void:
	overview = not overview
	_refresh_buttons()


func day_count() -> int:
	return report.get("log", []).size()


func _cycle_speed() -> void:
	_speed_i = (_speed_i + 1) % SPEEDS.size()
	_refresh_buttons()


func _seek_day(delta: int) -> void:
	var d := clampi(int(t / DAY_SECONDS) + delta, 0, maxi(0, day_count() - 1))
	t = d * DAY_SECONDS + 0.001


func _refresh_buttons() -> void:
	if _play_btn:
		_play_btn.text = "PAUSE" if playing else "LECTURE"
		_speed_btn.text = "VITESSE ×%d" % int(SPEEDS[_speed_i])
		_cam_btn.text = "PLANS DE CINÉMA" if overview else "VUE D'ENSEMBLE"


func _process(delta: float) -> void:
	if not visible:
		return
	if playing:
		t += delta * float(SPEEDS[_speed_i])
		var end := day_count() * DAY_SECONDS
		if t >= end:
			t = end
			playing = false
			_refresh_buttons()
	_update(delta)


func _gui_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		if k.keycode == KEY_SPACE:
			toggle_play()
			accept_event()
		elif k.keycode == KEY_C:
			toggle_overview()
			accept_event()


# --- Scène ---------------------------------------------------------------------------------------

func _clear_world() -> void:
	if _world:
		# Hors de l'arbre (tests), queue_free ne s'exécuterait jamais : libérer tout de suite.
		if _world.is_inside_tree():
			_world.queue_free()
		else:
			_world.free()
		_world = null
	_units.clear()


func _build_world() -> void:
	_clear_world()
	_world = Node3D.new()
	_vp.add_child(_world)
	var star_col := Color(1.0, 0.85, 0.6)
	var sid := int(report.get("system", -1))
	if _state and sid >= 0 and sid < _state.galaxy.systems.size():
		star_col = GalaxyView.STAR_COLORS.get(_state.galaxy.systems[sid].star_type, star_col)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = _nebula_shader()
	sky_mat.set_shader_parameter("teinte", Vector3(star_col.r, star_col.g, star_col.b))
	sky_mat.set_shader_parameter("graine", float(sid % 97))
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = star_col.lerp(Color(0.4, 0.5, 0.8), 0.5)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	# L'étoile du système, loin derrière le camp de droite : elle découpe les coques en contre-jour.
	# La lumière principale vient d'en haut, du côté des caméras, pour que les vaisseaux restent lisibles.
	var star_dir := Vector3(0.75, 0.28, -0.6).normalized()
	var sun := DirectionalLight3D.new()
	sun.light_color = star_col.lerp(Color.WHITE, 0.3)
	sun.light_energy = 2.0
	sun.transform = Transform3D(Basis.looking_at(-star_dir, Vector3.UP), Vector3.ZERO)
	_world.add_child(sun)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.92)
	key.light_energy = 1.7
	key.transform = Transform3D(Basis.looking_at(-Vector3(-0.35, 0.8, 0.5).normalized(), Vector3.UP), Vector3.ZERO)
	_world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.45, 0.6, 1.0)
	rim.light_energy = 0.7
	rim.transform = Transform3D(Basis.looking_at(-Vector3(-0.6, -0.4, -0.5).normalized(), Vector3.UP), Vector3.ZERO)
	_world.add_child(rim)
	var star := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 26.0
	sphere.height = 52.0
	star.mesh = sphere
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = star_col
	smat.emission_enabled = true
	smat.emission = star_col
	smat.emission_energy_multiplier = 4.0
	star.material_override = smat
	star.position = star_dir * 300.0
	_world.add_child(star)
	_world.add_child(_starfield(sid))

	_fx = MeshInstance3D.new()
	_fx.mesh = _fx_mesh
	_fx.material_override = _additive(null)
	_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_fx)
	_flashes = MeshInstance3D.new()
	_flashes.mesh = _flash_mesh
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	grad.gradient = g
	_flashes.material_override = _additive(grad)
	_flashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_flashes)

	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 2000.0
	_world.add_child(_cam)
	_cam.current = true
	_place_units()


## Fond : nébuleuse discrète teintée par l'étoile du système, sur un noir bleuté.
func _nebula_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type sky;
uniform vec3 teinte = vec3(1.0, 0.85, 0.6);
uniform float graine = 0.0;
float h(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719)) + graine) * 43758.5453); }
float n(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int k = 0; k < 5; k++) { v += a * n(p); p *= 2.03; a *= 0.5; } return v; }
void sky() {
	vec3 d = EYEDIR;
	float c = fbm(d * 2.2 + vec3(graine));
	float neb = smoothstep(0.45, 0.85, c);
	vec3 base = vec3(0.006, 0.008, 0.02);
	vec3 col = base + neb * mix(vec3(0.10, 0.06, 0.20), teinte * 0.25, fbm(d * 4.0)) * 0.9;
	COLOR = col;
}
"""
	return sh


func _additive(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if tex:
		m.albedo_texture = tex
	return m


func _starfield(seed_value: int) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + seed_value
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	mm.mesh = quad
	mm.instance_count = 900
	for i in mm.instance_count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var p := dir * rng.randf_range(700.0, 900.0)
		mm.set_instance_transform(i, Transform3D(Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT).scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), p))
		var b := rng.randf_range(0.35, 1.0)
		mm.set_instance_color(i, Color(b, b, b * rng.randf_range(0.9, 1.15)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = m
	return mi


# --- Vaisseaux -----------------------------------------------------------------------------------

func _place_units() -> void:
	var units: Array = report["units"]
	var dead := {}
	var log: Array = report["log"]
	for d in log.size():
		for k in log[d]["kills"]:
			dead[int(k)] = d
	# Rang de chaque vaisseau dans sa colonne (camp + ligne), pour l'étaler en largeur.
	var counts := {}
	var lane_of: Array[int] = []
	for i in units.size():
		var key := "%s|%s" % [_on_left(int(units[i][0])), String(units[i][2])]
		lane_of.append(int(counts.get(key, 0)))
		counts[key] = int(counts.get(key, 0)) + 1
	for i in units.size():
		var u: Array = units[i]
		var eid := int(u[0])
		var ship_id := String(u[1])
		var e := _state.get_empire(eid) if _state else null
		var col := e.color() if e else Color.WHITE
		var node := _ship_node(e.faction_id if e else "", ship_id, col)
		_world.add_child(node)
		var key := "%s|%s" % [_on_left(eid), String(u[2])]
		_units.append({"node": node, "side": -1.0 if _on_left(eid) else 1.0, "line": maxi(0, LINES.find(String(u[2]))),
				"lane": lane_of[i], "lanes": int(counts[key]), "size": Combat.ship_size(ship_id),
				"dead_day": int(dead.get(i, -1)), "joined": int(u[3]), "phase": float(i) * 1.7})


func _on_left(eid: int) -> bool:
	return _left.has(eid)


## Modèle 3D allégé du vaisseau (teint aux couleurs de l'empire), sinon une silhouette simple.
func _ship_node(faction_id: String, ship_id: String, col: Color) -> Node3D:
	var holder := Node3D.new()
	var model := ship_model(faction_id, ship_id)
	if model:
		model.scale = Vector3.ONE * MODEL_SCALE
		_tint_model(model, faction_id, ship_id, col)
		holder.add_child(model)
		return holder
	var size := Combat.ship_size(ship_id)
	var length := float(FALLBACK_LENGTH.get(size, 1.6)) * MODEL_SCALE
	var body := MeshInstance3D.new()
	body.mesh = dart_mesh(length)
	var m := StandardMaterial3D.new()
	m.albedo_color = col.lerp(Color(0.62, 0.64, 0.68), 0.45)
	m.metallic = 0.55
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.35
	body.material_override = m
	holder.add_child(body)
	return holder


## Silhouette de repli : une fléchette facettée, nez vers -Z, de la longueur donnée.
static func dart_mesh(length: float) -> ArrayMesh:
	var l := length
	var nose := Vector3(0, 0, -l * 0.55)
	var tail_l := Vector3(-l * 0.32, 0, l * 0.45)
	var tail_r := Vector3(l * 0.32, 0, l * 0.45)
	var top := Vector3(0, l * 0.2, l * 0.18)
	var bottom := Vector3(0, -l * 0.13, l * 0.18)
	var back := Vector3(0, 0, l * 0.32)
	var faces := [[nose, tail_r, top], [nose, top, tail_l], [nose, bottom, tail_r], [nose, tail_l, bottom],
			[top, tail_r, back], [tail_l, top, back], [tail_r, bottom, back], [bottom, tail_l, back]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		for v: Vector3 in f:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Modèle 3D allégé d'un vaisseau pour un peuple (res://assets/ships/<peuple>_<coque>.glb), ou null.
static func ship_model(faction_id: String, ship_id: String) -> Node3D:
	if faction_id == "":
		return null
	var h := ShipArt.hull_of(ship_id)
	while h != "":
		var path := "%s%s_%s.glb" % [ShipArt.DIR, GameData.ship_style(faction_id), h]
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene:
				return scene.instantiate() as Node3D
		h = String(Designs.hull(h).get("variant_of", ""))
	return null


func _tint_model(model: Node3D, faction_id: String, ship_id: String, col: Color) -> void:
	var h := ShipArt.hull_of(ship_id)
	var mask_path := ""
	while h != "":
		var p := "%s%s_%s_masque.png" % [ShipArt.DIR, GameData.ship_style(faction_id), h]
		if ResourceLoader.exists(p):
			mask_path = p
			break
		h = String(Designs.hull(h).get("variant_of", ""))
	if mask_path == "":
		return
	var mask := load(mask_path) as Texture2D
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var base := mi.get_active_material(0) as StandardMaterial3D
		if base == null:
			continue
		# Passe multiplicative par-dessus le matériau d'origine : la zone du masque tire vers la teinte.
		var s := Shader.new()
		s.code = """
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never;
uniform sampler2D masque : source_color;
uniform vec3 teinte;
void fragment() {
	float m = texture(masque, UV).r;
	ALBEDO = mix(vec3(1.0), teinte, m * 0.55);
}
"""
		var pass_mat := ShaderMaterial.new()
		pass_mat.shader = s
		pass_mat.set_shader_parameter("masque", mask)
		pass_mat.set_shader_parameter("teinte", Vector3(col.r, col.g, col.b) * 1.25)
		var own := base.duplicate() as StandardMaterial3D
		own.next_pass = pass_mat
		mi.material_override = own


# --- Chorégraphie --------------------------------------------------------------------------------

## Avancement de la bataille (0 au début, 1 à la fin du dernier jour) au temps tt.
func _f(tt: float) -> float:
	return clampf(tt / maxf(0.001, day_count() * DAY_SECONDS), 0.0, 1.0)


## Position d'un vaisseau au temps tt. Longue puis moyenne portée : les flottes approchent ; courte
## portée (dernier tiers) : elles se croisent, chaque vaisseau sur son couloir, puis s'écartent.
func unit_pos(i: int, tt: float) -> Vector3:
	var u: Dictionary = _units[i]
	var s: float = u["side"]
	var f := _f(tt)
	var lanes := int(u["lanes"])
	var z := (float(u["lane"]) - (lanes - 1) * 0.5) * LANE
	# Le couloir d'un camp est décalé d'un demi-écart : les deux flottes passent entre les vaisseaux d'en face.
	z += s * LANE * 0.25
	var depth := float(u["line"]) * LINE_DEPTH
	var approach := 38.0 - 24.0 * smoothstep(0.0, 0.62, f)          # de 38 à 14 unités du centre
	var cross := smoothstep(0.62, 0.9, f)                              # traversée
	var x := s * (approach + depth) - s * cross * (approach * 2.0 + depth + 10.0)
	var y := s * 1.6 * sin(cross * PI) + sin(tt * 0.9 + float(u["phase"])) * 0.5
	# Après la traversée, chaque vaisseau s'écarte vers l'extérieur et prend de l'altitude.
	var out := smoothstep(0.78, 1.0, f)
	var side_z := signf(z) if absf(z) > 0.01 else s
	z += side_z * out * 16.0
	y += s * out * 5.0
	# Renforts : arrivent du fond, plus tard.
	var joined := int(u["joined"])
	if joined > _first_day:
		var arrive := clampf(tt / DAY_SECONDS - float(joined - _first_day), 0.0, 1.0)
		x += s * (1.0 - smoothstep(0.0, 1.0, arrive)) * 80.0
	return Vector3(x, y, z)


func _unit_basis(i: int, tt: float) -> Basis:
	var dt := 0.08
	var p0 := unit_pos(i, tt - dt)
	var p1 := unit_pos(i, tt)
	var p2 := unit_pos(i, tt + dt)
	var v := p2 - p0
	var s: float = _units[i]["side"]
	var fwd := Vector3(-s, 0, 0)  # face au camp d'en face
	if v.length() > 0.05:
		fwd = fwd.lerp(v.normalized(), clampf(v.length() / 1.2, 0.0, 1.0)).normalized()
	var acc := (p2 - p1) - (p1 - p0)
	var right := fwd.cross(Vector3.UP).normalized()
	var roll := clampf(-acc.dot(right) * 40.0, -0.7, 0.7)
	var b := Basis.looking_at(fwd, Vector3.UP)
	return b * Basis(Vector3.BACK, roll)


func _alive(i: int, d: int, frac: float) -> bool:
	var dd := int(_units[i]["dead_day"])
	return not (dd >= 0 and (dd < d or (dd == d and frac > 0.8)))


func _arrived(i: int, d: int) -> bool:
	var log: Array = report["log"]
	var today := int(log[d]["day"]) if d < log.size() else 0
	return int(_units[i]["joined"]) <= today


# --- Image ---------------------------------------------------------------------------------------

func _update(delta: float) -> void:
	if _world == null:
		return
	var log: Array = report["log"]
	var d := clampi(int(t / DAY_SECONDS), 0, maxi(0, log.size() - 1))
	var frac := clampf((t - d * DAY_SECONDS) / DAY_SECONDS, 0.0, 1.0)
	var day: Dictionary = log[d] if d < log.size() else {}
	_sub.text = "Jour %d sur %d  ·  %s" % [int(day.get("day", d + 1)), log.size(), Combat.phase_label(int(day.get("phase", 0)))]
	for i in _units.size():
		var node: Node3D = _units[i]["node"]
		var shown := _alive(i, d, frac) and _arrived(i, d)
		node.visible = shown
		if shown:
			node.transform = Transform3D(_unit_basis(i, t), unit_pos(i, t))
	_draw_fx(d, frac, day)
	_direct_camera(delta)


func _draw_fx(d: int, frac: float, day: Dictionary) -> void:
	_fx_mesh.clear_surfaces()
	_flash_mesh.clear_surfaces()
	var cam_pos := _cam.position  # la caméra est enfant direct du monde, à l'origine
	var lines := []
	var flashes := []
	var shots: Array = day.get("shots", [])
	var n := shots.size()
	for k in n:
		var sh: Array = shots[k]
		var a := int(sh[0])
		var b := int(sh[1])
		if a < 0 or b < 0 or a >= _units.size() or b >= _units.size():
			continue
		var w := String(sh[2])
		var start := 0.04 + 0.66 * float(k) / float(maxi(1, n))
		var travel := float(TRAVEL.get(w, 0.35))
		var p := (frac - start) / travel
		if p < 0.0 or p > 1.4:
			continue
		var col: Color = WEAPON_COLORS.get(w, Color.WHITE)
		var pa := unit_pos(a, t)
		var pb := unit_pos(b, t) + Vector3(sin(k * 1.3), cos(k * 0.7), sin(k * 2.1)) * 0.4
		if p > 1.0:
			var fade := 1.0 - (p - 1.0) / 0.4
			flashes.append([pb, 1.2 + 0.8 * fade, Color(col.r, col.g, col.b, fade)])
			continue
		match w:
			"beam", "stellar_lance":
				var width := 0.5 if w == "stellar_lance" else 0.14
				lines.append([pa, pb, width, Color(col.r, col.g, col.b, 0.9 * (1.0 - p * 0.5))])
			"kinetic":
				for j in 3:
					var q := clampf(p - j * 0.12, 0.0, 1.0)
					var h := pa.lerp(pb, q)
					lines.append([h, pa.lerp(pb, maxf(0.0, q - 0.06)), 0.08, Color(col.r, col.g, col.b, 0.9)])
			"missile", "torpedo", "artillery", "singularity":
				var bend := Vector3(0, 6.0 if w == "artillery" else 2.5, sin(k * 0.9) * 3.0)
				var h := _bez(pa, pb, bend, p)
				var tail := _bez(pa, pb, bend, maxf(0.0, p - 0.12))
				lines.append([h, tail, 0.12 if w != "torpedo" else 0.2, Color(col.r, col.g, col.b, 0.8)])
				flashes.append([h, 0.5 if w != "torpedo" else 0.8, col])
			"fighters", "bombers":
				for j in 5:
					var off := Vector3(sin(k + j * 2.0), cos(k * 1.7 + j), sin(j * 1.3 + k)) * 2.0
					var h := _bez(pa, pb, off * 2.0, clampf(p - j * 0.03, 0.0, 1.0)) + off * (1.0 - p)
					flashes.append([h, 0.35, col])
			_:
				flashes.append([pa.lerp(pb, p), 0.5, col])
	# Explosions : du dernier quart du jour jusqu'à la disparition.
	for i in _units.size():
		if int(_units[i]["dead_day"]) == d and frac > 0.68 and frac < 0.98:
			var e := (frac - 0.68) / 0.3
			var size := float(FALLBACK_LENGTH.get(String(_units[i]["size"]), 1.6)) * MODEL_SCALE
			flashes.append([unit_pos(i, t), size * (0.8 + e * 2.4), Color(1.0, 0.75, 0.4, 1.0 - e * 0.9)])
	if not lines.is_empty():
		_fx_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for l: Array in lines:
			_ribbon(l[0], l[1], l[2], l[3], cam_pos)
		_fx_mesh.surface_end()
	if not flashes.is_empty():
		_flash_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for fl: Array in flashes:
			_billboard(fl[0], fl[1], fl[2], cam_pos)
		_flash_mesh.surface_end()


func _ribbon(a: Vector3, b: Vector3, width: float, col: Color, cam_pos: Vector3) -> void:
	var dir := b - a
	if dir.length() < 0.001:
		return
	var side := dir.cross(cam_pos - a).normalized() * width
	for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
		_fx_mesh.surface_set_color(col)
		_fx_mesh.surface_add_vertex(v)


func _billboard(c: Vector3, size: float, col: Color, cam_pos: Vector3) -> void:
	var view := (cam_pos - c).normalized()
	var right := view.cross(Vector3.UP).normalized() * size
	if right.length() < 0.001:
		right = Vector3.RIGHT * size
	var up := right.cross(view).normalized() * size
	var pts := [c - right - up, c + right - up, c + right + up, c - right + up]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		_flash_mesh.surface_set_color(col)
		_flash_mesh.surface_set_uv(uvs[idx])
		_flash_mesh.surface_add_vertex(pts[idx])


static func _bez(a: Vector3, b: Vector3, bend: Vector3, q: float) -> Vector3:
	var m := (a + b) * 0.5 + bend
	return a.lerp(m, q).lerp(m.lerp(b, q), q)


# --- Caméra --------------------------------------------------------------------------------------

## Plan de caméra au temps tt : {kind, unit}. Le premier plan est toujours l'ensemble (arrivée) ;
## pendant la traversée, un plan sur deux est pris au point de croisement.
func shot_at(tt: float) -> Dictionary:
	var idx := int(tt / SHOT_SECONDS)
	if _shot_cache.has(idx):
		return _shot_cache[idx]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(report.get("id", 0)), idx])
	var kind := "ensemble"
	var f := _f(tt)
	if idx > 0:
		if f > 0.6 and f < 0.92 and idx % 2 == 0:
			kind = "croisement"
		else:
			kind = ["poursuite", "flanc", "ensemble", "poursuite", "flanc"][rng.randi() % 5]
	# Vaisseau suivi : de préférence un tireur du jour, vivant.
	var log: Array = report["log"]
	var d := clampi(int(tt / DAY_SECONDS), 0, maxi(0, log.size() - 1))
	var candidates: Array[int] = []
	var day_shots: Array = log[d]["shots"] if d < log.size() else []
	for sh: Array in day_shots:
		var a := int(sh[0])
		if a >= 0 and a < _units.size() and not candidates.has(a) and int(_units[a]["dead_day"]) != d:
			candidates.append(a)
	if candidates.is_empty():
		for i in _units.size():
			if int(_units[i]["dead_day"]) < 0 or int(_units[i]["dead_day"]) > d:
				candidates.append(i)
	var unit := candidates[rng.randi() % candidates.size()] if not candidates.is_empty() else 0
	var shot := {"kind": kind, "unit": unit, "angle": rng.randf_range(-1.0, 1.0)}
	_shot_cache[idx] = shot
	return shot


func _direct_camera(_delta: float) -> void:
	var center := Vector3.ZERO
	var n := 0
	for i in _units.size():
		if (_units[i]["node"] as Node3D).visible:
			center += (_units[i]["node"] as Node3D).position
			n += 1
	if n > 0:
		center /= float(n)
	var pos: Vector3
	var look: Vector3
	var label := ""
	if overview:
		pos = center + Vector3(0, 62, 46)
		look = center
		label = "VUE D'ENSEMBLE"
	else:
		var shot := shot_at(t)
		var local := fmod(t, SHOT_SECONDS) / SHOT_SECONDS
		var ui: int = shot["unit"]
		var up := unit_pos(ui, t) if ui < _units.size() else center
		var ub := _unit_basis(ui, t) if ui < _units.size() else Basis()
		var ang: float = shot["angle"]
		match String(shot["kind"]):
			"ensemble":
				var orbit := ang * 0.6 + local * 0.25
				pos = center + Vector3(sin(orbit) * 18.0, 20.0 - local * 4.0, 58.0 - local * 8.0).rotated(Vector3.UP, orbit * 0.3)
				look = center
				label = "PLAN D'ENSEMBLE"
			"poursuite":
				# Derrière et au-dessus du vaisseau, vers l'avant.
				pos = up + ub * Vector3(ang * 2.0, 2.4, 8.0 - local * 1.5)
				look = up + ub * Vector3(0, 0, -30.0)
				label = "POURSUITE"
			"flanc":
				# Au ras du vaisseau, de côté, qui le laisse filer.
				# (au-dessus plutôt que de côté : les voisins du même rang sont à LANE d'écart sur le flanc)
				pos = up + ub * Vector3(2.2 * signf(ang if ang != 0.0 else 1.0), 3.2, -5.0 + local * 9.0)
				look = up
				label = "PLAN DE FLANC"
			"croisement":
				pos = Vector3(ang * 4.0, 2.5 + ang * 1.5, center.z + 26.0 + local * 3.0)
				look = Vector3(0, 0, center.z)
				label = "CROISEMENT"
	if pos.is_equal_approx(look):
		look = pos + Vector3.FORWARD
	_cam.transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	_shot_label.text = label
