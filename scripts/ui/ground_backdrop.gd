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
var _hills: Array = []      # [gx, gz, rayon (px), hauteur (px)] : reliefs du champ
var city_style := {}        # style de la ville (peuple du défenseur, SpeciesLook)
var city_biome := {}        # adaptations de la ville au biome
var city_size := 0.0        # 0 (avant-poste) à 1 (métropole), selon la population


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


## Point du terrain (gx, gz) à l'écran, relief compris.
func project(gx: float, gz: float) -> Vector2:
	var p := flat(gx, gz)
	p.y -= elev(gx, gz) * scale_at(gz)
	return p


## Point du terrain à l'écran, sans relief (pied des collines).
func flat(gx: float, gz: float) -> Vector2:
	var cx := size.x * 0.5
	return Vector2(cx + (gx - cx) * scale_at(gz), lerpf(horizon_y + 14.0, near_y, gz))


## Hauteur du terrain en (gx, gz), en pixels à l'échelle 1 : somme de collines en cloche.
func elev(gx: float, gz: float) -> float:
	var e := 0.0
	var depth := near_y - horizon_y
	for h: Array in _hills:
		var dx := (gx - float(h[0])) / float(h[2])
		var dz := (gz - float(h[1])) * depth / (float(h[2]) * 0.6)
		var q := dx * dx + dz * dz
		if q < 6.0:
			e += float(h[3]) * exp(-q)
	# Collines qui se chevauchent : la hauteur plafonne en douceur.
	return 55.0 * tanh(e / 55.0)


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
	# Reliefs : quelques collines, plus douces sur les océans et les géantes gazeuses ; une hauteur
	# derrière les lignes du défenseur, et le centre du champ reste assez dégagé.
	_hills.clear()
	var flatness := 0.35 if ter in ["ocean", "gas_giant"] else (0.6 if ter == "ecumenopole" else 1.0)
	var nh := 3 + rng.randi() % 4
	for k in nh:
		var hx := rng.randf_range(-w * 0.05, w * 1.05)
		if absf(hx - w * 0.5) < w * 0.1:
			hx += w * 0.18 * (1.0 if rng.randf() < 0.5 else -1.0)
		_hills.append([hx, rng.randf_range(0.05, 0.95), rng.randf_range(90.0, 220.0), rng.randf_range(14.0, 42.0) * flatness])
	_hills.append([w * 0.8, rng.randf_range(0.3, 0.7), rng.randf_range(140.0, 200.0), rng.randf_range(18.0, 30.0) * flatness])
	_hills.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	_layout_city(rng, w)
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
	_draw_relief(far_c, near_c)
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
	_draw_city_defenses()
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


## Le relief : une grille du sol projetée avec sa hauteur, ombrée selon la pente et le côté du soleil.
func _draw_relief(far_c: Color, near_c: Color) -> void:
	if _hills.is_empty():
		return
	var w := size.x
	var nx := 40
	var nz := 24
	var sun_side := -1.0 if int(scene.get("seed", 1)) % 2 == 0 else 1.0
	var pts: Array = []
	var cols: Array = []
	for j in nz + 1:
		var gz := float(j) / nz * 1.08
		var row_p := PackedVector2Array()
		var row_c := PackedColorArray()
		for i in nx + 1:
			var gx := lerpf(-w * 0.3, w * 1.3, float(i) / nx)
			var e := elev(gx, gz)
			var dx := elev(gx + 12.0, gz) - elev(gx - 12.0, gz)
			var dz := elev(gx, gz + 0.03) - elev(gx, gz - 0.03)
			var base := far_c.lerp(near_c, clampf(gz, 0.0, 1.0))
			var light := clampf(-dx * sun_side * 0.09 + dz * 0.04 + e * 0.005, -0.4, 0.32)
			row_p.append(project(gx, gz))
			row_c.append(base.lightened(light) if light > 0.0 else base.darkened(-light))
		pts.append(row_p)
		cols.append(row_c)
	for j in nz:
		var a: PackedVector2Array = pts[j]
		var b: PackedVector2Array = pts[j + 1]
		var ca: PackedColorArray = cols[j]
		var cb: PackedColorArray = cols[j + 1]
		for i in nx:
			draw_polygon(PackedVector2Array([a[i], a[i + 1], b[i + 1], b[i]]), PackedColorArray([ca[i], ca[i + 1], cb[i + 1], cb[i]]))


## Ville futuriste : tours effilées à flèche, dômes d'habitat, tours jumelles reliées par une passerelle,
## arcologies en gradins, aiguilles à anneau ; bandeaux lumineux, plus vifs la nuit.
func _draw_city() -> void:
	var night := time_of_day != "day"
	var st := city_style
	var bt: Array = city_biome.get("tint", [1, 1, 1])
	var mat := Color(float(bt[0]), float(bt[1]), float(bt[2]))
	var body := _col(st.get("body", [0.34, 0.36, 0.42])) * mat * tint
	var roof := _col(st.get("roof", [0.25, 0.26, 0.3])) * mat * tint
	var acc := _col(st.get("accent", [0.45, 0.9, 1.0]))
	var glow := Color(acc, 0.95 if night else 0.55)
	var gr: Array = biome(String(scene.get("ter", ""))).get("ground", [[0.3, 0.3, 0.25], [0.4, 0.4, 0.33]])
	for b in _city:
		var p := project(float(b[0]), float(b[1]))
		var s := scale_at(float(b[1]))
		var bw := float(b[2]) * s
		var bh := float(b[3]) * s
		var kind := String(b[5])
		# Pied selon le biome : pilotis au-dessus de l'eau, plate-forme suspendue au-dessus des nuages.
		if bool(city_biome.get("stilts", false)):
			_ellipse_at(p, bw * 0.9, bw * 0.22, Color(Color(0.16, 0.36, 0.56) * tint, 0.85))
			for k in 3:
				draw_line(p + Vector2(-bw * 0.4 + k * bw * 0.4, 0), p + Vector2(-bw * 0.4 + k * bw * 0.4, -6.0 * s), roof.darkened(0.3), maxf(1.0, 1.5 * s))
			p.y -= 6.0 * s
		elif bool(city_biome.get("platforms", false)):
			draw_line(p, p + Vector2(0, 14.0 * s), roof.darkened(0.3), maxf(1.0, 2.0 * s))
			draw_rect(Rect2(p + Vector2(-bw * 0.7, -2.0 * s), Vector2(bw * 1.4, 4.0 * s)), roof)
		_building(kind, p, bw, bh, s, int(b[4]), body, roof, glow, night)
		if bool(city_biome.get("snow", false)) and not kind in ["dome", "aire", "jardin"]:
			draw_rect(Rect2(p + Vector2(-bw * 0.45, -bh - 1.5 * s), Vector2(bw * 0.9, 2.5 * s)), Color(0.95, 0.97, 1.0) * tint)
		if bool(city_biome.get("green", false)) and kind in ["tour", "gradins", "module", "donjon", "bloc", "monolithe"]:
			draw_rect(Rect2(p + Vector2(-bw * 0.4, -bh - 2.0 * s), Vector2(bw * 0.8, 2.5 * s)), _col(gr[0]).lightened(0.15) * tint)


func _ellipse_at(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, ry / maxf(0.01, rx)))
	draw_circle(Vector2.ZERO, rx, col)
	draw_set_transform(Vector2.ZERO)


## Un bâtiment de la ville, posé en p (pied au centre), de largeur bw et de hauteur bh.
func _building(kind: String, p: Vector2, bw: float, bh: float, s: float, seed_value: int, body: Color, roof: Color, glow: Color, night: bool) -> void:
	var dark := body.darkened(0.25)
	var lw := maxf(1.0, 1.3 * s)
	match kind:
		"donjon":
			draw_rect(Rect2(p + Vector2(-bw * 0.5, -bh), Vector2(bw, bh)), body)
			draw_rect(Rect2(p + Vector2(-bw * 0.5, -bh), Vector2(bw * 0.3, bh)), dark)
			for k in 4:
				draw_rect(Rect2(p + Vector2(-bw * 0.5 + k * bw * 0.27, -bh - 3.0 * s), Vector2(bw * 0.16, 3.0 * s)), body)
			draw_colored_polygon(PackedVector2Array([p + Vector2(bw * 0.1, -bh), p + Vector2(bw * 0.25, -bh - bh * 0.45), p + Vector2(bw * 0.4, -bh)]), roof)
			draw_rect(Rect2(p + Vector2(-bw * 0.1, -bh * 0.5), Vector2(bw * 0.15, bh * 0.12)), glow)
		"fleche":
			draw_rect(Rect2(p + Vector2(-bw * 0.3, -bh * 0.6), Vector2(bw * 0.6, bh * 0.6)), body)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-bw * 0.3, -bh * 0.6), p + Vector2(0, -bh * 1.5), p + Vector2(bw * 0.3, -bh * 0.6)]), roof)
			draw_line(p + Vector2(0, -bh * 1.5), p + Vector2(0, -bh * 1.7), glow, lw)
		"tour":
			draw_rect(Rect2(p + Vector2(-bw * 0.35, -bh), Vector2(bw * 0.7, bh)), body)
			draw_rect(Rect2(p + Vector2(-bw * 0.35, -bh), Vector2(bw * 0.2, bh)), dark)
			for k in int(bh / (8.0 * s)):
				draw_line(p + Vector2(-bw * 0.1, -bh + (k + 0.6) * 8.0 * s), p + Vector2(bw * 0.3, -bh + (k + 0.6) * 8.0 * s), Color(glow, glow.a * 0.6), 1.0)
		"dome":
			draw_rect(Rect2(p + Vector2(-bw * 0.6, -bh * 0.12), Vector2(bw * 1.2, bh * 0.12)), dark)
			draw_colored_polygon(_dome(p - Vector2(0, bh * 0.12), bw * 0.6, bh * 0.5), Color(body.lightened(0.15), 0.9))
			draw_arc(p - Vector2(0, bh * 0.12), bw * 0.6, PI, TAU, 16, Color(0.8, 0.92, 1.0, 0.5), lw)
			draw_line(p + Vector2(-bw * 0.6, -bh * 0.12), p + Vector2(bw * 0.6, -bh * 0.12), glow, lw)
		"aiguille":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-bw * 0.25, 0), p + Vector2(0, -bh * 1.3), p + Vector2(bw * 0.25, 0)]), body)
			draw_set_transform(p + Vector2(0, -bh * 0.75), 0.0, Vector2(1.0, 0.3))
			draw_arc(Vector2.ZERO, bw * 0.55, 0.0, TAU, 20, glow, maxf(1.5, 2.0 * s))
			draw_set_transform(Vector2.ZERO)
		"passerelle":
			var tw := bw * 0.34
			draw_rect(Rect2(p + Vector2(-bw * 0.5, -bh), Vector2(tw, bh)), body)
			draw_rect(Rect2(p + Vector2(bw * 0.5 - tw, -bh * 0.85), Vector2(tw, bh * 0.85)), dark)
			draw_rect(Rect2(p + Vector2(-bw * 0.5 + tw, -bh * 0.62), Vector2(bw - 2.0 * tw, 3.0 * s)), roof)
			draw_line(p + Vector2(-bw * 0.5 + tw, -bh * 0.62 + 1.5 * s), p + Vector2(bw * 0.5 - tw, -bh * 0.62 + 1.5 * s), glow, lw)
		"gradins":
			for j in 3:
				var fw := bw * (1.3 - j * 0.35)
				var fy := -bh * 0.33 * j
				draw_rect(Rect2(p + Vector2(-fw * 0.5, fy - bh * 0.33), Vector2(fw, bh * 0.33)), body.darkened(0.06 * j))
				draw_line(p + Vector2(-fw * 0.5, fy - bh * 0.33), p + Vector2(fw * 0.5, fy - bh * 0.33), glow, lw)
		"cathedrale":
			draw_rect(Rect2(p + Vector2(-bw * 0.6, -bh * 0.6), Vector2(bw * 1.2, bh * 0.6)), body)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-bw * 0.6, -bh * 0.6), p + Vector2(0, -bh * 0.85), p + Vector2(bw * 0.6, -bh * 0.6)]), roof)
			for sx in [-0.5, 0.5]:
				draw_rect(Rect2(p + Vector2(bw * sx - bw * 0.12, -bh * 1.0), Vector2(bw * 0.24, bh * 1.0)), dark)
				draw_colored_polygon(PackedVector2Array([p + Vector2(bw * sx - bw * 0.12, -bh), p + Vector2(bw * sx, -bh * 1.45), p + Vector2(bw * sx + bw * 0.12, -bh)]), roof)
			draw_circle(p + Vector2(0, -bh * 0.4), bw * 0.14, glow)
		"cheminee":
			draw_rect(Rect2(p + Vector2(-bw * 0.4, -bh * 0.45), Vector2(bw * 0.8, bh * 0.45)), body)
			draw_rect(Rect2(p + Vector2(bw * 0.1, -bh * 1.1), Vector2(bw * 0.18, bh * 0.7)), dark)
			draw_circle(p + Vector2(bw * 0.2, -bh * 1.2), bw * 0.25, Color(0.4, 0.38, 0.36, 0.35))
			draw_rect(Rect2(p + Vector2(-bw * 0.3, -bh * 0.3), Vector2(bw * 0.25, bh * 0.08)), glow)
		"module":
			for j in 2:
				var r := Rect2(p + Vector2(-bw * 0.5 + j * bw * 0.12, -bh * 0.45 * (j + 1)), Vector2(bw * (1.0 - j * 0.24), bh * 0.42))
				draw_rect(r, body.darkened(0.08 * j))
				draw_line(r.position + Vector2(2 * s, r.size.y * 0.5), r.position + Vector2(r.size.x - 2 * s, r.size.y * 0.5), Color(glow, glow.a * 0.7), 1.0)
		"habitat":
			draw_rect(Rect2(p + Vector2(-bw * 0.25, -bh), Vector2(bw * 0.5, bh)), body)
			draw_set_transform(p + Vector2(0, -bh * 0.7), 0.0, Vector2(1.0, 0.28))
			draw_arc(Vector2.ZERO, bw * 0.8, 0.0, TAU, 24, roof.lightened(0.2), maxf(2.0, 3.0 * s))
			draw_set_transform(Vector2.ZERO)
			draw_circle(p + Vector2(0, -bh), bw * 0.2, glow)
		"radiateur":
			draw_rect(Rect2(p + Vector2(-bw * 0.15, -bh * 0.7), Vector2(bw * 0.3, bh * 0.7)), dark)
			for k in 4:
				draw_rect(Rect2(p + Vector2(-bw * 0.6, -bh * 0.65 + k * bh * 0.16), Vector2(bw * 1.2, bh * 0.06)), roof.lightened(0.1))
		"antenne":
			draw_line(p, p + Vector2(0, -bh * 1.2), dark, lw)
			draw_arc(p + Vector2(0, -bh * 0.9), bw * 0.4, PI * 1.1, PI * 1.9, 10, body.lightened(0.2), maxf(1.5, 2.0 * s))
			draw_circle(p + Vector2(0, -bh * 1.2), 1.5 * s, Color(1, 0.3, 0.25, 0.9))
		"baraque":
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			draw_rect(Rect2(p + Vector2(-bw * 0.5, -bh * 0.5), Vector2(bw, bh * 0.5)), body)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-bw * 0.6, -bh * 0.5), p + Vector2(bw * 0.6, -bh * 0.62), p + Vector2(bw * 0.6, -bh * 0.5)]), roof)
			draw_rect(Rect2(p + Vector2(rng.randf_range(-bw * 0.4, 0), -bh * 0.4), Vector2(bw * 0.3, bh * 0.15)), Color(0.7, 0.55, 0.3) * tint)
		"enseigne":
			draw_rect(Rect2(p + Vector2(-bw * 0.4, -bh * 0.7), Vector2(bw * 0.8, bh * 0.7)), body)
			draw_line(p + Vector2(bw * 0.4, -bh * 0.7), p + Vector2(bw * 0.4, -bh * 1.05), dark, lw)
			draw_rect(Rect2(p + Vector2(bw * 0.1, -bh * 1.15), Vector2(bw * 0.6, bh * 0.18)), glow)
		"grue":
			draw_line(p, p + Vector2(0, -bh * 1.3), dark, maxf(1.5, 2.0 * s))
			draw_line(p + Vector2(-bw * 0.4, -bh * 1.25), p + Vector2(bw * 1.0, -bh * 1.25), dark, lw)
			draw_line(p + Vector2(bw * 0.9, -bh * 1.25), p + Vector2(bw * 0.9, -bh * 0.8), dark, 1.0)
			draw_rect(Rect2(p + Vector2(-bw * 0.6, -bh * 0.35), Vector2(bw * 0.9, bh * 0.35)), body)
		"tertre":
			draw_colored_polygon(_dome(p, bw * 0.7, bh * 0.6), body)
			for k in 3:
				draw_circle(p + Vector2((k - 1) * bw * 0.3, -bh * (0.2 + 0.1 * (k % 2))), bw * 0.07, Color(0.08, 0.08, 0.05))
			draw_circle(p + Vector2(0, -bh * 0.6), bw * 0.08, glow)
		"cocon":
			_ellipse_at(p - Vector2(0, bh * 0.5), bw * 0.32, bh * 0.5, body)
			_ellipse_at(p - Vector2(bw * 0.05, bh * 0.6), bw * 0.12, bh * 0.25, Color(glow, glow.a * 0.5))
		"tour_organique":
			var pts := PackedVector2Array()
			for k in 9:
				var q := k / 8.0
				pts.append(p + Vector2(-bw * 0.35 * (1.0 - q * 0.7) + sin(q * 6.0) * 2.0 * s, -bh * 1.2 * q))
			for k in range(8, -1, -1):
				var q := k / 8.0
				pts.append(p + Vector2(bw * 0.35 * (1.0 - q * 0.7) + sin(q * 6.0 + 1.0) * 2.0 * s, -bh * 1.2 * q))
			draw_colored_polygon(pts, body)
			draw_circle(p + Vector2(0, -bh * 1.2), bw * 0.16, glow)
		"cristal":
			for k in 3:
				var off := (k - 1) * bw * 0.28
				var hh := bh * (1.2 - absf(k - 1) * 0.4)
				draw_colored_polygon(PackedVector2Array([p + Vector2(off - bw * 0.14, 0), p + Vector2(off, -hh), p + Vector2(off + bw * 0.14, 0)]),
						Color(body.lightened(0.1 * k), 0.92))
			draw_line(p + Vector2(0, -bh * 1.2), p + Vector2(0, -bh * 0.3), Color(glow, 0.8), lw)
		"anneau":
			draw_rect(Rect2(p + Vector2(-bw * 0.3, -bh * 0.25), Vector2(bw * 0.6, bh * 0.25)), body)
			draw_arc(p + Vector2(0, -bh * 0.75), bw * 0.45, 0.0, TAU, 24, glow, maxf(2.0, 3.0 * s))
		"obelisque":
			var lift := -bh * 0.18
			draw_colored_polygon(PackedVector2Array([p + Vector2(-bw * 0.2, lift), p + Vector2(-bw * 0.12, lift - bh), p + Vector2(0, lift - bh * 1.15),
					p + Vector2(bw * 0.12, lift - bh), p + Vector2(bw * 0.2, lift)]), body)
			draw_line(p + Vector2(-bw * 0.2, 0), p + Vector2(bw * 0.2, 0), Color(glow, 0.6), lw)
		"monolithe":
			draw_rect(Rect2(p + Vector2(-bw * 0.45, -bh), Vector2(bw * 0.9, bh)), body)
			for k in 3:
				draw_line(p + Vector2(-bw * 0.3, -bh * (0.25 + k * 0.25)), p + Vector2(bw * 0.3, -bh * (0.25 + k * 0.25)), dark, lw)
			draw_rect(Rect2(p + Vector2(-bw * 0.08, -bh * 0.9), Vector2(bw * 0.16, bh * 0.1)), glow)
		"forge":
			draw_rect(Rect2(p + Vector2(-bw * 0.55, -bh * 0.5), Vector2(bw * 1.1, bh * 0.5)), body)
			draw_rect(Rect2(p + Vector2(bw * 0.2, -bh * 0.95), Vector2(bw * 0.2, bh * 0.45)), dark)
			draw_rect(Rect2(p + Vector2(-bw * 0.35, -bh * 0.32), Vector2(bw * 0.4, bh * 0.2)), Color(1.0, 0.55, 0.2, 0.9))
		"arche":
			draw_rect(Rect2(p + Vector2(-bw * 0.6, -bh), Vector2(bw * 0.3, bh)), body)
			draw_rect(Rect2(p + Vector2(bw * 0.3, -bh), Vector2(bw * 0.3, bh)), body)
			draw_rect(Rect2(p + Vector2(-bw * 0.6, -bh * 1.15), Vector2(bw * 1.2, bh * 0.2)), roof)
			draw_rect(Rect2(p + Vector2(-bw * 0.3, -bh * 0.95), Vector2(bw * 0.6, bh * 0.05)), glow)
		"bloc":
			draw_rect(Rect2(p + Vector2(-bw * 0.5, -bh), Vector2(bw, bh)), body)
			for k in int(bh / (5.0 * s)):
				draw_line(p + Vector2(-bw * 0.4, -bh + (k + 0.5) * 5.0 * s), p + Vector2(bw * (0.4 - 0.3 * ((seed_value + k) % 3) / 2.0), -bh + (k + 0.5) * 5.0 * s), Color(glow, glow.a * 0.5), 1.0)
		"capteur_vent":
			draw_rect(Rect2(p + Vector2(-bw * 0.2, -bh), Vector2(bw * 0.4, bh)), body)
			draw_rect(Rect2(p + Vector2(-bw * 0.3, -bh - 4.0 * s), Vector2(bw * 0.6, 4.0 * s)), roof)
			draw_rect(Rect2(p + Vector2(-bw * 0.12, -bh + 2.0 * s), Vector2(bw * 0.24, 3.0 * s)), dark)
		"cheminee_filtre":
			draw_rect(Rect2(p + Vector2(-bw * 0.15, -bh * 1.1), Vector2(bw * 0.3, bh * 1.1)), dark)
			draw_circle(p + Vector2(0, -bh * 1.2), bw * 0.3, Color(0.6, 0.85, 0.3, 0.35))
		"aire":
			_ellipse_at(p, bw * 0.9, bw * 0.3, Color(roof, 0.9))
			draw_set_transform(p, 0.0, Vector2(1.0, 0.33))
			draw_arc(Vector2.ZERO, bw * 0.7, 0.0, TAU, 20, glow, lw)
			draw_set_transform(Vector2.ZERO)
		"jardin":
			draw_rect(Rect2(p + Vector2(-bw * 0.6, -bh * 0.3), Vector2(bw * 1.2, bh * 0.3)), body)
			for k in 4:
				draw_circle(p + Vector2(-bw * 0.45 + k * bw * 0.3, -bh * 0.35), bw * 0.16, Color(0.3, 0.55, 0.25) * tint)
		_:
			draw_rect(Rect2(p + Vector2(-bw * 0.4, -bh), Vector2(bw * 0.8, bh)), body)
	if night and not kind in ["dome", "aire", "jardin", "antenne", "grue"]:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = seed_value
		for j in 3:
			draw_rect(Rect2(p + Vector2(rng2.randf_range(-bw * 0.25, bw * 0.15), -rng2.randf_range(0.15, 0.85) * bh), Vector2(2.0 * s, 1.5 * s)),
					Color(1.0, 0.85, 0.55, 0.9))


func _draw_city_defenses() -> void:
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


func _dome(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 17:
		var a := PI + PI * float(k) / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Ville du défenseur (lot 3) : style du peuple qui l'a bâtie, adaptée au biome, et d'autant plus
## étendue, dense et haute que la population est grande ; un grand édifice au-delà d'un seuil.
## Elle reste au fond à droite, posée sur le sol (jamais au-delà de l'horizon) ; une grande ville
## déborde sur le flanc droit, derrière les lignes du défenseur.
func _layout_city(rng: RandomNumberGenerator, w: float) -> void:
	_city.clear()
	var ter := String(scene.get("ter", ""))
	city_style = SpeciesLook.city_style(String(scene.get("csp", "")))
	city_biome = SpeciesLook.city_biome(ter)
	var cs: Dictionary = GameData.battle_visuals().get("cities", {}).get("size", {})
	var pop := int(scene.get("pop", 0))
	var small := float(cs.get("pop_small", 4))
	var large := float(cs.get("pop_large", 20))
	city_size = clampf((pop - small) / maxf(1.0, large - small), 0.0, 1.0)
	if ter == "ecumenopole":
		city_size = 1.0
	var cc: Dictionary = cfg().get("city", {})
	var density := float(city_biome.get("density", 1.0))
	var hk := float(city_biome.get("height", 1.0)) * lerpf(0.7, 1.35, city_size)
	var nb := mini(int(int(cc.get("max", 56)) * lerpf(0.55, 1.0, city_size) * density), int((3 + pop * int(cc.get("per_pop", 3))) * density))
	var kinds: Array = city_style.get("kinds", ["tour"])
	var domes := float(city_biome.get("domes", 0.0))
	var extra := String(city_biome.get("extra", ""))
	if pop <= 0:
		# Avant-poste : quelques dômes préfabriqués et une aire.
		kinds = ["dome", "dome", "aire"]
		nb = 3
	var x0 := w * lerpf(0.86, 0.64, city_size)
	for k in nb:
		var flank := city_size > 0.35 and rng.randf() < city_size * 0.45
		var gx := rng.randf_range(w * 0.93, w * 1.02) if flank else rng.randf_range(x0, w * 0.99)
		var gz := rng.randf_range(0.18, lerpf(0.3, 0.9, city_size)) if flank else rng.randf_range(0.02, lerpf(0.1, 0.22, city_size))
		var kind := String(kinds[rng.randi() % kinds.size()])
		if domes > 0.0 and rng.randf() < domes:
			kind = "dome"
		elif extra != "" and rng.randf() < 0.12:
			kind = extra
		_city.append([gx, gz, rng.randf_range(16.0, 30.0), rng.randf_range(26.0, 60.0) * hk, rng.randi(), kind])
	if pop >= int(cs.get("landmark_pop", 10)):
		_city.append([w * 0.84, 0.05, 44.0, 90.0 * hk, rng.randi(), String(city_style.get("landmark", "tour"))])
	_city.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
