class_name HullArt
extends RefCounted
## Silhouettes 2D des coques pour la vue de bataille spatiale (étude visuel des combats, lot 3, prop. 14) :
## une par style de peuple (fuseau, nef, brique, treillis, bricole, organique, cristal, roc) et par coque
## (corvette, croiseur, porte-vaisseaux, titan, nef-monde…). Dessinées pixel par pixel, vues de dessus,
## nez vers la droite, avec leurs normales pour l'éclairage de l'étoile (shaders/ship_lit.gdshader) :
## un vaisseau sans sprite pré-rendu (ShipArt) a quand même une coque à sa forme et à celle de son peuple.
## Tout vient du bloc "hulls" de data/battle_visuals.json ; un PNG posé à
## assets/battle/hulls/<style>_<coque>.png (et _n.png pour les normales) remplace le dessin.

const SS := 2.0  # pixels d'image par pixel d'écran

static var _cache := {}

var img: Image
var nrm: Image
var W := 1
var H := 1
var _style := {}
var _parts: Array = []
var _width := 0.24
var _sid := ""
var _seed := 0
var _tint := Color.WHITE


static func cfg() -> Dictionary:
	return GameData.battle_visuals().get("hulls", {})


## Coque montrée pour une classe : celle du modèle, sinon une forme selon la taille.
static func shape_id(ship_id: String) -> String:
	var shapes: Dictionary = cfg().get("shapes", {})
	var h := ShipArt.hull_of(ship_id)
	while h != "":
		if shapes.has(h):
			return h
		h = String(Designs.hull(h).get("variant_of", ""))
	match String(GameData.ship(ship_id).get("size", "small")):
		"medium": return "fregate"
		"large": return "croiseur"
		"titan": return "titan"
	return "corvette"


## Pièces de la coque : celles de sa forme, plus celle du rôle d'une classe sans modèle.
static func parts_of(ship_id: String) -> Array:
	var shapes: Dictionary = cfg().get("shapes", {})
	var sid := shape_id(ship_id)
	var parts: Array = (shapes.get(sid, shapes.get("_default", {})).get("parts", []) as Array).duplicate()
	var role := String(GameData.ship(ship_id).get("role", ""))
	var extra := String(cfg().get("roles", {}).get(role, ""))
	if extra != "" and not parts.has(extra):
		parts.append(extra)
	var w := Combat.weapons(ship_id)
	if (int(w.get("fighters", 0)) > 0 or int(w.get("bombers", 0)) > 0) and not parts.has("hangar"):
		parts.append("hangar")
	return parts


## Sprite éclairable (CanvasTexture : couleur + normales) d'une classe pour un style et une couleur.
static func lit_texture(style: String, ship_id: String, tint: Color) -> CanvasTexture:
	var sid := shape_id(ship_id)
	var parts := parts_of(ship_id)
	var key := "%s|%s|%s|%s" % [style, sid, ",".join(parts), tint.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var ct := CanvasTexture.new()
	var art := String(cfg().get("art", "res://assets/battle/hulls/%s.png")) % ("%s_%s" % [style, sid])
	if ResourceLoader.exists(art):
		ct.diffuse_texture = load(art)
		var np := art.replace(".png", "_n.png")
		if ResourceLoader.exists(np):
			ct.normal_texture = load(np)
	else:
		var ha := HullArt.new()
		ha.paint(style, ship_id, tint)
		ct.diffuse_texture = ImageTexture.create_from_image(ha.img)
		ct.normal_texture = ImageTexture.create_from_image(ha.nrm)
	_cache[key] = ct
	return ct


## Peint la coque dans img (couleur) et nrm (normales).
func paint(style: String, ship_id: String, tint: Color) -> void:
	var styles: Dictionary = cfg().get("styles", {})
	_style = styles.get(style, styles.get("fuseau", {}))
	_style["id"] = style
	_sid = shape_id(ship_id)
	var shapes: Dictionary = cfg().get("shapes", {})
	_width = float(shapes.get(_sid, shapes.get("_default", {})).get("width", 0.24))
	_parts = parts_of(ship_id)
	_tint = tint
	_seed = hash(style + _sid)
	var size := String(GameData.ship(ship_id).get("size", "small"))
	W = int(float(cfg().get("sizes", {}).get(size, 64)) * SS)
	H = int(W * _width * 2.0 * 1.7) + 6
	img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	nrm = Image.create(W, H, false, Image.FORMAT_RGB8)
	nrm.fill(Color(0.5, 0.5, 1.0))
	var metal := _col(_style.get("metal", [0.7, 0.72, 0.78]))
	var engine := _col(_style.get("engine", [0.5, 0.8, 1.0]))
	var trim := float(_style.get("trim", 0.35))
	var cy := H * 0.5
	for x in W:
		var u := (x + 0.5) / W
		var wt := _half(u, -1.0) * W * _width
		var wb := _half(u, 1.0) * W * _width
		var slope := (_half(minf(1.0, u + 0.02), 1.0) - _half(maxf(0.0, u - 0.02), 1.0)) * _width * 25.0
		for y in H:
			var dy := y + 0.5 - cy
			var hw := wt if dy < 0.0 else wb
			var a := clampf(hw - absf(dy) + 0.5, 0.0, 1.0)
			var extra := _extra(u, dy, hw)
			if a <= 0.0 and extra.is_empty():
				continue
			if a <= 0.0:
				img.set_pixel(x, y, extra["c"])
				nrm.set_pixel(x, y, extra["n"])
				continue
			var yr := clampf(dy / maxf(1.0, hw), -1.0, 1.0)
			var n := _normal(u, yr, slope)
			var c := metal * (0.88 + 0.12 * _noise(x, y))
			# Panneaux : fines lignes sombres en travers de la coque.
			if _style["id"] in ["fuseau", "brique", "treillis", "nef"] and x % int(10 * SS) == 0:
				c = c.darkened(0.25)
			# Bande aux couleurs de l'empire le long de l'échine.
			if absf(yr) < trim * 0.45 and u > 0.18 and u < 0.82:
				c = c.lerp(_tint, 0.75)
			c = _part_color(u, yr, dy, hw, c, engine)
			# Moteurs : la poupe rougeoie.
			if u < 0.045 and absf(yr) < 0.8:
				c = engine.lerp(Color.WHITE, 0.3)
				n = Vector3(0, 0, 1)
			c.a = a
			img.set_pixel(x, y, c)
			nrm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	img.generate_mipmaps()
	nrm.generate_mipmaps()


static func _col(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))


func _noise(x: int, y: int) -> float:
	return float(hash(Vector3i(x / 3, y / 3, _seed)) % 1000) / 1000.0


func _rnd(k: int) -> float:
	return float(hash(Vector2i(k, _seed)) % 1000) / 1000.0


## Demi-largeur relative (0 à 1) de la coque à l'abscisse u (0 poupe, 1 proue), côté haut (-1) ou bas (1).
func _half(u: float, side: float) -> float:
	var nose := 1.0
	if _parts.has("canon"):
		nose = 0.82
	elif _parts.has("eperon"):
		nose = 0.88
	var v := u / nose
	var p := 0.0
	match String(_style["id"]):
		"brique":
			p = 0.85 if v < 0.15 else (1.0 if v < 0.68 else (0.78 if v < 0.88 else (0.58 if v <= 1.0 else 0.0)))
		"nef":
			p = 0.0 if v > 1.0 else (0.55 + v * 2.0 if v < 0.2 else pow(maxf(0.0, 1.0 - (v - 0.2) / 0.8), 0.5) * 0.95)
		"treillis":
			p = 0.0 if v > 1.0 else 0.28
			for b in [[0.12, 0.3], [0.42, 0.6]]:
				if v >= float(b[0]) and v <= float(b[1]):
					p = 0.95
			if v > 0.85 and v <= 1.0:
				p = 0.5
		"bricole":
			var seg := int(v * 6.0)
			p = 0.0 if v > 1.0 else (0.6 + 0.4 * _rnd(seg * 2 + (1 if side > 0 else 0))) * (1.0 if v < 0.75 else (1.0 - v) * 4.0)
		"organique":
			p = 0.0 if v > 1.0 else pow(sin(PI * clampf(v, 0.0, 1.0)), 0.55) * (1.0 + 0.14 * sin(v * 22.0 + side * 1.3))
			if v < 0.22:
				p *= 0.55 + v * 2.0
		"cristal":
			p = 0.0 if v > 1.0 else (v / 0.55 if v < 0.55 else (1.0 - v) / 0.45)
			p = maxf(p, 0.0) * (1.0 if side < 0 else 0.86)
		"roc":
			var r := sqrt(maxf(0.0, 1.0 - pow(2.0 * v - 1.0, 2.0)))
			p = 0.0 if v > 1.0 else r * (0.78 + 0.3 * _rnd(int(v * 9.0) + (20 if side > 0 else 0)))
		_:
			p = 0.0 if v > 1.0 else (lerpf(0.7, 1.0, v / 0.4) if v < 0.4 else pow(1.0 - (v - 0.4) / 0.6, 0.7))
	if _parts.has("canon") and u > 0.55:
		p = maxf(p, 0.11 if u < 0.99 else 0.0)
	if _parts.has("eperon") and u > 0.7:
		p = maxf(p, (1.0 - u) * 1.4)
	if _parts.has("soute") and u > 0.3 and u < 0.62:
		p = maxf(p, 1.08)
	if _parts.has("ville") and u > 0.2 and u < 0.75:
		p = maxf(p, 1.0)
	return clampf(p, 0.0, 1.3)


## Normale vue de dessus (x à droite, y en haut, z vers la caméra) selon le style.
func _normal(u: float, yr: float, slope: float) -> Vector3:
	var ny := -yr
	match String(_style["id"]):
		"brique":
			ny = 0.0 if absf(yr) < 0.55 else -signf(yr) * 0.7
		"cristal":
			ny = -signf(yr) * 0.55
			slope = 0.5 if u < 0.55 else -0.5
		"roc":
			ny = -yr * (0.8 + 0.4 * _noise(int(u * 40), int(yr * 6)))
	var nx := clampf(-slope, -0.6, 0.6)
	var nz := sqrt(maxf(0.05, 1.0 - ny * ny - nx * nx))
	return Vector3(nx, ny, nz).normalized()


## Couleur des pièces posées sur la coque.
func _part_color(u: float, yr: float, dy: float, hw: float, c: Color, engine: Color) -> Color:
	var ay := absf(yr)
	if _parts.has("blindage") and ay > 0.78:
		c = c.darkened(0.3)
	if _parts.has("tour") and u > 0.24 and u < 0.36 and ay < 0.45:
		c = c.lightened(0.22)
	if _parts.has("hangar") and u > 0.34 and u < 0.7 and ay < 0.32:
		c = Color(0.06, 0.06, 0.08)
		if int(u * W) % int(8 * SS) < 2:
			c = engine.lerp(Color.WHITE, 0.4)
	if _parts.has("tourelles"):
		for tu in [0.4, 0.56, 0.72]:
			var dx := (u - float(tu)) * W
			for sgn in [-0.5, 0.5]:
				var d := Vector2(dx, dy - float(sgn) * hw).length()
				if d < hw * 0.22:
					c = c.darkened(0.35) if d > hw * 0.12 else c.lightened(0.3)
	if _parts.has("ville") and u > 0.22 and u < 0.74 and ay < 0.85 and _noise(int(u * W), int(dy)) > 0.86:
		c = Color(1.0, 0.85, 0.5)
	if _parts.has("bouclier") and ay > 0.7 and int(u * 10.0) % 3 == 1:
		c = c.lerp(Color(0.45, 0.8, 1.0), 0.7)
	if String(_style["id"]) == "organique" and _noise(int(u * W) + 7, int(dy)) > 0.9:
		c = c.lerp(engine, 0.5)
	if String(_style["id"]) == "cristal" and absf(yr) < 0.08:
		c = c.lightened(0.35)
	return c


## Éléments hors de la coque : voiles de la nef, ailerons, antenne. {} si rien.
func _extra(u: float, dy: float, hw: float) -> Dictionary:
	var ext := W * _width
	if _style.get("sails", false) and u > 0.3 and u < 0.68:
		var reach := ext * 1.45 * sin(PI * (u - 0.3) / 0.38)
		if absf(dy) > hw and absf(dy) < reach:
			var c := _tint.lerp(Color(0.95, 0.9, 0.8), 0.45)
			c.a = 0.7
			return {"c": c, "n": Color(0.5, 0.5, 1.0)}
	if _parts.has("ailerons") and u < 0.16:
		var reach2 := ext * (1.4 - u * 3.0)
		if absf(dy) > hw and absf(dy) < reach2:
			return {"c": _col(_style.get("metal", [0.7, 0.7, 0.7])).darkened(0.2), "n": Color(0.5, 0.5, 1.0)}
	if _parts.has("antenne") and u > 0.9 and absf(dy) < SS * 0.8:
		return {"c": Color(0.85, 0.85, 0.9), "n": Color(0.5, 0.5, 1.0)}
	return {}
