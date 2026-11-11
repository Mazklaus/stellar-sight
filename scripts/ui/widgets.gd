class_name Widgets
extends RefCounted
## Petits contrôles réutilisables de l'interface : bouton à pictogramme dessiné,
## panneau à infobulle enrichie (couleurs), emblème de faction.


## Bouton avec un pictogramme vectoriel (pas besoin de police à symboles ni d'image).
## glyph : "pause", "play", "menu", "prev", "next", "close", "home", "economy", "colonies", "research", "diplomacy", "shipyard", "victory".
class IconButton:
	extends Button
	var glyph := ""
	var glyph_color := UiTheme.TEXT

	func _init(g := "", side := 32.0) -> void:
		glyph = g
		custom_minimum_size = Vector2(side, side)
		focus_mode = Control.FOCUS_NONE
		theme_type_variation = &"BarButton"

	func set_glyph(g: String) -> void:
		glyph = g
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.22
		var col := glyph_color
		if disabled:
			col = Color(col, 0.35)
		elif is_hovered():
			col = UiTheme.GOLD
		match glyph:
			"pause":
				draw_rect(Rect2(c + Vector2(-s, -s), Vector2(s * 0.7, s * 2)), col)
				draw_rect(Rect2(c + Vector2(s * 0.3, -s), Vector2(s * 0.7, s * 2)), col)
			"play":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.8, -s), c + Vector2(s, 0), c + Vector2(-s * 0.8, s)]), col)
			"menu":
				for i in 3:
					draw_rect(Rect2(c + Vector2(-s, -s + i * s * 0.9), Vector2(s * 2, s * 0.32)), col)
			"prev":
				draw_polyline(PackedVector2Array([c + Vector2(s * 0.5, -s), c + Vector2(-s * 0.5, 0), c + Vector2(s * 0.5, s)]), col, 2.0, true)
			"next":
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.5, -s), c + Vector2(s * 0.5, 0), c + Vector2(-s * 0.5, s)]), col, 2.0, true)
			"close":
				draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, 2.0, true)
				draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, 2.0, true)
			"economy":
				for i in 3:
					var h := s * (0.8 + 0.6 * i)
					draw_rect(Rect2(c + Vector2(-s * 1.1 + i * s * 0.8, s - h), Vector2(s * 0.55, h)), col)
			"colonies":
				draw_circle(c, s * 0.62, col)
				draw_arc(c, s * 1.15, -0.5, PI - 0.5, 24, col, 1.5, true)
				draw_arc(c, s * 1.15, PI - 0.1, TAU - 0.9, 24, Color(col, 0.45), 1.5, true)
			"research":
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.35, -s * 1.1), c + Vector2(-s * 0.35, -s * 0.2),
						c + Vector2(-s * 1.0, s), c + Vector2(s * 1.0, s), c + Vector2(s * 0.35, -s * 0.2),
						c + Vector2(s * 0.35, -s * 1.1)]), col, 1.6, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, s * 0.45), c + Vector2(s * 0.7, s * 0.45),
						c + Vector2(s * 0.95, s * 0.95), c + Vector2(-s * 0.95, s * 0.95)]), col)
			"diplomacy":
				draw_arc(c + Vector2(-s * 0.45, 0), s * 0.75, 0.0, TAU, 24, col, 1.6, true)
				draw_arc(c + Vector2(s * 0.45, 0), s * 0.75, 0.0, TAU, 24, col, 1.6, true)
			"shipyard":
				draw_colored_polygon(PackedVector2Array([c + Vector2(s * 1.2, 0), c + Vector2(s * 0.3, -s * 0.7), c + Vector2(-s * 1.1, -s * 0.55),
						c + Vector2(-s * 1.1, s * 0.55), c + Vector2(s * 0.3, s * 0.7)]), col)
				draw_line(c + Vector2(-s * 0.6, -s * 1.1), c + Vector2(-s * 0.6, s * 1.1), Color(col, 0.6), 1.5, true)
			"home":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.2), c + Vector2(s * 1.1, 0), c + Vector2(0, s * 1.2), c + Vector2(-s * 1.1, 0)]), col)
			"victory":
				# Une étoile à cinq branches.
				var pts := PackedVector2Array()
				for i in 10:
					var r := s * (1.25 if i % 2 == 0 else 0.5)
					var a := -PI / 2.0 + i * PI / 5.0
					pts.append(c + Vector2(cos(a), sin(a)) * r)
				draw_colored_polygon(pts, col)


## Conteneur dont l'infobulle accepte le BBCode ([color], [b]…) : tooltip_text est lu comme du BBCode.
class RichTipPanel:
	extends PanelContainer
	var tip_width := 280.0

	func _make_custom_tooltip(for_text: String) -> Object:
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.custom_minimum_size = Vector2(tip_width, 0)
		rt.add_theme_font_size_override("normal_font_size", 14)
		rt.add_theme_font_size_override("bold_font_size", 15)
		rt.add_theme_font_override("bold_font", UiTheme.numbers_font())
		rt.add_theme_font_override("normal_font", UiTheme.body_font())
		rt.text = for_text
		return rt


## Losange aux couleurs d'une faction, avec un liseré clair.
class Emblem:
	extends Control
	var color := Color.WHITE

	func _init(side := 26.0) -> void:
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		var outer := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(outer, color.darkened(0.45))
		var inner := PackedVector2Array()
		for p in outer:
			inner.append(c + (p - c) * 0.58)
		draw_colored_polygon(inner, color)
		outer.append(outer[0])
		draw_polyline(outer, color.lightened(0.4), 1.5, true)


## Pastille ronde ombrée (type de planète, statut).
class Dot:
	extends Control
	var color := Color.WHITE
	## Anneau autour de la pastille (couleur du propriétaire), transparent = aucun.
	var ring := Color(0, 0, 0, 0)

	func _init(c := Color.WHITE, side := 12.0) -> void:
		color = c
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var rr := r * (0.62 if ring.a > 0.0 else 1.0)
		draw_circle(size * 0.5, rr, color.darkened(0.35))
		draw_circle(size * 0.5 - Vector2(rr, rr) * 0.18, rr * 0.72, color)
		if ring.a > 0.0:
			draw_arc(size * 0.5, r - 1.0, 0.0, TAU, 24, ring, 1.5, true)


## Petite « illustration » d'un système : fond étoilé et étoile animée, avec les shaders de la vue système.
class StarPortrait:
	extends Control
	var _back: ColorRect
	var _star: ColorRect

	func _init(portrait_size := Vector2(300, 130)) -> void:
		custom_minimum_size = portrait_size
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back = ColorRect.new()
		_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bm := ShaderMaterial.new()
		bm.shader = SystemView.BACKDROP_SHADER
		_back.material = bm
		add_child(_back)
		_star = ColorRect.new()
		_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = SystemView.STAR_SHADER
		_star.material = sm
		add_child(_star)

	func set_star(star_type: String, seed_value: float) -> void:
		var col: Color = GalaxyView.STAR_COLORS.get(star_type, Color.WHITE)
		var look: Dictionary = SystemView.STAR_LOOKS.get(star_type, SystemView.STAR_LOOKS["yellow"])
		var bm := _back.material as ShaderMaterial
		bm.set_shader_parameter("tint", col)
		bm.set_shader_parameter("seed", seed_value)
		var sm := _star.material as ShaderMaterial
		sm.set_shader_parameter("star_color", col)
		sm.set_shader_parameter("mode", int(look["mode"]))
		sm.set_shader_parameter("core", float(look["core"]))
		# L'étoile est décalée à droite, comme une vignette ; sa taille suit son type.
		var side := clampf(float(look["radius"]) * 4.2, 60.0, 230.0)
		_star.size = Vector2(side, side)
		_star.position = Vector2(custom_minimum_size.x * 0.66, custom_minimum_size.y * 0.5) - _star.size * 0.5


## Emplacement d'illustration. Si un fichier res://assets/art/<art_id>.png (ou .jpg, .webp) existe,
## il est affiché en couvrant le cadre ; sinon un motif dessiné tient la place, dans la teinte donnée.
## L'habillage final du jeu consistera donc à déposer des images, sans toucher au code.
## motif : "faction", "planet", "star", "galaxy", "lock", "none".
class ArtSlot:
	extends Control
	const ART_DIR := "res://assets/art/"
	var art_id := ""
	var tint := Color(0.38, 0.86, 0.92)
	var motif := "none"
	## Graine du motif (une planète, une étoile…), pour que chaque emplacement ait sa variante.
	var variant := 0
	var _tex: TextureRect
	var _caption: Label

	func _init(id := "", slot_size := Vector2(300, 160), color := Color(0.38, 0.86, 0.92), m := "none") -> void:
		art_id = id
		tint = color
		motif = m
		custom_minimum_size = slot_size
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tex = TextureRect.new()
		_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tex)
		_load()

	## Chemin de l'illustration si elle existe, "" sinon.
	static func art_path(id: String) -> String:
		if id == "":
			return ""
		for ext in ["png", "jpg", "webp"]:
			var p := "%s%s.%s" % [ART_DIR, id, ext]
			if ResourceLoader.exists(p):
				return p
		return ""

	func set_art(id: String, color: Color, m := "") -> void:
		art_id = id
		tint = color
		if m != "":
			motif = m
		_load()
		queue_redraw()

	func has_art() -> bool:
		return _tex.texture != null

	## Grand libellé posé en bas de l'illustration (comme un titre de carte).
	func set_caption(text: String, size := 26) -> void:
		if _caption == null:
			_caption = Label.new()
			_caption.theme_type_variation = &"Title"
			_caption.anchor_top = 1.0
			_caption.anchor_bottom = 1.0
			_caption.anchor_right = 1.0
			_caption.offset_top = -size - 18.0
			_caption.offset_left = 12.0
			_caption.offset_bottom = -6.0
			_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
			_caption.add_theme_constant_override("shadow_offset_y", 1)
			_caption.add_theme_constant_override("shadow_outline_size", 4)
			_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_caption)
		_caption.add_theme_font_size_override("font_size", size)
		_caption.text = text
		queue_redraw()

	func _load() -> void:
		var p := art_path(art_id)
		_tex.texture = load(p) as Texture2D if p != "" else null

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if has_art():
			if _caption and _caption.text != "":
				_shade(r)
			return
		# Fond : dégradé sombre dans la teinte, quelques hachures très légères.
		var top := tint.darkened(0.72)
		var bottom := tint.darkened(0.9)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
				PackedColorArray([top, top.darkened(0.3), bottom, bottom]))
		var step := 14.0
		var x := -size.y
		while x < size.x:
			draw_line(Vector2(x, size.y), Vector2(x + size.y, 0), Color(tint, 0.05), 1.0)
			x += step
		var c := size * Vector2(0.62, 0.5)
		var s := minf(size.x, size.y)
		if art_id.begins_with("portrait_"):
			_draw_portrait(r)
			if _caption and _caption.text != "":
				_shade(r)
			draw_rect(r, Color(1, 1, 1, 0.08), false, 1.0)
			return
		match motif:
			"faction":
				for i in 3:
					draw_arc(c, s * (0.22 + 0.12 * i), 0.0, TAU, 64, Color(tint, 0.28 - 0.07 * i), 1.0, true)
				var d := s * 0.2
				var pts := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
				draw_colored_polygon(pts, Color(tint, 0.22))
				pts.append(pts[0])
				draw_polyline(pts, Color(tint.lightened(0.3), 0.7), 1.5, true)
			"planet":
				var pr := s * 0.34
				draw_circle(c, pr * 1.25, Color(tint, 0.06))
				draw_circle(c, pr, tint.darkened(0.55))
				draw_circle(c + Vector2(-pr, -pr) * 0.18, pr * 0.82, Color(tint.darkened(0.15), 0.85))
				draw_arc(c, pr, PI * 0.9, PI * 1.6, 32, Color(tint.lightened(0.5), 0.7), 2.0, true)
			"star":
				for i in 5:
					draw_circle(c, s * (0.42 - 0.07 * i), Color(tint.lightened(0.2), 0.05 + 0.04 * i))
				draw_circle(c, s * 0.12, tint.lightened(0.6))
			"galaxy":
				var rng := RandomNumberGenerator.new()
				rng.seed = 7 + variant
				for i in 260:
					var t := rng.randf()
					var arm := float(rng.randi() % 3) * TAU / 3.0
					var a := arm + t * 4.2 + rng.randf_range(-0.25, 0.25)
					var rad := t * s * 0.62
					var p := c + Vector2(cos(a), sin(a) * 0.45) * rad
					draw_circle(p, rng.randf_range(0.6, 1.7), Color(tint.lightened(0.4), rng.randf_range(0.2, 0.8) * (1.0 - t * 0.6)))
				draw_circle(c, s * 0.06, Color(tint.lightened(0.7), 0.8))
			"lock":
				var w := s * 0.16
				draw_arc(c + Vector2(0, -w * 0.4), w * 0.6, PI, TAU, 16, Color(1, 1, 1, 0.35), 2.0, true)
				draw_rect(Rect2(c + Vector2(-w * 0.8, -w * 0.4), Vector2(w * 1.6, w * 1.2)), Color(1, 1, 1, 0.35), false, 2.0)
				draw_circle(c + Vector2(0, w * 0.15), w * 0.14, Color(1, 1, 1, 0.35))
		if _caption and _caption.text != "":
			_shade(r)
		draw_rect(r, Color(1, 1, 1, 0.08), false, 1.0)

	## Portrait provisoire d'un peuple créé (« portrait_<id> ») tant qu'aucune illustration n'est
	## déposée : un buste en silhouette, humanoïde ou insectoïde, avec l'ornement décrit par le champ
	## "look" du portrait (data/species_parts.json) pour que chaque portrait de la galerie se distingue.
	func _draw_portrait(r: Rect2) -> void:
		var pid := art_id.trim_prefix("portrait_")
		var look := String(Species.portrait_def(pid).get("look", ""))
		var hive := pid.begins_with("ruche")
		var rock := pid.begins_with("lithoide")
		var s := minf(r.size.x, r.size.y * 0.9)
		var cx := r.size.x * 0.5
		var base := r.size.y
		var fill := Color(tint.darkened(0.35), 0.95)
		var edge := Color(tint.lightened(0.35), 0.8)
		var eye := Color(tint.lightened(0.7), 0.95)
		draw_circle(Vector2(cx, base * 0.42), s * 0.42, Color(tint, 0.07))
		var sw := s * (0.5 if look == "colossus" or look == "boulder" else 0.4)
		var sh_y := base * 0.78
		draw_colored_polygon(PackedVector2Array([Vector2(cx - sw, base), Vector2(cx - sw * 0.85, sh_y), Vector2(cx - sw * 0.3, sh_y - s * 0.08),
				Vector2(cx + sw * 0.3, sh_y - s * 0.08), Vector2(cx + sw * 0.85, sh_y), Vector2(cx + sw, base)]), fill.darkened(0.2))
		var head := Vector2(cx, base * 0.48)
		var hr := s * (0.14 if look == "crown" and hive else 0.17)
		if rock:
			# Tête à facettes : un polygone irrégulier, des arêtes claires, des yeux comme des braises.
			var k := 7 if look != "boulder" else 9
			var rp := PackedVector2Array()
			for i in k:
				var a := TAU * i / float(k) - PI * 0.5
				var rr := hr * (1.25 if look == "boulder" else 1.05) * (0.86 + 0.14 * float((i * 5) % 3))
				rp.append(head + Vector2(cos(a) * rr, sin(a) * rr * 1.1))
			draw_colored_polygon(rp, fill)
			for i in k:
				if i % 2 == 0:
					draw_line(head, rp[i], Color(edge, 0.35), 1.0, true)
			rp.append(rp[0])
			draw_polyline(rp, edge, 1.5, true)
			match look:
				"shards":
					for x in [-0.6, -0.15, 0.35, 0.75]:
						var b0 := head + Vector2(hr * x, -hr * 0.85)
						var h := hr * (0.9 + 0.5 * absf(x))
						draw_colored_polygon(PackedVector2Array([b0 + Vector2(-hr * 0.13, 0), b0 + Vector2(hr * 0.12 * x, -h), b0 + Vector2(hr * 0.13, 0)]), Color(eye, 0.75))
				"geode":
					draw_circle(head + Vector2(0, hr * 0.15), hr * 0.42, Color(eye, 0.35))
					for i in 6:
						var a := TAU * i / 6.0
						draw_line(head + Vector2(0, hr * 0.15), head + Vector2(0, hr * 0.15) + Vector2(cos(a), sin(a)) * hr * 0.42, eye, 1.5, true)
				"boulder":
					for i in 3:
						draw_arc(head + Vector2(-hr * 0.2, hr * 0.5), hr * (0.25 + 0.15 * i), PI * 1.1, PI * 1.6, 10, Color(edge, 0.6), 1.0, true)
			for side in [-1.0, 1.0]:
				draw_line(head + Vector2(side * hr * 0.55, -hr * 0.15), head + Vector2(side * hr * 0.2, -hr * 0.05), eye, 3.0, true)
		elif hive:
			var hp := PackedVector2Array()
			for i in 24:
				var a := TAU * i / 24.0
				hp.append(head + Vector2(cos(a) * hr * (1.3 if look == "colossus" else 1.05), sin(a) * hr * 1.35))
			draw_colored_polygon(hp, fill)
			hp.append(hp[0])
			draw_polyline(hp, edge, 1.5, true)
			for side in [-1.0, 1.0]:
				var m0 := head + Vector2(side * hr * 0.5, hr * 1.1)
				var big := 1.6 if look == "mandibles" else 1.0
				draw_polyline(PackedVector2Array([m0, m0 + Vector2(side * hr * 0.5, hr * 0.5) * big, m0 + Vector2(side * hr * 0.1, hr * 0.8) * big]), edge, 2.5, true)
				if look != "colossus":
					var a0 := head + Vector2(side * hr * 0.4, -hr * 1.2)
					var a1 := a0 + Vector2(side * hr * 0.9, -hr * 1.2)
					draw_line(a0, a1, edge, 1.5, true)
					draw_circle(a1, 2.5, edge)
				var n := 6 if look == "eyes" else 2
				for k in n:
					draw_circle(head + Vector2(side * hr * (0.3 + 0.12 * k), -hr * 0.25 + (k % 3) * 5.0), 2.6 if look != "eyes" else 3.2, eye)
			if look == "crown":
				for k in 5:
					var x := -hr * 0.8 + k * hr * 0.4
					draw_colored_polygon(PackedVector2Array([head + Vector2(x - 4, -hr * 1.25), head + Vector2(x, -hr * 1.75), head + Vector2(x + 4, -hr * 1.25)]), edge)
			if look == "colossus":
				for k in 3:
					draw_arc(head, hr * (1.0 - 0.25 * k), PI * 1.15, PI * 1.85, 16, edge, 1.5, true)
		else:
			draw_line(head + Vector2(0, hr), head + Vector2(0, hr * 1.6), fill, hr * 0.7)
			draw_circle(head, hr, fill)
			draw_arc(head, hr, 0.0, TAU, 40, edge, 1.5, true)
			match look:
				"horns":
					for side in [-1.0, 1.0]:
						draw_polyline(PackedVector2Array([head + Vector2(side * hr * 0.6, -hr * 0.7), head + Vector2(side * hr * 1.1, -hr * 1.4), head + Vector2(side * hr * 0.8, -hr * 1.9)]), edge, 2.5, true)
				"horns2":
					for side in [-1.0, 1.0]:
						draw_polyline(PackedVector2Array([head + Vector2(side * hr * 0.9, -hr * 0.3), head + Vector2(side * hr * 1.6, -hr * 0.2), head + Vector2(side * hr * 1.7, hr * 0.5)]), edge, 3.0, true)
				"crest":
					draw_colored_polygon(PackedVector2Array([head + Vector2(-hr * 0.25, -hr * 0.9), head + Vector2(-hr * 0.1, -hr * 1.9), head + Vector2(hr * 0.5, -hr * 1.5), head + Vector2(hr * 0.25, -hr * 0.9)]), edge)
				"crown":
					for k in 5:
						var x := -hr * 0.7 + k * hr * 0.35
						draw_line(head + Vector2(x, -hr * 0.85), head + Vector2(x, -hr * 1.25), edge, 2.0, true)
				"hood":
					draw_arc(head, hr * 1.25, PI * 0.95, PI * 2.05, 24, edge, 2.5, true)
					draw_line(head + Vector2(-hr * 1.25, 0), head + Vector2(-hr * 1.1, hr * 1.4), edge, 2.5, true)
					draw_line(head + Vector2(hr * 1.25, 0), head + Vector2(hr * 1.1, hr * 1.4), edge, 2.5, true)
				"wrinkles":
					for k in 3:
						draw_arc(head + Vector2(0, -hr * 0.45), hr * (0.25 + 0.12 * k), PI * 1.2, PI * 1.8, 12, edge, 1.0, true)
					draw_line(head + Vector2(-hr * 0.4, hr * 0.7), head + Vector2(hr * 0.4, hr * 0.7), edge, 1.5, true)
			if look == "hood":
				for side in [-1.0, 1.0]:
					draw_line(head + Vector2(side * hr * 0.5, -hr * 0.05), head + Vector2(side * hr * 0.2, -hr * 0.05), eye, 2.0)
			else:
				for side in [-1.0, 1.0]:
					draw_circle(head + Vector2(side * hr * 0.38, -hr * 0.05), 2.2, eye)

	## Ombre en bas pour la lisibilité du libellé.
	func _shade(r: Rect2) -> void:
		var y := r.end.y - 56.0
		draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(r.end.x, y), r.end, Vector2(0, r.end.y)]),
				PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.75), Color(0, 0, 0, 0.75)]))


## Bouton rond avec un pictogramme et un libellé à côté (« Commencer », « Annuler »…).
## glyph : "check", "back", "close", "plus", "next".
class RoundButton:
	extends Button
	const DIAMETER := 44.0
	var glyph := "check"
	var label_text := ""

	func _init(g := "check", text_value := "", text_size := 20) -> void:
		glyph = g
		label_text = text_value.to_upper()
		focus_mode = Control.FOCUS_NONE
		flat = true
		var f := UiTheme.font(400, 2)
		add_theme_font_override("font", f)
		add_theme_font_size_override("font_size", text_size)
		var w := DIAMETER + 14.0 + f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x + 4.0
		custom_minimum_size = Vector2(w, DIAMETER + 4.0)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var hot := is_hovered() and not disabled
		var col := UiTheme.ACCENT if hot else UiTheme.TEXT
		if disabled:
			col = Color(UiTheme.TEXT, 0.3)
		var c := Vector2(DIAMETER * 0.5 + 1.0, size.y * 0.5)
		var r := DIAMETER * 0.5
		if hot:
			draw_circle(c, r, Color(UiTheme.ACCENT, 0.12))
		draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.75), 1.2, true)
		var s := r * 0.42
		match glyph:
			"check":
				draw_polyline(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(-s * 0.3, s * 0.7), c + Vector2(s, -s * 0.6)]), col, 2.0, true)
			"back":
				draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), col, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.8), c + Vector2(-s, 0), c + Vector2(-s * 0.2, s * 0.8)]), col, 2.0, true)
			"next":
				draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), col, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(s * 0.2, -s * 0.8), c + Vector2(s, 0), c + Vector2(s * 0.2, s * 0.8)]), col, 2.0, true)
			"close":
				draw_line(c + Vector2(-s, -s) * 0.8, c + Vector2(s, s) * 0.8, col, 2.0, true)
				draw_line(c + Vector2(-s, s) * 0.8, c + Vector2(s, -s) * 0.8, col, 2.0, true)
			"plus":
				draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), col, 2.0, true)
				draw_line(c + Vector2(0, -s), c + Vector2(0, s), col, 2.0, true)
			"reset":
				draw_arc(c, s, -PI * 0.35, PI * 1.45, 28, col, 2.0, true)
				var tip := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * s
				draw_polyline(PackedVector2Array([tip + Vector2(-s * 0.55, -s * 0.05), tip, tip + Vector2(-s * 0.05, s * 0.55)]), col, 2.0, true)
		var f := get_theme_font("font")
		var fs := get_theme_font_size("font_size")
		var ty := size.y * 0.5 + f.get_ascent(fs) * 0.5 - 2.0
		draw_string(f, Vector2(DIAMETER + 14.0, ty), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Bloc titré des écrans d'empire : un titre fin au-dessus d'un cadre translucide à filet clair.
## Le contenu se met dans body.
class Block:
	extends VBoxContainer
	var body: VBoxContainer
	var heading: Label

	func _init(title_text := "", padding := 14) -> void:
		add_theme_constant_override("separation", 6)
		heading = Label.new()
		heading.text = title_text
		heading.theme_type_variation = &"Title"
		heading.add_theme_font_size_override("font_size", 26)
		add_child(heading)
		var frame := PanelContainer.new()
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 0.6), Color(1, 1, 1, 0.14), padding, 1))
		add_child(frame)
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 8)
		frame.add_child(body)


## Titre centré en capitales fines, souligné d'un filet avec une petite encoche au milieu.
class NotchHeader:
	extends Control
	var text := ""
	var font_size := 20

	func _init(t := "", fs := 20) -> void:
		text = t.to_upper()
		font_size = fs
		custom_minimum_size = Vector2(0, fs + 18.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := UiTheme.font(300, 1)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(f, Vector2((size.x - w) * 0.5, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(UiTheme.TEXT, 0.85))
		var y := font_size + 10.0
		var m := size.x * 0.5
		var col := Color(1, 1, 1, 0.22)
		draw_polyline(PackedVector2Array([Vector2(0, y), Vector2(m - 7, y), Vector2(m, y + 6), Vector2(m + 7, y), Vector2(size.x, y)]), col, 1.0, true)


## Anneau de répartition (parts colorées) avec un total au centre.
class Donut:
	extends Control
	## [{"value": float, "color": Color}]
	var parts: Array = []
	var center_title := "TOTAL"
	var center_value := ""

	func _init(side := 180.0) -> void:
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_parts(value: Array, total_text: String) -> void:
		parts = value
		center_value = total_text
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 8.0
		var total := 0.0
		for p in parts:
			total += maxf(0.0, float(p["value"]))
		draw_arc(c, r, 0.0, TAU, 96, Color(1, 1, 1, 0.08), 14.0, true)
		if total > 0.0:
			var a := -PI / 2.0
			for p in parts:
				var v := maxf(0.0, float(p["value"]))
				if v <= 0.0:
					continue
				var span := TAU * v / total
				draw_arc(c, r, a + 0.02, a + span - 0.02, maxi(4, int(96 * span / TAU)), p["color"], 14.0, true)
				a += span
		draw_arc(c, r - 14.0, 0.0, TAU, 96, Color(1, 1, 1, 0.12), 1.0, true)
		var cf := UiTheme.caps_font()
		var tw := cf.get_string_size(center_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(cf, c + Vector2(-tw * 0.5, -8), center_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.TEXT_DIM)
		var nf := UiTheme.font(300)
		var vw := nf.get_string_size(center_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_string(nf, c + Vector2(-vw * 0.5, 24), center_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.TEXT)


## Entrée du menu principal : pictogramme dans un cercle, libellé en capitales sur un bandeau
## translucide qui s'efface vers la droite. Les entrées se posent le long d'une orbite.
## glyph : "new", "load", "resume", "options", "quit".
class OrbitMenuItem:
	extends Button
	const DIAMETER := 52.0
	var glyph := "new"
	var label_text := ""
	## Phrase d'aide affichée à côté de l'entrée survolée.
	var description := ""

	func _init(g := "new", text_value := "", desc := "") -> void:
		glyph = g
		label_text = text_value.to_upper()
		description = desc
		focus_mode = Control.FOCUS_NONE
		flat = true
		var f := UiTheme.font(400, 1)
		add_theme_font_override("font", f)
		add_theme_font_size_override("font_size", 22)
		custom_minimum_size = Vector2(DIAMETER + 300.0, DIAMETER + 8.0)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var hot := is_hovered() and not disabled
		var col := UiTheme.TEXT
		if disabled:
			col = Color(UiTheme.TEXT, 0.32)
		elif hot:
			col = UiTheme.ACCENT.lightened(0.25)
		var c := Vector2(DIAMETER * 0.5 + 2.0, size.y * 0.5)
		var r := DIAMETER * 0.5
		# Bandeau du libellé.
		var band := Rect2(c.x, c.y - 24.0, size.x - c.x, 48.0)
		var a0 := 0.42 if hot else 0.26
		draw_polygon(PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]),
				PackedColorArray([Color(0.08, 0.12, 0.16, a0), Color(0.08, 0.12, 0.16, 0.0), Color(0.08, 0.12, 0.16, 0.0), Color(0.08, 0.12, 0.16, a0)]))
		draw_circle(c, r, Color(0.02, 0.04, 0.06, 0.85))
		if hot:
			draw_circle(c, r, Color(UiTheme.ACCENT, 0.16))
		draw_arc(c, r, 0.0, TAU, 56, Color(col, 0.6 if not hot else 0.95), 1.3, true)
		var s := r * 0.38
		var w := 1.8
		match glyph:
			"new":
				draw_rect(Rect2(c + Vector2(-s, -s * 0.7), Vector2(s * 1.7, s * 1.6)), col, false, w)
				draw_line(c + Vector2(s * 0.55, -s * 1.15), c + Vector2(s * 0.55, -s * 0.25), col, w, true)
				draw_line(c + Vector2(s * 0.1, -s * 0.7), c + Vector2(s, -s * 0.7), col, w, true)
			"load":
				draw_line(c + Vector2(0, -s), c + Vector2(0, s * 0.4), col, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.55, -s * 0.1), c + Vector2(0, s * 0.45), c + Vector2(s * 0.55, -s * 0.1)]), col, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.3), c + Vector2(-s, s), c + Vector2(s, s), c + Vector2(s, s * 0.3)]), col, w, true)
			"resume":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.6, -s), c + Vector2(s, 0), c + Vector2(-s * 0.6, s)]), col)
			"options":
				draw_arc(c, s * 0.42, 0.0, TAU, 20, col, w, true)
				for i in 8:
					var a := TAU * i / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * s * 0.72, c + Vector2(cos(a), sin(a)) * s * 1.1, col, w + 0.8, true)
				draw_arc(c, s * 0.78, 0.0, TAU, 28, col, w, true)
			"quit":
				draw_polyline(PackedVector2Array([c + Vector2(s * 0.3, -s), c + Vector2(-s * 0.8, -s), c + Vector2(-s * 0.8, s), c + Vector2(s * 0.3, s)]), col, w, true)
				draw_line(c + Vector2(-s * 0.2, 0), c + Vector2(s * 1.05, 0), col, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(s * 0.6, -s * 0.45), c + Vector2(s * 1.05, 0), c + Vector2(s * 0.6, s * 0.45)]), col, w, true)
		var f := get_theme_font("font")
		var fs := get_theme_font_size("font_size")
		draw_string(f, Vector2(DIAMETER + 18.0, c.y + f.get_ascent(fs) * 0.36), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Emblème-titre du menu principal : un anneau fin, deux arcs hachurés, un cercle pointillé et
## un petit cercle satellite autour du nom du jeu en lettres très espacées.
class TitleRing:
	extends Control
	var lines: Array[String] = ["STELLAR", "SIGTH"]
	var radius := 180.0
	var _t := 0.0

	func _init(r := 180.0) -> void:
		radius = r
		custom_minimum_size = Vector2(r * 2.6, r * 2.6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := radius
		var line := Color(UiTheme.ACCENT.lightened(0.35), 0.75)
		draw_arc(c, r, 0.0, TAU, 128, line, 1.4, true)
		# Arcs hachurés, qui tournent très lentement.
		var rot := _t * 0.03
		for span in [[-0.55, 0.62], [2.45, 3.62]]:
			var a0: float = span[0] + rot
			var a1: float = span[1] + rot
			var n := 46
			for i in n:
				var a := lerpf(a0, a1, float(i) / float(n - 1))
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * (r + 12.0), c + d * (r + 26.0), Color(line, 0.65), 1.6, true)
		# Cercle pointillé intérieur.
		for i in 60:
			var a := TAU * i / 60.0 - rot * 2.0
			draw_circle(c + Vector2(cos(a), sin(a)) * (r * 0.72), 1.4, Color(1, 1, 1, 0.5))
		# Satellite.
		var sa := 0.75 + rot * 0.5
		draw_arc(c + Vector2(cos(sa), sin(sa)) * r, r * 0.27, 0.0, TAU, 64, Color(1, 1, 1, 0.8), 1.4, true)
		var f := UiTheme.font(300, 22)
		var fs := int(r * 0.24)
		var total := lines.size() * fs * 1.45
		for i in lines.size():
			var w := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var y := c.y - total * 0.5 + (i + 0.8) * fs * 1.45
			draw_string(f, Vector2(c.x - w * 0.5 + 11.0, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.88, 0.95, 1.0, 0.95))
