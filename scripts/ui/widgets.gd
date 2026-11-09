class_name Widgets
extends RefCounted
## Petits contrôles réutilisables de l'interface : bouton à pictogramme dessiné,
## panneau à infobulle enrichie (couleurs), emblème de faction.


## Bouton avec un pictogramme vectoriel (pas besoin de police à symboles ni d'image).
## glyph : "pause", "play", "menu", "prev", "next", "close", "home".
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
		rt.add_theme_font_override("bold_font", UiTheme.FONT_NUMBERS)
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

	func _init(c := Color.WHITE, side := 12.0) -> void:
		color = c
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, color.darkened(0.35))
		draw_circle(size * 0.5 - Vector2(r, r) * 0.18, r * 0.72, color)
