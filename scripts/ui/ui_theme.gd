class_name UiTheme
extends RefCounted
## Thème visuel de toute l'interface. L'esprit vient des 4X spatiaux « épurés » (Endless Space 2 en
## tête) : panneaux plats et translucides à angles droits, filets très fins, une seule famille de
## police en graisses fines, petites majuscules espacées, très peu de couleur (un accent cyan).
## Un seul endroit à modifier pour changer l'allure du jeu. main.gd l'applique à la fenêtre
## (get_tree().root.theme, pour les infobulles) et aux contrôles de chaque calque (apply_to).
##
## Variantes de types (theme_type_variation) disponibles :
##   "BarButton"      bouton plat sans fond (icônes)
##   "TabButton"      onglet en petites majuscules (vues, menus d'empire)
##   "PrimaryButton"  action principale (liseré cyan)
##   "MenuItem"       grand bouton des menus principal et pause
##   "WindowPanel"    cadre d'une fenêtre (menus d'empire, menu pause)
##   "SidePanel"      panneau translucide (fiches, panneau d'empire)
##   "Chip"           petit cadre (ressource, carte)
##   "KeyCap"         touche de clavier dans les aides
##   "Title" / "Section" / "Dim" / "Numbers"  styles de libellés

const BG := Color(0.02, 0.025, 0.04)
const PANEL := Color(0.035, 0.045, 0.065, 0.82)
const PANEL_SOFT := Color(0.06, 0.075, 0.1, 0.6)
const LINE := Color(1, 1, 1, 0.1)
const LINE_STRONG := Color(1, 1, 1, 0.28)
const ACCENT := Color(0.38, 0.86, 0.92)
## Couleur de mise en évidence (sélection, survol, action principale).
const GOLD := ACCENT
const TEXT := Color(0.92, 0.94, 0.97)
const TEXT_DIM := Color(0.62, 0.66, 0.72)
const GOOD := Color(0.5, 0.9, 0.55)
const BAD := Color(1.0, 0.45, 0.42)
const WARN := Color(1.0, 0.76, 0.35)

const FONT_FILE := preload("res://assets/fonts/Exo2-Variable.ttf")

static var _theme: Theme
static var _fonts := {}


static func theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Police Exo 2 à une graisse donnée (100 à 900), avec un espacement de lettres facultatif.
static func font(weight := 400, spacing := 0) -> Font:
	var key := "%d/%d" % [weight, spacing]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = FONT_FILE
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		f.spacing_glyph = spacing
		_fonts[key] = f
	return _fonts[key]


static func body_font() -> Font:
	return font(400)


## Fine (titres), demi-grasse (chiffres), petites majuscules espacées (sections, onglets).
static func title_font() -> Font:
	return font(300)


static func numbers_font() -> Font:
	return font(560)


static func caps_font() -> Font:
	return font(560, 1)


## Applique le thème aux contrôles de premier niveau sous node. Les CanvasLayer coupent l'héritage
## du thème de la fenêtre : chaque contrôle posé directement sur un calque doit le recevoir.
static func apply_to(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).theme = theme()
		else:
			apply_to(child)


## Cadre plat à angles droits. border_all : épaisseur des filets (0 = aucun) ; border_top >= 0 la change en haut.
static func box(bg: Color, border: Color, margin := 10, border_all := 1, border_top := -1) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(border_all)
	if border_top >= 0:
		st.border_width_top = border_top
	st.set_content_margin_all(margin)
	return st


## Libellé de titre (graisse fine).
static func title(text: String, size := 26, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Title"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Petit titre de section en majuscules espacées.
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
	l.add_theme_font_override("font", numbers_font())
	l.add_theme_font_size_override("font_size", 13)
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
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)

	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", title_font())
	t.set_font_size("font_size", "Title", 26)
	t.set_type_variation("Section", "Label")
	t.set_font("font", "Section", caps_font())
	t.set_font_size("font_size", "Section", 12)
	t.set_color("font_color", "Section", TEXT_DIM)
	t.set_type_variation("Dim", "Label")
	t.set_color("font_color", "Dim", TEXT_DIM)
	t.set_type_variation("Numbers", "Label")
	t.set_font("font", "Numbers", numbers_font())
	t.set_font_size("font_size", "Numbers", 16)

	# Boutons : fond à peine marqué, le survol éclaire, l'état enfoncé prend l'accent.
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.08), 8))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.25), 8))
	t.set_stylebox("pressed", "Button", box(Color(ACCENT, 0.2), Color(ACCENT, 0.7), 8))
	t.set_stylebox("hover_pressed", "Button", box(Color(ACCENT, 0.26), ACCENT, 8))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.04), 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.45))
	t.set_constant("h_separation", "Button", 8)

	t.set_type_variation("BarButton", "Button")
	var clear := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0)
	var bar_hover := box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 4, 0)
	var bar_pressed := box(Color(ACCENT, 0.16), ACCENT, 4, 0)
	bar_pressed.border_width_bottom = 2
	t.set_stylebox("normal", "BarButton", clear)
	t.set_stylebox("hover", "BarButton", bar_hover)
	t.set_stylebox("pressed", "BarButton", bar_pressed)
	t.set_stylebox("hover_pressed", "BarButton", bar_pressed)
	t.set_stylebox("disabled", "BarButton", clear)

	t.set_type_variation("TabButton", "Button")
	var tab := box(Color(0.035, 0.045, 0.065, 0.78), Color(0, 0, 0, 0), 10, 0)
	tab.content_margin_left = 22
	tab.content_margin_right = 22
	var tab_hover := tab.duplicate()
	tab_hover.bg_color = Color(0.1, 0.12, 0.16, 0.9)
	var tab_on := tab.duplicate()
	tab_on.bg_color = Color(0.06, 0.08, 0.11, 0.92)
	tab_on.border_color = ACCENT
	tab_on.border_width_bottom = 2
	var tab_off := tab.duplicate()
	tab_off.bg_color = Color(0.03, 0.035, 0.05, 0.6)
	t.set_stylebox("normal", "TabButton", tab)
	t.set_stylebox("hover", "TabButton", tab_hover)
	t.set_stylebox("pressed", "TabButton", tab_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_on)
	t.set_stylebox("disabled", "TabButton", tab_off)
	t.set_font("font", "TabButton", caps_font())
	t.set_font_size("font_size", "TabButton", 14)
	t.set_color("font_color", "TabButton", Color(TEXT, 0.85))
	t.set_color("font_pressed_color", "TabButton", TEXT)
	t.set_color("font_hover_pressed_color", "TabButton", TEXT)
	t.set_color("font_disabled_color", "TabButton", Color(TEXT_DIM, 0.4))

	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(Color(ACCENT, 0.12), Color(ACCENT, 0.6), 10))
	t.set_stylebox("hover", "PrimaryButton", box(Color(ACCENT, 0.24), ACCENT, 10))
	t.set_stylebox("pressed", "PrimaryButton", box(Color(ACCENT, 0.34), ACCENT, 10))
	t.set_color("font_color", "PrimaryButton", TEXT)
	t.set_color("font_hover_color", "PrimaryButton", Color.WHITE)
	t.set_font("font", "PrimaryButton", caps_font())
	t.set_font_size("font_size", "PrimaryButton", 15)

	t.set_type_variation("MenuItem", "Button")
	var menu_normal := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 10, 0)
	menu_normal.content_margin_left = 18
	var menu_hover := box(Color(1, 1, 1, 0.07), ACCENT, 10, 0)
	menu_hover.border_width_left = 2
	menu_hover.content_margin_left = 24  # le texte glisse légèrement au survol
	t.set_stylebox("normal", "MenuItem", menu_normal)
	t.set_stylebox("hover", "MenuItem", menu_hover)
	t.set_stylebox("pressed", "MenuItem", menu_hover)
	t.set_stylebox("disabled", "MenuItem", menu_normal)
	t.set_font("font", "MenuItem", title_font())
	t.set_font_size("font_size", "MenuItem", 26)
	t.set_color("font_hover_color", "MenuItem", Color.WHITE)
	t.set_color("font_pressed_color", "MenuItem", ACCENT)

	# Cadres.
	t.set_stylebox("panel", "PanelContainer", box(PANEL, Color(0, 0, 0, 0), 12, 0))
	t.set_stylebox("panel", "Panel", box(PANEL, Color(0, 0, 0, 0), 12, 0))
	t.set_type_variation("WindowPanel", "PanelContainer")
	t.set_stylebox("panel", "WindowPanel", box(Color(0.03, 0.038, 0.055, 0.94), LINE, 22, 1))
	t.set_type_variation("SidePanel", "PanelContainer")
	t.set_stylebox("panel", "SidePanel", box(PANEL, LINE, 14, 1))
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", box(PANEL_SOFT, Color(0, 0, 0, 0), 6, 0))
	t.set_type_variation("KeyCap", "PanelContainer")
	var cap := box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.22), 2, 1)
	cap.content_margin_left = 7
	cap.content_margin_right = 7
	t.set_stylebox("panel", "KeyCap", cap)

	# Infobulles.
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.03, 0.04, 0.06, 0.96), LINE_STRONG, 10, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)

	# Champs de saisie.
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.18), 8))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.4), ACCENT, 8))
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)

	# Barres de progression et séparateurs.
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color(0, 0, 0, 0), 0, 0))
	var sep := StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)

	# Barres de défilement fines.
	var grab := box(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 0, 0)
	grab.content_margin_left = 2
	grab.content_margin_right = 2
	var grab_hi := grab.duplicate()
	grab_hi.bg_color = Color(ACCENT, 0.7)
	var track := StyleBoxEmpty.new()
	track.content_margin_left = 2
	track.content_margin_right = 2
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)

	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	return t
