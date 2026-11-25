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
			"intel":
				# Un œil : deux arcs et la pupille.
				draw_arc(c + Vector2(0, s * 0.9), s * 1.5, -PI * 0.78, -PI * 0.22, 16, col, 1.6, true)
				draw_arc(c + Vector2(0, -s * 0.9), s * 1.5, PI * 0.22, PI * 0.78, 16, col, 1.6, true)
				draw_circle(c, s * 0.42, col)
			"heroes":
				# Une couronne de lauriers autour d'un buste.
				draw_arc(c + Vector2(0, -s * 0.1), s * 1.2, PI * 0.15, PI * 0.85, 14, col, 1.6, true)
				for k in 4:
					for side in [-1.0, 1.0]:
						var a: float = PI * 0.5 + side * (0.55 + 0.42 * k)
						draw_circle(c + Vector2(0, -s * 0.1) + Vector2(cos(a), sin(a)) * s * 1.2, s * 0.17, col)
				draw_circle(c + Vector2(0, -s * 0.35), s * 0.38, col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.6, s * 0.65), c + Vector2(0, s * 0.1), c + Vector2(s * 0.6, s * 0.65)]), col)
			"armies":
				# Un casque à cimier au-dessus de deux lances croisées.
				draw_line(c + Vector2(-s * 1.1, s * 1.1), c + Vector2(s * 1.1, -s * 0.2), Color(col, 0.75), 1.5, true)
				draw_line(c + Vector2(s * 1.1, s * 1.1), c + Vector2(-s * 1.1, -s * 0.2), Color(col, 0.75), 1.5, true)
				draw_arc(c + Vector2(0, -s * 0.15), s * 0.7, PI, TAU, 14, col, 2.2, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.15), c + Vector2(s * 0.7, -s * 0.15),
						c + Vector2(s * 0.45, s * 0.5), c + Vector2(-s * 0.45, s * 0.5)]), col)
				draw_line(c + Vector2(0, -s * 0.85), c + Vector2(0, -s * 1.25), col, 2.0, true)
			"order":
				# Une balance : fléau, colonne et deux plateaux.
				draw_line(c + Vector2(0, -s * 1.1), c + Vector2(0, s * 1.0), col, 1.6, true)
				draw_line(c + Vector2(-s * 1.1, -s * 0.7), c + Vector2(s * 1.1, -s * 0.7), col, 1.6, true)
				draw_line(c + Vector2(-s * 0.5, s * 1.0), c + Vector2(s * 0.5, s * 1.0), col, 1.6, true)
				for side in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([c + Vector2(side * s * 1.1, -s * 0.6), c + Vector2(side * s * 1.1 - s * 0.45, s * 0.15),
							c + Vector2(side * s * 1.1 + s * 0.45, s * 0.15)]), col)
			"trade":
				# Deux flèches opposées : l'aller et le retour d'une route.
				for side in [-1.0, 1.0]:
					var y: float = side * s * 0.45
					var x0: float = -side * s * 1.1
					var x1: float = side * s * 1.1
					draw_line(c + Vector2(x0, y), c + Vector2(x1, y), col, 1.6, true)
					draw_colored_polygon(PackedVector2Array([c + Vector2(x1 + side * s * 0.1, y), c + Vector2(x1 - side * s * 0.45, y - s * 0.35),
							c + Vector2(x1 - side * s * 0.45, y + s * 0.35)]), col)
			"faith":
				# Une flamme au-dessus d'un autel.
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.25), c + Vector2(s * 0.55, -s * 0.2), c + Vector2(s * 0.3, s * 0.35),
						c + Vector2(-s * 0.3, s * 0.35), c + Vector2(-s * 0.55, -s * 0.2)]), col)
				draw_rect(Rect2(c + Vector2(-s * 0.95, s * 0.5), Vector2(s * 1.9, s * 0.25)), col)
				draw_rect(Rect2(c + Vector2(-s * 0.6, s * 0.75), Vector2(s * 1.2, s * 0.4)), Color(col, 0.7))
			"culture":
				# Un masque de théâtre et ses rayons : le rayonnement culturel.
				for k in 8:
					var a := TAU * float(k) / 8.0
					draw_line(c + Vector2(cos(a), sin(a)) * s * 0.95, c + Vector2(cos(a), sin(a)) * s * 1.3, Color(col, 0.75), 1.3, true)
				draw_circle(c, s * 0.78, col)
				draw_circle(c + Vector2(-s * 0.3, -s * 0.15), s * 0.14, Color(0.05, 0.07, 0.1))
				draw_circle(c + Vector2(s * 0.3, -s * 0.15), s * 0.14, Color(0.05, 0.07, 0.1))
				draw_arc(c + Vector2(0, s * 0.12), s * 0.38, PI * 0.15, PI * 0.85, 12, Color(0.05, 0.07, 0.1), 1.6, true)
			"psionics":
				# Un œil fermé d'où montent trois ondes : le Songe.
				draw_arc(c + Vector2(0, s * 0.25), s * 0.85, PI * 1.15, PI * 1.85, 14, col, 1.6, true)
				draw_arc(c + Vector2(0, -s * 0.55), s * 0.85, PI * 0.15, PI * 0.85, 14, col, 1.6, true)
				draw_circle(c + Vector2(0, -s * 0.15), s * 0.18, col)
				for k in 3:
					var r := s * (0.55 + 0.3 * float(k))
					draw_arc(c + Vector2(0, -s * 0.15), r, PI * 1.3, PI * 1.7, 10, Color(col, 0.75 - 0.2 * float(k)), 1.2, true)
			"genome":
				# Une double hélice et ses barreaux : le génome.
				var prev_a := Vector2.ZERO
				var prev_b := Vector2.ZERO
				for k in 9:
					var y := -s * 1.2 + s * 2.4 * float(k) / 8.0
					var x := sin(float(k) / 8.0 * TAU) * s * 0.75
					var pa := c + Vector2(x, y)
					var pb := c + Vector2(-x, y)
					if k > 0:
						draw_line(prev_a, pa, col, 1.6, true)
						draw_line(prev_b, pb, Color(col, 0.7), 1.6, true)
					if k % 2 == 1:
						draw_line(pa, pb, Color(col, 0.6), 1.0, true)
					prev_a = pa
					prev_b = pb
			"wonders":
				# Une pyramide à degrés sous une étoile : les grands œuvres.
				for k in 3:
					var w := s * (1.2 - 0.38 * k)
					draw_rect(Rect2(c + Vector2(-w, s * (0.75 - 0.5 * k)), Vector2(w * 2.0, s * 0.42)), col)
				draw_circle(c + Vector2(0, -s * 0.95), s * 0.22, col)
			"amphictyony":
				# Un fronton à colonnes : la tribune de l'Amphictyonie.
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.2, -s * 0.45), c + Vector2(0, -s * 1.15), c + Vector2(s * 1.2, -s * 0.45)]), col)
				for k in 4:
					var x := -s * 0.9 + k * s * 0.6
					draw_rect(Rect2(c + Vector2(x - s * 0.12, -s * 0.3), Vector2(s * 0.24, s * 1.05)), col)
				draw_rect(Rect2(c + Vector2(-s * 1.2, s * 0.8), Vector2(s * 2.4, s * 0.25)), col)
			"senate":
				# Un hémicycle : deux rangées de sièges en demi-cercle et la tribune.
				for k in 2:
					var r := s * (0.75 + 0.5 * k)
					for j in 5 + 2 * k:
						var a := PI + PI * (float(j) + 0.5) / float(5 + 2 * k)
						draw_circle(c + Vector2(0, s * 0.55) + Vector2(cos(a), sin(a)) * r, s * 0.16, col)
				draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.35), Vector2(s * 0.6, s * 0.45)), col)
			"codex":
				# Un livre fermé, son dos et une étoile sur le plat (Codex de l'Archonte).
				draw_rect(Rect2(c + Vector2(-s * 0.95, -s * 1.15), Vector2(s * 1.9, s * 2.3)), col, false, 1.5)
				draw_line(c + Vector2(-s * 0.55, -s * 1.15), c + Vector2(-s * 0.55, s * 1.15), col, 1.5, true)
				var star := PackedVector2Array()
				for i in 10:
					var r := s * (0.5 if i % 2 == 0 else 0.2)
					var a := -PI / 2.0 + i * PI / 5.0
					star.append(c + Vector2(s * 0.22, -s * 0.1) + Vector2(cos(a), sin(a)) * r)
				draw_colored_polygon(star, col)
				if has_meta("badge") and bool(get_meta("badge")):
					draw_circle(c + Vector2(s * 1.15, -s * 1.15), 3.0, UiTheme.ACCENT)
			"chronicles":
				# Un livre ouvert : deux pages et le dos.
				for side in [-1.0, 1.0]:
					draw_polyline(PackedVector2Array([c + Vector2(0, -s * 0.7), c + Vector2(side * s * 1.2, -s * 0.95),
							c + Vector2(side * s * 1.2, s * 0.85), c + Vector2(0, s * 1.05), c + Vector2(0, -s * 0.7)]), col, 1.5, true)
					for k in 3:
						var y := -s * 0.45 + k * s * 0.45
						draw_line(c + Vector2(side * s * 0.25, y), c + Vector2(side * s * 0.95, y - s * 0.15), Color(col, 0.6), 1.0, true)
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
	## Portrait d'un héros précis (voir set_hero) : classe, niveau, âge, état, couleur de son empire.
	var hero := {}
	## Technologie dont l'image est dessinée (TechArt) quand res://assets/tech/<id>.png manque.
	var tech_id := ""
	var _tex: TextureRect
	var _caption: Label
	## Icône encadrée de l'entrée (GameIcon), posée dans le coin bas gauche ; voir set_icon.
	var _medal: GameIcon.Medal
	## Portrait dessiné animé (essai « portraits animés ») : horloge propre et cadence de redessin.
	var _anim_t := 0.0
	var _anim_acc := 0.0

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

	## Pose dans le coin bas gauche l'icône encadrée d'une entrée du jeu (haut fait, relique…) ;
	## id vide l'enlève. side : côté de l'icône, par défaut la moitié de la hauteur de l'emplacement.
	func set_icon(family: String, id: String, side := 0.0) -> void:
		if _medal == null:
			_medal = GameIcon.Medal.new()
			add_child(_medal)
		var s := side if side > 0.0 else clampf(custom_minimum_size.y * 0.5, 22.0, 72.0)
		_medal.custom_minimum_size = Vector2(s, s)
		_medal.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_medal.offset_left = 4.0
		_medal.offset_right = 4.0 + s
		_medal.offset_top = -4.0 - s
		_medal.offset_bottom = -4.0
		_medal.set_entry(family, id)

	## Personnalise un portrait de la galerie des héros : info = {"seed", "cls", "lvl", "age", "wound",
	## "prisoner", "heir", "faction": Color}. Le portrait de galerie donne la silhouette ; le héros y met
	## sa tenue de classe, ses lauriers et ses étoiles, son âge, ses blessures et la cape de son empire.
	func set_hero(info: Dictionary) -> void:
		hero = info
		queue_redraw()

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
		# Bandeau (très large, peu haut) : le motif se range à droite, le libellé s'arrête avant lui.
		if is_banner():
			_caption.offset_right = -custom_minimum_size.y * 1.6
			_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		queue_redraw()

	## Emplacement en bandeau : au moins quatre fois plus large que haut.
	func is_banner() -> bool:
		return custom_minimum_size.x >= custom_minimum_size.y * 4.0

	func _load() -> void:
		if tech_id != "":
			_tex.texture = TechArt.texture(tech_id)
			return
		var p := art_path(art_id)
		_tex.texture = load(p) as Texture2D if p != "" else null
		# Essai « portraits animés » : une illustration de personnage respire, regarde, cligne.
		PortraitMotion.attach(self, _tex, art_id)
		# Sans illustration, la silhouette dessinée s'anime elle aussi (voir _draw_portrait).
		set_process(PortraitMotion.enabled and _tex.texture == null and _is_drawn_portrait())

	func _is_drawn_portrait() -> bool:
		return art_id.begins_with("portrait_") or art_id.begins_with("hero_") or art_id.begins_with("ruler_")

	## Redessine la silhouette animée environ 30 fois par seconde, seulement quand elle est visible.
	func _process(delta: float) -> void:
		_anim_t += delta
		_anim_acc += delta
		if _anim_acc >= 1.0 / 30.0 and is_visible_in_tree():
			_anim_acc = 0.0
			queue_redraw()

	## Pose animée du buste : [respiration 0..1, angle de la tête, décalage de la tête, fermeture des yeux].
	func _pose() -> Array:
		if not PortraitMotion.enabled:
			return [0.0, 0.0, Vector2.ZERO, 0.0]
		var ph := float(hash(art_id) % 997) * 0.37 + float(variant) * 1.3 + float(int(hero.get("seed", 0)) % 101) * 0.11
		var t := _anim_t + ph
		var period := 4.6
		var u := fmod(t, period) / period
		var b := 0.5 + 0.5 * sin(u * TAU - 0.6 * sin(u * TAU))
		var ang := deg_to_rad(2.4) * (sin(t * 0.37) * 0.6 + sin(t * 0.83 + 1.7) * 0.4)
		var sway := Vector2(sin(t * 0.29 + 0.5), sin(t * 0.41) * 0.4)
		# Clignement : une fois par intervalle de 4,3 s, à un moment tiré de l'intervalle.
		var every := 4.3
		var slot := floorf(t / every)
		var at := 0.5 + absf(fmod(sin(slot * 91.3 + ph) * 9137.1, 1.0)) * (every - 1.2)
		var blink := clampf(1.0 - absf(t - slot * every - at - 0.08) / 0.08, 0.0, 1.0)
		return [b, ang, sway, blink]

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if has_art():
			if _caption and _caption.text != "":
				_shade(r)
			return
		if tech_id != "":
			TechArt.draw_full(self, r, tech_id)
			draw_rect(r, Color(1, 1, 1, 0.08), false, 1.0)
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
		if is_banner() and _caption and _caption.text != "":
			c.x = size.x - size.y * 0.8
		if art_id.begins_with("portrait_") or art_id.begins_with("hero_") or art_id.begins_with("ruler_"):
			_draw_portrait(r)
			if _caption and _caption.text != "":
				_shade(r)
			draw_rect(r, Color(1, 1, 1, 0.08), false, 1.0)
			return
		if _wants_tableau():
			_draw_tableau(r)
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

	## Un emplacement nommé, assez grand et sans illustration reçoit un tableau provisoire (refonte, F3).
	func _wants_tableau() -> bool:
		return art_id != "" and motif != "none" and motif != "lock" and not is_banner() and minf(size.x, size.y) >= 70.0

	## Tableau provisoire : un ciel, un astre et un horizon tirés de l'identifiant, dans la teinte de
	## l'emplacement, avec son nom dans un coin pour savoir quelle image manque. Le fichier déposé
	## sous ce nom dans assets/art/ le remplace.
	func _draw_tableau(r: Rect2) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(art_id)
		var w := r.size.x
		var h := r.size.y
		var s := minf(w, h)
		var night := Color(0.03, 0.05, 0.09)
		var top := night.lerp(tint, 0.10)
		var glow := night.lerp(tint, 0.42)
		var hz := h * rng.randf_range(0.66, 0.8)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, hz), Vector2(0, hz)]), PackedColorArray([top, top, glow, glow]))
		var near := night.lerp(tint, 0.16)
		draw_polygon(PackedVector2Array([Vector2(0, hz), Vector2(w, hz), Vector2(w, h), Vector2(0, h)]), PackedColorArray([near, near, night, night]))
		for i in int(clampf(w * h / 900.0, 24.0, 160.0)):
			var p := Vector2(rng.randf() * w, rng.randf() * hz * 0.92)
			draw_circle(p, rng.randf_range(0.5, 1.3), Color(1, 1, 1, rng.randf_range(0.15, 0.7) * (1.0 - p.y / hz * 0.7)))
		# L'astre : une planète et son croissant, un soleil bas, une galaxie ou deux lunes selon le motif.
		var c := Vector2(w * rng.randf_range(0.58, 0.8), hz * rng.randf_range(0.3, 0.55))
		match motif:
			"planet", "faction":
				var pr := s * rng.randf_range(0.2, 0.3)
				draw_circle(c, pr * 1.3, Color(tint, 0.07))
				draw_circle(c, pr, night.lerp(tint, 0.3))
				draw_circle(c + Vector2(-pr, -pr) * 0.16, pr * 0.84, Color(night.lerp(tint, 0.62), 0.9))
				draw_arc(c, pr, PI * 0.9, PI * 1.6, 40, Color(tint.lightened(0.5), 0.75), 1.5, true)
				if rng.randf() < 0.45:
					draw_set_transform(c, rng.randf_range(-0.5, 0.5), Vector2(1.0, 0.28))
					draw_arc(Vector2.ZERO, pr * 1.7, 0.0, TAU, 64, Color(tint.lightened(0.35), 0.5), 2.0, true)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if motif == "faction":
					draw_circle(c + Vector2(-pr * 2.2, -pr * 0.6), pr * 0.22, Color(tint.lightened(0.4), 0.8))
			"galaxy":
				for i in 220:
					var t := rng.randf()
					var a := float(rng.randi() % 2) * PI + t * 4.4 + rng.randf_range(-0.25, 0.25)
					draw_circle(c + Vector2(cos(a), sin(a) * 0.42) * t * s * 0.42, rng.randf_range(0.5, 1.5), Color(tint.lightened(0.45), rng.randf_range(0.2, 0.8) * (1.0 - t * 0.6)))
				draw_circle(c, s * 0.04, Color(tint.lightened(0.7), 0.85))
			_:
				c.y = hz - s * rng.randf_range(0.02, 0.16)
				for i in 5:
					draw_circle(c, s * (0.4 - 0.07 * i), Color(tint.lightened(0.2), 0.05 + 0.035 * i))
				draw_circle(c, s * 0.09, tint.lightened(0.65))
		# L'horizon : crêtes, tours ou dunes, en deux plans.
		var kind := rng.randi() % 3
		for layer in 2:
			var base := hz - (1 - layer) * h * 0.035
			var col := night.lerp(tint, 0.2 - 0.12 * layer)
			var pts := PackedVector2Array([Vector2(0, h), Vector2(0, base)])
			var x := 0.0
			var ph := rng.randf() * TAU
			while x < w:
				var step := rng.randf_range(0.03, 0.09) * w
				match kind:
					0:
						pts.append(Vector2(x + step * 0.5, base - rng.randf_range(0.02, 0.14) * h * (1.4 - 0.6 * layer)))
						pts.append(Vector2(x + step, base - rng.randf_range(0.0, 0.03) * h))
					1:
						var th := rng.randf_range(0.02, 0.16) * h * (1.3 - 0.5 * layer)
						pts.append(Vector2(x, base - th))
						pts.append(Vector2(x + step * 0.7, base - th))
						pts.append(Vector2(x + step * 0.7, base))
						pts.append(Vector2(x + step, base))
					_:
						pts.append(Vector2(x + step, base - (0.5 + 0.5 * sin(ph + x / w * 9.0)) * h * 0.05 * (1.5 - layer)))
				x += step
			pts.append(Vector2(w, base))
			pts.append(Vector2(w, h))
			var tri := Geometry2D.triangulate_polygon(pts)
			if not tri.is_empty():
				draw_colored_polygon(pts, col)
			else:
				draw_rect(Rect2(0, base, w, h - base), col)
		# Le premier plan s'assombrit vers le bas du cadre.
		draw_polygon(PackedVector2Array([Vector2(0, hz), Vector2(w, hz), Vector2(w, h), Vector2(0, h)]),
				PackedColorArray([Color(night, 0.0), Color(night, 0.0), Color(night, 0.85), Color(night, 0.85)]))
		if UiSettings.art_ids and w >= 150.0:
			draw_string(ThemeDB.fallback_font, Vector2(7, 14), art_id, HORIZONTAL_ALIGNMENT_LEFT, w - 14.0, 10, Color(1, 1, 1, 0.5))

	## Portrait provisoire d'un peuple créé (« portrait_<id> ») tant qu'aucune illustration n'est
	## déposée : un buste en silhouette, humanoïde ou insectoïde, avec l'ornement décrit par le champ
	## "look" du portrait (data/species_parts.json) pour que chaque portrait de la galerie se distingue.
	func _draw_portrait(r: Rect2) -> void:
		var hero_ref := art_id.begins_with("hero_")
		var ruler_ref := art_id.begins_with("ruler_")
		var pid := art_id.trim_prefix("hero_") if hero_ref else (art_id.trim_prefix("ruler_") if ruler_ref else art_id.trim_prefix("portrait_"))
		var rdef := Rulers.portrait_def(art_id) if ruler_ref else {}
		var look := String((rdef if ruler_ref else (Heroes.portrait_def(art_id) if hero_ref else Species.portrait_def(pid))).get("look", ""))
		var hive := pid.begins_with("ruche")
		var rock := pid.begins_with("lithoide")
		var synth := pid.begins_with("synthetique")
		var scaly := pid.begins_with("reptilien")
		var glow := pid.begins_with("energetique")
		var s := minf(r.size.x, r.size.y * 0.9)
		var cx := r.size.x * 0.5
		var base := r.size.y
		var fill := Color(tint.darkened(0.35), 0.95)
		var edge := Color(tint.lightened(0.35), 0.8)
		var eye := Color(tint.lightened(0.7), 0.95)
		var me := hero_ref and not self.hero.is_empty()
		var hseed := int(self.hero.get("seed", 0))
		var head_k := 1.0
		var sw_k := 1.0
		if me:
			# Chaque héros a sa carrure, son teint et la couleur de son regard (tirés de son identifiant).
			head_k = 0.92 + 0.16 * _jit(hseed, 1)
			sw_k = 0.88 + 0.24 * _jit(hseed, 2)
			var shade := (_jit(hseed, 3) - 0.5) * 0.35
			fill = fill.lightened(shade) if shade > 0.0 else fill.darkened(-shade)
			eye = eye.lerp(Color(1.0, 0.82, 0.45), _jit(hseed, 4) * 0.6)
			# L'âge grise les contours (cheveux, crête, écailles) à partir de 55 ans.
			var age := int(self.hero.get("age", 30))
			if age >= 55:
				edge = edge.lerp(Color(0.86, 0.86, 0.88, edge.a), clampf((age - 55) / 30.0, 0.15, 0.75))
		draw_circle(Vector2(cx, base * 0.42), s * 0.42, Color(tint, 0.07))
		var sw := s * (0.5 if look == "colossus" or look == "boulder" else 0.4) * sw_k
		var sh_y := base * 0.78
		# Animation : les yeux s'éteignent le temps d'un clignement et leur lueur pulse doucement.
		var pose := _pose()
		var breath: float = pose[0]
		eye = Color(eye.lightened(0.08 * sin(_anim_t * 1.7 + float(variant))), eye.a * (1.0 - 0.9 * float(pose[3])))
		if ruler_ref:
			_draw_ruler_backdrop(r, String(rdef.get("backdrop", "")), cx, base, s)
		# Respiration : le buste s'étire un peu vers le haut depuis le bas du cadre.
		var sy := 1.0 + 0.02 * breath
		draw_set_transform(Vector2(0.0, base * (1.0 - sy)), 0.0, Vector2(1.0, sy))
		if ruler_ref:
			_draw_ruler_mantle(String(rdef.get("mantle", "")), cx, sh_y, sw, s, base)
		if me:
			# La cape aux couleurs de son empire, derrière les épaules.
			var fc: Color = self.hero.get("faction", tint)
			draw_colored_polygon(PackedVector2Array([Vector2(cx - sw * 1.25, base), Vector2(cx - sw * 0.95, sh_y - s * 0.02), Vector2(cx - sw * 0.2, sh_y - s * 0.14),
					Vector2(cx + sw * 0.2, sh_y - s * 0.14), Vector2(cx + sw * 0.95, sh_y - s * 0.02), Vector2(cx + sw * 1.25, base)]), Color(fc.darkened(0.25), 0.9))
		draw_colored_polygon(PackedVector2Array([Vector2(cx - sw, base), Vector2(cx - sw * 0.85, sh_y), Vector2(cx - sw * 0.3, sh_y - s * 0.08),
				Vector2(cx + sw * 0.3, sh_y - s * 0.08), Vector2(cx + sw * 0.85, sh_y), Vector2(cx + sw, base)]), Color(fill.darkened(0.2), 0.25 if glow else 1.0))
		var head := Vector2(cx, base * 0.48)
		var hr := s * (0.14 if look == "crown" and hive else 0.17) * head_k
		# Tête : soulevée avec les épaules, elle pivote autour du cou et dérive un peu.
		var neck := Vector2(cx, (sh_y - s * 0.08) - (base - (sh_y - s * 0.08)) * (sy - 1.0))
		var hang: float = pose[1]
		var hoff: Vector2 = pose[2] * s * 0.012
		var hxf := Transform2D(hang, neck + hoff) * Transform2D(0.0, -Vector2(cx, sh_y - s * 0.08))
		draw_set_transform_matrix(hxf)
		if hero_ref:
			_draw_hero_attire(head, hr, cx, sh_y, sw, s, base, edge, me)
		if synth:
			# Tête de châssis : un carré arrondi, des joints, une lumière à la place des yeux.
			draw_line(head + Vector2(-hr * 0.2, hr), head + Vector2(-hr * 0.2, hr * 1.6), fill, hr * 0.25)
			draw_line(head + Vector2(hr * 0.2, hr), head + Vector2(hr * 0.2, hr * 1.6), fill, hr * 0.25)
			var box := Rect2(head - Vector2(hr, hr * 1.05), Vector2(hr * 2, hr * 2.1))
			draw_rect(box, fill)
			draw_rect(box, edge, false, 1.5)
			draw_line(head + Vector2(-hr, hr * 0.45), head + Vector2(hr, hr * 0.45), Color(edge, 0.5), 1.0)
			match look:
				"visor":
					draw_rect(Rect2(head + Vector2(-hr * 0.75, -hr * 0.35), Vector2(hr * 1.5, hr * 0.35)), Color(eye, 0.85))
				"antenna":
					for side in [-1.0, 1.0]:
						var a0 := head + Vector2(side * hr * 0.6, -hr * 1.05)
						draw_line(a0, a0 + Vector2(side * hr * 0.3, -hr * 0.9), edge, 1.5, true)
						draw_circle(a0 + Vector2(side * hr * 0.3, -hr * 0.9), 3.0, eye)
					for side in [-1.0, 1.0]:
						draw_circle(head + Vector2(side * hr * 0.4, -hr * 0.15), 3.0, eye)
				"core":
					draw_circle(head + Vector2(0, -hr * 0.1), hr * 0.45, Color(eye, 0.3))
					draw_circle(head + Vector2(0, -hr * 0.1), hr * 0.22, eye)
					draw_arc(head + Vector2(0, -hr * 0.1), hr * 0.45, 0.0, TAU, 24, edge, 1.5, true)
		elif rock:
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
		elif glow:
			# Être d'énergie : un halo en couches, sans contour net, et des yeux comme des trous de lumière.
			for k in 5:
				draw_circle(head, hr * (1.7 - 0.25 * k), Color(eye, 0.06 + 0.05 * k))
			match look:
				"wisp":
					var wp := PackedVector2Array()
					for i in 17:
						var t := i / 16.0
						var a := PI * (1.0 + t)
						wp.append(head + Vector2(cos(a) * hr * 0.9, sin(a) * hr * 1.6 * (0.7 + 0.3 * sin(t * PI * 3.0))))
					wp.append(head + Vector2(hr * 0.9, hr * 0.6))
					wp.append(head + Vector2(0, hr * 1.5))
					wp.append(head + Vector2(-hr * 0.9, hr * 0.6))
					draw_colored_polygon(wp, Color(edge, 0.35))
				"rings":
					for k in 3:
						draw_arc(head, hr * (0.6 + 0.35 * k), -PI * 0.1 * k, PI * (1.4 - 0.2 * k), 24, Color(eye, 0.7 - 0.15 * k), 1.5, true)
				"veil":
					var vp := PackedVector2Array([head + Vector2(-hr * 1.1, hr * 1.4), head + Vector2(-hr * 0.9, -hr * 0.6), head + Vector2(0, -hr * 1.3),
							head + Vector2(hr * 0.9, -hr * 0.6), head + Vector2(hr * 1.1, hr * 1.4)])
					draw_colored_polygon(vp, Color(fill, 0.85))
					vp.append(vp[0])
					draw_polyline(vp, Color(edge, 0.6), 1.5, true)
			for side in [-1.0, 1.0]:
				draw_circle(head + Vector2(side * hr * 0.35, -hr * 0.1), hr * 0.16, Color(1, 1, 1, 0.9))
				draw_circle(head + Vector2(side * hr * 0.35, -hr * 0.1), hr * 0.3, Color(eye, 0.35))
		elif scaly:
			# Tête de reptile : un crâne en coin qui s'affine vers le museau, des écailles, des yeux fendus.
			draw_line(head + Vector2(0, hr), head + Vector2(0, hr * 1.6), fill, hr * 0.8)
			if look == "frill":
				var fp := PackedVector2Array()
				for i in 13:
					var a := PI * 0.95 + PI * 1.1 * i / 12.0
					var rr := hr * (1.9 if i % 2 == 0 else 1.55)
					fp.append(head + Vector2(cos(a) * rr, sin(a) * rr * 0.9 + hr * 0.2))
				fp.append(head + Vector2(0, hr * 0.2))
				draw_colored_polygon(fp, Color(edge, 0.45))
			var long := 1.35 if look == "snout" else 1.15
			var sp := PackedVector2Array([head + Vector2(-hr * 0.95, -hr * 0.55), head + Vector2(-hr * 0.55, -hr * 1.0), head + Vector2(hr * 0.55, -hr * 1.0),
					head + Vector2(hr * 0.95, -hr * 0.55), head + Vector2(hr * 0.6, hr * 0.5), head + Vector2(hr * 0.25, hr * long),
					head + Vector2(-hr * 0.25, hr * long), head + Vector2(-hr * 0.6, hr * 0.5)])
			draw_colored_polygon(sp, fill)
			sp.append(sp[0])
			draw_polyline(sp, edge, 1.5, true)
			for k in 3:
				for j in 3 - (k % 2):
					var x := -hr * 0.4 + j * hr * 0.4 + (hr * 0.2 if k % 2 == 1 else 0.0)
					draw_arc(head + Vector2(x, -hr * 0.65 + k * hr * 0.22), hr * 0.13, 0.0, PI, 6, Color(edge, 0.45), 1.0, true)
			for side in [-1.0, 1.0]:
				var e0 := head + Vector2(side * hr * 0.45, -hr * 0.05)
				draw_circle(e0, hr * 0.17, Color(eye, 0.35))
				draw_line(e0 + Vector2(0, -hr * 0.14), e0 + Vector2(0, hr * 0.14), eye, 2.0, true)
				draw_circle(head + Vector2(side * hr * 0.12, hr * (long - 0.2)), 1.5, Color(edge, 0.8))
			if look == "spines":
				for k in 5:
					var x := -hr * 0.5 + k * hr * 0.25
					var h := hr * (0.5 + 0.35 * (2 - absi(k - 2)) * 0.5)
					draw_colored_polygon(PackedVector2Array([head + Vector2(x - 4, -hr * 0.95), head + Vector2(x, -hr * 0.95 - h), head + Vector2(x + 4, -hr * 0.95)]), edge)
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
				"helm":
					# Heaume d'amirale : calotte, nasal, deux ailes.
					draw_arc(head, hr * 1.08, PI * 1.0, PI * 2.0, 24, edge, 3.0, true)
					draw_line(head + Vector2(0, -hr * 1.08), head + Vector2(0, hr * 0.35), edge, 2.5, true)
					for side in [-1.0, 1.0]:
						# Deux plumes en triangles : d'un seul tenant, le contour se recoupait et la triangulation échouait.
						draw_colored_polygon(PackedVector2Array([head + Vector2(side * hr * 0.95, -hr * 0.5), head + Vector2(side * hr * 1.9, -hr * 1.5),
								head + Vector2(side * hr * 1.5, -hr * 0.6)]), Color(edge, 0.8))
						draw_colored_polygon(PackedVector2Array([head + Vector2(side * hr * 1.2, -hr * 0.45), head + Vector2(side * hr * 1.8, -hr * 0.9),
								head + Vector2(side * hr * 1.05, -hr * 0.15)]), Color(edge, 0.8))
				"eyepatch":
					draw_line(head + Vector2(-hr * 0.95, -hr * 0.45), head + Vector2(hr * 0.95, hr * 0.1), edge, 1.5, true)
					draw_circle(head + Vector2(hr * 0.38, -hr * 0.05), hr * 0.22, edge.darkened(0.6))
					for k in 3:
						draw_line(head + Vector2(-hr * 0.5 + k * hr * 0.5, hr * 0.55), head + Vector2(-hr * 0.4 + k * hr * 0.5, hr * 0.95), Color(edge, 0.6), 1.5, true)
				"scar":
					draw_line(head + Vector2(-hr * 0.7, -hr * 0.7), head + Vector2(-hr * 0.05, hr * 0.6), Color(1.0, 0.55, 0.5, 0.85), 2.0, true)
					for k in 3:
						var p0 := head + Vector2(-hr * 0.6 + k * hr * 0.22, -hr * 0.45 + k * hr * 0.4)
						draw_line(p0 + Vector2(-hr * 0.1, -hr * 0.05), p0 + Vector2(hr * 0.1, hr * 0.05), Color(1.0, 0.55, 0.5, 0.7), 1.0, true)
					draw_arc(head, hr * 1.15, PI * 1.05, PI * 1.95, 20, Color(edge, 0.7), 4.0, true)
				"braids":
					for side in [-1.0, 1.0]:
						var b0 := head + Vector2(side * hr * 0.9, -hr * 0.2)
						for k in 4:
							draw_circle(b0 + Vector2(side * hr * 0.12, hr * 0.45 * k), hr * 0.17, edge)
					draw_arc(head, hr * 1.02, PI * 1.1, PI * 1.9, 20, edge, 3.0, true)
			if look == "hood":
				for side in [-1.0, 1.0]:
					draw_line(head + Vector2(side * hr * 0.5, -hr * 0.05), head + Vector2(side * hr * 0.2, -hr * 0.05), eye, 2.0)
			elif look == "eyepatch":
				draw_circle(head + Vector2(-hr * 0.38, -hr * 0.05), 2.2, eye)
			else:
				for side in [-1.0, 1.0]:
					draw_circle(head + Vector2(side * hr * 0.38, -hr * 0.05), 2.2, eye)
		if ruler_ref:
			_draw_ruler_regalia(String(rdef.get("regalia", "")), head, hr)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if me:
			_draw_hero_state(r, head, hr, edge)

	## Décor d'un portrait de souverain (data/rulers.json « portraits ») : trône, étoiles, colonnes,
	## bannière, rayons ou arche, derrière le buste.
	func _draw_ruler_backdrop(r: Rect2, kind: String, cx: float, base: float, s: float) -> void:
		var gold := Color(0.95, 0.78, 0.36, 0.22)
		var dim := Color(tint.lightened(0.3), 0.16)
		match kind:
			"throne":
				var w := s * 0.62
				draw_rect(Rect2(cx - w * 0.5, base * 0.1, w, base * 0.9), Color(tint.darkened(0.5), 0.55))
				draw_rect(Rect2(cx - w * 0.5, base * 0.1, w, base * 0.9), gold, false, 2.0)
				for side in [-1.0, 1.0]:
					draw_circle(Vector2(cx + side * w * 0.5, base * 0.1), s * 0.035, gold)
			"stars":
				for i in 24:
					var p := Vector2(_jit(i, 11) * r.size.x, _jit(i, 12) * r.size.y * 0.7)
					draw_circle(p, 0.6 + _jit(i, 13) * 1.4, Color(1, 1, 1, 0.25 + _jit(i, 14) * 0.4))
			"pillars":
				for side in [-1.0, 1.0]:
					var x: float = cx + side * s * 0.62
					draw_rect(Rect2(x - s * 0.06, base * 0.05, s * 0.12, base * 0.95), dim)
					draw_rect(Rect2(x - s * 0.09, base * 0.05, s * 0.18, s * 0.04), gold)
			"banner":
				var w2 := s * 0.36
				var pts := PackedVector2Array([Vector2(cx - w2, 0), Vector2(cx + w2, 0), Vector2(cx + w2, base * 0.62), Vector2(cx, base * 0.52), Vector2(cx - w2, base * 0.62)])
				draw_colored_polygon(pts, Color(tint.darkened(0.2), 0.35))
				pts.append(pts[0])
				draw_polyline(pts, gold, 1.5, true)
			"rays":
				var o := Vector2(cx, base * 0.45)
				for i in 16:
					var a := TAU * i / 16.0
					draw_line(o, o + Vector2(cos(a), sin(a)) * s * 0.75, Color(0.95, 0.8, 0.45, 0.1), 3.0)
			"arch":
				draw_arc(Vector2(cx, base * 0.5), s * 0.5, PI, TAU, 40, gold, 3.0, true)
				for side in [-1.0, 1.0]:
					draw_line(Vector2(cx + side * s * 0.5, base * 0.5), Vector2(cx + side * s * 0.5, base), gold, 3.0)

	## Manteau du souverain, plus large que la cape d'un héros, sous les épaules.
	func _draw_ruler_mantle(kind: String, cx: float, sh_y: float, sw: float, s: float, base: float) -> void:
		var col := Color(tint.darkened(0.15), 0.95)
		match kind:
			"ermine": col = Color(0.55, 0.1, 0.14, 0.95)
			"scales": col = Color(0.18, 0.4, 0.3, 0.95)
			"chains": col = Color(0.3, 0.3, 0.34, 0.95)
			"stars": col = Color(0.12, 0.14, 0.38, 0.95)
			"rays": col = Color(0.62, 0.45, 0.12, 0.95)
		var pts := PackedVector2Array([Vector2(cx - sw * 1.45, base), Vector2(cx - sw * 1.05, sh_y - s * 0.04), Vector2(cx - sw * 0.25, sh_y - s * 0.17),
				Vector2(cx + sw * 0.25, sh_y - s * 0.17), Vector2(cx + sw * 1.05, sh_y - s * 0.04), Vector2(cx + sw * 1.45, base)])
		draw_colored_polygon(pts, col)
		match kind:
			"ermine":
				draw_line(Vector2(cx - sw * 1.05, sh_y - s * 0.04), Vector2(cx + sw * 1.05, sh_y - s * 0.04), Color(0.95, 0.95, 0.92), s * 0.05)
				for k in 7:
					draw_circle(Vector2(cx - sw + sw * 2.0 * k / 6.0, sh_y - s * 0.04), s * 0.008, Color(0.05, 0.05, 0.05))
			"scales":
				for k in 6:
					draw_arc(Vector2(cx - sw + sw * 0.4 * k, base - s * 0.08), s * 0.04, 0.0, PI, 8, Color(0.6, 0.9, 0.7, 0.5), 1.0)
			"chains":
				for k in 5:
					draw_arc(Vector2(cx - sw * 0.5 + sw * 0.25 * k, sh_y + s * 0.02), s * 0.025, 0.0, TAU, 10, Color(0.9, 0.8, 0.5, 0.8), 1.5)
			"stars":
				for k in 9:
					draw_circle(Vector2(cx - sw * 1.2 + _jit(k, 21) * sw * 2.4, sh_y + _jit(k, 22) * (base - sh_y)), 1.2, Color(1, 1, 0.9, 0.8))
			"rays":
				for k in 5:
					draw_line(Vector2(cx, sh_y), Vector2(cx - sw * 1.2 + sw * 0.6 * k, base), Color(1, 0.9, 0.5, 0.45), 1.5)

	## Insigne du pouvoir posé sur la tête : tiare, pointes, diadème d'étoiles, heaume couronné,
	## couronne fermée ou lauriers.
	func _draw_ruler_regalia(kind: String, head: Vector2, hr: float) -> void:
		var gold := Color(0.97, 0.8, 0.36, 0.95)
		var top := head.y - hr * 1.05
		match kind:
			"crown":
				var pts := PackedVector2Array([Vector2(head.x - hr * 0.8, top), Vector2(head.x - hr * 0.8, top - hr * 0.5), Vector2(head.x - hr * 0.4, top - hr * 0.25),
						Vector2(head.x, top - hr * 0.6), Vector2(head.x + hr * 0.4, top - hr * 0.25), Vector2(head.x + hr * 0.8, top - hr * 0.5), Vector2(head.x + hr * 0.8, top)])
				draw_colored_polygon(pts, gold)
				draw_circle(Vector2(head.x, top - hr * 0.15), hr * 0.1, Color(0.8, 0.15, 0.2))
			"tiara":
				draw_colored_polygon(PackedVector2Array([Vector2(head.x - hr * 0.6, top + hr * 0.05), Vector2(head.x, top - hr * 0.95), Vector2(head.x + hr * 0.6, top + hr * 0.05)]), gold)
				for k in 3:
					draw_line(Vector2(head.x - hr * 0.45 + hr * 0.15 * k, top - hr * 0.2 * k), Vector2(head.x + hr * 0.45 - hr * 0.15 * k, top - hr * 0.2 * k), Color(0.6, 0.45, 0.1), 1.5)
			"spikes":
				for k in 5:
					var x := head.x - hr * 0.8 + hr * 0.4 * k
					draw_colored_polygon(PackedVector2Array([Vector2(x - hr * 0.12, top + hr * 0.1), Vector2(x, top - hr * (0.5 + 0.25 * (2 - absi(k - 2)))), Vector2(x + hr * 0.12, top + hr * 0.1)]), gold)
			"star_diadem":
				draw_arc(head, hr * 1.1, PI * 1.15, PI * 1.85, 24, gold, 2.0, true)
				for k in 5:
					var a := PI * (1.2 + 0.15 * k)
					draw_circle(head + Vector2(cos(a), sin(a)) * hr * 1.25, hr * 0.09, Color(1, 1, 0.85))
			"helm_crown":
				draw_arc(head, hr * 1.05, PI, TAU, 24, Color(0.7, 0.72, 0.78, 0.95), hr * 0.3, true)
				for k in 3:
					var x := head.x - hr * 0.5 + hr * 0.5 * k
					draw_colored_polygon(PackedVector2Array([Vector2(x - hr * 0.12, top - hr * 0.1), Vector2(x, top - hr * 0.5), Vector2(x + hr * 0.12, top - hr * 0.1)]), gold)
			"laurel":
				for side in [-1.0, 1.0]:
					for k in 5:
						var a: float = PI * 1.5 + side * (0.35 + 0.18 * k)
						var p := head + Vector2(cos(a), sin(a)) * hr * 1.08
						draw_circle(p, hr * 0.11, Color(0.75, 0.82, 0.35, 0.95))

	## Tirage stable 0-1 pour les variations d'un héros (même héros, même visage).
	static func _jit(seed_value: int, k: int) -> float:
		return float(absi(hash([seed_value, "visage", k])) % 1000) / 1000.0

	## Ce qu'un héros a gagné : lauriers (niveau 3 et plus, plus fournis à chaque niveau) et tenue de sa
	## classe. Sans héros précis (galerie), les lauriers complets et un médaillon d'or.
	func _draw_hero_attire(head: Vector2, hr: float, cx: float, sh_y: float, sw: float, s: float, base: float, edge: Color, me: bool) -> void:
		var gold := Color(0.95, 0.78, 0.36, 0.85)
		var lvl := int(hero.get("lvl", 5)) if me else 5
		if lvl >= 3:
			for side in [-1.0, 1.0]:
				for k in 2 + lvl:
					var a: float = PI * 0.5 + side * (0.55 + 0.32 * k)
					var p0 := head + Vector2(cos(a), sin(a)) * hr * 2.05
					var leaf: Vector2 = Vector2(cos(a + side * 1.2), sin(a + side * 1.2)) * hr * 0.32
					draw_line(p0 - leaf * 0.5, p0 + leaf, Color(gold, 0.55), 3.0, true)
		var chest := Vector2(cx, sh_y + s * 0.05)
		match String(hero.get("cls", "")) if me else "":
			"stratege":
				# Épaulettes à franges et une rangée de décorations.
				for side in [-1.0, 1.0]:
					var e0 := Vector2(cx + side * sw * 0.62, sh_y - s * 0.035)
					draw_rect(Rect2(e0 - Vector2(sw * 0.2, s * 0.02), Vector2(sw * 0.4, s * 0.04)), gold)
					for k in 5:
						var x := e0.x - sw * 0.18 + k * sw * 0.09
						draw_line(Vector2(x, e0.y + s * 0.02), Vector2(x, e0.y + s * 0.065), Color(gold, 0.7), 1.5)
				for k in mini(lvl, 4):
					draw_rect(Rect2(chest + Vector2(-sw * 0.5 + k * sw * 0.13, s * 0.02), Vector2(sw * 0.1, s * 0.03)), Color(edge, 0.9))
			"intendant":
				# Chaîne d'office et son sceau.
				for k in 9:
					var a := PI * (0.15 + 0.7 * k / 8.0)
					draw_circle(chest + Vector2(cos(a) * sw * 0.45, sin(a) * s * 0.09 - s * 0.06), s * 0.012, gold)
				draw_rect(Rect2(chest + Vector2(-s * 0.03, s * 0.03), Vector2(s * 0.06, s * 0.06)), gold)
				draw_rect(Rect2(chest + Vector2(-s * 0.03, s * 0.03), Vector2(s * 0.06, s * 0.06)), Color(1, 0.95, 0.7, 0.9), false, 1.0)
			"orateur":
				# Écharpe en travers de la poitrine et col haut.
				draw_colored_polygon(PackedVector2Array([Vector2(cx - sw * 0.7, sh_y - s * 0.02), Vector2(cx - sw * 0.45, sh_y - s * 0.06),
						Vector2(cx + sw * 0.85, base), Vector2(cx + sw * 0.5, base)]), Color(tint.lightened(0.25), 0.8))
				draw_circle(Vector2(cx - sw * 0.05, sh_y + s * 0.07), s * 0.025, gold)
			"ombre":
				# Col relevé et une lame qui dépasse de l'épaule.
				for side in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([Vector2(cx + side * sw * 0.18, sh_y - s * 0.07), Vector2(cx + side * sw * 0.55, sh_y - s * 0.22),
							Vector2(cx + side * sw * 0.6, sh_y - s * 0.02)]), Color(fill_dark(), 0.95))
				var hilt := Vector2(cx + sw * 0.75, sh_y - s * 0.12)
				draw_line(hilt, hilt + Vector2(s * 0.05, -s * 0.12), Color(0.85, 0.88, 0.95, 0.9), 2.0, true)
				draw_line(hilt + Vector2(-s * 0.02, -s * 0.01), hilt + Vector2(s * 0.03, s * 0.01), gold, 2.0, true)
			_:
				draw_circle(chest, s * 0.045, gold)
				draw_arc(chest, s * 0.045, 0.0, TAU, 20, Color(1, 0.95, 0.7, 0.9), 1.2, true)

	func fill_dark() -> Color:
		return tint.darkened(0.7)

	## L'état du héros, par-dessus : étoiles de niveau, diadème de l'héritier, bandage, barreaux.
	func _draw_hero_state(r: Rect2, head: Vector2, hr: float, edge: Color) -> void:
		var gold := Color(0.95, 0.78, 0.36, 0.95)
		for k in int(hero.get("lvl", 1)):
			_star(Vector2(10 + k * 12, 11), 4.5, gold)
		if bool(hero.get("heir", false)):
			draw_arc(head + Vector2(0, -hr * 0.2), hr * 1.0, PI * 1.2, PI * 1.8, 16, gold, 2.5, true)
			for k in 3:
				var a := PI * (1.3 + 0.2 * k)
				var p0 := head + Vector2(0, -hr * 0.2) + Vector2(cos(a), sin(a)) * hr
				draw_line(p0, p0 + Vector2(cos(a), sin(a)) * hr * 0.35, gold, 2.0, true)
		if bool(hero.get("wound", false)):
			draw_line(head + Vector2(-hr * 1.05, -hr * 0.55), head + Vector2(hr * 1.05, -hr * 0.05), Color(0.92, 0.9, 0.84, 0.95), hr * 0.32, true)
			draw_circle(head + Vector2(hr * 0.3, -hr * 0.22), hr * 0.1, Color(0.85, 0.2, 0.2, 0.9))
		if bool(hero.get("prisoner", false)):
			var x := r.size.x * 0.12
			while x < r.size.x:
				draw_line(Vector2(x, 0), Vector2(x, r.size.y), Color(0.05, 0.05, 0.07, 0.75), 4.0)
				x += r.size.x * 0.19
			draw_line(Vector2(0, r.size.y * 0.2), Vector2(r.size.x, r.size.y * 0.2), Color(0.05, 0.05, 0.07, 0.75), 4.0)

	func _star(c: Vector2, rad: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + PI * i / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (rad if i % 2 == 0 else rad * 0.45))
		draw_colored_polygon(pts, col)

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

	## Change le libellé (un bouton Suivant porte le nom de l'étape où il mène).
	func set_label(text_value: String) -> void:
		label_text = text_value.to_upper()
		var f := UiTheme.font(400, 2)
		var w := DIAMETER + 14.0 + f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x + 4.0
		var right := offset_right
		var grows_left := grow_horizontal == Control.GROW_DIRECTION_BEGIN
		custom_minimum_size.x = w
		if grows_left:
			offset_left = right - w
			offset_right = right
		else:
			size.x = w
		queue_redraw()

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


## Barre empilée : des parts côte à côte, à une échelle donnée (pour comparer deux barres).
class StackBar:
	extends Control
	## [{"value": int, "color": Color, "label": String}]
	var parts: Array = []
	var scale_max := 1.0

	func _init(w := 700.0, h := 16.0) -> void:
		custom_minimum_size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_parts(value: Array, top: float) -> void:
		parts = value
		scale_max = maxf(1.0, top)
		var tips := PackedStringArray()
		for p in parts:
			if int(p["value"]) > 0:
				tips.append("%s : %d" % [p["label"], int(p["value"])])
		tooltip_text = "\n".join(tips)
		queue_redraw()

	func total() -> int:
		var t := 0
		for p in parts:
			t += maxi(0, int(p["value"]))
		return t

	## Rectangles des parts, dans l'ordre.
	func rects() -> Array[Rect2]:
		var out: Array[Rect2] = []
		var x := 0.0
		for p in parts:
			var w := size.x * maxf(0.0, float(p["value"])) / scale_max
			out.append(Rect2(x, 0, w, size.y))
			x += w
		return out

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.05))
		var rs := rects()
		for i in rs.size():
			if rs[i].size.x >= 1.0:
				draw_rect(Rect2(rs[i].position, Vector2(maxf(1.0, rs[i].size.x - 1.0), rs[i].size.y)), parts[i]["color"])


## Courbe d'une série de valeurs (bilan des derniers mois) : ligne, repère du zéro, dernier point marqué.
class Sparkline:
	extends Control
	var values: Array = []
	var color := Color.WHITE

	func _init(w := 150.0, h := 26.0) -> void:
		custom_minimum_size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_values(v: Array, col: Color) -> void:
		values = v
		color = col
		if v.is_empty():
			tooltip_text = "Pas encore de mois écoulé."
		else:
			tooltip_text = "Bilan net des %d derniers mois : de %+d à %+d, dernier %+d." % [v.size(), v.min(), v.max(), v[v.size() - 1]]
		queue_redraw()

	## Points de la courbe dans le cadre, du plus ancien au plus récent.
	func points() -> PackedVector2Array:
		var out := PackedVector2Array()
		if values.is_empty():
			return out
		var lo := minf(0.0, float(values.min()))
		var hi := maxf(0.0, float(values.max()))
		var span := maxf(1.0, hi - lo)
		var n := values.size()
		for i in n:
			var x := 2.0 + (size.x - 6.0) * (float(i) / float(maxi(1, n - 1)) if n > 1 else 1.0)
			out.append(Vector2(x, 2.0 + (size.y - 4.0) * (1.0 - (float(values[i]) - lo) / span)))
		return out

	func _draw() -> void:
		if values.is_empty():
			draw_line(Vector2(2, size.y * 0.5), Vector2(size.x - 2, size.y * 0.5), Color(1, 1, 1, 0.1), 1.0)
			return
		var lo := minf(0.0, float(values.min()))
		var hi := maxf(0.0, float(values.max()))
		var zero := 2.0 + (size.y - 4.0) * (1.0 - (0.0 - lo) / maxf(1.0, hi - lo))
		draw_line(Vector2(2, zero), Vector2(size.x - 2, zero), Color(1, 1, 1, 0.14), 1.0)
		var pts := points()
		if pts.size() > 1:
			draw_polyline(pts, color, 1.5, true)
		draw_circle(pts[pts.size() - 1], 2.5, color)


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
			"species":
				# Deux silhouettes : une tête et des épaules, la seconde en retrait.
				for o: Vector2 in [Vector2(s * 0.45, -s * 0.1), Vector2(-s * 0.25, 0)]:
					draw_arc(c + o + Vector2(0, -s * 0.45), s * 0.32, 0.0, TAU, 20, col, w, true)
					draw_arc(c + o + Vector2(0, s * 0.75), s * 0.62, PI * 1.08, PI * 1.92, 20, col, w, true)
			"join":
				# Deux mondes reliés : l'hôte et le joueur qui le rejoint.
				draw_arc(c + Vector2(-s * 0.55, s * 0.35), s * 0.42, 0.0, TAU, 20, col, w, true)
				draw_arc(c + Vector2(s * 0.55, -s * 0.35), s * 0.42, 0.0, TAU, 20, col, w, true)
				draw_line(c + Vector2(-s * 0.22, s * 0.12), c + Vector2(s * 0.22, -s * 0.12), col, w, true)
			"quick":
				for dx in [-s * 0.55, s * 0.25]:
					draw_polyline(PackedVector2Array([c + Vector2(dx - s * 0.35, -s * 0.8), c + Vector2(dx + s * 0.45, 0), c + Vector2(dx - s * 0.35, s * 0.8)]), col, w, true)
			"resume":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.6, -s), c + Vector2(s, 0), c + Vector2(-s * 0.6, s)]), col)
			"codex":
				# Un livre ouvert : deux pages et le dos.
				draw_polyline(PackedVector2Array([c + Vector2(0, s * 0.85), c + Vector2(-s, s * 0.6), c + Vector2(-s, -s * 0.75), c + Vector2(0, -s * 0.5), c + Vector2(s, -s * 0.75), c + Vector2(s, s * 0.6), c + Vector2(0, s * 0.85)]), col, w, true)
				draw_line(c + Vector2(0, -s * 0.5), c + Vector2(0, s * 0.85), col, w, true)
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
	var lines: Array[String] = ["STELLAR", "SIGHT"]
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


## Trajet d'une route en miniature : les systèmes traversés reliés d'un trait, les deux bouts marqués,
## le système qui bloque en rouge.
class RouteMap:
	extends Control
	var path := PackedVector2Array()
	var color := Color.WHITE
	var blocked_at := -1

	func _init(w := 120.0, h := 34.0) -> void:
		custom_minimum_size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_STOP

	## `positions` : positions des systèmes sur la carte, dans l'ordre du trajet.
	func set_path(positions: PackedVector2Array, col: Color, blocked := -1) -> void:
		path = positions
		color = col
		blocked_at = blocked
		queue_redraw()

	## Le trajet ramené dans le cadre, proportions gardées.
	func fitted(frame: Vector2) -> PackedVector2Array:
		var out := PackedVector2Array()
		if path.is_empty():
			return out
		var lo := path[0]
		var hi := path[0]
		for p in path:
			lo = lo.min(p)
			hi = hi.max(p)
		var span := (hi - lo).max(Vector2(1, 1))
		var inner := frame - Vector2(12, 12)
		var k := minf(inner.x / span.x, inner.y / span.y)
		var off := Vector2(6, 6) + (inner - span * k) * 0.5
		for p in path:
			out.append(off + (p - lo) * k)
		return out

	func _draw() -> void:
		var pts := fitted(size)
		if pts.is_empty():
			return
		if pts.size() > 1:
			draw_polyline(pts, Color(color, 0.75), 1.5, true)
		for i in pts.size():
			var end := i == 0 or i == pts.size() - 1
			draw_circle(pts[i], 3.0 if end else 1.5, color if end else Color(color, 0.6))
		if blocked_at >= 0 and blocked_at < pts.size():
			draw_circle(pts[blocked_at], 4.5, UiTheme.BAD)
