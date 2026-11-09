class_name OptionsPanel
extends VBoxContainer
## Page Options, partagée par le menu principal et le menu du jeu, sur le modèle des 4X « épurés » :
## un titre fin centré, une rangée d'onglets, puis une ligne par réglage (libellé à gauche,
## valeur dans une case sombre à droite), et des boutons ronds en bas.
## Les réglages s'appliquent tout de suite et sont propres au poste (UiSettings, user://settings.cfg).

signal back_requested

const ROW_WIDTH := 760.0
const VALUE_WIDTH := 300.0
const TABS := [["display", "Affichage"], ["game", "Partie"], ["controls", "Commandes"]]

var tab := "display"
## Rangée des boutons du bas (Retour, Valeurs par défaut), que le menu principal place dans les coins.
var footer: HBoxContainer
var _tabs := {}
var _pages := {}
var _fullscreen: Button
var _auto_pause: Button
var _scale: Button


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	custom_minimum_size = Vector2(ROW_WIDTH, 0)
	var title := UiTheme.title("Options", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 40)
	add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(t[1]).to_upper()
		var id: String = t[0]
		b.pressed.connect(func() -> void: show_tab(id))
		tabs.add_child(b)
		_tabs[id] = b
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.14)
	rule.custom_minimum_size = Vector2(0, 1)
	add_child(rule)

	var display := _page("display")
	_fullscreen = _toggle_row(display, "Plein écran", "Touche F11, à tout moment.", func() -> void:
		UiSettings.toggle_fullscreen()
		sync())
	var srow := _row(display, "Échelle de l'interface", "Agrandit textes et panneaux, pour les grands écrans.")
	_scale = _value_box("", false) as Button
	_scale.tooltip_text = "Clic : 100 %, 125 %, 150 %"
	_scale.pressed.connect(func() -> void:
		UiSettings.cycle_ui_scale()
		sync())
	srow.add_child(_scale)
	var game := _page("game")
	_auto_pause = _toggle_row(game, "Pause automatique dans les écrans d'empire",
			"Le temps s'arrête quand vous consultez l'économie ou vos colonies, et repart à la fermeture.", func() -> void:
		UiSettings.auto_pause_menus = not UiSettings.auto_pause_menus
		UiSettings.save_settings()
		sync())
	var controls := _page("controls")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(ROW_WIDTH, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	controls.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for g in PauseMenu.SHORTCUT_GROUPS:
		list.add_child(UiTheme.section(String(g[0])))
		for sc in g[1]:
			var row := _row(list, String(sc[1]), "")
			row.add_child(_value_box(String(sc[0]), true))

	var foot := HBoxContainer.new()
	footer = foot
	add_child(foot)
	var back := Widgets.RoundButton.new("back", "Retour", 18)
	back.tooltip_text = "Échap"
	back.pressed.connect(func() -> void: back_requested.emit())
	foot.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var reset := Widgets.RoundButton.new("back", "Valeurs par défaut", 18)
	reset.glyph = "reset"
	reset.tooltip_text = "Fenêtré, interface à 100 %, sans pause automatique."
	reset.pressed.connect(reset_defaults)
	foot.add_child(reset)
	show_tab("display")
	sync()


func show_tab(id: String) -> void:
	tab = id
	for t in _tabs:
		(_tabs[t] as Button).set_pressed_no_signal(t == id)
		(_pages[t] as Control).visible = t == id


## Remet les réglages par défaut (fenêtré, pas de pause automatique).
func reset_defaults() -> void:
	if UiSettings.fullscreen:
		UiSettings.toggle_fullscreen()
	UiSettings.ui_scale = 1.0
	UiSettings.apply()
	UiSettings.auto_pause_menus = false
	UiSettings.save_settings()
	sync()


## Recopie les réglages actuels dans les cases.
func sync() -> void:
	if _fullscreen == null:
		return
	_set_toggle(_fullscreen, UiSettings.fullscreen)
	_set_toggle(_auto_pause, UiSettings.auto_pause_menus)
	_scale.text = "%d %%" % roundi(UiSettings.ui_scale * 100.0)


func _page(id: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 6)
	p.custom_minimum_size = Vector2(ROW_WIDTH, 360)
	add_child(p)
	_pages[id] = p
	return p


func _row(parent: Control, label: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.tooltip_text = tip
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 16)
	row.add_child(l)
	return row


func _value_box(text: String, read_only: bool) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.custom_minimum_size = Vector2(VALUE_WIDTH, 36)
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(0.0, 0.0, 0.0, 0.55), Color(0, 0, 0, 0), 6, 0))
	b.add_theme_stylebox_override("hover", UiTheme.box(Color(0.1, 0.13, 0.16, 0.9), Color(0, 0, 0, 0), 6, 0))
	b.add_theme_stylebox_override("disabled", UiTheme.box(Color(0.0, 0.0, 0.0, 0.4), Color(0, 0, 0, 0), 6, 0))
	b.add_theme_color_override("font_disabled_color", Color(UiTheme.TEXT, 0.8))
	b.disabled = read_only
	return b


func _toggle_row(parent: Control, label: String, tip: String, action: Callable) -> Button:
	var row := _row(parent, label, tip)
	var b := _value_box("", false) as Button
	b.tooltip_text = tip
	b.pressed.connect(action)
	row.add_child(b)
	return b


func _set_toggle(b: Button, on: bool) -> void:
	b.text = "Activé" if on else "Désactivé"
	b.add_theme_color_override("font_color", UiTheme.ACCENT if on else UiTheme.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", UiTheme.ACCENT.lightened(0.3) if on else UiTheme.TEXT)
