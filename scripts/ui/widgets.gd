class_name Widgets
extends RefCounted
## Petits contrôles réutilisables de l'interface : bouton à pictogramme dessiné,
## panneau à infobulle enrichie (couleurs), emblème de faction.


## Bouton avec un pictogramme vectoriel (pas besoin de police à symboles ni d'image).
## glyph : "pause", "play", "menu", "prev", "next", "close", "home", "economy", "colonies", "research", "diplomacy".
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
			"home":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.2), c + Vector2(s * 1.1, 0), c + Vector2(0, s * 1.2), c + Vector2(-s * 1.1, 0)]), col)


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
