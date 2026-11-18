class_name HullArt
extends RefCounted
## Silhouettes 2D des coques (étude visuel des combats, lot 3, prop. 14 ; étude « Les chantiers des
## peuples », lot 3) : une par style de peuple (fuseau, nef, brique, treillis, bricole, organique, cristal,
## roc) et par coque. Dessinées pixel par pixel, vues de dessus, nez vers la droite, avec leurs normales
## pour l'éclairage de l'étoile (shaders/ship_lit.gdshader) : un vaisseau sans sprite pré-rendu (ShipArt)
## a quand même une coque à sa forme et à celle de son peuple.
##
## Trois couches se superposent :
## - la forme de la coque ("shapes" : largeur, "form" qui change le contour, pièces) : chaque classe se
##   distingue par sa silhouette (dard, épaules, pont plat, couronne…), chaque coque de peuple a la sienne ;
## - la signature du style de peuple, sur toutes ses coques (voiles, flèches, ailes en V, sacs, cornes,
##   pièces flottantes…), dessinée par _signature ;
## - les modules posés (tourelles, canon, hangar, plaques, bouclier, voile de furtivité), lus dans les
##   caractéristiques du vaisseau ou du modèle en cours de conception.
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
var _form := ""
var _sid := ""
var _seed := 0
var _tint := Color.WHITE


static func cfg() -> Dictionary:
	return GameData.battle_visuals().get("hulls", {})


## Forme montrée pour une coque : la sienne, sinon celle de la coque dont elle est une variante, sinon "".
static func shape_of_hull(hull_id: String) -> String:
	var shapes: Dictionary = cfg().get("shapes", {})
	var h := hull_id
	while h != "":
		if shapes.has(h):
			return h
		h = String(Designs.hull(h).get("variant_of", ""))
	return ""


## Coque montrée pour une classe : celle du modèle, sinon une forme selon la taille.
static func shape_id(ship_id: String) -> String:
	var sh := shape_of_hull(ShipArt.hull_of(ship_id))
	if sh != "":
		return sh
	return _size_shape(String(GameData.ship(ship_id).get("size", "small")))


static func _size_shape(size: String) -> String:
	match size:
		"medium": return "fregate"
		"large": return "croiseur"
		"titan": return "titan"
	return "corvette"


static func _shape(sid: String) -> Dictionary:
	var shapes: Dictionary = cfg().get("shapes", {})
	return shapes.get(sid, shapes.get("_default", {}))


## Pièces de la coque : celles de sa forme, plus celle du rôle d'une classe sans modèle, plus celles de
## ses modules.
static func parts_of(ship_id: String) -> Array:
	var sid := shape_id(ship_id)
	var parts: Array = (_shape(sid).get("parts", []) as Array).duplicate()
	var role := String(GameData.ship(ship_id).get("role", ""))
	var extra := String(cfg().get("roles", {}).get(role, ""))
	if extra != "" and not parts.has(extra):
		parts.append(extra)
	_add_module_parts(parts, GameData.ship(ship_id))
	return parts


## Pièces montrées par les modules posés (prop. 35) : armes en tourelles, artillerie et torpilles en long
## canon, hangars, plaques sur les flancs, bouclier, voile de furtivité.
static func _add_module_parts(parts: Array, sd: Dictionary) -> void:
	var w: Dictionary = sd.get("weapons", {})
	var add := func(p: String) -> void:
		if not parts.has(p):
			parts.append(p)
	for fam in w:
		if int(w[fam]) <= 0:
			continue
		if fam in ["fighters", "bombers"]:
			add.call("hangar")
		elif fam in ["artillery", "stellar_lance", "singularity"]:
			add.call("canon")
		elif fam in ["kinetic", "beam", "missile", "torpedo", "psychic"]:
			add.call("tourelles")
	var mods: Array = sd.get("modules", [])
	if mods.count("plaques_blindage") >= 2:
		add.call("blindage")
	if mods.has("bouclier") or mods.has("boucliers_durcis") or int(sd.get("shield_fleet", 0)) > 0:
		add.call("bouclier")
	if int(sd.get("cloak", 0)) > 0:
		add.call("voile")


## Sprite éclairable (CanvasTexture : couleur + normales) d'une classe pour un style et une couleur.
static func lit_texture(style: String, ship_id: String, tint: Color) -> CanvasTexture:
	var sid := shape_id(ship_id)
	var parts := parts_of(ship_id)
	var key := "%s|%s|%s|%s" % [style, sid, ",".join(parts), tint.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var ct := CanvasTexture.new()
	var art := art_path(style, sid)
	if art != "":
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


## Fichier de remplacement (prop. 40) : assets/battle/hulls/<style>_<forme>.png, ou "" s'il n'existe pas.
static func art_path(style: String, sid: String) -> String:
	var art := String(cfg().get("art", "res://assets/battle/hulls/%s.png")) % ("%s_%s" % [style, sid])
	return art if ResourceLoader.exists(art) else ""


## Image (couleur seule) d'une coque équipée de modules, pour l'interface : Chantier (modèle en cours),
## vignettes. hull_id + modules : comme Designs.compute.
static func hull_texture(style: String, hull_id: String, modules: Array, tint: Color) -> Texture2D:
	var sid := shape_of_hull(hull_id)
	var size := String(Designs.hull(hull_id).get("size", "small"))
	if sid == "":
		sid = _size_shape(size)
	var parts: Array = (_shape(sid).get("parts", []) as Array).duplicate()
	var sd := Designs.compute(hull_id, modules)
	sd["modules"] = modules
	_add_module_parts(parts, sd)
	var key := "ui|%s|%s|%s|%s" % [style, sid, ",".join(parts), tint.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D
	var art := art_path(style, sid)
	if art != "":
		tex = load(art)
	else:
		var ha := HullArt.new()
		ha._paint(style, sid, parts, size, tint)
		tex = ImageTexture.create_from_image(ha.img)
	_cache[key] = tex
	return tex


## Vignette d'une classe ou d'un modèle (liste du Chantier, rapport de bataille, carte).
static func icon(style: String, ship_id: String, tint: Color) -> Texture2D:
	return lit_texture(style, ship_id, tint).diffuse_texture


## Peint la coque dans img (couleur) et nrm (normales).
func paint(style: String, ship_id: String, tint: Color) -> void:
	_paint(style, shape_id(ship_id), parts_of(ship_id), String(GameData.ship(ship_id).get("size", "small")), tint)


func _paint(style: String, sid: String, parts: Array, size: String, tint: Color) -> void:
	var styles: Dictionary = cfg().get("styles", {})
	_style = (styles.get(style, styles.get("fuseau", {})) as Dictionary).duplicate()
	_style["id"] = style
	_sid = sid
	var sh := _shape(sid)
	_width = float(sh.get("width", 0.24))
	_form = String(sh.get("form", ""))
	_parts = parts
	_tint = tint
	_seed = hash(style + _sid)
	W = int(float(cfg().get("sizes", {}).get(size, 64)) * float(sh.get("scale", 1.0)) * SS)
	H = int(W * _width * 2.0 * 2.3) + 6
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
			if a > 0.0 and _form == "anneau":
				# Onde-nef : un anneau de lumière autour d'un petit cœur, vide entre les deux.
				var rr := Vector2((u - 0.5) * 2.0, dy / maxf(1.0, W * _width)).length()
				if rr > 0.2 and rr < 0.62:
					a = 0.0
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
			if _parts.has("voile"):
				c.a = a * (0.55 + 0.25 * _noise(x + 11, y))  # voile de furtivité : la coque se brouille
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
	p = _form_profile(p, v, side)
	if _parts.has("canon") and u > 0.55:
		p = maxf(p, 0.11 if u < 0.99 else 0.0)
	if _parts.has("eperon") and u > 0.7:
		p = maxf(p, (1.0 - u) * 1.4)
	if _parts.has("soute") and u > 0.3 and u < 0.62:
		p = maxf(p, 1.08)
	if _parts.has("ville") and u > 0.2 and u < 0.75:
		p = maxf(p, 1.0)
	return clampf(p, 0.0, 1.4)


## Contour propre à la forme de la coque (prop. 31 et 33) : chaque classe et chaque coque de peuple a
## sa silhouette, quel que soit le style du peuple. p : demi-largeur du style, v : abscisse (0 poupe, 1 proue).
func _form_profile(p: float, v: float, side: float) -> float:
	if v > 1.0 or p <= 0.0 and _form not in ["sac", "plat", "anneau", "relie"]:
		return p
	match _form:
		"dard":  # corvette, éclaireurs : une pointe
			return p * clampf(1.15 - v * 0.75, 0.25, 1.0)
		"epaules":  # cuirassé : larges épaules au milieu
			return maxf(p, 1.12) if v > 0.3 and v < 0.56 else p
		"plat":  # porte-vaisseaux : pont d'envol rectangulaire
			return 0.0 if v > 1.0 else (0.92 if v > 0.08 and v < 0.86 else (0.6 if v >= 0.86 else p))
		"couronne":  # titans : une couronne de pointes à la poupe
			return 1.25 if v < 0.22 and posmod(int(v * 27.0), 2) == 0 else p
		"eperon":  # Martyr : corps fin, éperon
			return p * 0.7
		"sac":  # Ruche-mère, Mère-monde : un ventre
			var t := (v - 0.4) / 0.46
			return 1.12 * sqrt(maxf(0.0, 1.0 - t * t)) if v < 0.86 else (0.25 if v <= 1.0 else 0.0)
		"relie":  # Châssis relié, Noosphère-mère : modules séparés, reliés par des filins
			for b in [[0.04, 0.28], [0.38, 0.62], [0.72, 0.96]]:
				if v >= float(b[0]) and v <= float(b[1]):
					return 0.85
			return 0.07 if v <= 1.0 else 0.0
		"anneau":  # Onde-nef : un disque (évidé dans paint)
			return sqrt(maxf(0.0, 1.0 - pow(2.0 * v - 1.0, 2.0))) if v <= 1.0 else 0.0
		"asym":  # Épave, Comète-marché : un flanc plus gros que l'autre
			return p * (1.15 if side < 0 else 0.75)
		"montagne":  # Montagne-forteresse, Astéroïde : un bloc de roc
			return maxf(p, (0.9 + 0.2 * _rnd(int(v * 12.0) + (40 if side > 0 else 0))) * sqrt(maxf(0.0, 1.0 - pow(2.0 * v - 1.0, 2.0))))
		"voilier":  # Grand Voilier : long et fin (les voiles sont dans _signature)
			return p * 0.75
		"tour":  # croiseur : une tour au tiers arrière
			return maxf(p, 1.05) if v > 0.24 and v < 0.36 else p
	return p


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


## Éléments hors de la coque : voiles de la nef, ailerons, antenne, signature du peuple. {} si rien.
func _extra(u: float, dy: float, hw: float) -> Dictionary:
	var sig := _signature(u, dy, hw)
	if not sig.is_empty():
		return sig
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


## Signature du style de peuple (prop. 32), hors de la coque, sur toutes ses coques : un motif qui
## se reconnaît de loin (leçon d'Endless Sky et d'Ashes of the Singularity). {} si rien ici.
func _signature(u: float, dy: float, hw: float) -> Dictionary:
	var ext := W * _width
	var ay := absf(dy)
	if ay <= hw:
		return {}
	var flat := Color(0.5, 0.5, 1.0)
	var metal := _col(_style.get("metal", [0.7, 0.7, 0.7]))
	var engine := _col(_style.get("engine", [0.6, 0.8, 1.0]))
	match String(_style["id"]):
		"fuseau":  # ailes en V vers la poupe
			if u > 0.04 and u < 0.34:
				var reach := hw + ext * 1.1 * (0.34 - u) / 0.3
				if ay < reach and ay > hw:
					return {"c": metal.darkened(0.15), "n": flat}
		"brique":  # flèches gothiques le long des flancs
			for uc in [0.3, 0.46, 0.62]:
				var d := absf(u - float(uc))
				if d < 0.035 and ay < hw + ext * 0.45 * (1.0 - d / 0.035):
					return {"c": metal.darkened(0.3), "n": flat}
		"bricole":  # une nacelle rapportée d'un seul côté, une caisse de l'autre
			if dy < 0.0 and u > 0.34 and u < 0.56 and ay < hw + ext * 0.5:
				return {"c": Color(0.42, 0.54, 0.6), "n": flat}
			if dy > 0.0 and u > 0.46 and u < 0.58 and ay < hw + ext * 0.28:
				return {"c": Color(0.72, 0.32, 0.24), "n": flat}
		"organique":  # sacs verts sur les flancs
			var sac := Vector2((u - 0.42) * W / maxf(1.0, ext * 0.7), (ay - hw - ext * 0.18) / maxf(1.0, ext * 0.2))
			if sac.length() < 1.0:
				return {"c": Color(0.5, 0.75, 0.3).lerp(engine, 0.3), "n": flat}
		"cristal":  # pièces flottantes, sans attache
			for c in [[0.2, 1.35, 0.32], [0.62, 1.25, 0.26]]:
				var d2 := Vector2((u - float(c[0])) * W, ay - ext * float(c[1])).length()
				if d2 < ext * float(c[2]):
					var glow := Color(0.92, 0.88, 1.0).lerp(metal, d2 / maxf(1.0, ext * float(c[2])))
					return {"c": glow, "n": flat}
		"roc":  # cornes à la proue
			if u > 0.72 and u < 0.97:
				var horn := hw + ext * 0.8 * (u - 0.72) / 0.25
				if ay < horn and ay > horn - ext * 0.22:
					return {"c": Color(0.85, 0.79, 0.66), "n": flat}
	# Grand Voilier : des voiles immenses, quel que soit le style.
	if _form == "voilier" and u > 0.2 and u < 0.8:
		var reach2 := hw + ext * 1.6 * sin(PI * (u - 0.2) / 0.6)
		if ay < reach2:
			var sc := _tint.lerp(Color(0.95, 0.9, 0.8), 0.5)
			sc.a = 0.75
			return {"c": sc, "n": flat}
	return {}
