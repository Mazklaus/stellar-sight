class_name PauseMenu
extends CanvasLayer
## Menu du jeu (Échap) : reprendre, sauvegarder, charger, raccourcis, options, menu principal, quitter.
## main.gd met la partie en pause pendant qu'il est ouvert.

signal resume_requested
signal save_requested
signal load_requested
signal main_menu_requested
signal quit_requested

## Liste complète des raccourcis, affichée dans la page « Raccourcis ».
const SHORTCUTS := [
	["Espace", "Pause / reprise"],
	["1 à 5", "Vitesse du temps"],
	["Clic", "Sélectionner un système ou une planète"],
	["Double-clic / Entrée", "Ouvrir la vue système"],
	["Échap", "Revenir en arrière, puis ce menu"],
	["Tab / Maj+Tab", "Système suivant / précédent de l'empire (carte)"],
	["Tab", "Vue orbitale / gestion du système (vue système)"],
	["Page préc. / suiv.", "Système précédent / suivant (vue système)"],
	["H", "Revenir à la capitale"],
	["Flèches gauche / droite", "Planète précédente / suivante (vue système)"],
	["F1", "Économie"],
	["F2", "Colonies"],
	["L", "Lentille économique de la carte"],
	["ZQSD / flèches", "Déplacer la carte"],
	["Clic droit glissé", "Déplacer la carte"],
	["Molette", "Zoomer vers le curseur"],
	["F5 / F9", "Sauvegarde / chargement rapide"],
	["F11", "Plein écran"],
]

var page := "home"
var _window: PanelContainer
var _home: VBoxContainer
var _shortcuts: VBoxContainer
var _options: OptionsPanel
var _date: Label
var _quit_button: Button
var _quit_armed := false


func _ready() -> void:
	layer = 9
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.7)
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
	_home.custom_minimum_size = Vector2(380, 0)
	_home.add_theme_constant_override("separation", 8)
	stack.add_child(_home)
	_home.add_child(UiTheme.title("Pause", 38))
	_date = UiTheme.dim("", 14)
	_home.add_child(_date)
	_home.add_child(HSeparator.new())
	_item("Reprendre  (Échap)", func() -> void: resume_requested.emit())
	_item("Sauvegarder  (F5)", func() -> void: save_requested.emit())
	_item("Charger  (F9)", func() -> void: load_requested.emit())
	_item("Raccourcis", func() -> void: show_page("shortcuts"))
	_item("Options", func() -> void: show_page("options"))
	_item("Menu principal", func() -> void: main_menu_requested.emit())
	_quit_button = _item("Quitter le jeu", _on_quit)

	_shortcuts = VBoxContainer.new()
	_shortcuts.add_theme_constant_override("separation", 10)
	stack.add_child(_shortcuts)
	_shortcuts.add_child(UiTheme.title("Raccourcis", 34))
	_shortcuts.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	_shortcuts.add_child(grid)
	for s in SHORTCUTS:
		var cap := UiTheme.key_cap(s[0])
		cap.size_flags_horizontal = Control.SIZE_SHRINK_END
		grid.add_child(cap)
		var l := Label.new()
		l.text = s[1]
		grid.add_child(l)
	var back := Button.new()
	back.text = "Retour  (Échap)"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func() -> void: show_page("home"))
	_shortcuts.add_child(back)

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


func show_page(name: String) -> void:
	page = name
	_quit_armed = false
	_quit_button.text = "Quitter le jeu"
	_quit_button.remove_theme_color_override("font_color")
	_home.visible = name == "home"
	_shortcuts.visible = name == "shortcuts"
	_options.visible = name == "options"
	if name == "options":
		_options.sync()
	_window.reset_size()


## Échap : revient à la page d'accueil du menu. Renvoie false si l'on y était déjà.
func back() -> bool:
	if page != "home":
		show_page("home")
		return true
	return false


func _on_quit() -> void:
	# Deux clics pour quitter : le premier demande confirmation.
	if not _quit_armed:
		_quit_armed = true
		_quit_button.text = "Vraiment ? Cliquer pour quitter"
		_quit_button.add_theme_color_override("font_color", UiTheme.BAD)
		return
	quit_requested.emit()


func _item(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"MenuItem"
	b.add_theme_font_size_override("font_size", 21)
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(380, 46)
	b.pressed.connect(action)
	_home.add_child(b)
	return b
