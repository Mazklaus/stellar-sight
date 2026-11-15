class_name ArmyLayer
extends Node2D
## Les armées de la vue de bataille au sol (étude visuel des combats, prop. 23 à 28) : chaque régiment
## devient une petite troupe de figurines (nombre selon sa famille et le réglage « Échelle des batailles »),
## rangée selon la tactique, qui avance, tombe à mesure que le régiment perd sa santé (les corps restent
## là où ils sont tombés) et s'enfuit quand il est mis en déroute.
##
## Tout est fonction du temps du replay : rien n'est mémorisé d'une image à l'autre, on peut revenir en
## arrière. Les figurines sont dessinées par lots (MultiMeshInstance2D, une texture par silhouette) ; le
## reste (bannières, chevrons, général, traçantes) est dessiné par la vue.

const DAY_SECONDS := 1.6
const KINDS := ["corpse", "wreck", "shadow", "mil", "inf", "tank", "big", "air"]
const SIZES := {"corpse": Vector2(12, 5), "wreck": Vector2(22, 10), "shadow": Vector2(22, 6), "mil": Vector2(9, 13),
		"inf": Vector2(9, 14), "tank": Vector2(22, 12), "big": Vector2(30, 40), "air": Vector2(24, 10)}

var backdrop: GroundBackdrop
var report: Dictionary = {}
var scale_level := 0
var reduced := false           # moitié des figurines (sous le plancher d'images par seconde)
var colors: Array = [Color(0.85, 0.6, 0.3), Color(0.4, 0.65, 0.95)]
var units: Array = []          # par unité : {fam, kind, n, side, offsets, rank, die_t, base, rout_t, tactic}
var total := 0
var cap_hit := false

var _mm: Dictionary = {}       # kind -> MultiMeshInstance2D
var _buf: Dictionary = {}      # kind -> PackedFloat32Array (12 flottants par figurine)
var _dmg_until: Array = []
var _dead_day: Array = []
var _days := 1


func _ready() -> void:
	for k: String in KINDS:
		var mi := MultiMeshInstance2D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = _quad()
		mi.multimesh = mm
		mi.texture = _texture(k)
		mi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(mi)
		_mm[k] = mi


static func cfg() -> Dictionary:
	return GroundBackdrop.cfg()


## Quadrilatère posé sur ses pieds (origine en bas au centre), de taille 1.
static func _quad() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -1), Vector2(0.5, -1), Vector2(0.5, 0), Vector2(-0.5, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Silhouettes dessinées pixel par pixel (en gris, teintées par la couleur de l'empire), tournées vers la droite.
static func _texture(kind: String) -> ImageTexture:
	var sz: Vector2 = SIZES[kind] * 2.0
	var img := Image.create(int(sz.x), int(sz.y), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var w := img.get_width()
	var h := img.get_height()
	var dark := Color(0.35, 0.35, 0.38)
	var mid := Color(0.75, 0.75, 0.78)
	var light := Color(1, 1, 1)
	match kind:
		"inf", "mil":
			# Casque, buste, jambes, arme pointée vers l'avant.
			_disc(img, Vector2(w * 0.45, h * 0.13), w * 0.2, dark if kind == "inf" else mid)
			img.fill_rect(Rect2i(int(w * 0.25), int(h * 0.24), int(w * 0.45), int(h * 0.38)), light)
			img.fill_rect(Rect2i(int(w * 0.25), int(h * 0.62), int(w * 0.18), int(h * 0.38)), mid)
			img.fill_rect(Rect2i(int(w * 0.52), int(h * 0.62), int(w * 0.18), int(h * 0.38)), mid)
			if kind == "inf":
				img.fill_rect(Rect2i(int(w * 0.5), int(h * 0.3), int(w * 0.5), 2), dark)
		"corpse":
			img.fill_rect(Rect2i(int(w * 0.1), int(h * 0.35), int(w * 0.7), int(h * 0.5)), mid)
			_disc(img, Vector2(w * 0.85, h * 0.6), h * 0.3, dark)
		"tank", "wreck":
			img.fill_rect(Rect2i(0, int(h * 0.55), w, int(h * 0.45)), dark)
			for k in 5:
				_disc(img, Vector2(w * (0.12 + k * 0.19), h * 0.78), h * 0.13, mid)
			img.fill_rect(Rect2i(int(w * 0.08), int(h * 0.3), int(w * 0.8), int(h * 0.3)), light if kind == "tank" else mid)
			img.fill_rect(Rect2i(int(w * 0.3), int(h * 0.05), int(w * 0.35), int(h * 0.3)), light if kind == "tank" else dark)
			if kind == "tank":
				img.fill_rect(Rect2i(int(w * 0.6), int(h * 0.14), int(w * 0.4), int(h * 0.1)), mid)
		"big":
			# Colosse ou marcheur : deux pattes, une caisse, une tête.
			img.fill_rect(Rect2i(int(w * 0.2), int(h * 0.55), int(w * 0.16), int(h * 0.45)), dark)
			img.fill_rect(Rect2i(int(w * 0.62), int(h * 0.55), int(w * 0.16), int(h * 0.45)), dark)
			img.fill_rect(Rect2i(int(w * 0.1), int(h * 0.22), int(w * 0.8), int(h * 0.36)), light)
			img.fill_rect(Rect2i(int(w * 0.6), int(h * 0.08), int(w * 0.3), int(h * 0.16)), mid)
			img.fill_rect(Rect2i(int(w * 0.8), int(h * 0.3), int(w * 0.2), int(h * 0.06)), dark)
		"air":
			img.fill_rect(Rect2i(0, int(h * 0.4), w, int(h * 0.25)), light)
			img.fill_rect(Rect2i(int(w * 0.3), 0, int(w * 0.25), h), mid)
			img.fill_rect(Rect2i(0, int(h * 0.15), int(w * 0.12), int(h * 0.5)), mid)
		"shadow":
			_ellipse(img, Color(0, 0, 0, 0.45))
	return ImageTexture.create_from_image(img)


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(int(c.y - r), int(c.y + r) + 1):
		for x in range(int(c.x - r), int(c.x + r) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and Vector2(x, y).distance_to(c) <= r:
				img.set_pixel(x, y, col)


static func _ellipse(img: Image, col: Color) -> void:
	var c := Vector2(img.get_width(), img.get_height()) * 0.5
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2((x - c.x) / c.x, (y - c.y) / c.y)
			if d.length() <= 1.0:
				img.set_pixel(x, y, col)


static func family_of(ty: String) -> String:
	return String(Ground.type_def(ty).get("family", ty)) if ty != "milice" else "milice"


## Nombre de figurines d'un régiment à l'échelle choisie (avant le plafond).
static func figures_for(ty: String, level: int) -> int:
	if ty == "marcheur":
		return 1
	var fam := family_of(ty)
	var f: Array = cfg().get("figures", {}).get(fam, [10, 30, 90])
	var n := int(f[clampi(level, 0, f.size() - 1)])
	if ty in cfg().get("big", []):
		n = maxi(1, int(n / 3.0))
	if ty == "essaims":
		n = int(n * 1.5)
	return n


func setup(r: Dictionary, bd: GroundBackdrop, level: int, dmg_until: Array, dead_day: Array, side_colors: Array) -> void:
	report = r
	backdrop = bd
	scale_level = level
	_dmg_until = dmg_until
	_dead_day = dead_day
	_days = maxi(1, dmg_until.size() - 1)
	colors = side_colors
	_build()


func set_reduced(value: bool) -> void:
	if value != reduced:
		reduced = value
		_build()


func _build() -> void:
	units.clear()
	total = 0
	cap_hit = false
	var rs: Array = report.get("units", [])
	var counts: Array = []
	var want := 0
	for u: Dictionary in rs:
		var n := figures_for(String(u["t"]), scale_level)
		counts.append(n)
		want += n
	# Plafond de toute la bataille : chaque régiment est réduit en proportion.
	var caps: Array = cfg().get("cap", [1500, 4500, 9000])
	var cap := int(caps[clampi(scale_level, 0, caps.size() - 1)])
	if reduced:
		cap = int(cap * 0.5)
	var k := 1.0
	if want > cap:
		k = float(cap) / float(want)
		cap_hit = true
	var routs := {}
	for ro: Array in report.get("routs", []):
		routs[int(ro[1])] = int(ro[0]) - 1
	var anchors := _anchors()
	for i in rs.size():
		var u: Dictionary = rs[i]
		var ty := String(u["t"])
		var fam := family_of(ty)
		var n := maxi(1, int(round(int(counts[i]) * k)))
		var side := int(u["side"])
		var tac := String(report.get("ta" if side == 0 else "td", ""))
		var kind := "inf"
		match fam:
			"milice": kind = "mil"
			"blindes": kind = "big" if ty in cfg().get("big", []) else "tank"
			"aerien": kind = "air"
		var e := {"fam": fam, "kind": kind, "n": n, "side": side, "base": anchors[i], "tactic": tac,
				"rout_t": -1.0 if not routs.has(i) else (float(routs[i]) + 0.85) * DAY_SECONDS}
		_formation(e, i)
		_deaths(e, i)
		units.append(e)
		total += n
	_alloc()


## Ancres des régiments sur le terrain : colonnes depuis la ligne de front (le centre) vers l'arrière,
## rangées dans la profondeur. Régiments devant, milice derrière.
func _anchors() -> Array:
	var rs: Array = report.get("units", [])
	var out: Array = []
	out.resize(rs.size())
	var w := backdrop.size.x if backdrop and backdrop.size.x > 0 else 1600.0
	for side in 2:
		var members: Array[int] = []
		for pass_i in 2:
			for i in rs.size():
				var u: Dictionary = rs[i]
				if int(u["side"]) == side and (String(u["t"]) == "milice") == (pass_i == 1):
					members.append(i)
		var rows := clampi(int(ceil(sqrt(members.size() * 1.4))), 1, 6)
		var cols := maxi(1, int(ceil(float(members.size()) / rows)))
		var col_w := minf(150.0, (w * 0.4) / cols)
		for k in members.size():
			@warning_ignore("integer_division")
			var c := k / rows
			var row := k % rows
			var in_col := mini(rows, members.size() - c * rows)
			var gz := 0.5 + (row - (in_col - 1) * 0.5) * (0.84 / rows)
			var gx := w * 0.5 + (-1.0 if side == 0 else 1.0) * (70.0 + col_w * (c + 0.5))
			out[members[k]] = Vector3(gx, gz, col_w)
	return out


## Places des figurines autour de l'ancre (dx en pixels, dz en part de profondeur), de la plus lointaine
## à la plus proche ; « rank » fixe l'ordre dans lequel elles tombent.
func _formation(e: Dictionary, idx: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(report.get("sc", {}).get("seed", 1)) * 31 + idx * 977
	var forms: Dictionary = cfg().get("formations", {})
	var f: Dictionary = forms.get(String(e["tactic"]), forms.get("_default", {}))
	var shape := String(f.get("shape", "ligne"))
	if int(e["side"]) == 0 and shape == "retranche":
		shape = "ligne"
	var n := int(e["n"])
	var base: Vector3 = e["base"]
	var slot_w := float(base.z) * 0.8
	var depth_px := (backdrop.near_y - backdrop.horizon_y) if backdrop else 460.0
	var rows_n := 6
	var slot_h := depth_px * 0.84 / rows_n * 0.85
	var sp := float(cfg().get("spacing", {}).get(String(e["fam"]), 10)) * float(f.get("spread", 1.0))
	if String(e["kind"]) == "big":
		sp = 40.0
	var nominal := sp
	sp = minf(sp, sqrt(slot_w * slot_h / float(n)) * 1.05)
	sp = maxf(sp, 3.0)
	# Régiment serré : figurines plus petites, pour que les blocs ne se chevauchent pas.
	e["fig"] = clampf(sp / nominal, 0.5, 1.0)
	var files := maxi(1, mini(n, int(slot_h / sp)))
	if shape == "colonne":
		files = maxi(1, int(files * 0.5))
	var ranks := int(ceil(float(n) / files))
	var dir := 1.0 if int(e["side"]) == 0 else -1.0
	var offs: Array = []
	for j in n:
		@warning_ignore("integer_division")
		var rk := j / files
		var fl := j % files
		var dx := -dir * (rk - (ranks - 1) * 0.5) * sp
		var dzp := (fl - (files - 1) * 0.5) * sp
		match shape:
			"disperse":
				dx += rng.randf_range(-0.6, 0.6) * sp
				dzp += rng.randf_range(-0.6, 0.6) * sp
			"coin":
				dx -= dir * absf(fl - (files - 1) * 0.5) * sp * 0.9
			_:
				dx += rng.randf_range(-0.15, 0.15) * sp
				dzp += rng.randf_range(-0.15, 0.15) * sp
		offs.append(Vector3(dx, dzp / depth_px, rng.randf() * TAU))
	offs.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	var order: Array = range(n)
	for j in range(n - 1, 0, -1):
		var s := rng.randi() % (j + 1)
		var tmp: int = order[j]
		order[j] = order[s]
		order[s] = tmp
	var rank := PackedInt32Array()
	rank.resize(n)
	for j in n:
		rank[order[j]] = j
	e["offsets"] = offs
	e["rank"] = rank


## Temps du replay où tombe chaque figurine : la figurine de rang k tombe quand il reste k figurines
## ou moins (les dégâts d'un jour s'étalent de 25 % à 85 % du jour).
func _deaths(e: Dictionary, idx: int) -> void:
	var n := int(e["n"])
	var mh := maxi(1, int((report["units"][idx] as Dictionary).get("hp", 100)))
	var die := PackedFloat32Array()
	die.resize(n)
	die.fill(INF)
	for kk in n:
		var need := float(mh) * (1.0 - float(kk) / float(n))
		for d in _days:
			var d0 := float(_dmg(d, idx, mh))
			var d1 := float(_dmg(d + 1, idx, mh))
			if d1 >= need and d1 > d0:
				var f := clampf((need - d0) / (d1 - d0), 0.0, 1.0)
				die[kk] = (d + 0.25 + 0.6 * f) * DAY_SECONDS
				break
	e["die_t"] = die


## Dégâts cumulés avant le jour d (indice 0 : avant le premier) ; une unité détruite a tout perdu.
func _dmg(d: int, idx: int, mh: int) -> int:
	if d >= _dmg_until.size():
		d = _dmg_until.size() - 1
	var v := int(_dmg_until[d][idx])
	if idx < _dead_day.size() and int(_dead_day[idx]) >= 0 and d > int(_dead_day[idx]):
		v = maxi(v, mh)
	return v


## Ancre d'un régiment au temps t : l'assaillant débarque près des barges et avance, le défenseur tient
## (ou avance un peu s'il n'est pas retranché) ; un régiment en déroute repart vers l'arrière.
func anchor(i: int, t: float) -> Vector2:
	var e: Dictionary = units[i]
	var b: Vector3 = e["base"]
	var x := b.x
	var side := int(e["side"])
	if side == 0:
		x -= 220.0 * (1.0 - smoothstep(0.0, DAY_SECONDS * 1.3, t))
		x += 60.0 * smoothstep(DAY_SECONDS, _days * DAY_SECONDS, t)
	elif not String(e["tactic"]) in ["defense", "civils"] and String(e["fam"]) != "milice":
		x -= 26.0 * smoothstep(0.0, DAY_SECONDS * 2.0, t)
	var rt := float(e["rout_t"])
	if rt >= 0.0 and t > rt:
		var p := (t - rt) / DAY_SECONDS
		x += (-1.0 if side == 0 else 1.0) * 260.0 * p
	return Vector2(x, b.y)


func moving(i: int, t: float) -> bool:
	var e: Dictionary = units[i]
	var rt := float(e["rout_t"])
	if rt >= 0.0 and t > rt:
		return true
	return int(e["side"]) == 0 and t < DAY_SECONDS * 1.3


func routed(i: int, t: float) -> bool:
	var rt := float(units[i]["rout_t"])
	return rt >= 0.0 and t > rt


func alive_count(i: int, t: float) -> int:
	var e: Dictionary = units[i]
	var die: PackedFloat32Array = e["die_t"]
	var c := 0
	for v in die:
		if v > t:
			c += 1
	return c


## Centre d'un régiment à l'écran (pour les bannières et les traçantes).
func center(i: int, t: float) -> Vector2:
	var a := anchor(i, t)
	return backdrop.project(a.x, a.y)


## Une figurine vivante au hasard (k) du régiment, à l'écran : départ ou arrivée d'une traçante.
func figure_pos(i: int, k: int, t: float) -> Vector2:
	var e: Dictionary = units[i]
	var offs: Array = e["offsets"]
	if offs.is_empty():
		return center(i, t)
	var o: Vector3 = offs[absi(k) % offs.size()]
	var a := anchor(i, t)
	var gz := a.y + o.y
	var p := backdrop.project(a.x + o.x, gz)
	var lift := 34.0 * backdrop.scale_at(gz) if String(e["kind"]) == "air" else 0.0
	return p - Vector2(0, (SIZES[e["kind"]] as Vector2).y * 0.5 * backdrop.scale_at(gz) + lift)


## Capacité de chaque lot (figurines debout, corps, épaves, ombres), fixée au montage.
func _alloc() -> void:
	var cap := {}
	for k: String in KINDS:
		cap[k] = 0
	for e: Dictionary in units:
		var kind := String(e["kind"])
		var n := int(e["n"])
		cap[kind] = int(cap[kind]) + n
		cap[_dead_kind(kind)] = int(cap[_dead_kind(kind)]) + n
		if kind == "air":
			cap["shadow"] = int(cap["shadow"]) + n
	for k: String in KINDS:
		var mm := (_mm[k] as MultiMeshInstance2D).multimesh
		mm.instance_count = maxi(1, int(cap[k]))
		mm.visible_instance_count = 0
		var b := PackedFloat32Array()
		b.resize(mm.instance_count * 12)
		_buf[k] = b


static func _dead_kind(kind: String) -> String:
	return "wreck" if kind in ["tank", "big", "air"] else "corpse"


## Écrit une figurine dans le lot (transformation 2D sur 8 flottants, puis la couleur).
func _put(buf: PackedFloat32Array, j: int, p: Vector2, sx: float, sy: float, col: Color) -> void:
	var o := j * 12
	buf[o] = sx
	buf[o + 1] = 0.0
	buf[o + 2] = 0.0
	buf[o + 3] = p.x
	buf[o + 4] = 0.0
	buf[o + 5] = sy
	buf[o + 6] = 0.0
	buf[o + 7] = p.y
	buf[o + 8] = col.r
	buf[o + 9] = col.g
	buf[o + 10] = col.b
	buf[o + 11] = col.a


## Remplit les lots de figurines pour le temps t.
func update(t: float, tint: Color) -> void:
	if backdrop == null or _buf.is_empty():
		return
	var cnt := {}
	for k: String in KINDS:
		cnt[k] = 0
	for i in units.size():
		var e: Dictionary = units[i]
		var side := int(e["side"])
		var col: Color = (colors[side] as Color) * tint
		col.a = 1.0
		var dcol := Color(col.darkened(0.55), 0.85)
		var kind := String(e["kind"])
		var dk := _dead_kind(kind)
		var sz: Vector2 = SIZES[kind]
		var dsz: Vector2 = SIZES[dk] * (1.4 if kind == "big" else 1.0)
		var shz: Vector2 = SIZES["shadow"]
		var buf: PackedFloat32Array = _buf[kind]
		var dbuf: PackedFloat32Array = _buf[dk]
		var sbuf: PackedFloat32Array = _buf["shadow"]
		var fig_k := float(e.get("fig", 1.0))
		var a := anchor(i, t)
		var mv := moving(i, t)
		var flee := routed(i, t)
		var dirx := (1.0 if side == 0 else -1.0) * (-1.0 if flee else 1.0)
		var offs: Array = e["offsets"]
		var rank: PackedInt32Array = e["rank"]
		var die: PackedFloat32Array = e["die_t"]
		var fade := 1.0
		if flee:
			fade = clampf(1.0 - (t - float(e["rout_t"])) / (DAY_SECONDS * 1.6), 0.0, 1.0)
		var lcol := Color(col, fade)
		var scol := Color(1, 1, 1, 0.6 * fade)
		var bob := 9.0 if kind != "big" else 3.0
		var bob_h := 1.6 if kind != "big" else 2.0
		for j in offs.size():
			var o: Vector3 = offs[j]
			var dt := die[rank[j]]
			if t >= dt:
				# Les corps restent là où la figurine est tombée.
				var ca := anchor(i, dt)
				var cz := ca.y + o.y
				var cs := backdrop.scale_at(cz) * fig_k
				_put(dbuf, cnt[dk], backdrop.project(ca.x + o.x, cz), dsz.x * cs * dirx, dsz.y * cs, dcol)
				cnt[dk] = int(cnt[dk]) + 1
				continue
			if fade <= 0.0:
				continue
			var gz := a.y + o.y
			var s := backdrop.scale_at(gz) * fig_k
			var p := backdrop.project(a.x + o.x, gz)
			if kind == "air":
				p.x += sin(t * 1.4 + o.z) * 18.0 * s
				_put(sbuf, cnt["shadow"], p, shz.x * s, shz.y * s, scol)
				cnt["shadow"] = int(cnt["shadow"]) + 1
				p.y -= 34.0 * s + sin(t * 2.0 + o.z) * 3.0
			elif mv:
				p.y -= absf(sin(t * bob + o.z)) * bob_h * s
			_put(buf, cnt[kind], p, sz.x * s * dirx, sz.y * s, lcol)
			cnt[kind] = int(cnt[kind]) + 1
	for k: String in KINDS:
		var mm := (_mm[k] as MultiMeshInstance2D).multimesh
		mm.buffer = _buf[k]
		mm.visible_instance_count = int(cnt[k])


func living_total(t: float) -> int:
	var c := 0
	for i in units.size():
		c += alive_count(i, t)
	return c
