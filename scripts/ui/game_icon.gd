class_name GameIcon
extends RefCounted
## Pictogrammes du jeu (technologies, bâtiments, hauts faits, reliques, préceptes et natures de foi,
## fouilles, ressources). Ils vivent tous sur une seule planche, assets/icons/atlas.png, blancs sur fond
## transparent : le code les teinte et dessine le cadre de leur famille autour (disque pour une
## technologie, carré pour un bâtiment, losange pour un haut fait…), à la façon d'Endless Space 2.
## La planche se fabrique avec tools/icons/atlas.py à partir des motifs de tools/icons/ ; une entrée
## ajoutée aux données reçoit son pictogramme dans tools/icons/table.py.
##
## Familles : "tech", "batiment", "haut_fait", "relique", "precepte", "nature", "fouille", "ressource".

const ATLAS := "res://assets/icons/atlas.png"
const INDEX := "res://assets/icons/atlas.json"

## Cadre et teinte du filet par famille.
const FRAMES := {
	"tech": {"shape": "disc", "color": Color(0.914, 0.631, 0.306)},
	"batiment": {"shape": "square", "color": Color(0.624, 0.69, 0.741)},
	"haut_fait": {"shape": "diamond", "color": Color(0.373, 0.859, 0.914)},
	"relique": {"shape": "hexagon", "color": Color(0.89, 0.757, 0.416)},
	"precepte": {"shape": "arch", "color": Color(0.725, 0.545, 0.902)},
	"nature": {"shape": "arch", "color": Color(0.725, 0.545, 0.902)},
	"fouille": {"shape": "cut", "color": Color(0.624, 0.69, 0.741)},
	"ressource": {"shape": "double", "color": Color(0.89, 0.757, 0.416)},
}
const BACK := Color(0.071, 0.11, 0.149)

static var _atlas: Texture2D
static var _index := {}
static var _cell := 96
static var _cols := 1
static var _loaded := false
static var _tex_cache := {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not ResourceLoader.exists(ATLAS) or not FileAccess.file_exists(INDEX):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not d is Dictionary:
		return
	_atlas = load(ATLAS) as Texture2D
	_index = d.get("index", {})
	_cell = int(d.get("cell", 96))
	_cols = maxi(1, int(d.get("cols", 1)))


## Vrai si cette entrée a un pictogramme sur la planche.
static func has(family: String, id: String) -> bool:
	_load()
	return _atlas != null and _index.has("%s/%s" % [family, id])


## Toutes les clés "famille/identifiant" de la planche.
static func keys() -> Array:
	_load()
	return _index.keys()


## Case de la planche pour cette entrée (Rect2() si elle n'en a pas).
static func region(family: String, id: String) -> Rect2:
	if not has(family, id):
		return Rect2()
	var i := int(_index["%s/%s" % [family, id]])
	return Rect2(Vector2(i % _cols, i / _cols) * _cell, Vector2(_cell, _cell))


## Texture du pictogramme seul (pour Button.icon, une ligne d'arbre ou de liste) ; null s'il n'existe pas.
static func texture(family: String, id: String) -> Texture2D:
	var key := "%s/%s" % [family, id]
	if not _tex_cache.has(key):
		var tex: AtlasTexture = null
		if has(family, id):
			tex = AtlasTexture.new()
			tex.atlas = _atlas
			tex.region = region(family, id)
		_tex_cache[key] = tex
	return _tex_cache[key]


## Dessine le pictogramme seul dans rect. Renvoie faux s'il n'existe pas (rien n'est dessiné).
static func draw_glyph(ci: CanvasItem, rect: Rect2, family: String, id: String, color := Color.WHITE) -> bool:
	if not has(family, id):
		return false
	ci.draw_texture_rect_region(_atlas, rect, region(family, id), color)
	return true


static func frame_color(family: String) -> Color:
	return FRAMES.get(family, {}).get("color", Color.WHITE)


## Contour du cadre d'une famille, centré sur c, inscrit dans un carré de demi-côté r.
static func frame_points(family: String, c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match String(FRAMES.get(family, {}).get("shape", "disc")):
		"square":
			for p: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				pts.append(c + p * r * 0.9)
		"diamond":
			for p: Vector2 in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
				pts.append(c + p * r)
		"hexagon":
			for i in 6:
				pts.append(c + Vector2.UP.rotated(i * TAU / 6.0) * r)
		"cut":
			for p: Vector2 in [Vector2(-0.6, -0.9), Vector2(0.6, -0.9), Vector2(0.9, -0.6), Vector2(0.9, 0.6),
					Vector2(0.6, 0.9), Vector2(-0.6, 0.9), Vector2(-0.9, 0.6), Vector2(-0.9, -0.6)]:
				pts.append(c + p * r)
		"arch":
			pts.append(c + Vector2(-0.8, 0.9) * r)
			for i in 13:
				var a := PI + i * PI / 12.0
				pts.append(c + Vector2(cos(a) * 0.8, -0.1 + sin(a) * 0.82) * r)
			pts.append(c + Vector2(0.8, 0.9) * r)
		_:
			for i in 40:
				pts.append(c + Vector2.RIGHT.rotated(i * TAU / 40.0) * r * 0.94)
	return pts


## Part du cadre que le pictogramme occupe (les cadres pointus en laissent moins).
static func glyph_scale(family: String) -> float:
	match String(FRAMES.get(family, {}).get("shape", "disc")):
		"diamond":
			return 0.56
		"hexagon", "arch":
			return 0.6
	return 0.64


## Icône complète : fond sombre, filet de la famille (ou tint), pictogramme. state : "" disponible,
## "locked" hors de portée (estompée), "done" acquise (fond plein de la couleur du filet, pictogramme sombre).
static func draw_framed(ci: CanvasItem, c: Vector2, r: float, family: String, id: String, tint := Color(0, 0, 0, 0), state := "") -> void:
	var col := tint if tint.a > 0.0 else frame_color(family)
	var a := 0.45 if state == "locked" else 1.0
	var pts := frame_points(family, c, r)
	ci.draw_colored_polygon(pts, Color(col, a) if state == "done" else Color(BACK, a))
	var line := pts.duplicate()
	line.append(pts[0])
	ci.draw_polyline(line, Color(col, a), maxf(1.2, r * 0.07), true)
	if String(FRAMES.get(family, {}).get("shape", "")) == "double":
		ci.draw_arc(c, r * 0.8, 0.0, TAU, 40, Color(col, 0.6 * a), 1.0, true)
	var g := r * glyph_scale(family) * 2.0
	var gc := c + (Vector2(0, r * 0.06) if String(FRAMES.get(family, {}).get("shape", "")) == "arch" else Vector2.ZERO)
	draw_glyph(ci, Rect2(gc - Vector2(g, g) * 0.5, Vector2(g, g)), family, id, Color(BACK, a) if state == "done" else Color(1, 1, 1, a))


## Petit contrôle qui montre l'icône encadrée d'une entrée (à poser devant un titre, dans une carte).
class Medal:
	extends Control
	var family := ""
	var id := ""
	var state := ""
	var tint := Color(0, 0, 0, 0)

	func _init(fam := "", ident := "", side := 40.0) -> void:
		family = fam
		id = ident
		custom_minimum_size = Vector2(side, side)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = GameIcon.has(fam, ident)

	func set_entry(fam: String, ident: String, st := "") -> void:
		family = fam
		id = ident
		state = st
		visible = GameIcon.has(fam, ident)
		queue_redraw()

	func _draw() -> void:
		if GameIcon.has(family, id):
			GameIcon.draw_framed(self, size * 0.5, minf(size.x, size.y) * 0.5 - 1.0, family, id, tint, state)


## Pose le pictogramme d'une entrée sur un bouton (sans effet si elle n'en a pas).
static func on_button(b: Button, family: String, id: String, width := 26) -> void:
	var tex := texture(family, id)
	if tex == null:
		return
	b.icon = tex
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", width)
