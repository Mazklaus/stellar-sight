class_name PortraitRig
extends Control
## Essai « portraits animés », méthode 3 (découpage en pièces, à la Live2D / Spine / Stellaris) :
## le portrait est découpé en calques (fond repeint, buste, mâchoire, intérieur de bouche, paupières)
## et le buste porte un maillage déformé par des « os » (poitrine, cou/tête, visage, mâchoire).
## Les pièces sont préparées hors du jeu (assets/art/essais/rig/<id>/ : fond.jpg, corps.png,
## machoire.png, bouche.png, paupiere_0/1.png, rig.json avec sommets, triangles et poids par os).
## La déformation est faite ici sur le processeur (≈ 2 000 sommets par portrait), ce qui revient au
## même que Skeleton2D + Polygon2D de Godot mais se règle plus simplement. Purement visuel.

const RIG_DIR := "res://assets/art/essais/rig/"

## Réglages de l'animation.
var breath_px := 8.0
var breath_period := 4.6
var head_deg := 3.2
var turn_px := 13.0
## Mâchoire qui parle : coupée (jugée inutile par l'utilisateur), gardée en option.
var talk := false
var seed_value := 0.0

var _rig := {}
var _stage: Node2D
var _body: Polygon2D
var _chin: Sprite2D
var _mouth: Sprite2D
var _lids: Array[Sprite2D] = []
var _glows: Array[Sprite2D] = []
var _rest := PackedVector2Array()
var _wh := PackedFloat32Array()
var _wf := PackedFloat32Array()
var _wc := PackedFloat32Array()
var _deformed := PackedVector2Array()
var _t := 0.0


func _init(rig_id := "", slot_size := Vector2(300, 400), seed_v := 0.0) -> void:
	custom_minimum_size = slot_size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	seed_value = seed_v
	if rig_id != "":
		build(rig_id)


static func exists(rig_id: String) -> bool:
	return FileAccess.file_exists(RIG_DIR + rig_id + "/rig.json")


func build(rig_id: String) -> void:
	var dir := RIG_DIR + rig_id + "/"
	_rig = JSON.parse_string(FileAccess.get_file_as_string(dir + "rig.json"))
	var sz := Vector2(_rig["size"][0], _rig["size"][1])
	_stage = Node2D.new()
	add_child(_stage)
	var bg := Sprite2D.new()
	bg.texture = load(dir + "fond.jpg")
	bg.centered = false
	_stage.add_child(bg)
	_rest = PackedVector2Array()
	for v in _rig["verts"]:
		_rest.append(Vector2(v[0], v[1]))
	_wh = PackedFloat32Array(_rig["w_head"])
	_wf = PackedFloat32Array(_rig["w_face"])
	_wc = PackedFloat32Array(_rig["w_chest"])
	_body = Polygon2D.new()
	_body.texture = load(dir + "corps.png")
	_body.polygon = _rest
	_body.uv = _rest
	var polys := []
	for t in _rig["tris"]:
		polys.append(PackedInt32Array(t))
	_body.polygons = polys
	_stage.add_child(_body)
	var box: Array = _rig["chin_box"]
	_mouth = _piece(load(dir + "bouche.png"), box)
	_chin = _piece(load(dir + "machoire.png"), box)
	var glow_tex := _radial()
	var gcol := Color(String(_rig["glow"]))
	for i in (_rig["lids"] as Array).size():
		var g := Sprite2D.new()
		g.texture = glow_tex
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		g.material = mat
		g.modulate = gcol
		var ew := float(_rig["eye"][0])
		g.scale = Vector2(ew * 3.2, ew * 2.0) / 64.0
		_stage.add_child(g)
		_glows.append(g)
		var l := Sprite2D.new()
		l.texture = load(dir + "paupiere_%d.png" % i)
		l.centered = false
		_stage.add_child(l)
		_lids.append(l)
	_layout(sz)
	resized.connect(func() -> void: _layout(sz))
	_update(0.0)


func _piece(tex: Texture2D, box: Array) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = Vector2(box[0], box[1])
	_stage.add_child(s)
	return s


## Le portrait couvre le cadre (comme TextureRect STRETCH_KEEP_ASPECT_COVERED).
func _layout(sz: Vector2) -> void:
	var area := size if size.x > 0.0 else custom_minimum_size
	# Un peu plus grand que le cadre : les bords du maillage (qui bougent) restent hors champ.
	var k := maxf(area.x / sz.x, area.y / sz.y) * 1.02
	_stage.scale = Vector2(k, k)
	_stage.position = (area - sz * k) * 0.5


static func _radial() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _process(delta: float) -> void:
	_t += delta
	_update(_t)


static func _noise(x: float, s: float) -> float:
	var i := floorf(x)
	var f := x - i
	var u := f * f * (3.0 - 2.0 * f)
	var a := fmod(sin(i * 127.1 + s * 31.7) * 43758.5453, 1.0)
	var b := fmod(sin((i + 1.0) * 127.1 + s * 31.7) * 43758.5453, 1.0)
	return lerpf(absf(a), absf(b), u) * 2.0 - 1.0


func _blink(t: float) -> float:
	var every := 4.3
	var slot := floorf(t / every)
	var local := t - slot * every
	var at := 0.5 + absf(fmod(sin(slot * 91.3 + seed_value * 7.0) * 9137.1, 1.0)) * (every - 1.2)
	var d := local - at
	return clampf(1.0 - absf(d - 0.08) / 0.08, 0.0, 1.0)


## Ouverture de la mâchoire (en pixels de l'image) : par moments le personnage « parle ».
func _jaw(t: float) -> float:
	if not talk:
		return 0.0
	var cycle := fmod(t + seed_value * 3.0, 9.0)
	if cycle < 5.5 or cycle > 8.5:
		return 0.0
	var env := clampf((cycle - 5.5) * 4.0, 0.0, 1.0) * clampf((8.5 - cycle) * 4.0, 0.0, 1.0)
	var syl := maxf(0.0, sin(t * 13.0) * 0.6 + _noise(t * 7.0, seed_value) * 0.5)
	return syl * env * float(_rig["eye"][1]) * 1.5


func _update(t: float) -> void:
	if _rig.is_empty():
		return
	var ph := fmod(t + seed_value, breath_period) / breath_period
	var b := 0.5 + 0.5 * sin(ph * TAU - 0.6 * sin(ph * TAU))
	var neck := Vector2(_rig["neck"][0], _rig["neck"][1])
	var ang := deg_to_rad(head_deg) * (_noise(t * 0.17, seed_value + 1.0) + 0.35 * _noise(t * 0.5, seed_value + 4.0))
	var gaze := Vector2(_noise(t * 0.21, seed_value + 2.0), _noise(t * 0.16, seed_value + 3.0) * 0.4)
	var turn := gaze * turn_px
	var hx := float(_rig["head"][0])
	var lift := Vector2(0.0, -breath_px * b)
	var rot := Transform2D(ang, Vector2.ZERO)
	_deformed.resize(_rest.size())
	for i in _rest.size():
		var v := _rest[i]
		# Poitrine : le buste se soulève et s'élargit un peu.
		var wc := _wc[i]
		v += lift * wc
		v.x += (v.x - hx) * 0.004 * b * wc
		# Tête : rotation autour du cou, puis le visage glisse (illusion de tête qui tourne).
		var wh := _wh[i]
		if wh > 0.0:
			var hv := rot * (v - neck) + neck
			v = v.lerp(hv, wh)
			v += turn * _wf[i]
		_deformed[i] = v
	_body.polygon = _deformed
	# Les pièces rattachées à la tête suivent la même transformation (poids pleins).
	var face := Vector2(_rig["face"][0], _rig["face"][1])
	var fr := float(_rig["face"][2])
	var head_xf := func(p: Vector2) -> Vector2:
		var q := p + lift
		q = rot * (q - neck) + neck
		var df := (p - face).length() / fr
		return q + turn * exp(-df * df * 1.6)
	var box: Array = _rig["chin_box"]
	var seam := Vector2(_rig["seam"][0], _rig["seam"][1])
	var base: Vector2 = head_xf.call(seam)
	# Pivot des deux pièces sur la ligne des lèvres, pour tourner avec la tête sans décalage.
	var pivot := seam - Vector2(box[0], box[1])
	_mouth.offset = -pivot
	_mouth.position = base
	_mouth.rotation = ang
	var jaw := _jaw(t)
	_chin.offset = -pivot
	_chin.position = base + Vector2(0.0, jaw).rotated(ang)
	_chin.rotation = ang
	_chin.scale = Vector2(1.0, 1.0 + jaw * 0.004)
	var closed := _blink(t)
	var pulse := 0.75 + 0.25 * sin(t * 1.7 + seed_value)
	for i in _lids.size():
		var lid: Dictionary = _rig["lids"][i]
		var e: Vector2 = head_xf.call(Vector2(lid["pos"][0], lid["pos"][1]))
		var w := float(lid["size"][0])
		var h := float(lid["size"][1])
		var l := _lids[i]
		l.visible = closed > 0.02
		l.scale = Vector2(1.0, closed)
		l.position = e - Vector2(w * 0.5, h * 0.55)
		l.rotation = ang
		_glows[i].position = e
		_glows[i].modulate.a = 0.55 * pulse * (1.0 - closed)
