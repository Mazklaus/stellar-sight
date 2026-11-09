class_name OptionsPanel
extends VBoxContainer
## Contenu de la page Options, partagé par le menu principal et le menu pause.

signal back_requested

var _fullscreen: CheckBox
var _auto_pause: CheckBox


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var title := UiTheme.title("OPTIONS", 30)
	title.add_theme_font_override("font", UiTheme.font(300, 3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	add_child(Widgets.NotchHeader.new("Affichage", 18))
	_fullscreen = CheckBox.new()
	_fullscreen.text = "Plein écran  (F11)"
	_fullscreen.focus_mode = Control.FOCUS_NONE
	_fullscreen.toggled.connect(func(on: bool) -> void:
		if on != UiSettings.fullscreen:
			UiSettings.toggle_fullscreen())
	add_child(_fullscreen)
	add_child(Widgets.NotchHeader.new("Partie", 18))
	_auto_pause = CheckBox.new()
	_auto_pause.text = "Pause automatique dans les menus d'empire"
	_auto_pause.tooltip_text = "Le temps s'arrête quand vous consultez l'économie ou vos colonies, et repart à la fermeture."
	_auto_pause.focus_mode = Control.FOCUS_NONE
	_auto_pause.toggled.connect(func(on: bool) -> void:
		UiSettings.auto_pause_menus = on
		UiSettings.save_settings())
	add_child(_auto_pause)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	add_child(gap)
	var back := Widgets.RoundButton.new("back", "Retour", 16)
	back.tooltip_text = "Échap"
	back.pressed.connect(func() -> void: back_requested.emit())
	add_child(back)
	sync()


## Recopie les réglages actuels dans les cases.
func sync() -> void:
	if _fullscreen == null:
		return
	_fullscreen.set_pressed_no_signal(UiSettings.fullscreen)
	_auto_pause.set_pressed_no_signal(UiSettings.auto_pause_menus)
