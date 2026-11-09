class_name UiTheme
extends RefCounted
## Thème visuel de toute l'interface : palette, polices, cadres à coins biseautés.
## Un seul endroit à modifier pour changer l'allure du jeu. main.gd l'applique à la fenêtre
## (get_tree().root.theme, pour les infobulles) et aux contrôles de chaque calque (apply_to).
##
## Variantes de types (theme_type_variation) disponibles :
##   "BarButton"    bouton plat de la barre d'empire
##   "PrimaryButton"  action principale (bord doré)
##   "MenuItem"     grand bouton des menus principal et pause
##   "WindowPanel"  cadre d'une fenêtre (menus d'empire, menu pause)
##   "SidePanel"    panneau latéral (fiches)
##   "Chip"         petit cadre (ressource, carte)
##   "KeyCap"       touche de clavier dans les aides
##   "Title" / "Section" / "Dim" / "Numbers"  styles de libellés

const BG := Color(0.02, 0.028, 0.05)
const PANEL := Color(0.028, 0.04, 0.075, 0.97)
const PANEL_SOFT := Color(0.05, 0.07, 0.12, 0.86)
const LINE := Color(0.45, 0.65, 1.0, 0.26)
const LINE_STRONG := Color(0.55, 0.76, 1.0, 0.75)
const ACCENT := Color(0.55, 0.78, 1.0)
const GOLD := Color(1.0, 0.82, 0.38)
const TEXT := Color(0.9, 0.93, 1.0)
const TEXT_DIM := Color(0.6, 0.67, 0.8)
const GOOD := Color(0.45, 0.9, 0.55)
const BAD := Color(1.0, 0.45, 0.4)
const WARN := Color(1.0, 0.74, 0.3)
## Biseau des coins (en pixels) : la signature visuelle de l'interface.
const BEVEL := 7

const FONT_BODY := preload("res://assets/fonts/Exo2-Variable.ttf")
const FONT_TITLE := preload("res://assets/fonts/Rajdhani-Bold.ttf")
const FONT_NUMBERS := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")

static var _theme: Theme
static var _body: FontVariation


static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func body_font() -> Font:
	if _body == null:
		_body = FontVariation.new()
		_body.base_font = FONT_BODY
		_body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 460}
	return _body


## Applique le thème aux contrôles de premier niveau sous node. Les CanvasLayer coupent l'héritage
## du thème de la fenêtre : chaque contrôle posé directement sur un calque doit le recevoir.
static func apply_to(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).theme = theme()
		else:
			apply_to(child)


## Cadre à coins biseautés. border_top permet un liseré plus épais en haut (fenêtres).
static func box(bg: Color, border: Color, margin := 10, bevel := BEVEL, border_top := 1) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(1)
	st.border_width_top = border_top
	st.set_corner_radius_all(bevel)
	st.corner_detail = 1  # un seul segment par coin : biseau droit plutôt qu'arrondi
	st.anti_aliasing = true
	st.set_content_margin_all(margin)
	return st


## Libellé de titre (police de titre, ombre).
static func title(text: String, size := 26, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Title"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Petit titre de section en capitales.
static func section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = &"Section"
	return l


static func dim(text: String, size := 14) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Dim"
	l.add_theme_font_size_override("font_size", size)
	return l


## Texte qui passe à la ligne, de largeur minimale donnée.
static func paragraph(text: String, width: float, size := 15) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", size)
	return l


## Rangée de touches pour les aides : [["Espace", "Pause"], ["1-5", "Vitesse"]…].
static func key_hints(hints: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for h in hints:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 6)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(key_cap(String(h[0])))
		var l := Label.new()
		l.text = String(h[1])
		l.theme_type_variation = &"Dim"
		l.add_theme_font_size_override("font_size", 13)
		pair.add_child(l)
		row.add_child(pair)
	return row


static func key_cap(key: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.theme_type_variation = &"KeyCap"
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = key
	l.add_theme_font_override("font", FONT_NUMBERS)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", TEXT)
	cap.add_child(l)
	return cap


## Couleur d'un bilan : vert s'il est positif, rouge s'il est négatif.
static func delta_color(v: int) -> Color:
	return GOOD if v > 0 else (BAD if v < 0 else TEXT_DIM)


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 15

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)

	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", FONT_TITLE)
	t.set_font_size("font_size", "Title", 26)
	t.set_color("font_shadow_color", "Title", Color(0, 0, 0, 0.85))
	t.set_constant("shadow_offset_y", "Title", 2)
	t.set_type_variation("Section", "Label")
	t.set_font("font", "Section", FONT_NUMBERS)
	t.set_font_size("font_size", "Section", 13)
	t.set_color("font_color", "Section", Color(ACCENT, 0.9))
	t.set_type_variation("Dim", "Label")
	t.set_color("font_color", "Dim", TEXT_DIM)
	t.set_type_variation("Numbers", "Label")
	t.set_font("font", "Numbers", FONT_NUMBERS)
	t.set_font_size("font_size", "Numbers", 18)

	# Boutons ordinaires.
	t.set_stylebox("normal", "Button", box(Color(0.07, 0.1, 0.18, 0.95), Color(ACCENT, 0.32), 8))
	t.set_stylebox("hover", "Button", box(Color(0.11, 0.16, 0.28, 1.0), Color(ACCENT, 0.85), 8))
	t.set_stylebox("pressed", "Button", box(Color(0.17, 0.14, 0.06, 1.0), Color(GOLD, 0.9), 8))
	t.set_stylebox("hover_pressed", "Button", box(Color(0.2, 0.17, 0.07, 1.0), GOLD, 8))
	t.set_stylebox("disabled", "Button", box(Color(0.04, 0.05, 0.08, 0.8), Color(1, 1, 1, 0.07), 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_hover_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.55))
	t.set_constant("h_separation", "Button", 8)

	t.set_type_variation("BarButton", "Button")
	var bar_normal := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6)
	bar_normal.content_margin_left = 12
	bar_normal.content_margin_right = 12
	var bar_hover := box(Color(ACCENT, 0.12), Color(ACCENT, 0.45), 6)
	bar_hover.content_margin_left = 12
	bar_hover.content_margin_right = 12
	var bar_pressed := box(Color(GOLD, 0.14), Color(GOLD, 0.7), 6)
	bar_pressed.content_margin_left = 12
	bar_pressed.content_margin_right = 12
	t.set_stylebox("normal", "BarButton", bar_normal)
	t.set_stylebox("hover", "BarButton", bar_hover)
	t.set_stylebox("pressed", "BarButton", bar_pressed)
	t.set_stylebox("hover_pressed", "BarButton", bar_pressed)
	t.set_stylebox("disabled", "BarButton", bar_normal)
	t.set_font("font", "BarButton", FONT_NUMBERS)
	t.set_font_size("font_size", "BarButton", 17)

	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(Color(0.16, 0.13, 0.05, 0.95), Color(GOLD, 0.6), 10))
	t.set_stylebox("hover", "PrimaryButton", box(Color(0.24, 0.19, 0.07, 1.0), GOLD, 10))
	t.set_stylebox("pressed", "PrimaryButton", box(Color(0.3, 0.24, 0.08, 1.0), GOLD, 10))
	t.set_color("font_color", "PrimaryButton", GOLD)
	t.set_color("font_hover_color", "PrimaryButton", Color(1, 0.93, 0.7))
	t.set_font("font", "PrimaryButton", FONT_NUMBERS)
	t.set_font_size("font_size", "PrimaryButton", 18)

	t.set_type_variation("MenuItem", "Button")
	var menu_normal := box(Color(0.04, 0.06, 0.11, 0.7), Color(ACCENT, 0.18), 12)
	menu_normal.content_margin_left = 22
	var menu_hover := box(Color(0.1, 0.15, 0.27, 0.95), Color(ACCENT, 0.8), 12)
	menu_hover.content_margin_left = 30  # le texte glisse légèrement au survol
	menu_hover.border_width_left = 3
	var menu_disabled := menu_normal.duplicate()
	menu_disabled.bg_color = Color(0.03, 0.04, 0.07, 0.5)
	menu_disabled.border_color = Color(1, 1, 1, 0.05)
	t.set_stylebox("normal", "MenuItem", menu_normal)
	t.set_stylebox("hover", "MenuItem", menu_hover)
	t.set_stylebox("pressed", "MenuItem", menu_hover)
	t.set_stylebox("disabled", "MenuItem", menu_disabled)
	t.set_font("font", "MenuItem", FONT_TITLE)
	t.set_font_size("font_size", "MenuItem", 24)
	t.set_color("font_hover_color", "MenuItem", GOLD)
	t.set_color("font_pressed_color", "MenuItem", GOLD)

	# Cadres.
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 12))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 12))
	t.set_type_variation("WindowPanel", "PanelContainer")
	t.set_stylebox("panel", "WindowPanel", box(Color(0.025, 0.035, 0.065, 0.97), LINE_STRONG, 20, 12, 2))
	t.set_type_variation("SidePanel", "PanelContainer")
	t.set_stylebox("panel", "SidePanel", box(PANEL, LINE, 16, BEVEL, 2))
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", box(PANEL_SOFT, Color(ACCENT, 0.18), 6, 5))
	t.set_type_variation("KeyCap", "PanelContainer")
	var cap := box(Color(0.12, 0.16, 0.26, 0.95), Color(ACCENT, 0.45), 2, 3)
	cap.content_margin_left = 7
	cap.content_margin_right = 7
	cap.border_width_bottom = 2
	t.set_stylebox("panel", "KeyCap", cap)

	# Infobulles : même cadre que le reste, texte un peu plus petit.
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.03, 0.045, 0.085, 0.98), LINE_STRONG, 10, 5))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)

	# Champs de saisie.
	t.set_stylebox("normal", "LineEdit", box(Color(0.02, 0.03, 0.06, 0.95), Color(ACCENT, 0.35), 8, 4))
	t.set_stylebox("focus", "LineEdit", box(Color(0.02, 0.03, 0.06, 0.95), Color(GOLD, 0.8), 8, 4))
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", GOLD)

	# Barres de progression et séparateurs.
	var bar_bg := box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 2)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color(0, 0, 0, 0), 0, 2))
	var sep := StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)

	# Barres de défilement fines.
	var grab := box(Color(ACCENT, 0.35), Color(0, 0, 0, 0), 0, 3)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	var grab_hi := grab.duplicate()
	grab_hi.bg_color = Color(ACCENT, 0.7)
	var track := StyleBoxEmpty.new()
	track.content_margin_left = 3
	track.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)

	# Cases à cocher.
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	return t
