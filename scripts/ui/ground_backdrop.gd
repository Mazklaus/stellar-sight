class_name GroundBackdrop
extends Control
## Décor de la vue de bataille au sol (étude visuel des combats, bloc D) : champ de bataille vu en
## légère plongée, comme une table de jeu.
##   ciel (selon la planète, son étoile et l'heure) · flotte en orbite · horizon et reliefs ·
##   sol en perspective semé du décor du biome · ville et fortifications du défenseur (à droite) ·
##   dévastation · barges posées de l'assaillant (à gauche)
## Le décor est tiré de report["sc"] (BattleScene.ground_capture) et d'une graine fixe. Il ne bouge pas :
## la météo, le bombardement et les armées sont dessinés par la vue (GroundReplayPanel, ArmyLayer).
##
## Coordonnées du terrain : gx (pixels à l'échelle 1, de gauche à droite) et gz (0 = au loin, 1 = au
## premier plan) ; project() les ramène à l'écran.

const DEFAULT_SCENE := {"seed": 1, "star": "yellow", "ter": "continental", "pop": 6, "fort": 0, "fort_max": 0,
		"citadel": false, "bastion": false, "dev0": 0, "dev1": 0, "orbit": 4, "bombard": false}
const FAR_SCALE := 0.5
const NEAR_SCALE := 1.1

var scene: Dictionary = {}
var detail := 1
var time_of_day := "day"
var weather := "none"
var tint := Color.WHITE
var horizon_y := 300.0
var near_y := 790.0

var _rng := RandomNumberGenerator.new()
var _props: Array = []      # [kind, gx, gz, taille, graine]
var _city: Array = []       # [gx, gz, largeur, hauteur, graine]
var _walls: Array = []      # [gz, gx0, gx1]
var _craters: Array = []    # [gx, gz, rayon, feu]
var _barges: Array = []     # [gx, gz]
var _ridges: Array = []     # polylignes de l'horizon
var _ships: Array = []      # silhouettes dans le ciel
var _stars: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func cfg() -> Dictionary:
	return GameData.battle_visuals().get("ground", {})


static func biome(ter: String) -> Dictionary:
	var b: Dictionary = cfg().get("biomes", {})
	return b.get(ter, b.get("_default", {}))


static func _col(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))


func setup(value: Dictionary, detail_level: int) -> void:
	scene = value if not value.is_empty() else DEFAULT_SCENE.duplicate(true)
	detail = detail_level
	_rng.seed = int(scene.get("seed", 1))
	var times := ["day", "day", "dusk", "night"]
	time_of_day = times[_rng.randi() % times.size()]
	var tc: Array = cfg().get("times", {}).get(time_of_day, [1, 1, 1])
	tint = _col(tc)
	var ws: Array = biome(String(scene.get("ter", ""))).get("weather", ["none"])
	weather = String(ws[_rng.randi() % ws.size()])
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not scene.is_empty():
		_layout()


## Échelle des figurines à la profondeur gz.
func scale_at(gz: float) -> float:
	return lerpf(FAR_SCALE, NEAR_SCALE, clampf(gz, -0.2, 1.2))


## Point du terrain (gx, gz) à l'écran.
func project(gx: float, gz: float) -> Vector2:
	var cx := size.x * 0.5
	return Vector2(cx + (gx - cx) * scale_at(gz), lerpf(horizon_y + 14.0, near_y, gz))


func _layout() -> void:
	var w := size.x if size.x > 0 else 1600.0
	var h := size.y if size.y > 0 else 900.0
	horizon_y = h * 0.33
	near_y = h - 96.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(scene.get("seed", 1)) + 101
	var ter := String(scene.get("ter", ""))
	var props: Array = biome(ter).get("props", ["rocks"])
	# Décor semé (plus dense en Riche), à l'écart du centre du champ pour garder les armées lisibles.
	_props.clear()
	var n: int = [14, 30, 52][clampi(detail, 0, 2)]
	for k in n:
		var kind := String(props[rng.randi() % props.size()])
		var gz := rng.randf_range(0.0, 1.05)
		var gx := rng.randf_range(-w * 0.1, w * 1.1)
		if gz > 0.18 and gz < 0.92 and absf(gx - w * 0.5) < w * 0.3 and kind != "water" and kind != "craters":
			gz = rng.randf_range(0.0, 0.14) if rng.randf() < 0.6 else rng.randf_range(0.93, 1.08)
		_props.append([kind, gx, gz, rng.randf_range(0.6, 1.4), rng.randi()])
	_props.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) < float(b[2]))
	# Ville du défenseur : bâtiments au fond à droite, d'autant plus nombreux que la population est grande.
	_city.clear()
	var cc: Dictionary = cfg().get("city", {})
	var nb := mini(int(cc.get("max", 34)), 4 + int(scene.get("pop", 0)) * int(cc.get("per_pop", 3)))
	if ter == "ecumenopole":
		nb = int(cc.get("max", 34))
	for k in nb:
		_city.append([rng.randf_range(w * 0.72, w * 1.12), rng.randf_range(-0.08, 0.12), rng.randf_range(14.0, 34.0),
				rng.randf_range(24.0, 90.0) * (1.6 if ter == "ecumenopole" else 1.0), rng.randi()])
	_city.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	# Fortifications : un rempart en tranches devant les lignes du défenseur ; plus les défenses sont
	# entamées, plus les brèches sont larges.
	_walls.clear()
	var fmax := int(scene.get("fort_max", 0))
	if fmax > 0:
		var share := clampf(float(scene.get("fort", 0)) / float(fmax), 0.0, 1.0)
		if share > 0.05:
			for z in [0.14, 0.38, 0.62, 0.86]:
				_walls.append([z, w * 0.5 + 46.0, 0.05 + 0.065 * share])
	# Dévastation : cratères (et feux) du côté du défenseur.
	_craters.clear()
	var dev := int(scene.get("dev1", scene.get("dev0", 0)))
	for k in mini(40, dev / 2):
		_craters.append([rng.randf_range(w * 0.45, w * 1.05), rng.randf_range(0.0, 1.0), rng.randf_range(6.0, 18.0), rng.randf() < 0.35])
	# Barges posées de l'assaillant.
	_barges.clear()
	for k in 3 + detail:
		_barges.append([rng.randf_range(w * 0.02, w * 0.16), rng.randf_range(0.15, 0.95)])
	_barges.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	# Reliefs à l'horizon.
	_ridges.clear()
	for layer in 2:
		var pts := PackedVector2Array()
		var base := horizon_y - (18.0 if layer == 0 else 4.0)
		var amp := (46.0 if layer == 0 else 22.0) * (0.3 if ter == "ocean" or ter == "gas_giant" else 1.0)
		var x := -20.0
		while x <= w + 40.0:
			pts.append(Vector2(x, base - absf(sin(x * 0.006 + layer * 2.0 + float(scene.get("seed", 1)))) * amp - rng.randf_range(0.0, amp * 0.3)))
			x += 40.0
		_ridges.append(pts)
	# Flotte de l'assaillant en orbite, minuscule dans le ciel.
	_ships.clear()
	for k in mini(int(scene.get("orbit", 0)), 12):
		_ships.append(Vector2(rng.randf_range(w * 0.15, w * 0.6), rng.randf_range(h * 0.05, horizon_y - 70.0)))
	_stars.clear()
	if time_of_day == "night" or ter == "barren" or ter == "asteroids":
		for k in 90:
			_stars.append(Vector2(rng.randf_range(0.0, w), rng.randf_range(0.0, horizon_y - 30.0)))
	queue_redraw()


func _draw() -> void:
	if scene.is_empty():
		return
	var w := size.x
	var ter := String(scene.get("ter", ""))
	var bio := biome(ter)
	var sky: Array = bio.get("sky", [[0.2, 0.3, 0.5], [0.6, 0.7, 0.8]])
	var gr: Array = bio.get("ground", [[0.3, 0.3, 0.25], [0.4, 0.4, 0.33]])
	var top := _col(sky[0]) * tint
	var hor := _col(sky[1]) * tint
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, horizon_y), Vector2(0, horizon_y)]),
			PackedColorArray([top, top, hor, hor]))
	for s in _stars:
		draw_circle(s, 1.0, Color(1, 1, 1, 0.7))
	# Le soleil du système, bas sur l'horizon.
	var sun_col: Color = GalaxyView.STAR_COLORS.get(String(scene.get("star", "yellow")), Color.WHITE)
	var sun := Vector2(w * (0.2 if int(scene.get("seed", 1)) % 2 == 0 else 0.8), horizon_y * (0.42 if time_of_day == "day" else 0.82))
	if time_of_day != "night":
		draw_circle(sun, 60.0, Color(sun_col, 0.12))
		draw_circle(sun, 30.0, Color(sun_col, 0.3))
		draw_circle(sun, 16.0, sun_col.lightened(0.4))
	for p in _ships:
		draw_colored_polygon(PackedVector2Array([p + Vector2(7, 0), p + Vector2(-5, -2.5), p + Vector2(-5, 2.5)]), Color(0.05, 0.06, 0.08, 0.7))
		draw_circle(p + Vector2(-5, 0), 1.0, Color(0.6, 0.85, 1.0, 0.8))
	for i in _ridges.size():
		var pts: PackedVector2Array = _ridges[i]
		var poly := pts.duplicate()
		poly.append(Vector2(w + 40.0, horizon_y + 20.0))
		poly.append(Vector2(-20.0, horizon_y + 20.0))
		var rc := (_col(gr[1]).darkened(0.35 if i == 0 else 0.2)).lerp(hor, 0.45 if i == 0 else 0.25) * tint
		draw_colored_polygon(poly, Color(rc, 1.0))
	# Le sol en perspective.
	var far_c := _col(gr[1]) * tint
	var near_c := _col(gr[0]) * tint
	var y0 := horizon_y + 6.0
	draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, size.y), Vector2(0, size.y)]),
			PackedColorArray([far_c, far_c, near_c, near_c]))
	if ter == "gas_giant":
		_draw_cloud_sea(w)
	# Taches du sol, pour la matière.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(scene.get("seed", 1)) + 7
	for k in 60:
		var gz := rng.randf()
		var p := project(rng.randf_range(-w * 0.2, w * 1.2), gz)
		var s := scale_at(gz)
		draw_set_transform(p, 0.0, Vector2(1.0, 0.32))
		draw_circle(Vector2.ZERO, rng.randf_range(20.0, 70.0) * s, Color(near_c.darkened(0.25) if k % 2 == 0 else near_c.lightened(0.08), 0.25))
		draw_set_transform(Vector2.ZERO)
	for c in _craters:
		var p := project(float(c[0]), float(c[1]))
		var s := scale_at(float(c[1]))
		draw_set_transform(p, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, float(c[2]) * s, Color(0.08, 0.07, 0.06, 0.7))
		draw_arc(Vector2.ZERO, float(c[2]) * s, 0.0, TAU, 18, Color(0.3, 0.26, 0.22, 0.5), 1.5)
		draw_set_transform(Vector2.ZERO)
	for pr in _props:
		_draw_prop(String(pr[0]), float(pr[1]), float(pr[2]), float(pr[3]), int(pr[4]))
	_draw_city()
	for b in _barges:
		_draw_barge(float(b[0]), float(b[1]))


func _draw_cloud_sea(w: float) -> void:
	for k in 8:
		var y := horizon_y + 30.0 + k * 60.0
		draw_rect(Rect2(0, y, w, 26.0), Color(1, 0.95, 0.85, 0.06))


func _draw_prop(kind: String, gx: float, gz: float, k: float, seed_value: int) -> void:
	var p := project(gx, gz)
	var s := scale_at(gz) * k
	var bio := biome(String(scene.get("ter", "")))
	var gr: Array = bio.get("ground", [[0.3, 0.3, 0.25], [0.4, 0.4, 0.33]])
	var base := _col(gr[0]) * tint
	match kind:
		"trees":
			draw_rect(Rect2(p + Vector2(-1.5 * s, -8 * s), Vector2(3 * s, 8 * s)), Color(0.25, 0.18, 0.1) * tint)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -34 * s), p + Vector2(-10 * s, -6 * s), p + Vector2(10 * s, -6 * s)]),
					Color(base.darkened(0.35), 1.0))
		"flowers":
			for j in 4:
				draw_circle(p + Vector2((j - 1.5) * 4.0 * s, -2.0 * s), 1.6 * s, Color(0.95, 0.5 + 0.1 * j, 0.6, 0.9) * tint)
		"rocks":
			draw_colored_polygon(BattleBackdrop.rock(p + Vector2(0, -5 * s), 7.0 * s, seed_value, 7), Color(0.32, 0.3, 0.29) * tint)
		"dunes":
			draw_set_transform(p, 0.0, Vector2(1.0, 0.3))
			draw_circle(Vector2.ZERO, 46.0 * s, Color(base.lightened(0.12), 0.8))
			draw_set_transform(Vector2.ZERO)
		"ice":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-14 * s, 0), p + Vector2(-4 * s, -20 * s), p + Vector2(6 * s, -12 * s), p + Vector2(14 * s, 0)]),
					Color(0.86, 0.92, 1.0) * tint)
		"water":
			draw_set_transform(p, 0.0, Vector2(1.0, 0.28))
			draw_circle(Vector2.ZERO, 60.0 * s, Color(Color(0.16, 0.36, 0.56) * tint, 0.85))
			draw_set_transform(Vector2.ZERO)
		"pools":
			draw_set_transform(p, 0.0, Vector2(1.0, 0.3))
			draw_circle(Vector2.ZERO, 26.0 * s, Color(Color(0.56, 0.74, 0.14) * tint, 0.8))
			draw_set_transform(Vector2.ZERO)
		"craters":
			draw_set_transform(p, 0.0, Vector2(1.0, 0.35))
			draw_arc(Vector2.ZERO, 22.0 * s, 0.0, TAU, 20, Color(0.2, 0.18, 0.17, 0.7) * tint, 2.0)
			draw_set_transform(Vector2.ZERO)
		"platforms":
			draw_rect(Rect2(p + Vector2(-30 * s, -4 * s), Vector2(60 * s, 6 * s)), Color(0.5, 0.48, 0.5) * tint)
			draw_rect(Rect2(p + Vector2(-2 * s, 2 * s), Vector2(4 * s, 30 * s)), Color(0.35, 0.33, 0.35) * tint)
		"towers":
			draw_rect(Rect2(p + Vector2(-8 * s, -60 * s), Vector2(16 * s, 60 * s)), Color(0.26, 0.25, 0.28) * tint)
			for j in 5:
				draw_rect(Rect2(p + Vector2(-5 * s, (-55 + j * 11) * s), Vector2(10 * s, 3 * s)), Color(1.0, 0.8, 0.45, 0.6))


func _draw_city() -> void:
	var night := time_of_day != "day"
	for b in _city:
		var p := project(float(b[0]), float(b[1]))
		var s := scale_at(float(b[1]))
		var bw := float(b[2]) * s
		var bh := float(b[3]) * s
		var r := Rect2(p - Vector2(bw * 0.5, bh), Vector2(bw, bh))
		draw_rect(r, Color(0.3, 0.31, 0.35) * tint)
		draw_rect(Rect2(r.position, Vector2(bw * 0.25, bh)), Color(0.22, 0.23, 0.27) * tint)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(b[4])
		var rows := int(bh / (6.0 * s))
		for j in rows:
			if rng.randf() < (0.55 if night else 0.3):
				draw_rect(Rect2(r.position + Vector2(bw * 0.4, 3.0 * s + j * 6.0 * s), Vector2(bw * 0.4, 2.0 * s)),
						Color(1.0, 0.82, 0.45, 0.85) if night else Color(0.55, 0.65, 0.75, 0.6))
	if bool(scene.get("citadel", false)):
		var c := project(size.x * 0.88, 0.05)
		draw_arc(c, 70.0 * scale_at(0.05), PI, TAU, 32, Color(0.5, 0.75, 1.0, 0.7), 3.0, true)
		draw_circle(c, 70.0 * scale_at(0.05), Color(0.5, 0.75, 1.0, 0.08))
	if bool(scene.get("bastion", false)):
		var bp := Vector2(size.x * 0.82, horizon_y * 0.35)
		draw_arc(bp, 12.0, 0.0, TAU, 20, Color(0.7, 0.75, 0.82, 0.8), 2.0)
		draw_circle(bp, 4.0, Color(0.6, 0.65, 0.72))
	for wl in _walls:
		var gz := float(wl[0])
		var half := float(wl[2])
		var gx := float(wl[1])
		var s := scale_at(gz)
		var hh := 16.0 * s
		var la := project(gx - 9.0, gz - half)
		var lb := project(gx - 9.0, gz + half)
		var ra := project(gx + 9.0, gz - half)
		var rb := project(gx + 9.0, gz + half)
		var up := Vector2(0, -hh)
		var face := Color(0.46, 0.44, 0.4) * tint
		# Face tournée vers l'assaillant, puis le dessus du rempart et ses créneaux.
		draw_colored_polygon(PackedVector2Array([la, lb, lb + up, la + up]), face.darkened(0.3))
		draw_colored_polygon(PackedVector2Array([la + up, lb + up, rb + up, ra + up]), face.lightened(0.15))
		draw_colored_polygon(PackedVector2Array([lb, rb, rb + up, lb + up]), face)
		for k in 6:
			var q := (k + 0.5) / 6.0
			var c := la.lerp(lb, q) + up
			draw_rect(Rect2(c - Vector2(3.0 * s, 5.0 * s), Vector2(5.0 * s, 5.0 * s)), face.lightened(0.05))


func _draw_barge(gx: float, gz: float) -> void:
	var p := project(gx, gz)
	var s := scale_at(gz)
	draw_set_transform(p, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 34.0 * s, Color(0.1, 0.09, 0.08, 0.5))
	draw_set_transform(Vector2.ZERO)
	var hull := PackedVector2Array([p + Vector2(-26 * s, 0), p + Vector2(-18 * s, -16 * s), p + Vector2(20 * s, -16 * s),
			p + Vector2(30 * s, -4 * s), p + Vector2(24 * s, 0)])
	draw_colored_polygon(hull, Color(0.46, 0.48, 0.52) * tint)
	draw_line(p + Vector2(-18 * s, -16 * s), p + Vector2(20 * s, -16 * s), Color(0.7, 0.72, 0.76) * tint, 1.5)
	draw_rect(Rect2(p + Vector2(22 * s, -10 * s), Vector2(6 * s, 3 * s)), Color(1.0, 0.6, 0.3, 0.6))
