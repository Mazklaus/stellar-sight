class_name SystemView
extends Control
## Vue d'un système stellaire : l'étoile au centre, les orbites vues en légère plongée
## et les planètes qui tournent, éclairées par leur étoile.
## Purement visuelle : elle lit l'état sans jamais le modifier et signale les clics sur les planètes.
## Le mouvement des orbites est décoratif (temps réel), il n'a aucun effet sur la partie.

signal planet_clicked(planet_id: int)

const PLANET_SHADER := preload("res://shaders/planet.gdshader")
const STAR_SHADER := preload("res://shaders/star.gdshader")
const BACKDROP_SHADER := preload("res://shaders/space_backdrop.gdshader")

## Aplatissement des orbites : 1 = vue de dessus, plus petit = vue rasante.
const TILT := 0.42
## Rayon du cœur de l'étoile (pixels à l'échelle 1) et part du rectangle qu'il occupe dans le shader.
const STAR_LOOKS := {
	"yellow": {"radius": 40.0, "core": 0.2, "mode": 0},
	"red": {"radius": 32.0, "core": 0.2, "mode": 0},
	"white": {"radius": 20.0, "core": 0.16, "mode": 0},
	"blue_giant": {"radius": 56.0, "core": 0.22, "mode": 0},
	"neutron": {"radius": 9.0, "core": 0.06, "mode": 1},
	"black_hole": {"radius": 24.0, "core": 0.16, "mode": 2},
}
## Apparence de chaque type de planète (paramètres du shader planet.gdshader).
const PLANET_LOOKS := {
	"continental": {"c_deep": Color(0.03, 0.1, 0.3), "c_shallow": Color(0.1, 0.38, 0.62), "c_low": Color(0.22, 0.45, 0.18),
		"c_high": Color(0.58, 0.52, 0.34), "atmo": Color(0.45, 0.7, 1.0), "sea_level": 0.52, "ice": 0.12, "clouds": 0.6},
	"ocean": {"c_deep": Color(0.02, 0.07, 0.28), "c_shallow": Color(0.08, 0.36, 0.66), "c_low": Color(0.78, 0.72, 0.5),
		"c_high": Color(0.3, 0.55, 0.25), "atmo": Color(0.4, 0.72, 1.0), "sea_level": 0.68, "ice": 0.08, "clouds": 0.7},
	"desert": {"c_deep": Color(0.5, 0.3, 0.15), "c_shallow": Color(0.6, 0.4, 0.2), "c_low": Color(0.72, 0.46, 0.22),
		"c_high": Color(0.96, 0.8, 0.55), "atmo": Color(1.0, 0.75, 0.45), "atmo_strength": 0.5, "sea_level": -1.0,
		"clouds": 0.12, "relief_scale": 3.2},
	"arctic": {"c_deep": Color(0.18, 0.32, 0.52), "c_shallow": Color(0.42, 0.58, 0.74), "c_low": Color(0.72, 0.82, 0.92),
		"c_high": Color(0.95, 0.98, 1.0), "atmo": Color(0.7, 0.85, 1.0), "sea_level": 0.36, "ice": 0.45, "clouds": 0.3},
	"toxic": {"c_deep": Color(0.22, 0.28, 0.05), "c_shallow": Color(0.38, 0.44, 0.1), "c_low": Color(0.5, 0.56, 0.14),
		"c_high": Color(0.72, 0.66, 0.2), "atmo": Color(0.72, 0.92, 0.2), "sea_level": 0.45, "clouds": 0.85,
		"cloud_color": Color(0.82, 0.86, 0.32)},
	"gas_giant": {"mode": 1, "c_deep": Color(0.72, 0.56, 0.4), "c_shallow": Color(0.93, 0.86, 0.72), "c_low": Color(0.6, 0.38, 0.25),
		"c_high": Color(0.86, 0.45, 0.3), "atmo": Color(1.0, 0.86, 0.62), "atmo_strength": 0.4},
	"barren": {"mode": 2, "c_deep": Color(0.27, 0.26, 0.25), "c_shallow": Color(0.5, 0.48, 0.45), "c_low": Color(0.18, 0.17, 0.16),
		"c_high": Color(0.66, 0.63, 0.58), "atmo": Color(0.6, 0.6, 0.6), "atmo_strength": 0.05},
	"asteroids": {"mode": 2, "c_deep": Color(0.3, 0.27, 0.24), "c_shallow": Color(0.5, 0.46, 0.4), "c_low": Color(0.2, 0.18, 0.16),
		"c_high": Color(0.62, 0.58, 0.52), "atmo": Color(0.5, 0.5, 0.5), "atmo_strength": 0.0, "relief_scale": 4.0},
	"gaia": {"c_deep": Color(0.02, 0.12, 0.32), "c_shallow": Color(0.1, 0.48, 0.6), "c_low": Color(0.2, 0.55, 0.22),
		"c_high": Color(0.42, 0.68, 0.3), "atmo": Color(0.5, 0.85, 1.0), "sea_level": 0.48, "ice": 0.04, "clouds": 0.55},
	"ecumenopole": {"c_deep": Color(0.16, 0.15, 0.17), "c_shallow": Color(0.3, 0.28, 0.3), "c_low": Color(0.46, 0.42, 0.36),
		"c_high": Color(0.9, 0.76, 0.42), "atmo": Color(1.0, 0.82, 0.5), "atmo_strength": 0.45, "sea_level": -1.0,
		"clouds": 0.15, "relief_scale": 6.0},
}
## Variantes de couleurs des géantes gazeuses (choisies d'après la planète).
const GAS_PALETTES := [
	[Color(0.72, 0.56, 0.4), Color(0.93, 0.86, 0.72), Color(0.6, 0.38, 0.25), Color(0.86, 0.45, 0.3), Color(1.0, 0.86, 0.62)],
	[Color(0.3, 0.42, 0.72), Color(0.72, 0.84, 0.96), Color(0.45, 0.6, 0.88), Color(0.92, 0.95, 1.0), Color(0.55, 0.75, 1.0)],
	[Color(0.5, 0.36, 0.6), Color(0.86, 0.76, 0.9), Color(0.68, 0.45, 0.62), Color(0.98, 0.82, 0.62), Color(0.85, 0.7, 1.0)],
]
const ORBIT_COLOR := Color(0.6, 0.75, 1.0, 0.14)
const SELECT_COLOR := Color(0.38, 0.86, 0.92)
const ORBIT_SPEED := 0.07

var state: GameState
var system: StarSystem
var player := 0
var selected_planet := -1
var hovered_planet := -1
## Marges couvertes par l'interface (gauche, haut, droite, bas) : la scène se place dans le reste.
var margins := Vector4(0, 0, 0, 0)
## false : seul le fond est dessiné (la vue de gestion s'affiche par-dessus).
var show_scene := true:
	set(value):
		show_scene = value
		if _star:
			_star.visible = value
			for b in _bodies.values():
				b.visible = value
			queue_redraw()

var _backdrop: ColorRect
var _star: ColorRect
var _overlay: Control
var _bodies := {}
var _belts := {}
var _time := 0.0
var _font: Font
var _title_font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_font = UiTheme.body_font()
	_title_font = UiTheme.title_font()
	# Le fond est un frère placé avant nous : il doit passer sous les orbites que l'on dessine.
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.material = _material(BACKDROP_SHADER)
	_backdrop.show_behind_parent = true
	add_child(_backdrop)
	_star = ColorRect.new()
	_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_star.material = _material(STAR_SHADER)
	add_child(_star)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Affiche un système (ou rien avec null).
func set_system(value_state: GameState, s: StarSystem, viewer: int) -> void:
	state = value_state
	system = s
	player = viewer
	hovered_planet = -1
	for b in _bodies.values():
		b.queue_free()
	_bodies.clear()
	_belts.clear()
	if s == null:
		return
	var look: Dictionary = STAR_LOOKS.get(s.star_type, STAR_LOOKS["yellow"])
	var star_mat := _star.material as ShaderMaterial
	star_mat.set_shader_parameter("star_color", GalaxyView.STAR_COLORS.get(s.star_type, Color.WHITE))
	star_mat.set_shader_parameter("mode", int(look["mode"]))
	star_mat.set_shader_parameter("core", float(look["core"]))
	var bd := _backdrop.material as ShaderMaterial
	bd.set_shader_parameter("tint", GalaxyView.STAR_COLORS.get(s.star_type, Color.WHITE))
	bd.set_shader_parameter("seed", fmod(float(s.id) * 0.731, 7.0))
	for pid in s.planet_ids:
		var p := state.galaxy.get_planet(pid)
		var body := ColorRect.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.material = make_planet_material(p)
		body.visible = show_scene
		add_child(body)
		_bodies[pid] = body
		if p.type == "asteroids":
			_belts[pid] = _make_belt(p)
	move_child(_overlay, get_child_count() - 1)
	_update_layout()
	queue_redraw()


func _process(delta: float) -> void:
	if system == null or not is_visible_in_tree():
		return
	_time += delta
	_update_layout()
	queue_redraw()
	_overlay.queue_redraw()


# --- Géométrie -------------------------------------------------------------------------------

## Rectangle libre pour la scène, entre les panneaux.
func scene_rect() -> Rect2:
	var r := Rect2(margins.x, margins.y, size.x - margins.x - margins.z, size.y - margins.y - margins.w)
	r.size = r.size.max(Vector2(1, 1))
	return r


func scale_factor() -> float:
	var r := scene_rect()
	return clampf(minf(r.size.y / 640.0, r.size.x / 1100.0), 0.25, 1.4)


func star_center() -> Vector2:
	return scene_rect().get_center()


func star_radius() -> float:
	if system == null:
		return 0.0
	return float(STAR_LOOKS.get(system.star_type, STAR_LOOKS["yellow"])["radius"]) * scale_factor()


## Demi-grand axe (horizontal) de l'orbite de rang index.
func orbit_radius(index: int) -> float:
	var r := scene_rect()
	var outer := minf(r.size.x * 0.5 - 70.0 * scale_factor(), (r.size.y * 0.5 - 50.0 * scale_factor()) / TILT)
	var inner := maxf(star_radius() * 2.0 + 40.0 * scale_factor(), outer * 0.3)
	outer = maxf(outer, inner + 1.0)
	var n := maxi(system.planet_count if system else 1, 1)
	if n == 1:
		return (inner + outer) * 0.5
	return lerpf(inner, outer, float(index) / float(n - 1))


func _angle(p: Planet) -> float:
	var r0 := orbit_radius(0)
	var r := orbit_radius(p.index)
	var base := fmod(float(p.id) * 2.39996 + float(p.system_id) * 0.7, TAU)
	return base + _time * ORBIT_SPEED * pow(r0 / r, 1.5)


## Position à l'écran du centre d'une planète.
func planet_position(pid: int) -> Vector2:
	var p := state.galaxy.get_planet(pid)
	var a := _angle(p)
	var rx := orbit_radius(p.index)
	return star_center() + Vector2(cos(a) * rx, sin(a) * rx * TILT)


## Profondeur de -1 (derrière l'étoile) à 1 (devant).
func planet_depth(pid: int) -> float:
	return sin(_angle(state.galaxy.get_planet(pid)))


## Rayon affiché d'une planète, perspective comprise.
func planet_radius(pid: int) -> float:
	var p := state.galaxy.get_planet(pid)
	var r := 11.0 + 6.0 * p.size
	if p.type == "gas_giant":
		r *= 1.3
	elif p.type == "asteroids":
		r = 9.0
	var depth := 0.86 + 0.14 * planet_depth(pid)
	return r * depth * scale_factor()


## Planète sous un point de l'écran (la plus en avant si plusieurs se recouvrent), ou -1.
func planet_at(pos: Vector2) -> int:
	if system == null or not show_scene:
		return -1
	var best := -1
	var best_depth := -INF
	for pid in system.planet_ids:
		var reach := planet_radius(pid) + 8.0
		if pos.distance_to(planet_position(pid)) <= reach and planet_depth(pid) > best_depth:
			best = pid
			best_depth = planet_depth(pid)
	return best


func _update_layout() -> void:
	if system == null:
		return
	var bd := _backdrop.material as ShaderMaterial
	bd.set_shader_parameter("size", size)
	bd.set_shader_parameter("focus", star_center())
	var look: Dictionary = STAR_LOOKS.get(system.star_type, STAR_LOOKS["yellow"])
	var star_size := star_radius() / float(look["core"]) * 2.0
	_star.size = Vector2(star_size, star_size)
	_star.position = star_center() - _star.size * 0.5
	# Ordre de dessin : fond, planètes de l'arrière, étoile, planètes de l'avant, annotations.
	var order: Array = system.planet_ids.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool: return planet_depth(a) < planet_depth(b))
	var nodes: Array[Node] = [_backdrop]
	var star_placed := false
	for pid in order:
		if not star_placed and planet_depth(pid) >= 0.0:
			nodes.append(_star)
			star_placed = true
		nodes.append(_bodies[pid])
	if not star_placed:
		nodes.append(_star)
	nodes.append(_overlay)
	for i in nodes.size():
		if nodes[i].get_index() != i:
			move_child(nodes[i], i)
	for pid in order:
		var body: ColorRect = _bodies[pid]
		var mat := body.material as ShaderMaterial
		var side := planet_radius(pid) / float(mat.get_shader_parameter("body")) * 2.0
		body.size = Vector2(side, side)
		var pos := planet_position(pid)
		body.position = pos - body.size * 0.5
		var to_star := star_center() - pos
		var light := Vector3(to_star.x, to_star.y, 0.0).normalized() if to_star.length() > 1.0 else Vector3(0, 0, 1)
		light.z = 0.35
		mat.set_shader_parameter("light_dir", light)


# --- Dessin ----------------------------------------------------------------------------------

func _draw() -> void:
	if system == null or not show_scene:
		return
	var c := star_center()
	for pid in system.planet_ids:
		var p := state.galaxy.get_planet(pid)
		var rx := orbit_radius(p.index)
		var col := ORBIT_COLOR
		var owner := _owner_of(pid)
		if owner:
			col = Color(owner.color(), 0.32)
		if pid == selected_planet:
			col = Color(SELECT_COLOR, 0.55)
		elif pid == hovered_planet:
			col = Color(1, 1, 1, 0.3)
		_draw_ellipse(c, rx, rx * TILT, col, 1.5 if pid == selected_planet else 1.0)
		if _belts.has(pid):
			_draw_belt(pid, c, rx)


func _draw_ellipse(c: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var n := 96
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, width, true)


## Ceinture d'astéroïdes : des cailloux répartis autour de l'orbite.
func _make_belt(p: Planet) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([p.id, "belt"])
	var rocks := PackedVector3Array()
	for _i in 220:
		rocks.append(Vector3(rng.randf() * TAU, rng.randf_range(-1.0, 1.0), rng.randf_range(0.6, 2.0)))
	return rocks


func _draw_belt(pid: int, c: Vector2, rx: float) -> void:
	var spread := 16.0 * scale_factor()
	var drift := _time * ORBIT_SPEED * 0.4
	var rocks: PackedVector3Array = _belts[pid]
	for rock in rocks:
		var a := rock.x + drift
		var r := rx + rock.y * spread
		var pos := c + Vector2(cos(a) * r, sin(a) * r * TILT)
		var depth := 0.55 + 0.45 * sin(a)
		draw_circle(pos, rock.z * scale_factor() * (0.7 + 0.3 * depth), Color(0.72, 0.66, 0.58, 0.35 + 0.45 * depth))


## Annotations au-dessus de tout : propriété et population, sélection, et une fiche accrochée
## à chaque planète (nom, taille et type, disponibilité ; barres de potentiel pour la planète
## survolée ou choisie).
func _draw_overlay() -> void:
	if system == null or not show_scene:
		return
	var sf := scale_factor()
	for pid in system.planet_ids:
		var pos := planet_position(pid)
		var r := planet_radius(pid)
		var c: Colony = state.colonies.get(pid)
		if c:
			_draw_claim_ring(pid, c, pos, r + 5.0 * sf)
		if pid == selected_planet:
			_draw_brackets(pos, r + 11.0 * sf, SELECT_COLOR)
		elif pid == hovered_planet:
			_overlay.draw_arc(pos, r + 9.0 * sf, 0.0, TAU, 48, Color(1, 1, 1, 0.6), 1.5, true)
	# Fiches dessinées de l'arrière vers l'avant, celle de la planète choisie en dernier.
	var order: Array = system.planet_ids.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool:
		var ka := planet_depth(a) + (4.0 if a == selected_planet else (2.0 if a == hovered_planet else 0.0))
		var kb := planet_depth(b) + (4.0 if b == selected_planet else (2.0 if b == hovered_planet else 0.0))
		return ka < kb)
	for pid in order:
		_draw_card(pid, sf)


## Anneau de propriété : une colonie montre sa population en arc (comme une jauge),
## un avant-poste un anneau plein, une fondation un anneau pointillé qui tourne.
func _draw_claim_ring(pid: int, c: Colony, pos: Vector2, radius: float) -> void:
	var owner := state.get_empire(c.owner)
	var col := owner.color()
	if not c.is_established():
		for i in 12:
			var a := TAU * i / 12.0 + _time * 0.3
			_overlay.draw_arc(pos, radius, a, a + TAU / 24.0, 6, col, 2.0, true)
	elif c.is_colony():
		var p := state.galaxy.get_planet(pid)
		var cap := maxi(Economy.max_pop(state, p, c.owner, c.buildings), 1)
		var frac := clampf(float(c.population) / float(cap), 0.0, 1.0)
		_overlay.draw_arc(pos, radius, 0.0, TAU, 48, Color(col, 0.25), 3.0, true)
		if frac > 0.0:
			_overlay.draw_arc(pos, radius, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, col, 3.0, true)
	else:
		_overlay.draw_arc(pos, radius, 0.0, TAU, 48, col, 1.5, true)
	if owner.capital_planet == pid:
		var top := pos + Vector2(0, -radius - 9.0)
		var d := 6.0 * scale_factor()
		_overlay.draw_colored_polygon(PackedVector2Array([top + Vector2(0, -d), top + Vector2(d * 0.7, 0),
				top + Vector2(0, d), top + Vector2(-d * 0.7, 0)]), col)


## Fiche accrochée à une planète, reliée par un trait fin. Placée à droite de la planète,
## ou à gauche quand la planète est dans la moitié droite de la scène.
func _draw_card(pid: int, sf: float) -> void:
	var p := state.galaxy.get_planet(pid)
	var pos := planet_position(pid)
	var r := planet_radius(pid)
	var detailed := pid == selected_planet or pid == hovered_planet
	var fs := int(round(clampf(15.0 * sf, 10.0, 18.0)))
	var fs_small := maxi(fs - 3, 9)
	var avail := PlanetInfo.availability(state, p, player)
	var lines: Array[Dictionary] = [
		{"text": p.display_name(state.galaxy), "size": fs, "color": _name_color(pid)},
		{"text": "%s, taille %d" % [p.type_label(), p.size], "size": fs_small, "color": Color(0.8, 0.84, 0.94, 0.85)},
		{"text": avail["text"], "size": fs_small, "color": PlanetInfo.AVAILABILITY_COLORS.get(avail["kind"], Color.WHITE)},
	]
	var width := 0.0
	for l in lines:
		width = maxf(width, _font.get_string_size(l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, l["size"]).x)
	# Bilan mensuel d'une revendication établie, une pastille par ressource.
	var yields: Array[Dictionary] = []
	var c: Colony = state.colonies.get(pid)
	if c and c.is_established():
		var yl := Economy.colony_yields(state, c)
		for res in GameData.resource_ids():
			var v := int(yl["gross"][res]) - int(yl["upkeep"][res])
			if v != 0:
				yields.append({"r": res, "v": v})
	var yields_h := 0.0
	if not yields.is_empty():
		width = maxf(width, yields.size() * 34.0)
		yields_h = float(fs_small) + 6.0
	var pips_h := 0.0
	var pip := 6.0
	if detailed:
		width = maxf(width, 22.0 + 5.0 * (pip + 2.0) + 4.0)
		pips_h = GameData.resource_ids().size() * (pip + 3.0) + 4.0
	var pad := 6.0
	var h := 0.0
	for l in lines:
		h += int(l["size"]) + 3
	var size_card := Vector2(width + pad * 2.0, h + yields_h + pips_h + pad * 2.0)
	var right := pos.x < star_center().x + orbit_radius(system.planet_count - 1) * 0.35
	var anchor := pos + Vector2((r + 14.0 * sf) * (1.0 if right else -1.0), -r * 0.6)
	var top_left := Vector2(anchor.x if right else anchor.x - size_card.x, anchor.y - size_card.y * 0.35)
	var rect := Rect2(top_left, size_card)
	var bg := Color(0.02, 0.03, 0.05, 0.72 if detailed else 0.5)
	_overlay.draw_rect(rect, bg)
	var edge := Color(1, 1, 1, 0.35 if detailed else 0.18)
	if c:
		edge = Color(state.get_empire(c.owner).color(), 0.9)
	if pid == selected_planet:
		edge = Color(SELECT_COLOR, 0.9)
	_overlay.draw_line(rect.position, rect.position + Vector2(0, rect.size.y), edge, 2.0)
	_overlay.draw_line(pos + Vector2((r + 2.0) * (1.0 if right else -1.0), -r * 0.4),
			Vector2(rect.position.x if right else rect.end.x, anchor.y), Color(edge, edge.a * 0.8), 1.0, true)
	var y := rect.position.y + pad
	for l in lines:
		y += int(l["size"])
		_overlay.draw_string(_font, Vector2(rect.position.x + pad, y), l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, l["size"], l["color"])
		y += 3
	if not yields.is_empty():
		y += float(fs_small) + 2.0
		var x := rect.position.x + pad
		for yv in yields:
			_overlay.draw_circle(Vector2(x + 3.5, y - fs_small * 0.35), 3.5, ResourceIcon.color_of(yv["r"]))
			_overlay.draw_string(_font, Vector2(x + 10.0, y), "%+d" % yv["v"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs_small, UiTheme.delta_color(yv["v"]))
			x += 34.0
		y += 4.0
	if detailed:
		y += 4
		var pot := PlanetInfo.potential(p)
		for res in GameData.resource_ids():
			var rc: Color = PlanetInfo.RESOURCE_COLORS.get(res, Color.WHITE)
			_overlay.draw_string(_font, Vector2(rect.position.x + pad, y + pip), GameData.resource_label(res, true).left(2),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(rc, 0.9))
			for i in 5:
				var cell := Rect2(rect.position.x + pad + 22.0 + i * (pip + 2.0), y + 1.0, pip, pip - 1.0)
				_overlay.draw_rect(cell, rc if i < int(pot[res]) else Color(rc, 0.14))
			y += pip + 3.0


func _name_color(pid: int) -> Color:
	if pid == selected_planet:
		return SELECT_COLOR
	var c: Colony = state.colonies.get(pid)
	return state.get_empire(c.owner).color().lightened(0.3) if c else UiTheme.TEXT


func _draw_brackets(pos: Vector2, r: float, col: Color) -> void:
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		_overlay.draw_arc(pos, r, a - 0.35, a + 0.35, 10, col, 2.5, true)


func _owner_of(pid: int) -> Empire:
	var c: Colony = state.colonies.get(pid)
	return state.get_empire(c.owner) if c else null


# --- Entrées ---------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion:
		var h := planet_at(motion.position)
		if h != hovered_planet:
			hovered_planet = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var pid := planet_at(mb.position)
		if pid >= 0:
			planet_clicked.emit(pid)
			accept_event()


# --- Matériaux -------------------------------------------------------------------------------

static func _material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


## Matériau d'une planète selon son type (partagé avec la vue de gestion).
static func make_planet_material(p: Planet) -> ShaderMaterial:
	var m := _material(PLANET_SHADER)
	var look: Dictionary = PLANET_LOOKS.get(p.type, PLANET_LOOKS["barren"])
	for key in look:
		m.set_shader_parameter(key, look[key])
	var seed_value := fposmod(float(p.id) * 0.6180339 + float(p.system_id) * 0.137, 1.0)
	m.set_shader_parameter("seed", seed_value)
	m.set_shader_parameter("spin", 0.025 + 0.03 * fposmod(seed_value * 7.0, 1.0))
	m.set_shader_parameter("body", 0.78 if look.get("atmo_strength", 0.8) > 0.1 else 0.92)
	if p.type == "gas_giant":
		var pal: Array = GAS_PALETTES[p.id % GAS_PALETTES.size()]
		for i in 5:
			m.set_shader_parameter(["c_deep", "c_shallow", "c_low", "c_high", "atmo"][i], pal[i])
	return m
