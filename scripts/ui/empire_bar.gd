class_name EmpireBar
extends PanelContainer
## Panneau d'empire, en haut à gauche : une rangée de pictogrammes pour les menus d'empire,
## les cinq ressources (stock et bilan mensuel, détail en infobulle) et une ligne d'état
## (fondations, chantiers, alertes). Il lit l'état et n'émet que des demandes.
## La date, la pause et la vitesse sont sur le cadran du temps (TimeDial), en bas à droite.

signal screen_requested(screen_id: String)

const WIDTH := 330.0
## Hauteur réservée au panneau : la colonne de la vue système commence en dessous.
const HEIGHT := 132.0
const MARGIN := 10.0
## Menus d'empire : identifiant, libellé, raccourci, pictogramme, disponible ou non (et pourquoi).
const SCREENS := [
	{"id": "economy", "label": "Économie", "key": "F1", "glyph": "economy", "ready": true},
	{"id": "colonies", "label": "Colonies", "key": "F2", "glyph": "colonies", "ready": true},
	{"id": "research", "label": "Recherche", "key": "F3", "glyph": "research", "ready": true,
		"why": "Quatre domaines sur cinq ères, tout l'arbre visible. Le Savoir finance la technologie en tête de file ; une ère s'ouvre quand on connaît assez de technologies de la précédente."},
	{"id": "diplomacy", "label": "Diplomatie", "key": "F4", "glyph": "diplomacy", "ready": true,
		"why": "Guerre froide à la rencontre, puis la paix, l'alliance, le commerce ou la guerre. Survolez une opinion pour en voir les raisons, et une proposition pour savoir ce que l'autre en pense."},
]
## Description d'un menu d'empire (entrée de SCREENS), {} s'il n'existe pas.
static func screen_info(screen_id: String) -> Dictionary:
	for sc: Dictionary in SCREENS:
		if sc["id"] == screen_id:
			return sc
	return {}


## Disposition des ressources : deux lignes.
const ROWS := [["energy", "materials", "food"], ["influence", "crystals", "knowledge"]]

var _state: GameState
var _player := 0
var _emblem: Widgets.Emblem
var _name: Label
var _chips := {}
var _screen_buttons := {}
var _status: Label
## Jauge du trait de faction (ferveur, fiefs, ambassades, biomasse), au bout de la 2e ligne.
var _gauge: Widgets.RichTipPanel
var _gauge_label: Label


func _ready() -> void:
	position = Vector2(MARGIN, MARGIN)
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.LINE, 8, 1))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 2)
	box.add_child(icons)
	for sc in SCREENS:
		var b := Widgets.IconButton.new(String(sc["glyph"]), 34)
		b.toggle_mode = true
		b.disabled = not sc["ready"]
		b.tooltip_text = "%s  (%s)" % [sc["label"], sc["key"]] + ("\nBientôt : l'écran est en place." if sc.get("soon", false) else "")
		var id: String = sc["id"]
		b.pressed.connect(func() -> void: screen_requested.emit(id))
		icons.add_child(b)
		_screen_buttons[id] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons.add_child(spacer)
	_name = Label.new()
	_name.theme_type_variation = &"Section"
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name.mouse_filter = Control.MOUSE_FILTER_STOP
	icons.add_child(_name)
	_emblem = Widgets.Emblem.new(20)
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icons.add_child(_emblem)

	box.add_child(_rule())
	for row_ids in ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)
		for r: String in row_ids:
			var chip := Widgets.RichTipPanel.new()
			chip.mouse_filter = Control.MOUSE_FILTER_STOP
			chip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			var cbox := HBoxContainer.new()
			cbox.add_theme_constant_override("separation", 4)
			cbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(cbox)
			var icon := ResourceIcon.make(r, 15)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cbox.add_child(icon)
			var stock := Label.new()
			stock.theme_type_variation = &"Numbers"
			stock.add_theme_font_size_override("font_size", 16)
			cbox.add_child(stock)
			var delta := Label.new()
			delta.theme_type_variation = &"Numbers"
			delta.add_theme_font_size_override("font_size", 13)
			delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cbox.add_child(delta)
			row.add_child(chip)
			_chips[r] = {"panel": chip, "stock": stock, "delta": delta}
		if row_ids == ROWS[ROWS.size() - 1]:
			_gauge = Widgets.RichTipPanel.new()
			_gauge.mouse_filter = Control.MOUSE_FILTER_STOP
			_gauge.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			_gauge_label = Label.new()
			_gauge_label.add_theme_font_size_override("font_size", 14)
			_gauge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_gauge.add_child(_gauge_label)
			row.add_child(_gauge)
	box.add_child(_rule())
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	box.add_child(_status)


func set_state(state: GameState, player: int) -> void:
	_state = state
	_player = player
	refresh()


## Ressources et ligne d'état (à chaque tick et après chaque ordre).
func refresh() -> void:
	var me := _state.get_empire(_player) if _state else null
	_emblem.visible = me != null
	if me == null:
		_name.text = "OBSERVATEUR"
		return
	_emblem.color = me.color()
	_emblem.queue_redraw()
	_name.text = me.short_name().to_upper()
	_name.add_theme_color_override("font_color", me.color().lightened(0.25))
	_name.tooltip_text = "%s\n%s" % [me.display_name(), trait_summary(me.faction())]
	var g := FactionTraits.gauge(_state, _player)
	_gauge.visible = not g.is_empty()
	if not g.is_empty():
		var delta := " (%+d)" % int(g["delta"]) if g.has("delta") else ""
		_gauge_label.text = "%s %s%s" % [String(g["label"]).to_upper(), g["value"], delta]
		_gauge_label.add_theme_color_override("font_color", UiTheme.BAD if g["bad"] else me.color().lightened(0.35))
		_gauge.tooltip_text = String(g["tip"])
	for r: Dictionary in EmpireReport.resources(_state, _player):
		var chip: Dictionary = _chips[r["id"]]
		var net := int(r["net"])
		(chip["stock"] as Label).text = str(r["stock"])
		var low: bool = (r["id"] == "food" and me.starving) or (r["id"] == "energy" and me.blackout)
		(chip["stock"] as Label).add_theme_color_override("font_color", UiTheme.BAD if low else UiTheme.TEXT)
		(chip["delta"] as Label).text = "%+d" % net
		(chip["delta"] as Label).add_theme_color_override("font_color", UiTheme.delta_color(net))
		(chip["panel"] as Control).tooltip_text = _resource_tip(r, me)
	_status.text = _status_line(me)
	_status.add_theme_color_override("font_color", UiTheme.BAD if me.starving or me.blackout else UiTheme.TEXT_DIM)


## Traits d'une faction en lignes « Nom : effet » (infobulles, écrans d'empire).
static func trait_summary(faction: Dictionary) -> String:
	var lines := PackedStringArray()
	for t: Dictionary in faction.get("traits", []):
		lines.append("%s : %s" % [t["name"], t["text"]])
	return "\n".join(lines) if not lines.is_empty() else String(faction.get("trait", ""))


## Texte de la jauge de faction ("" si aucune), pour les tests.
func gauge_text() -> String:
	return _gauge_label.text if _gauge.visible else ""


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


func _status_line(me: Empire) -> String:
	if me.starving:
		return "Famine : la population décline"
	if me.blackout:
		return "Pénurie d'énergie : chantiers à l'arrêt"
	var t := EmpireReport.totals(_state, _player)
	var works := 0
	for c in EmpireReport.colonies(_state, _player):
		if c["construction"] != "":
			works += 1
	return "%d chantier%s  ·  fondations %d/%d  ·  %d pop" % [works, "s" if works > 1 else "", t["founding"], t["max_projects"], t["population"]]


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


func _rule() -> ColorRect:
	var d := ColorRect.new()
	d.color = UiTheme.LINE
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d
