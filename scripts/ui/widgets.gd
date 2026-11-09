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
