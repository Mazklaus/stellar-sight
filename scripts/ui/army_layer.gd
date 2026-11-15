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
const MASK_SHADER := preload("res://shaders/figure_mask.gdshader")
## Ordre de dessin des lots : corps et épaves, ombres, fantassins, véhicules, grandes figures, aérien.
const LAYERS := ["corpse", "wreck", "shadow", "mil", "inf", "tank", "big", "air"]

var backdrop: GroundBackdrop
var report: Dictionary = {}
var scale_level := 0
var reduced := false           # moitié des figurines (sous le plancher d'images par seconde)
var colors: Array = [Color(0.85, 0.6, 0.3), Color(0.4, 0.65, 0.95)]
var units: Array = []          # par unité : {fam, kind, n, side, offsets, rank, die_t, base, rout_t, tactic}
var total := 0
var cap_hit := false

var side_fids: Array = ["", ""]  # peuple de chaque camp (allure par défaut de ses régiments)
var _mm: Dictionary = {}       # clé d'allure -> MultiMeshInstance2D
var _buf: Dictionary = {}      # clé d'allure -> PackedFloat32Array (12 flottants par figurine)
var _size: Dictionary = {}     # clé d'allure -> taille à l'écran (échelle 1)
var _mat: ShaderMaterial
var _dmg_until: Array = []
var _dead_day: Array = []
var _days := 1
var _works: Array = []         # positions défensives : [genre, gx, gz0, gz1, graine]
var _t := 0.0


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = MASK_SHADER


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


## Clés d'allure (vivant, mort) d'un régiment : corps et équipement pour les fantassins, véhicule,
## appareil ou grande figure ; corps, éboulis ou épave une fois tombé.
static func look_keys(kind: String, ty: String, lk: Dictionary) -> Array:
	match kind:
		"mil", "inf":
			return ["%s|%s|%s" % [kind, lk.get("body", "bipede"), lk.get("gear", "aucun")], "corpse|%s" % lk.get("corpse", "corps")]
		"tank":
			return ["tank|%s" % lk.get("vehicle", "chenilles"), "wreck|%s" % lk.get("vehicle", "chenilles")]
		"big":
			var b := "colosse" if ty == "colosses" else "marcheur"
			return ["big|" + b, "corpse|eboulis" if b == "colosse" else "wreck|chenilles"]
		"air":
			return ["air|%s" % lk.get("air", "chasseur"), "wreck|chenilles"]
	return ["inf|bipede|aucun", "corpse|corps"]


func setup(r: Dictionary, bd: GroundBackdrop, level: int, dmg_until: Array, dead_day: Array, side_colors: Array, fids: Array = ["", ""]) -> void:
	report = r
	side_fids = fids
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
		var fid := String(u.get("sp", ""))
		if fid == "" or GameData.faction(fid).is_empty():
			fid = String(side_fids[side])
		var lk := SpeciesLook.look(fid, ty)
		var keys := look_keys(kind, ty, lk)
		var e := {"fam": fam, "kind": kind, "n": n, "side": side, "base": anchors[i], "tactic": tac,
				"key": keys[0], "dkey": keys[1], "gait": float(lk.get("gait", 9.0)), "lscale": float(lk.get("scale", 1.0)),
				"rout_t": -1.0 if not routs.has(i) else (float(routs[i]) + 0.85) * DAY_SECONDS}
		_formation(e, i)
		_deaths(e, i)
		units.append(e)
		total += n
	_alloc()
	_plan_works()


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
## ses positions ; un régiment en déroute repart vers l'arrière.
func anchor(i: int, t: float) -> Vector2:
	var e: Dictionary = units[i]
	var b: Vector3 = e["base"]
	var x := b.x
	var side := int(e["side"])
	if side == 0:
		x -= 220.0 * (1.0 - smoothstep(0.0, DAY_SECONDS * 1.3, t))
		x += 60.0 * smoothstep(DAY_SECONDS, _days * DAY_SECONDS, t)
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
	return p - Vector2(0, FigureArt.size_of(String(e["key"])).y * 0.5 * backdrop.scale_at(gz) + lift)


## Lots de figurines (un par clé d'allure, rangés par couche de dessin) et leur capacité, fixés au montage.
func _alloc() -> void:
	for mi in _mm.values():
		(mi as Node).queue_free()
	_mm.clear()
	_buf.clear()
	_size.clear()
	var cap := {}
	for e: Dictionary in units:
		var n := int(e["n"])
		for k: String in [String(e["key"]), String(e["dkey"])]:
			cap[k] = int(cap.get(k, 0)) + n
		if String(e["kind"]) == "air":
			cap["shadow"] = int(cap.get("shadow", 0)) + n
	var keys: Array = cap.keys()
	keys.sort_custom(func(x: String, y: String) -> bool:
		var lx := LAYERS.find(x.split("|")[0])
		var ly := LAYERS.find(y.split("|")[0])
		return lx < ly if lx != ly else x < y)
	for k: String in keys:
		var mi := MultiMeshInstance2D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = _quad()
		mm.instance_count = maxi(1, int(cap[k]))
		mm.visible_instance_count = 0
		mi.multimesh = mm
		var tex: Array = FigureArt.textures(k)
		mi.texture = tex[0]
		var mat := _mat.duplicate() as ShaderMaterial
		mat.set_shader_parameter("mask_tex", tex[1])
		mi.material = mat
		mi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(mi)
		_mm[k] = mi
		_size[k] = FigureArt.size_of(k)
		var b := PackedFloat32Array()
		b.resize(mm.instance_count * 12)
		_buf[k] = b


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
	for k: String in _buf:
		cnt[k] = 0
	for i in units.size():
		var e: Dictionary = units[i]
		var side := int(e["side"])
		var col: Color = colors[side]
		col.a = 1.0
		var dcol := Color(col.darkened(0.55), 0.85)
		var kind := String(e["kind"])
		var key := String(e["key"])
		var dk := String(e["dkey"])
		var ls := float(e.get("lscale", 1.0))
		var sz: Vector2 = _size[key] * ls
		var dsz: Vector2 = _size[dk] * ls * (1.4 if kind == "big" else 1.0)
		var shz: Vector2 = FigureArt.size_of("shadow")
		var buf: PackedFloat32Array = _buf[key]
		var dbuf: PackedFloat32Array = _buf[dk]
		var sbuf: PackedFloat32Array = _buf.get("shadow", PackedFloat32Array())
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
		var bob := float(e.get("gait", 9.0))
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
			_put(buf, cnt[key], p, sz.x * s * dirx, sz.y * s, lcol)
			cnt[key] = int(cnt[key]) + 1
	for k: String in _buf:
		var mi: MultiMeshInstance2D = _mm[k]
		var mm := mi.multimesh
		mm.buffer = _buf[k]
		mm.visible_instance_count = int(cnt[k])
		(mi.material as ShaderMaterial).set_shader_parameter("tint", tint)
	_t = t
	queue_redraw()


## Premier lot de figurines dont la clé d'allure commence par prefix (corpse, inf, tank…).
func batch(prefix: String) -> MultiMesh:
	var keys: Array = _mm.keys()
	keys.sort()
	for k: String in keys:
		if k.begins_with(prefix):
			return (_mm[k] as MultiMeshInstance2D).multimesh
	return null


func living_total(t: float) -> int:
	var c := 0
	for i in units.size():
		c += alive_count(i, t)
	return c


# --- Positions défensives ----------------------------------------------------------------------

## Retranchements du défenseur devant chaque régiment, choisis selon ce qu'il a : fortifications
## (tranchées, casemates), citadelle (mur d'énergie), bastion (tourelles), tactique (défense,
## civils, résistance), famille (blindés à l'abri d'un talus, aérien sur une aire). Obstacles
## (hérissons, barbelés) dans le no man's land si la place est fortifiée.
func _plan_works() -> void:
	_works.clear()
	var sc: Dictionary = report.get("sc", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sc.get("seed", 1)) * 13 + 5
	var fortified := int(sc.get("fort_max", 0)) > 0
	var pool: Array = ["sacs", "sacs"]
	if fortified:
		pool += ["tranchee", "casemate", "tranchee"]
	if bool(sc.get("citadel", false)):
		pool += ["bouclier", "bouclier"]
	if bool(sc.get("bastion", false)):
		pool += ["tourelle", "tourelle"]
	var td := String(report.get("td", ""))
	match td:
		"defense":
			pool += ["tranchee", "casemate", "sacs"]
		"civils":
			pool += ["barricade", "barricade"]
		"resistance":
			pool += ["ruines", "trous"]
	var front := INF
	var z0 := 1.0
	var z1 := 0.0
	for i in units.size():
		var e: Dictionary = units[i]
		if int(e["side"]) != 1:
			continue
		var ext := _extent(e)
		var b: Vector3 = e["base"]
		var gx := b.x + float(ext.x) - 8.0
		var a0 := b.y + float(ext.y)
		var a1 := b.y + float(ext.z)
		var kind: String
		match String(e["fam"]):
			"milice":
				kind = ["barricade", "trous", "sacs"][rng.randi() % 3]
			"blindes":
				kind = "talus"
			"aerien":
				kind = "aire"
				gx = b.x
			_:
				kind = String(pool[rng.randi() % pool.size()])
		_works.append([kind, gx, a0 - 0.02, a1 + 0.02, rng.randi()])
		front = minf(front, gx)
		z0 = minf(z0, a0)
		z1 = maxf(z1, a1)
	if front < INF and (fortified or td == "defense"):
		var z := z0
		while z < z1:
			var len_z := rng.randf_range(0.06, 0.14)
			_works.append(["herissons" if rng.randf() < 0.5 else "barbeles", front - rng.randf_range(40.0, 70.0), z, minf(z1, z + len_z), rng.randi()])
			z += len_z + rng.randf_range(0.04, 0.1)
	_works.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) < float(b[2]))


## Emprise d'un régiment autour de son ancre : (dx min, dz min, dz max).
func _extent(e: Dictionary) -> Vector3:
	var mnx := 0.0
	var mnz := 0.0
	var mxz := 0.0
	for o: Vector3 in e["offsets"]:
		mnx = minf(mnx, o.x)
		mnz = minf(mnz, o.y)
		mxz = maxf(mxz, o.y)
	return Vector3(mnx, mnz, mxz)


func _draw() -> void:
	if backdrop == null:
		return
	var tint := backdrop.tint
	for wk: Array in _works:
		_draw_work(String(wk[0]), float(wk[1]), float(wk[2]), float(wk[3]), int(wk[4]), tint)


func _draw_work(kind: String, gx: float, z0: float, z1: float, seed_value: int, tint: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var a := backdrop.project(gx, z0)
	var b := backdrop.project(gx, z1)
	var zm := (z0 + z1) * 0.5
	var s := backdrop.scale_at(zm)
	var earth := Color(0.42, 0.36, 0.28) * tint
	var sand := Color(0.66, 0.6, 0.46) * tint
	var concrete := Color(0.55, 0.55, 0.56) * tint
	var steps := maxi(2, int(a.distance_to(b) / (7.0 * s)))
	match kind:
		"sacs":
			for layer in 2:
				for k in steps:
					var p := a.lerp(b, (k + 0.5 * layer) / steps) - Vector2(0, layer * 3.5 * s)
					_oval(p, 4.2 * s, 2.4 * s, sand.darkened(0.1 * layer))
		"tranchee":
			var off := Vector2(10.0 * s, 0)
			draw_colored_polygon(PackedVector2Array([a, b, b + off, a + off]), Color(0.12, 0.1, 0.08, 0.75))
			draw_line(a - Vector2(2 * s, 2 * s), b - Vector2(2 * s, 2 * s), earth.lightened(0.15), 3.0 * s)
			for k in steps / 2:
				var p := a.lerp(b, (k + 0.5) / (steps / 2.0)) + Vector2(5 * s, 0)
				draw_line(p - Vector2(0, 3 * s), p + Vector2(0, 1 * s), Color(0.3, 0.24, 0.16) * tint, 1.0)
		"casemate":
			_draw_work("sacs", gx, z0, z1, seed_value, tint)
			var c := backdrop.project(gx + 4.0, zm)
			var bw := 26.0 * s
			var bh := 13.0 * s
			draw_colored_polygon(PackedVector2Array([c + Vector2(-bw * 0.5, 0), c + Vector2(-bw * 0.42, -bh), c + Vector2(bw * 0.42, -bh), c + Vector2(bw * 0.5, 0)]), concrete)
			draw_colored_polygon(_half_dome(c + Vector2(0, -bh), bw * 0.3, bh * 0.5), concrete.lightened(0.1))
			draw_line(c + Vector2(-bw * 0.4, -bh * 0.55), c + Vector2(bw * 0.05, -bh * 0.55), Color(0.05, 0.05, 0.06), 2.0 * s)
			draw_line(c + Vector2(-bw * 0.42, -bh * 0.55), c + Vector2(-bw * 0.75, -bh * 0.6), Color(0.2, 0.2, 0.22), 2.0 * s)
		"tourelle":
			for q in [0.25, 0.75]:
				var c: Vector2 = a.lerp(b, q)
				_oval(c, 9.0 * s, 4.0 * s, concrete.darkened(0.2))
				draw_colored_polygon(_half_dome(c - Vector2(0, 2 * s), 7.0 * s, 6.0 * s), concrete)
				var ang := PI + sin(_t * 0.9 + q * 7.0) * 0.25
				var mz := c - Vector2(0, 6 * s)
				draw_line(mz, mz + Vector2(cos(ang), sin(ang) * 0.4) * 14.0 * s, Color(0.25, 0.25, 0.28), 2.5 * s)
				draw_circle(mz, 1.6 * s, Color(0.45, 0.9, 1.0, 0.9))
		"bouclier":
			var hh := 30.0 * s
			var pulse := 0.5 + 0.5 * sin(_t * 2.2 + seed_value % 7)
			draw_colored_polygon(PackedVector2Array([a, b, b - Vector2(0, hh), a - Vector2(0, hh)]), Color(0.45, 0.75, 1.0, 0.1 + 0.06 * pulse))
			draw_line(a - Vector2(0, hh), b - Vector2(0, hh), Color(0.6, 0.85, 1.0, 0.55 + 0.3 * pulse), 1.6)
			for k in 4:
				var q := fposmod(_t * 0.25 + k * 0.25, 1.0)
				draw_line(a.lerp(b, q), a.lerp(b, q) - Vector2(0, hh), Color(0.7, 0.9, 1.0, 0.25), 1.0)
			_oval(a, 3 * s, 2 * s, concrete)
			_oval(b, 3 * s, 2 * s, concrete)
		"barricade":
			for k in steps / 2 + 1:
				var p := a.lerp(b, float(k) / maxf(1.0, steps / 2.0)) + Vector2(rng.randf_range(-4, 4) * s, 0)
				var bw := rng.randf_range(6.0, 12.0) * s
				var bh := rng.randf_range(4.0, 8.0) * s
				var col := [Color(0.5, 0.3, 0.22), Color(0.35, 0.38, 0.42), Color(0.6, 0.55, 0.3)][rng.randi() % 3] as Color
				draw_set_transform(p, rng.randf_range(-0.4, 0.4), Vector2.ONE)
				draw_rect(Rect2(Vector2(-bw * 0.5, -bh), Vector2(bw, bh)), col * tint)
				draw_set_transform(Vector2.ZERO)
		"ruines":
			for k in steps / 2 + 1:
				var p := a.lerp(b, float(k) / maxf(1.0, steps / 2.0))
				if k % 2 == 0:
					var hh := rng.randf_range(6.0, 16.0) * s
					draw_colored_polygon(PackedVector2Array([p + Vector2(-5 * s, 0), p + Vector2(-5 * s, -hh), p + Vector2(0, -hh * 0.7), p + Vector2(4 * s, -hh * 0.9), p + Vector2(4 * s, 0)]), concrete.darkened(0.15))
				else:
					draw_colored_polygon(BattleBackdrop.rock(p - Vector2(0, 2 * s), 4.0 * s, rng.randi(), 6), concrete.darkened(0.3))
		"trous":
			for k in steps / 2 + 1:
				var p := a.lerp(b, float(k) / maxf(1.0, steps / 2.0)) + Vector2(rng.randf_range(-6, 6) * s, 0)
				_oval(p, 6.0 * s, 2.6 * s, Color(0.1, 0.08, 0.07, 0.7))
				draw_arc(p, 6.0 * s, PI, TAU, 10, earth.lightened(0.1), 1.5)
		"talus":
			var off := Vector2(-14.0 * s, 0)
			draw_colored_polygon(PackedVector2Array([a + off, b + off, b - Vector2(0, 7 * s), a - Vector2(0, 7 * s)]), earth)
			draw_line(a - Vector2(0, 7 * s), b - Vector2(0, 7 * s), earth.lightened(0.2), 1.5)
		"aire":
			var c := backdrop.project(gx, zm)
			_oval(c, 38.0 * s, 13.0 * s, Color(concrete.darkened(0.3), 0.8))
			draw_set_transform(c, 0.0, Vector2(1.0, 0.34))
			draw_arc(Vector2.ZERO, 30.0 * s, 0.0, TAU, 24, Color(1.0, 0.8, 0.3, 0.6), 1.5)
			draw_set_transform(Vector2.ZERO)
		"herissons":
			for k in steps / 2 + 1:
				var p := a.lerp(b, float(k) / maxf(1.0, steps / 2.0)) + Vector2(rng.randf_range(-8, 8) * s, 0)
				var r := 5.0 * s
				var col := Color(0.25, 0.24, 0.24) * tint
				draw_line(p + Vector2(-r, 0), p + Vector2(r, -r * 1.4), col, 1.5)
				draw_line(p + Vector2(r, 0), p + Vector2(-r, -r * 1.4), col, 1.5)
				draw_line(p + Vector2(0, 0.5 * r), p + Vector2(0, -r * 1.2), col, 1.5)
		"barbeles":
			var pts := PackedVector2Array()
			for k in steps * 2 + 1:
				var q := float(k) / (steps * 2)
				pts.append(a.lerp(b, q) + Vector2((3.0 if k % 2 == 0 else -3.0) * s, -3.0 * s))
			draw_polyline(pts, Color(0.35, 0.33, 0.3, 0.85) * tint, 1.0)
			for k in steps + 1:
				var p := a.lerp(b, float(k) / steps)
				draw_line(p, p - Vector2(0, 7 * s), Color(0.3, 0.22, 0.14) * tint, 1.2)


func _oval(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, ry / maxf(0.01, rx)))
	draw_circle(Vector2.ZERO, rx, col)
	draw_set_transform(Vector2.ZERO)


func _half_dome(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 13:
		var ang := PI + PI * float(k) / 12.0
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	return pts
