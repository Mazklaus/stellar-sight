class_name PauseMenu
extends CanvasLayer
## Menu du jeu (Échap) : reprendre, sauvegarder, charger, raccourcis, options, menu principal, quitter.
## main.gd met la partie en pause pendant qu'il est ouvert. Quitter demande confirmation sur une page
## à deux boutons ronds (Annuler / Quitter), comme les choix importants des 4X.

signal resume_requested
signal save_requested
signal load_requested
signal main_menu_requested
signal quit_requested

## Raccourcis par thème, affichés dans la page « Raccourcis ».
const SHORTCUT_GROUPS := [
	["Temps", [
		["Espace", "Pause / reprise (tour par tour : fin de tour)"],
		["1 à 5", "Vitesse du temps"],
	]],
	["Carte", [
		["Clic", "Sélectionner un système"],
		["Double-clic / Entrée", "Ouvrir la vue système"],
		["Tab / Maj+Tab", "Système suivant / précédent de l'empire"],
		["H", "Revenir à la capitale"],
		["L", "Lentille économique"],
		["ZQSD / flèches", "Déplacer la carte"],
		["Clic droit glissé", "Déplacer la carte"],
		["Molette", "Zoomer vers le curseur"],
	]],
	["Flottes", [
		["Clic sur un chevron", "Sélectionner une flotte"],
		["F / Maj+F", "Flotte suivante / précédente"],
		["Clic droit", "Envoyer la flotte vers le système visé"],
		["Échap", "Désélectionner la flotte"],
	]],
	["Vue système", [
		["Clic", "Choisir une planète"],
		["Flèches gauche / droite", "Planète précédente / suivante"],
		["Tab", "Vue orbitale / gestion du système"],
		["Page préc. / suiv.", "Système précédent / suivant"],
	]],
	["Menus", [
		["F1 à F4", "Économie, Colonies, Recherche, Diplomatie"],
		["Échap", "Revenir en arrière, puis ce menu"],
		["F5 / F9", "Sauvegarde / chargement rapide"],
		["F11", "Plein écran"],
	]],
]

var page := "home"
var _window: PanelContainer
var _home: VBoxContainer
var _shortcuts: VBoxContainer
var _confirm: VBoxContainer
var _options: OptionsPanel
var _date: Label


func _ready() -> void:
	layer = 9
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_window = PanelContainer.new()
	_window.theme_type_variation = &"WindowPanel"
	center.add_child(_window)
	var stack := VBoxContainer.new()
	_window.add_child(stack)

	_home = VBoxContainer.new()
	_home.custom_minimum_size = Vector2(400, 0)
	_home.add_theme_constant_override("separation", 6)
	stack.add_child(_home)
	_home.add_child(_page_title("Menu du jeu"))
	_date = UiTheme.dim("", 14)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_home.add_child(_date)
	_home.add_child(Widgets.NotchHeader.new("", 4))
	_item("Reprendre", "Échap", func() -> void: resume_requested.emit())
	_item("Sauvegarder", "F5", func() -> void: save_requested.emit())
	_item("Charger", "F9", func() -> void: load_requested.emit())
	_item("Raccourcis", "", func() -> void: show_page("shortcuts"))
	_item("Options", "", func() -> void: show_page("options"))
	_item("Menu principal", "", func() -> void: main_menu_requested.emit())
	_item("Quitter le jeu", "", func() -> void: show_page("confirm_quit"))

	_shortcuts = VBoxContainer.new()
	_shortcuts.add_theme_constant_override("separation", 10)
	stack.add_child(_shortcuts)
	_shortcuts.add_child(_page_title("Raccourcis"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	_shortcuts.add_child(cols)
	var halves: Array[VBoxContainer] = []
	for i in 2:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.custom_minimum_size = Vector2(400, 0)
		cols.add_child(v)
		halves.append(v)
	for gi in SHORTCUT_GROUPS.size():
		var g: Array = SHORTCUT_GROUPS[gi]
		var col := halves[0] if gi % 2 == 0 else halves[1]
		if col.get_child_count() > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 10)
			col.add_child(gap)
		col.add_child(Widgets.NotchHeader.new(String(g[0]), 16))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 6)
		col.add_child(grid)
		for s in g[1]:
			var cap := UiTheme.key_cap(s[0])
			cap.size_flags_horizontal = Control.SIZE_SHRINK_END
			grid.add_child(cap)
			var l := Label.new()
			l.text = s[1]
			grid.add_child(l)
	var back := Widgets.RoundButton.new("back", "Retour", 16)
	back.tooltip_text = "Échap"
	back.pressed.connect(func() -> void: show_page("home"))
	_shortcuts.add_child(back)

	_confirm = VBoxContainer.new()
	_confirm.custom_minimum_size = Vector2(440, 0)
	_confirm.add_theme_constant_override("separation", 14)
	stack.add_child(_confirm)
	_confirm.add_child(_page_title("Quitter le jeu ?"))
	var why := UiTheme.paragraph("La partie n'est pas sauvegardée automatiquement. La galaxie continuera sans vous, ou plutôt ne continuera pas du tout.", 440, 15)
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	why.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_confirm.add_child(why)
	var buttons := HBoxContainer.new()
	_confirm.add_child(buttons)
	var cancel := Widgets.RoundButton.new("close", "Annuler", 16)
	cancel.pressed.connect(func() -> void: show_page("home"))
	buttons.add_child(cancel)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var quit := Widgets.RoundButton.new("check", "Quitter", 16)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	buttons.add_child(quit)

	_options = OptionsPanel.new()
	_options.custom_minimum_size = Vector2(440, 0)
	_options.back_requested.connect(func() -> void: show_page("home"))
	stack.add_child(_options)
	show_page("home")


func open(date_text: String) -> void:
	_date.text = "Le temps est suspendu au %s. Les flottes retiennent leur souffle." % date_text
	visible = true
	show_page("home")


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Pages : "home", "shortcuts", "options", "confirm_quit".
func show_page(name: String) -> void:
	page = name
	_home.visible = name == "home"
	_shortcuts.visible = name == "shortcuts"
	_options.visible = name == "options"
	_confirm.visible = name == "confirm_quit"
	if name == "options":
		_options.sync()
	_window.reset_size()


## Échap : revient à la page d'accueil du menu. Renvoie false si l'on y était déjà.
func back() -> bool:
	if page != "home":
		show_page("home")
		return true
	return false


func _page_title(text: String) -> Label:
	var t := UiTheme.title(text.to_upper(), 28)
	t.add_theme_font_override("font", UiTheme.font(300, 3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return t


## Entrée du menu : libellé à gauche, raccourci discret à droite.
func _item(text: String, key: String, action: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"MenuItem"
	b.add_theme_font_size_override("font_size", 21)
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(400, 46)
	b.pressed.connect(action)
	if key != "":
		var k := UiTheme.dim(key, 13)
		k.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		k.offset_left = -60
		k.offset_right = -14
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(k)
	_home.add_child(b)
	return b
