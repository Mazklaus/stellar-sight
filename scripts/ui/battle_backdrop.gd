class_name BattleBackdrop
extends Control
## Décor de la vue de bataille spatiale (étude visuel des combats, bloc B) : le vrai système où se livre
## la bataille, en couches qui bougent à des vitesses différentes (parallaxe).
##   fond (étoiles, nébuleuse) · étoile · lunes · planète · objets (astéroïdes, station, défenses, épaves)
## La couche de premier plan (poussière, gros rochers) est un nœud à part, `foreground`, que la vue
## place au-dessus des vaisseaux.
##
## Tout est tiré de report["scene"] (BattleScene) et d'une graine fixe : revoir un replay montre le
## même décor. Un PNG posé à l'emplacement prévu (data/battle_visuals.json, "art") remplace le dessin
## procédural de l'élément correspondant. Purement visuel.

const BACKDROP_SHADER := preload("res://shaders/space_backdrop.gdshader")
const STAR_SHADER := preload("res://shaders/star.gdshader")
const PARALLAX := {"bg": 0.12, "star": 0.2, "moons": 0.28, "planet": 0.4, "objects": 0.65, "fg": 1.5}
const DEFAULT_SCENE := {"seed": 1, "star": "yellow", "planet": {"type": "continental", "size": 3, "id": 0}, "moons": [{"type": "barren", "id": 1}],
		"belt": false, "station": "", "wrecks": 0, "siege": false}

var scene: Dictionary = {}
var detail := 1             # 0 sobre, 1 normal, 2 riche
## Décalage de caméra (pixels) : chaque couche le suit selon sa profondeur.
var cam := Vector2.ZERO:
	set(v):
		cam = v
		_apply_cam()
var foreground: Control      # à ajouter par la vue au-dessus des vaisseaux
## Position de l'étoile à l'écran (sert à éclairer planète et vaisseaux).
var star_pos := Vector2.ZERO

var _bg: Control
var _bg_rect: ColorRect
var _star: ColorRect
var _moons: Array[Control] = []
var _planet: Control
var _objects: Control
var _rng := RandomNumberGenerator.new()
var _asteroids: Array = []   # [position, rayon, graine, profondeur]
var _wrecks: Array = []      # [position, longueur, angle, graine]
var _station_pos := Vector2.ZERO
var _planet_center := Vector2.ZERO
var _planet_radius := 0.0
var _fg_rocks: Array = []
var _base := {}              # position de repos de chaque couche


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	foreground = Control.new()
	foreground.name = "PremierPlan"
	foreground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foreground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	foreground.draw.connect(_draw_foreground)


static func cfg() -> Dictionary:
	return GameData.battle_visuals()


## Couleur et puissance de la lumière de l'étoile de l'arène.
static func star_light(star: String) -> Dictionary:
	var s: Dictionary = cfg().get("stars", {}).get(star, cfg().get("stars", {}).get("yellow", {}))
	var l: Array = s.get("light", [1, 1, 1])
	return {"color": Color(float(l[0]), float(l[1]), float(l[2])), "power": float(s.get("power", 1.0)) ,
			"ambient": float(s.get("ambient", 0.3))}


## Chemin de l'asset final d'un élément, s'il existe (sinon "").
static func art_path(kind: String, id: String) -> String:
	var pattern := String(cfg().get("art", {}).get(kind, ""))
	if pattern == "":
		return ""
	var path := pattern % id
	return path if ResourceLoader.exists(path) else ""


func setup(value: Dictionary, detail_level: int) -> void:
	scene = value if not value.is_empty() else DEFAULT_SCENE.duplicate(true)
	detail = detail_level
	for c in get_children():
		c.queue_free()
	_moons.clear()
	_rng.seed = int(scene.get("seed", 1))
	var star := String(scene.get("star", "yellow"))
	var star_cfg: Dictionary = cfg().get("stars", {}).get(star, {})
	# Fond : une image peinte si elle existe, sinon étoiles et nébuleuse procédurales.
	var bg_art := art_path("space_background", star)
	if bg_art != "":
		var tr := TextureRect.new()
		tr.texture = load(bg_art)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg = tr
	else:
		_bg_rect = ColorRect.new()
		var m := ShaderMaterial.new()
		m.shader = BACKDROP_SHADER
		var neb: Array = star_cfg.get("nebula", [[0.3, 0.2, 0.45], [0.7, 0.5, 0.3]])
		var nc: Array = neb[_rng.randi() % neb.size()]
		m.set_shader_parameter("tint", Color(float(nc[0]), float(nc[1]), float(nc[2])))
		m.set_shader_parameter("seed", _rng.randf_range(0.0, 7.0))
		_bg_rect.material = m
		_bg = _bg_rect
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_star = ColorRect.new()
	var sm := ShaderMaterial.new()
	sm.shader = STAR_SHADER
	var look: Dictionary = SystemView.STAR_LOOKS.get(star, SystemView.STAR_LOOKS["yellow"])
	sm.set_shader_parameter("star_color", GalaxyView.STAR_COLORS.get(star, Color.WHITE))
	sm.set_shader_parameter("mode", int(look["mode"]))
	sm.set_shader_parameter("core", float(look["core"]))
	_star.material = sm
	_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_star)
	for mt in scene.get("moons", []):
		var md: Dictionary = mt if mt is Dictionary else {"type": String(mt), "id": _rng.randi_range(1, 9999)}
		var moon := _planet_node(String(md.get("type", "barren")), 1, int(md.get("id", 0)))
		add_child(moon)
		_moons.append(moon)
	var pl: Dictionary = scene.get("planet", {})
	_planet = null
	if not pl.is_empty():
		_planet = _planet_node(String(pl.get("type", "barren")), int(pl.get("size", 3)), int(pl.get("id", 0)))
		add_child(_planet)
	_objects = Control.new()
	_objects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objects.draw.connect(_draw_objects.bind(_objects))
	add_child(_objects)
	_layout()


## Planète : image finale si elle existe, sinon le shader de la vue système.
func _planet_node(ptype: String, psize: int, pid: int) -> Control:
	var art := art_path("planet", ptype)
	if art != "":
		var tr := TextureRect.new()
		tr.texture = load(art)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_meta("body", 0.95)
		return tr
	var p := Planet.new()
	p.id = pid
	p.type = ptype
	p.size = psize
	p.system_id = int(scene.get("seed", 0)) % 97
	var cr := ColorRect.new()
	cr.material = SystemView.make_planet_material(p)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.set_meta("body", float((cr.material as ShaderMaterial).get_shader_parameter("body")))
	return cr


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not scene.is_empty():
		_layout()


## Place les couches pour la taille actuelle (la graine fixe les choix, la taille les distances).
func _layout() -> void:
	if _bg == null:
		return
	var w := size.x if size.x > 0 else 1600.0
	var h := size.y if size.y > 0 else 900.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(scene.get("seed", 1)) + 17
	var margin := 80.0
	_bg.position = Vector2(-margin, -margin)
	_bg.size = Vector2(w, h) + Vector2(margin, margin) * 2.0
	# L'étoile en haut, d'un côté ; la planète en bas, de l'autre : la lumière traverse la bataille.
	var star_left := rng.randf() < 0.5
	var star_cfg: Dictionary = cfg().get("stars", {}).get(String(scene.get("star", "yellow")), {})
	var sr := float(star_cfg.get("size", 40)) * h / 900.0
	var look: Dictionary = SystemView.STAR_LOOKS.get(String(scene.get("star", "yellow")), SystemView.STAR_LOOKS["yellow"])
	star_pos = Vector2(w * (rng.randf_range(0.08, 0.2) if star_left else rng.randf_range(0.8, 0.92)), h * rng.randf_range(0.1, 0.2))
	var star_side := sr / float(look["core"]) * 2.0
	_star.size = Vector2(star_side, star_side)
	_star.position = star_pos - _star.size * 0.5
	if _bg_rect:
		(_bg_rect.material as ShaderMaterial).set_shader_parameter("size", _bg.size)
		(_bg_rect.material as ShaderMaterial).set_shader_parameter("focus", star_pos + Vector2(margin, margin))
	var pcfg: Dictionary = cfg().get("planet", {})
	var siege := bool(scene.get("siege", false))
	if _planet:
		var radii: Array = pcfg.get("radius", [0.3])
		var psize := clampi(int(scene.get("planet", {}).get("size", 3)), 1, radii.size())
		_planet_radius = h * (float(pcfg.get("siege_radius", 0.6)) if siege else float(radii[psize - 1]))
		var px := w * (rng.randf_range(0.68, 0.82) if star_left else rng.randf_range(0.18, 0.32))
		if siege:
			px = w * 0.5 + (w * 0.12 if star_left else -w * 0.12)
		_planet_center = Vector2(px, h + _planet_radius * (0.2 if siege else 0.5))
		_place_body(_planet, _planet_center, _planet_radius)
	for i in _moons.size():
		var mr := h * rng.randf_range(0.025, 0.05)
		var mpos := Vector2(w * (rng.randf_range(0.36, 0.46) if i % 2 == 0 else rng.randf_range(0.54, 0.64)), h * rng.randf_range(0.25, 0.34))
		_place_body(_moons[i], mpos, mr)
	# Objets : ceinture, station, épaves du cimetière.
	_asteroids.clear()
	if bool(scene.get("belt", false)):
		var counts: Array = cfg().get("objects", {}).get("belt", {}).get("count", [20, 40, 60])
		var n := int(counts[clampi(detail, 0, counts.size() - 1)])
		var band_y := h * rng.randf_range(0.3, 0.42)
		for k in n:
			var x := rng.randf_range(-40.0, w + 40.0)
			var y := band_y + rng.randf_range(-h * 0.07, h * 0.07) + sin(x / w * PI * 2.0) * h * 0.03
			_asteroids.append([Vector2(x, y), rng.randf_range(2.0, 9.0) * h / 900.0, rng.randi(), rng.randf_range(0.6, 1.0)])
	_wrecks.clear()
	var wmax: Array = cfg().get("objects", {}).get("wrecks_max", [6, 14, 24])
	var nw := mini(int(scene.get("wrecks", 0)), int(wmax[clampi(detail, 0, wmax.size() - 1)]))
	for k in nw:
		_wrecks.append([Vector2(rng.randf_range(w * 0.05, w * 0.95), rng.randf_range(h * 0.22, h * 0.86)),
				rng.randf_range(10.0, 26.0) * h / 900.0, rng.randf_range(0.0, TAU), rng.randi()])
	# Station en orbite, sur le bord de la planète tourné vers l'extérieur de l'écran.
	var out_a := -PI * 0.5 + (0.55 if _planet_center.x > w * 0.5 else -0.55)
	_station_pos = _planet_center + Vector2(cos(out_a), sin(out_a)) * (_planet_radius + h * 0.05)
	if _planet == null:
		_station_pos = Vector2(w * 0.5, h * 0.8)
	_fg_rocks.clear()
	if detail >= 1:
		for k in 3 + detail * 2:
			var left := k % 2 == 0
			_fg_rocks.append([Vector2(w * (rng.randf_range(-0.04, 0.1) if left else rng.randf_range(0.9, 1.04)), h * rng.randf_range(0.9, 1.04)),
					rng.randf_range(12.0, 34.0) * h / 900.0, rng.randi()])
	_base = {"bg": _bg.position, "star": _star.position, "planet": _planet.position if _planet else Vector2.ZERO}
	for i in _moons.size():
		_base["moon%d" % i] = _moons[i].position
	_apply_cam()


func _place_body(node: Control, center: Vector2, radius: float) -> void:
	var body := float(node.get_meta("body", 0.8))
	var side := radius / body * 2.0
	node.size = Vector2(side, side)
	node.position = center - node.size * 0.5
	var mat := node.material as ShaderMaterial
	if mat and mat.shader and mat.get_shader_parameter("light_dir") != null:
		var to_star := star_pos - center
		var light := Vector3(to_star.x, to_star.y, 0.0).normalized()
		light.z = 0.3
		mat.set_shader_parameter("light_dir", light)


func _apply_cam() -> void:
	if _base.is_empty():
		return
	var k := float(cfg().get("detail", {}).get("parallax", [0, 1, 1])[clampi(detail, 0, 2)])
	_bg.position = _base["bg"] + cam * PARALLAX["bg"] * k
	_star.position = _base["star"] + cam * PARALLAX["star"] * k
	for i in _moons.size():
		_moons[i].position = _base["moon%d" % i] + cam * PARALLAX["moons"] * k
	if _planet:
		_planet.position = _base["planet"] + cam * PARALLAX["planet"] * k
	_objects.position = cam * PARALLAX["objects"] * k
	_objects.queue_redraw()
	if foreground:
		foreground.position = cam * PARALLAX["fg"] * k
		foreground.queue_redraw()


# --- Objets dessinés -----------------------------------------------------------------------------

## Polygone irrégulier (rocher, épave) tiré d'une graine.
static func rock(center: Vector2, r: float, seed_value: int, points := 7) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := PackedVector2Array()
	for i in points:
		var a := TAU * float(i) / float(points) + rng.randf_range(-0.25, 0.25)
		pts.append(center + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.65, 1.15))
	return pts


func _draw_objects(ci: Control) -> void:
	var light := star_light(String(scene.get("star", "yellow")))
	var lc: Color = light["color"]
	for a: Array in _asteroids:
		var p: Vector2 = a[0]
		var r := float(a[1])
		var shade := 0.22 + 0.2 * float(a[3])
		var pts := rock(p, r, int(a[2]))
		ci.draw_colored_polygon(pts, Color(shade, shade * 0.95, shade * 0.9))
		var lit_off := (star_pos - p).normalized() * r * 0.3
		ci.draw_colored_polygon(rock(p + lit_off, r * 0.55, int(a[2]) + 1, 6), Color(lc.r, lc.g, lc.b, 0.22))
	for wk: Array in _wrecks:
		_draw_wreck(ci, wk[0], float(wk[1]), float(wk[2]), int(wk[3]))
	match String(scene.get("station", "")):
		"bastion":
			_draw_station(ci, _station_pos, 30.0, true)
		"colony", "outpost":
			_draw_station(ci, _station_pos, 18.0, false)
	if bool(scene.get("siege", false)) and _planet:
		var n := int(cfg().get("objects", {}).get("defenses", 4))
		for i in n:
			var a := PI * 1.2 + PI * 0.6 * (float(i) + 0.5) / float(n)
			var p := _planet_center + Vector2(cos(a), sin(a)) * (_planet_radius * 1.08)
			_draw_platform(ci, p)


## Épave : coque brisée en deux morceaux sombres, avec une braise qui rougeoie.
func _draw_wreck(ci: CanvasItem, p: Vector2, length: float, angle: float, seed_value: int) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	var nrm := dir.orthogonal()
	var a := PackedVector2Array([p - dir * length * 0.5 + nrm * length * 0.12, p + nrm * length * 0.18, p - nrm * length * 0.05,
			p - dir * length * 0.5 - nrm * length * 0.12])
	var b := PackedVector2Array([p + dir * length * 0.1 + nrm * length * 0.1, p + dir * length * 0.55, p + dir * length * 0.12 - nrm * length * 0.16])
	ci.draw_colored_polygon(a, Color(0.16, 0.16, 0.18, 0.85))
	ci.draw_colored_polygon(b, Color(0.2, 0.19, 0.2, 0.85))
	if seed_value % 3 == 0:
		ci.draw_circle(p + nrm * length * 0.04, 1.6, Color(1.0, 0.45, 0.2, 0.7))


## Station orbitale stylisée : anneau, moyeu et bras (bastion plus grand, avec tourelles).
func _draw_station(ci: Control, p: Vector2, r: float, armed: bool) -> void:
	var owner_col := Color(0.75, 0.8, 0.9)
	ci.draw_arc(p, r, 0.0, TAU, 40, Color(0.55, 0.6, 0.68), 3.0, true)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		ci.draw_line(p, p + Vector2(cos(a), sin(a)) * r, Color(0.45, 0.5, 0.56), 2.0)
	ci.draw_circle(p, r * 0.3, Color(0.38, 0.42, 0.5))
	ci.draw_circle(p, r * 0.12, Color(owner_col.r, owner_col.g, 1.0, 0.9))
	if armed:
		for i in 6:
			var a := TAU * float(i) / 6.0
			ci.draw_circle(p + Vector2(cos(a), sin(a)) * r, 3.0, Color(0.85, 0.7, 0.4))


func _draw_platform(ci: Control, p: Vector2) -> void:
	ci.draw_rect(Rect2(p - Vector2(7, 3), Vector2(14, 6)), Color(0.5, 0.52, 0.58))
	ci.draw_line(p - Vector2(12, 0), p + Vector2(12, 0), Color(0.4, 0.55, 0.85, 0.8), 1.5)
	ci.draw_circle(p, 2.0, Color(1.0, 0.4, 0.3))


func _draw_foreground() -> void:
	for r: Array in _fg_rocks:
		var pts := rock(r[0], float(r[1]), int(r[2]), 12)
		foreground.draw_colored_polygon(pts, Color(0.035, 0.035, 0.045, 0.92))
		var edge := (star_pos - Vector2(r[0])).normalized() * float(r[1]) * 0.12
		foreground.draw_polyline(rock(Vector2(r[0]) + edge, float(r[1]) * 0.98, int(r[2]), 12), Color(0.5, 0.45, 0.4, 0.25), 1.5)
