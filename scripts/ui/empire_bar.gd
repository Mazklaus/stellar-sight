class_name EmpireBar
extends PanelContainer
## Barre d'empire, en haut de l'écran : emblème et nom de l'empire, les cinq ressources (stock et
## bilan mensuel, détail en infobulle), l'accès aux menus d'empire, la date, la pause et la vitesse,
## et le menu du jeu. Elle lit l'état et l'horloge, et n'émet que des demandes.

signal screen_requested(screen_id: String)
signal menu_requested
signal pause_toggled
signal speed_requested(index: int)

const HEIGHT := 50.0
## Menus d'empire : identifiant, libellé, raccourci, disponible ou non (et pourquoi).
const SCREENS := [
	{"id": "economy", "label": "Économie", "key": "F1", "ready": true},
	{"id": "colonies", "label": "Colonies", "key": "F2", "ready": true},
	{"id": "research", "label": "Recherche", "key": "F3", "ready": false,
		"why": "Les savants de l'empire réclament encore des crédits. La recherche arrive bientôt."},
	{"id": "diplomacy", "label": "Diplomatie", "key": "F4", "ready": false,
		"why": "Personne n'a encore répondu à nos messages. La diplomatie arrive avec les autres empires joueurs."},
]

var _state: GameState
var _player := 0
var _emblem: Widgets.Emblem
var _name: Label
var _chips := {}
var _screen_buttons := {}
var _date: Label
var _pause: Widgets.IconButton
var _speeds: Array[Button] = []
## Horloge (autoload GameClock), récupérée à l'exécution : la barre peut ainsi être compilée
## par les tests avant que les autoloads n'existent.
var _clock: Node


func _ready() -> void:
	_clock = get_node("/root/GameClock")
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.022, 0.042, 0.96)
	style.border_color = UiTheme.LINE_STRONG
	style.border_width_bottom = 1
	style.content_margin_left = 14
	style.content_margin_right = 10
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	_emblem = Widgets.Emblem.new(28)
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_emblem)
	_name = UiTheme.title("", 21)
	_name.custom_minimum_size = Vector2(170, 0)
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_name)
	row.add_child(_divider())

	for r in GameData.resource_ids():
		var chip := Widgets.RichTipPanel.new()
		chip.theme_type_variation = &"Chip"
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 5)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(box)
		var icon := ResourceIcon.make(r, 18)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		var stock := Label.new()
		stock.theme_type_variation = &"Numbers"
		stock.add_theme_font_size_override("font_size", 20)
		box.add_child(stock)
		var delta := Label.new()
		delta.theme_type_variation = &"Numbers"
		delta.add_theme_font_size_override("font_size", 15)
		delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(delta)
		row.add_child(chip)
		_chips[r] = {"panel": chip, "stock": stock, "delta": delta}

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	for sc in SCREENS:
		var b := Button.new()
		b.theme_type_variation = &"BarButton"
		b.text = sc["label"]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not sc["ready"]
		b.tooltip_text = "%s  (%s)" % [sc["label"], sc["key"]] if sc["ready"] else "%s  (%s)\n%s" % [sc["label"], sc["key"], sc["why"]]
		var id: String = sc["id"]
		b.pressed.connect(func() -> void: screen_requested.emit(id))
		row.add_child(b)
		_screen_buttons[id] = b
	row.add_child(_divider())

	_date = Label.new()
	_date.theme_type_variation = &"Numbers"
	_date.add_theme_font_size_override("font_size", 20)
	_date.custom_minimum_size = Vector2(96, 0)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_date.mouse_filter = Control.MOUSE_FILTER_STOP
	_date.tooltip_text = "Date galactique (un jour par tick)"
	row.add_child(_date)
	_pause = Widgets.IconButton.new("play", 34)
	_pause.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pause.pressed.connect(func() -> void: pause_toggled.emit())
	row.add_child(_pause)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 1)
	row.add_child(speeds)
	for i in _clock.SECONDS_PER_DAY.size():
		var sb := Button.new()
		sb.theme_type_variation = &"BarButton"
		sb.text = str(i + 1)
		sb.toggle_mode = true
		sb.focus_mode = Control.FOCUS_NONE
		sb.custom_minimum_size = Vector2(26, 30)
		sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sb.add_theme_stylebox_override("normal", UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 2, 3))
		sb.tooltip_text = "Vitesse %d  (touche %d)" % [i + 1, i + 1]
		sb.pressed.connect(func() -> void: speed_requested.emit(i))
		speeds.add_child(sb)
		_speeds.append(sb)
	row.add_child(_divider())
	var menu := Widgets.IconButton.new("menu", 38)
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.tooltip_text = "Menu du jeu  (Échap)"
	menu.pressed.connect(func() -> void: menu_requested.emit())
	row.add_child(menu)

	_clock.day_passed.connect(func(_d: int) -> void: refresh_clock())
	_clock.speed_changed.connect(func(_s: int) -> void: refresh_clock())
	_clock.pause_changed.connect(func(_p: bool) -> void: refresh_clock())
	refresh_clock()


func set_state(state: GameState, player: int) -> void:
	_state = state
	_player = player
	refresh()


## Ressources et emblème (à chaque tick et après chaque ordre).
func refresh() -> void:
	refresh_clock()
	var me := _state.get_empire(_player) if _state else null
	_emblem.visible = me != null
	if me == null:
		_name.text = "Observateur"
		return
	_emblem.color = me.color()
	_emblem.queue_redraw()
	_name.text = me.short_name()
	_name.add_theme_color_override("font_color", me.color().lightened(0.3))
	_name.tooltip_text = "%s\n%s" % [me.display_name(), String(me.faction().get("trait", ""))]
	_name.mouse_filter = Control.MOUSE_FILTER_STOP
	for r: Dictionary in EmpireReport.resources(_state, _player):
		var chip: Dictionary = _chips[r["id"]]
		var net := int(r["net"])
		(chip["stock"] as Label).text = str(r["stock"])
		var low: bool = (r["id"] == "food" and me.starving) or (r["id"] == "energy" and me.blackout)
		(chip["stock"] as Label).add_theme_color_override("font_color", UiTheme.BAD if low else UiTheme.TEXT)
		(chip["delta"] as Label).text = "%+d" % net
		(chip["delta"] as Label).add_theme_color_override("font_color", UiTheme.delta_color(net))
		(chip["panel"] as Control).tooltip_text = _resource_tip(r, me)


func refresh_clock() -> void:
	if _date == null:
		return
	_date.text = _clock.date_string()
	_date.add_theme_color_override("font_color", UiTheme.WARN if _clock.paused else UiTheme.TEXT)
	_pause.set_glyph("play" if _clock.paused else "pause")
	_pause.tooltip_text = ("Reprendre" if _clock.paused else "Pause") + "  (Espace)"
	_pause.glyph_color = UiTheme.WARN if _clock.paused else UiTheme.TEXT
	for i in _speeds.size():
		_speeds[i].set_pressed_no_signal(i == _clock.speed_index)


## Le menu d'empire ouvert est mis en évidence ("" = aucun).
func set_open_screen(screen_id: String) -> void:
	for id in _screen_buttons:
		(_screen_buttons[id] as Button).set_pressed_no_signal(id == screen_id)


## Texte lisible des ressources ("Énergie 100 (+16)  Matériaux 200 (+17)…"), pour les tests.
func resource_text() -> String:
	var parts := PackedStringArray()
	for r in GameData.resource_ids():
		var chip: Dictionary = _chips[r]
		parts.append("%s %s (%s)" % [GameData.resource_label(r), (chip["stock"] as Label).text, (chip["delta"] as Label).text])
	return "  ".join(parts)


func screen_button(screen_id: String) -> Button:
	return _screen_buttons.get(screen_id)


func _resource_tip(r: Dictionary, me: Empire) -> String:
	var lines := PackedStringArray()
	lines.append("[b][color=#%s]%s[/color][/b]" % [ResourceIcon.color_of(r["id"]).to_html(false), r["label"]])
	lines.append("Stock : [b]%d[/b]" % r["stock"])
	var bonus := ""
	if int(r["bonus_pct"]) != 0:
		bonus = "  [color=#%s](%+d %% %s)[/color]" % [UiTheme.ACCENT.to_html(false), r["bonus_pct"], me.short_name()]
	lines.append("Production : [color=#%s]+%d[/color]%s" % [UiTheme.GOOD.to_html(false), r["gross"], bonus])
	lines.append("Entretien : [color=#%s]-%d[/color]" % [UiTheme.BAD.to_html(false), r["upkeep"]])
	var net := int(r["net"])
	lines.append("Bilan : [b][color=#%s]%+d par mois[/color][/b]" % [UiTheme.delta_color(net).to_html(false), net])
	if int(r["months_left"]) >= 0:
		lines.append("[color=#%s]Épuisé dans %d mois à ce rythme.[/color]" % [UiTheme.WARN.to_html(false), r["months_left"]])
	if r["id"] == "food" and me.starving:
		lines.append("[color=#%s]Famine : la population décline.[/color]" % UiTheme.BAD.to_html(false))
	if r["id"] == "energy" and me.blackout:
		lines.append("[color=#%s]Pénurie : les chantiers sont à l'arrêt.[/color]" % UiTheme.BAD.to_html(false))
	return "\n".join(lines)


func _divider() -> Control:
	var d := ColorRect.new()
	d.color = UiTheme.LINE
	d.custom_minimum_size = Vector2(1, 26)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(d)
	return m
