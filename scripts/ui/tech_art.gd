class_name TechArt
extends RefCounted
## Image de chaque technologie (props 112 et 113 de l'étude de l'arbre). Tant que l'illustration finale
## n'existe pas, elle est dessinée à partir des données : fond selon le domaine et l'ère, pictogramme
## selon ce qu'elle débloque, étoiles semées d'après une graine tirée de l'identifiant (deux technologies
## ne se ressemblent pas), liseré du peuple pour les siennes. Un fichier res://assets/tech/<id>.png la
## remplace dès qu'il existe, sans toucher au code (comme les silhouettes de coques).
## Les dessins passent par un CanvasItem (draw_*), à n'importe quelle taille : médaillon de l'arbre,
## grande image du Codex.

const ART_DIR := "res://assets/tech/"

static var _tex_cache := {}


## Illustration finale déposée pour cette technologie (null sinon).
static func texture(tid: String) -> Texture2D:
	if not _tex_cache.has(tid):
		var p := "%s%s.png" % [ART_DIR, tid]
		_tex_cache[tid] = load(p) as Texture2D if ResourceLoader.exists(p) else null
	return _tex_cache[tid]


static func domain_color(tid: String) -> Color:
	var t := Research.tech(tid)
	if t.has("victory"):
		return Color.html(String(Research.data().get("band", {}).get("color", "#c9a0dc")))
	return Color.html(String(Research.domain(String(t.get("domain", ""))).get("color", "#ffffff")))


## Pictogramme principal : la première sorte de déblocage (bâtiment, vaisseau, module…).
static func picto_kind(faction: Dictionary, tid: String) -> String:
	var t := Research.tech(tid)
	if t.has("victory"):
		return "destinee"
	if Research.is_mastery(tid):
		return "maitrise"
	var kinds := Research.unlock_kinds(faction, tid)
	for k in ["vaisseau", "coque", "mega", "merveille", "forge", "batiment", "regiment", "module"]:
		if kinds.has(k):
			return k
	if t.get("effects", {}).has("marks"):
		return "arme"
	return "regle"


## Médaillon rond (arbre de recherche) : miniature cerclée de la couleur du domaine, un cran par ère,
## liseré du peuple (people_col.a > 0) pour ses technologies propres.
static func draw_medallion(ci: CanvasItem, c: Vector2, r: float, tid: String, faction: Dictionary, people_col := Color(0, 0, 0, 0), dim := false) -> void:
	var col := domain_color(tid)
	var era := int(Research.tech(tid).get("era", 1))
	var tex := texture(tid)
	if tex != null:
		ci.draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, 0.5 if dim else 1.0))
	else:
		_draw_art(ci, c, r, tid, faction, col, dim)
	ci.draw_arc(c, r, 0.0, TAU, 32, Color(col, 0.55 if dim else 0.95), maxf(1.5, r * 0.12), true)
	# Crans d'ère, en haut du cercle.
	for i in era:
		var a := -PI * 0.5 + (float(i) - (era - 1) * 0.5) * 0.42
		var p := c + Vector2(cos(a), sin(a)) * r
		ci.draw_circle(p, maxf(1.2, r * 0.13), Color(col.lightened(0.45), 0.6 if dim else 1.0))
	if people_col.a > 0.0:
		ci.draw_arc(c, r + maxf(2.0, r * 0.18), 0.0, TAU, 32, Color(people_col, 0.6 if dim else 0.95), maxf(1.0, r * 0.08), true)


## Grande image (Codex) dans un rectangle : fond en dégradé, champ d'étoiles et pictogramme.
static func draw_full(ci: CanvasItem, rect: Rect2, tid: String, faction := {}) -> void:
	var col := domain_color(tid)
	var tex := texture(tid)
	if tex != null:
		ci.draw_texture_rect(tex, rect, false)
		return
	var top := col.darkened(0.7)
	var bottom := col.darkened(0.9)
	ci.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
			PackedColorArray([top, top.darkened(0.3), bottom, bottom]))
	var r := minf(rect.size.x, rect.size.y) * 0.4
	_draw_art(ci, rect.position + rect.size * Vector2(0.66, 0.5), r, tid, faction, col, false)
	ci.draw_arc(rect.position + rect.size * Vector2(0.66, 0.5), r, 0.0, TAU, 64, Color(col, 0.8), 2.0, true)


## Le dessin lui-même, dans un disque de rayon r.
static func _draw_art(ci: CanvasItem, c: Vector2, r: float, tid: String, faction: Dictionary, col: Color, dim: bool) -> void:
	var era := int(Research.tech(tid).get("era", 1))
	var a := 0.55 if dim else 1.0
	ci.draw_circle(c, r, Color(col.darkened(0.82 - era * 0.06), a))
	ci.draw_circle(c, r * 0.72, Color(col.darkened(0.7 - era * 0.05), 0.5 * a))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tid)
	var stars := 6 + era * 3 if r >= 30.0 else 3
	for i in stars:
		var ang := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.9
		ci.draw_circle(c + Vector2(cos(ang), sin(ang)) * d, maxf(0.6, r * rng.randf_range(0.015, 0.035)), Color(1, 1, 1, rng.randf_range(0.25, 0.7) * a))
	var rot := rng.randf_range(-0.3, 0.3)
	_draw_picto(ci, c, r * 0.5, picto_kind(faction, tid), col.lightened(0.45), rot, a)


static func _draw_picto(ci: CanvasItem, c: Vector2, s: float, kind: String, col: Color, rot: float, a: float) -> void:
	var k := Color(col, 0.95 * a)
	var w := maxf(1.0, s * 0.14)
	match kind:
		"vaisseau", "coque":
			var pts := _rot([Vector2(0, -s), Vector2(s * 0.55, s * 0.75), Vector2(0, s * 0.4), Vector2(-s * 0.55, s * 0.75)], c, rot)
			ci.draw_colored_polygon(pts, Color(col, 0.35 * a))
			pts.append(pts[0])
			ci.draw_polyline(pts, k, w, true)
		"batiment":
			var pts := _rot([Vector2(-s * 0.7, s * 0.7), Vector2(-s * 0.7, -s * 0.1), Vector2(0, -s * 0.75), Vector2(s * 0.7, -s * 0.1), Vector2(s * 0.7, s * 0.7)], c, 0.0)
			ci.draw_colored_polygon(pts, Color(col, 0.3 * a))
			pts.append(pts[0])
			ci.draw_polyline(pts, k, w, true)
		"module":
			ci.draw_arc(c, s * 0.6, 0.0, TAU, 24, k, w, true)
			for i in 6:
				var ang := rot + i * TAU / 6.0
				ci.draw_line(c + Vector2(cos(ang), sin(ang)) * s * 0.6, c + Vector2(cos(ang), sin(ang)) * s * 0.9, k, w, true)
		"regiment":
			for i in 2:
				var y := -s * 0.25 + i * s * 0.5
				ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, y), c + Vector2(0, y - s * 0.45), c + Vector2(s * 0.7, y)]), k, w * 1.3, true)
		"mega", "merveille":
			ci.draw_arc(c, s * 0.85, 0.0, TAU, 32, k, w, true)
			ci.draw_arc(c, s * 0.45, 0.0, TAU, 24, Color(col, 0.7 * a), w, true)
			ci.draw_circle(c, s * 0.18, k)
		"forge":
			ci.draw_circle(c, s * 0.6, Color(col, 0.3 * a))
			ci.draw_arc(c, s * 0.6, rot, rot + PI * 1.4, 24, k, w * 1.3, true)
		"arme":
			for i in 3:
				var off := Vector2(-s * 0.5 + i * s * 0.5, 0).rotated(rot)
				ci.draw_line(c + off + Vector2(0, s * 0.7).rotated(rot), c + off + Vector2(0, -s * 0.7).rotated(rot), k, w, true)
		"maitrise":
			var pts := _rot([Vector2(0, -s * 0.8), Vector2(s * 0.25, -s * 0.25), Vector2(s * 0.8, 0), Vector2(s * 0.25, s * 0.25),
					Vector2(0, s * 0.8), Vector2(-s * 0.25, s * 0.25), Vector2(-s * 0.8, 0), Vector2(-s * 0.25, -s * 0.25)], c, rot)
			ci.draw_colored_polygon(pts, k)
		"destinee":
			var pts := PackedVector2Array()
			for i in 10:
				var rr := s * (0.9 if i % 2 == 0 else 0.38)
				var ang := -PI * 0.5 + i * TAU / 10.0
				pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
			ci.draw_colored_polygon(pts, k)
		_:
			var pts := _rot([Vector2(0, -s * 0.7), Vector2(s * 0.7, 0), Vector2(0, s * 0.7), Vector2(-s * 0.7, 0)], c, rot)
			ci.draw_colored_polygon(pts, Color(col, 0.35 * a))
			pts.append(pts[0])
			ci.draw_polyline(pts, k, w, true)


static func _rot(pts: Array, c: Vector2, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(c + p.rotated(rot))
	return out
