class_name FigureArt
extends RefCounted
## Silhouettes des figurines de bataille au sol (étude visuel des combats, lot 3) : dessinées pixel par
## pixel, tournées vers la droite, pieds en bas. Chaque silhouette a deux images : la base (couleurs
## propres : peau, métal, pierre…) et un masque (où mettre la couleur de l'empire, prop. 33), mêlés par
## shaders/figure_mask.gdshader. Les clés : "inf|bipede|bouclier", "tank|glisseur", "air|voilier",
## "big|colosse", "corpse|corps"…
## Un PNG posé à res://assets/battle/troops/<clé avec _ à la place de |>.png (et _masque.png) remplace
## le dessin, comme pour les décors (prop. 34).

const PX := 3.0  # pixels de texture par pixel d'écran (à l'échelle 1)
const ART_DIR := "res://assets/battle/troops/"

## Taille à l'écran (échelle 1) de chaque silhouette.
const SIZES := {
	"bipede": Vector2(9, 14), "insecte": Vector2(13, 9), "bloc": Vector2(12, 13), "reptile": Vector2(13, 14),
	"robot": Vector2(9, 15), "feu_follet": Vector2(10, 13),
	"tank": Vector2(22, 12), "air": Vector2(24, 10), "big": Vector2(30, 40), "shadow": Vector2(22, 6),
	"corpse": Vector2(12, 5), "wreck": Vector2(22, 10),
}

static var _cache := {}

var img: Image
var mask: Image
var w := 1
var h := 1


static func size_of(key: String) -> Vector2:
	var parts := key.split("|")
	var k := parts[0]
	if k == "inf" or k == "mil":
		return SIZES.get(parts[1] if parts.size() > 1 else "bipede", SIZES["bipede"])
	return SIZES.get(k, Vector2(10, 10))


## Textures [base, masque] d'une clé (mises en cache).
static func textures(key: String) -> Array:
	if _cache.has(key):
		return _cache[key]
	var file := ART_DIR + key.replace("|", "_")
	var out: Array
	if ResourceLoader.exists(file + ".png"):
		var m: Texture2D = load(file + "_masque.png") if ResourceLoader.exists(file + "_masque.png") else null
		out = [load(file + ".png"), m if m else _blank_mask()]
	else:
		var fa := FigureArt.new()
		fa._paint(key)
		out = [ImageTexture.create_from_image(fa.img), ImageTexture.create_from_image(fa.mask)]
	_cache[key] = out
	return out


static func _blank_mask() -> ImageTexture:
	var m := Image.create(4, 4, false, Image.FORMAT_L8)
	m.fill(Color(0, 0, 0))
	return ImageTexture.create_from_image(m)


func _paint(key: String) -> void:
	var sz := size_of(key) * PX
	w = maxi(4, int(sz.x))
	h = maxi(4, int(sz.y))
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	mask = Image.create(w, h, false, Image.FORMAT_L8)
	mask.fill(Color(0, 0, 0))
	var parts := key.split("|")
	match parts[0]:
		"inf", "mil":
			_body(parts[1] if parts.size() > 1 else "bipede", parts[2] if parts.size() > 2 else "aucun", parts[0] == "mil")
		"tank":
			_vehicle(parts[1] if parts.size() > 1 else "chenilles", false)
		"wreck":
			_vehicle(parts[1] if parts.size() > 1 else "chenilles", true)
		"air":
			_aircraft(parts[1] if parts.size() > 1 else "chasseur")
		"big":
			_big(parts[1] if parts.size() > 1 else "marcheur")
		"corpse":
			_corpse(parts[1] if parts.size() > 1 else "corps")
		"shadow":
			_ellipse(0.5, 0.5, 0.5, 0.5, Color(0, 0, 0, 0.45), 0.0)


# --- Primitives (coordonnées de 0 à 1) ---------------------------------------------------------

func _px(x: int, y: int, col: Color, m: float) -> void:
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	img.set_pixel(x, y, col)
	mask.set_pixel(x, y, Color(m, m, m))


func _rect(x0: float, y0: float, x1: float, y1: float, col: Color, m: float) -> void:
	for y in range(int(y0 * h), int(ceil(y1 * h))):
		for x in range(int(x0 * w), int(ceil(x1 * w))):
			_px(x, y, col, m)


func _ellipse(cx: float, cy: float, rx: float, ry: float, col: Color, m: float) -> void:
	for y in range(int((cy - ry) * h) - 1, int((cy + ry) * h) + 2):
		for x in range(int((cx - rx) * w) - 1, int((cx + rx) * w) + 2):
			var dx := ((x + 0.5) / w - cx) / maxf(0.001, rx)
			var dy := ((y + 0.5) / h - cy) / maxf(0.001, ry)
			if dx * dx + dy * dy <= 1.0:
				_px(x, y, col, m)


func _poly(pts: Array, col: Color, m: float) -> void:
	var poly := PackedVector2Array()
	var mn := Vector2(1, 1)
	var mx := Vector2(0, 0)
	for p: Vector2 in pts:
		poly.append(Vector2(p.x * w, p.y * h))
		mn = mn.min(p)
		mx = mx.max(p)
	for y in range(int(mn.y * h) - 1, int(mx.y * h) + 2):
		for x in range(int(mn.x * w) - 1, int(mx.x * w) + 2):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				_px(x, y, col, m)


func _line(a: Vector2, b: Vector2, col: Color, m: float, thick := 1.0) -> void:
	var n := int(maxf(absf(b.x - a.x) * w, absf(b.y - a.y) * h)) + 1
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		for ox in int(thick):
			_px(int(p.x * w) + ox, int(p.y * h), col, m)


# --- Corps (prop. 29) --------------------------------------------------------------------------

const SKIN := Color(0.78, 0.62, 0.5)
const DARK := Color(0.2, 0.2, 0.22)
const METAL := Color(0.62, 0.64, 0.68)
const PALE := Color(0.92, 0.93, 0.95)


func _body(body: String, gear: String, militia: bool) -> void:
	var team := Color(0.85, 0.85, 0.85)  # sous le masque : teinté par l'empire
	match body:
		"insecte":
			for k in 3:
				var x := 0.3 + k * 0.18
				_line(Vector2(x, 0.6), Vector2(x - 0.1, 1.0), DARK, 0.0, 2)
			_ellipse(0.42, 0.55, 0.34, 0.22, team, 1.0)
			_ellipse(0.42, 0.5, 0.3, 0.1, team.lightened(0.15), 1.0)
			_ellipse(0.82, 0.45, 0.13, 0.2, Color(0.3, 0.28, 0.2), 0.3)
			_line(Vector2(0.9, 0.55), Vector2(1.0, 0.7), DARK, 0.0, 2)
			_line(Vector2(0.84, 0.3), Vector2(0.95, 0.05), DARK, 0.0, 1)
		"bloc":
			_rect(0.22, 0.78, 0.42, 1.0, Color(0.36, 0.32, 0.3), 0.0)
			_rect(0.58, 0.78, 0.78, 1.0, Color(0.36, 0.32, 0.3), 0.0)
			_rect(0.1, 0.18, 0.9, 0.8, Color(0.55, 0.5, 0.46), 0.55)
			_rect(0.35, 0.02, 0.7, 0.2, Color(0.5, 0.45, 0.42), 0.3)
			_line(Vector2(0.3, 0.3), Vector2(0.45, 0.6), DARK, 0.0, 1)
			_line(Vector2(0.65, 0.25), Vector2(0.55, 0.5), DARK, 0.0, 1)
			_rect(0.6, 0.08, 0.66, 0.12, Color(1.0, 0.6, 0.25), 0.0)
		"reptile":
			_poly([Vector2(0.0, 0.85), Vector2(0.35, 0.55), Vector2(0.4, 0.7)], Color(0.4, 0.5, 0.3), 0.3)
			_poly([Vector2(0.3, 0.6), Vector2(0.45, 0.22), Vector2(0.72, 0.28), Vector2(0.68, 0.65)], team, 1.0)
			_poly([Vector2(0.62, 0.12), Vector2(0.98, 0.18), Vector2(0.95, 0.28), Vector2(0.62, 0.3)], Color(0.42, 0.52, 0.32), 0.2)
			_rect(0.36, 0.62, 0.48, 1.0, Color(0.36, 0.44, 0.28), 0.0)
			_rect(0.56, 0.62, 0.68, 1.0, Color(0.36, 0.44, 0.28), 0.0)
		"robot":
			_rect(0.3, 0.02, 0.7, 0.2, METAL, 0.4)
			_rect(0.55, 0.08, 0.66, 0.13, Color(0.3, 1.0, 0.9), 0.0)
			_line(Vector2(0.4, 0.02), Vector2(0.36, -0.05), DARK, 0.0)
			_rect(0.28, 0.24, 0.72, 0.58, team, 1.0)
			_rect(0.33, 0.6, 0.42, 1.0, METAL.darkened(0.3), 0.0)
			_rect(0.58, 0.6, 0.67, 1.0, METAL.darkened(0.3), 0.0)
		"feu_follet":
			for r in [0.48, 0.38, 0.28]:
				_ellipse(0.5, 0.5, r, r * 0.9, Color(1, 1, 1, 0.25 + (0.48 - r) * 2.0), 1.0)
			_ellipse(0.5, 0.48, 0.16, 0.16, Color(1, 1, 0.95), 0.2)
		_:
			# Bipède.
			_rect(0.27, 0.62, 0.43, 1.0, DARK.lightened(0.15), 0.0)
			_rect(0.53, 0.62, 0.69, 1.0, DARK.lightened(0.15), 0.0)
			_rect(0.25, 0.24, 0.71, 0.64, PALE if militia else team, 0.0 if militia else 1.0)
			_ellipse(0.47, 0.13, 0.19, 0.12, SKIN if militia else team.darkened(0.2), 0.0 if militia else 0.8)
			if militia:
				_rect(0.25, 0.24, 0.71, 0.32, team, 1.0)  # brassard aux couleurs
	_gear(body, gear)


func _gear(body: String, gear: String) -> void:
	var biped := body in ["bipede", "reptile", "robot", "bloc"]
	match gear:
		"bouclier":
			if biped:
				_poly([Vector2(0.28, 0.25), Vector2(0.05, 0.75), Vector2(0.25, 0.7)], Color(0.55, 0.12, 0.12), 0.6)
				_rect(0.64, 0.28, 0.86, 0.66, METAL.lightened(0.15), 0.4)
				_line(Vector2(0.8, 0.0), Vector2(0.8, 0.3), Color(1.0, 0.85, 0.5), 0.0)
		"blaster":
			_rect(0.6, 0.34, 1.0, 0.42, DARK, 0.0)
			_rect(0.3, 0.3, 0.66, 0.36, PALE, 0.0)
		"lourd":
			_rect(0.15, 0.2, 0.36, 0.36, METAL.darkened(0.2), 0.3)
			_rect(0.6, 0.2, 0.82, 0.36, METAL.darkened(0.2), 0.3)
			_rect(0.6, 0.38, 1.0, 0.48, DARK, 0.0)
		"exo":
			_rect(0.05, 0.26, 0.26, 0.6, METAL, 0.2)
			_rect(0.55, 0.32, 1.0, 0.38, DARK, 0.0)
		"brocante":
			_rect(0.2, 0.0, 0.76, 0.05, Color(0.4, 0.28, 0.16), 0.0)
			_rect(0.35, 0.4, 0.55, 0.52, Color(0.8, 0.6, 0.2), 0.0)
			_line(Vector2(0.6, 0.45), Vector2(1.0, 0.32), Color(0.45, 0.3, 0.15), 0.0, 2)
		"epines":
			for k in 3:
				var x := 0.25 + k * 0.15
				_poly([Vector2(x, 0.3), Vector2(x + 0.08, 0.3), Vector2(x - 0.04, 0.08)], Color(0.85, 0.82, 0.7), 0.0)
		"halo":
			_ellipse(0.5, 0.04, 0.3, 0.05, Color(1.0, 0.92, 0.6, 0.9), 0.0)
		"banniere":
			_line(Vector2(0.15, 1.0), Vector2(0.15, 0.0), Color(0.35, 0.25, 0.15), 0.0, 1)
			_rect(0.16, 0.0, 0.42, 0.22, Color(0.9, 0.9, 0.9), 1.0)
			_rect(0.6, 0.38, 1.0, 0.46, DARK, 0.0)
		"cape":
			_poly([Vector2(0.25, 0.22), Vector2(0.75, 0.22), Vector2(0.85, 0.9), Vector2(0.1, 0.9)], Color(0.14, 0.15, 0.17), 0.15)
			_rect(0.6, 0.36, 1.0, 0.42, DARK, 0.0)
		_:
			if biped:
				_rect(0.55, 0.34, 1.0, 0.4, DARK, 0.0)


# --- Véhicules, aérien, grandes figures (prop. 26, 31, 32) ------------------------------------

func _vehicle(kind: String, wreck: bool) -> void:
	var team := Color(0.85, 0.85, 0.85) if not wreck else Color(0.3, 0.29, 0.28)
	var tm := 1.0 if not wreck else 0.25
	match kind:
		"glisseur":
			_ellipse(0.5, 0.92, 0.45, 0.07, Color(0.4, 0.85, 1.0, 0.0 if wreck else 0.8), 0.0)
			_poly([Vector2(0.02, 0.75), Vector2(0.15, 0.4), Vector2(0.85, 0.4), Vector2(1.0, 0.7), Vector2(0.9, 0.82), Vector2(0.1, 0.82)], team, tm)
			_rect(0.35, 0.18, 0.62, 0.42, team.lightened(0.1), tm)
			if not wreck:
				_rect(0.6, 0.26, 1.0, 0.32, DARK, 0.0)
		"roues":
			for k in 3:
				_ellipse(0.2 + k * 0.3, 0.85, 0.1, 0.15, DARK, 0.0)
			_rect(0.05, 0.38, 0.95, 0.75, team, tm)
			_rect(0.55, 0.15, 0.85, 0.4, team.darkened(0.1), tm)
			if not wreck:
				_rect(0.12, 0.25, 0.5, 0.3, DARK, 0.0)
		"bricole":
			_ellipse(0.2, 0.85, 0.12, 0.15, DARK, 0.0)
			_ellipse(0.78, 0.82, 0.16, 0.18, DARK, 0.0)
			_poly([Vector2(0.02, 0.7), Vector2(0.1, 0.35), Vector2(0.6, 0.3), Vector2(0.95, 0.5), Vector2(0.9, 0.72)], team, tm)
			_rect(0.3, 0.38, 0.5, 0.55, Color(0.7, 0.5, 0.2), 0.0)
			_rect(0.4, 0.08, 0.55, 0.32, Color(0.5, 0.45, 0.4), 0.0)
		"rampant":
			for k in 4:
				_line(Vector2(0.2 + k * 0.2, 0.7), Vector2(0.12 + k * 0.2, 1.0), Color(0.3, 0.32, 0.18), 0.0, 2)
			for k in 3:
				_ellipse(0.25 + k * 0.25, 0.55, 0.2, 0.3, team.darkened(0.08 * k), tm)
			_ellipse(0.92, 0.5, 0.08, 0.15, Color(0.85, 0.9, 0.5), 0.0)
		"pierre":
			_rect(0.1, 0.78, 0.25, 1.0, Color(0.36, 0.3, 0.26), 0.0)
			_rect(0.72, 0.78, 0.88, 1.0, Color(0.36, 0.3, 0.26), 0.0)
			_poly([Vector2(0.0, 0.8), Vector2(0.12, 0.25), Vector2(0.75, 0.15), Vector2(1.0, 0.55), Vector2(0.9, 0.8)], Color(0.52, 0.45, 0.4), 0.5)
			_rect(0.3, 0.3, 0.6, 0.38, team, tm)
			if not wreck:
				_ellipse(0.88, 0.45, 0.05, 0.08, Color(1.0, 0.55, 0.2), 0.0)
		"orbe":
			_ellipse(0.5, 0.95, 0.3, 0.05, Color(0.8, 0.6, 1.0, 0.0 if wreck else 0.6), 0.0)
			_ellipse(0.5, 0.5, 0.36, 0.42, team, tm)
			_ellipse(0.62, 0.42, 0.12, 0.14, Color(1, 1, 1, 0.85), 0.0)
		_:
			# Chenilles.
			_rect(0.0, 0.55, 1.0, 1.0, DARK, 0.0)
			for k in 5:
				_ellipse(0.12 + k * 0.19, 0.78, 0.08, 0.13, METAL, 0.0)
			_rect(0.08, 0.3, 0.88, 0.6, team, tm)
			_rect(0.3, 0.05, 0.65, 0.35, team.lightened(0.1), tm)
			if not wreck:
				_rect(0.6, 0.14, 1.0, 0.24, METAL.darkened(0.2), 0.0)


func _aircraft(kind: String) -> void:
	var team := Color(0.85, 0.85, 0.85)
	match kind:
		"voilier":
			_rect(0.1, 0.55, 0.95, 0.75, Color(0.45, 0.32, 0.2), 0.0)
			_poly([Vector2(0.35, 0.55), Vector2(0.5, 0.0), Vector2(0.75, 0.55)], team, 1.0)
			_poly([Vector2(0.15, 0.55), Vector2(0.3, 0.15), Vector2(0.35, 0.55)], team.darkened(0.1), 1.0)
		"canonniere":
			_rect(0.1, 0.35, 0.85, 0.85, team, 1.0)
			_rect(0.85, 0.5, 1.0, 0.7, DARK, 0.0)
			_line(Vector2(0.0, 0.15), Vector2(0.5, 0.15), DARK, 0.0, 2)
			_line(Vector2(0.45, 0.15), Vector2(0.45, 0.35), DARK, 0.0)
		"drone":
			_line(Vector2(0.1, 0.2), Vector2(0.9, 0.8), DARK, 0.0, 2)
			_line(Vector2(0.1, 0.8), Vector2(0.9, 0.2), DARK, 0.0, 2)
			for c in [Vector2(0.1, 0.2), Vector2(0.9, 0.8), Vector2(0.1, 0.8), Vector2(0.9, 0.2)]:
				_ellipse(c.x, c.y, 0.1, 0.18, METAL, 0.0)
			_ellipse(0.5, 0.5, 0.15, 0.3, team, 1.0)
		"coucou":
			_rect(0.1, 0.1, 0.7, 0.25, team, 1.0)
			_rect(0.1, 0.7, 0.7, 0.85, team, 1.0)
			_rect(0.0, 0.4, 0.9, 0.6, Color(0.6, 0.45, 0.25), 0.0)
			_line(Vector2(0.95, 0.2), Vector2(0.95, 0.8), DARK, 0.0, 2)
		"volant_bio":
			_poly([Vector2(0.5, 0.5), Vector2(0.1, 0.0), Vector2(0.0, 0.6)], team.darkened(0.1), 1.0)
			_poly([Vector2(0.5, 0.5), Vector2(0.75, 0.0), Vector2(0.95, 0.5)], team, 1.0)
			_ellipse(0.55, 0.6, 0.25, 0.2, Color(0.35, 0.4, 0.2), 0.3)
		"orbe":
			_ellipse(0.5, 0.5, 0.5, 0.3, team, 1.0)
			_ellipse(0.5, 0.45, 0.2, 0.25, Color(1, 1, 1, 0.8), 0.0)
		_:
			_rect(0.0, 0.4, 1.0, 0.65, team, 1.0)
			_rect(0.3, 0.0, 0.55, 1.0, team.darkened(0.15), 1.0)
			_rect(0.0, 0.15, 0.12, 0.65, METAL, 0.0)
			_rect(0.85, 0.45, 1.0, 0.6, Color(0.5, 0.8, 1.0), 0.0)


func _big(kind: String) -> void:
	var team := Color(0.85, 0.85, 0.85)
	match kind:
		"colosse":
			var stone := Color(0.5, 0.44, 0.4)
			_rect(0.22, 0.6, 0.42, 1.0, stone.darkened(0.15), 0.0)
			_rect(0.58, 0.6, 0.78, 1.0, stone.darkened(0.15), 0.0)
			_poly([Vector2(0.1, 0.62), Vector2(0.2, 0.18), Vector2(0.8, 0.18), Vector2(0.92, 0.62)], stone, 0.35)
			_rect(0.38, 0.02, 0.66, 0.2, stone.lightened(0.1), 0.2)
			_rect(0.82, 0.25, 0.98, 0.6, stone.darkened(0.1), 0.0)
			_rect(0.3, 0.3, 0.7, 0.4, team, 1.0)
			_ellipse(0.58, 0.1, 0.04, 0.03, Color(1.0, 0.6, 0.25), 0.0)
		_:
			# Marcheur de siège.
			_line(Vector2(0.3, 0.55), Vector2(0.15, 1.0), DARK, 0.0, 4)
			_line(Vector2(0.7, 0.55), Vector2(0.85, 1.0), DARK, 0.0, 4)
			_rect(0.1, 0.22, 0.9, 0.58, team, 1.0)
			_rect(0.6, 0.08, 0.9, 0.24, METAL, 0.3)
			_rect(0.8, 0.3, 1.0, 0.36, DARK, 0.0)
			_rect(0.8, 0.42, 1.0, 0.48, DARK, 0.0)


func _corpse(kind: String) -> void:
	match kind:
		"eboulis":
			_ellipse(0.3, 0.7, 0.2, 0.3, Color(0.4, 0.38, 0.36), 0.2)
			_ellipse(0.6, 0.65, 0.18, 0.35, Color(0.48, 0.45, 0.42), 0.2)
			_ellipse(0.82, 0.75, 0.12, 0.25, Color(0.36, 0.34, 0.32), 0.0)
		"aucun":
			_ellipse(0.5, 0.6, 0.4, 0.3, Color(1, 1, 1, 0.12), 1.0)
		_:
			_rect(0.1, 0.35, 0.8, 0.85, Color(0.75, 0.75, 0.75), 1.0)
			_ellipse(0.88, 0.6, 0.1, 0.3, DARK, 0.0)
