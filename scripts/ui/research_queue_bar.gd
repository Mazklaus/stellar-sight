class_name ResearchQueueBar
extends PanelContainer
## File de recherche en bandeau horizontal, au-dessus de l'arbre (refonte, C8). Une case par technologie :
## rang, nom, délai, croix pour la retirer. Une case se glisse à la souris sur une autre pour changer
## l'ordre ; les prérequis repassent d'eux-mêmes devant ce qui en dépend. N'émet que des demandes.

signal tech_picked(tech_id: String)
signal move_requested(tech_id: String, to: int)
signal remove_requested(tech_id: String)

const CHIP_WIDTH := 190.0

var _row: HBoxContainer
var _hint: Label
## Cases affichées, dans l'ordre de la file (pour les tests).
var chips: Array[Chip] = []


class Chip:
	extends Button
	var tech_id := ""
	var index := 0
	var bar: ResearchQueueBar

	func _get_drag_data(_at: Vector2) -> Variant:
		var ghost := Label.new()
		ghost.text = text
		set_drag_preview(ghost)
		return {"research_chip": tech_id}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("research_chip") and String(data["research_chip"]) != tech_id

	func _drop_data(_at: Vector2, data: Variant) -> void:
		bar.move_requested.emit(String(data["research_chip"]), index)


func _ready() -> void:
	_ensure()


func _ensure() -> void:
	if _row != null:
		return
	add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 0.6), UiTheme.LINE, 6, 1))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	add_child(line)
	var title := UiTheme.section("File")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 46)
	line.add_child(scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	scroll.add_child(_row)
	_hint = UiTheme.dim("", 13)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_hint)


## Délais cumulés de la file, en mois (-1 si le Savoir manque), dans l'ordre.
static func months(state: GameState, player: int) -> Array[int]:
	var out: Array[int] = []
	var e := state.get_empire(player)
	var income := int(Economy.empire_income(state, player)["net"].get("knowledge", 0))
	var left := 0
	for i in e.research_queue.size():
		var tid := e.research_queue[i]
		left += Research.cost(state, player, tid) - (e.research_progress if i == 0 else int(e.research_shelf.get(tid, 0)))
		@warning_ignore("integer_division")
		out.append((left + income - 1) / income if income > 0 else -1)
	return out


func fill(state: GameState, player: int) -> void:
	_ensure()
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	chips.clear()
	var e := state.get_empire(player)
	var delays := months(state, player)
	if e.research_queue.is_empty():
		_hint.text = "File vide : double-clic sur une technologie pour la lancer, clic droit pour planifier le chemin jusqu'à elle."
		return
	_hint.text = "%d / %d · glisser pour réordonner" % [e.research_queue.size(), Research.MAX_QUEUE]
	for i in e.research_queue.size():
		var tid := e.research_queue[i]
		var t := Research.tech(tid)
		var col := Color.html(String(Research.domain(String(t["domain"])).get("color", "#ffffff")))
		var chip := Chip.new()
		chip.tech_id = tid
		chip.index = i
		chip.bar = self
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(CHIP_WIDTH, 40)
		chip.clip_text = true
		chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
		chip.add_theme_font_size_override("font_size", 13)
		chip.text = "%d  %s" % [i + 1, String(t.get("label", tid))]
		var st := UiTheme.box(Color(col.darkened(0.7), 0.9 if i == 0 else 0.55), Color(col, 0.95 if i == 0 else 0.5), 0, 1)
		st.border_width_left = 3
		st.content_margin_left = 10
		st.content_margin_right = 26
		chip.add_theme_stylebox_override("normal", st)
		var hv := st.duplicate() as StyleBoxFlat
		hv.bg_color = Color(col.darkened(0.45), 0.9)
		chip.add_theme_stylebox_override("hover", hv)
		chip.add_theme_stylebox_override("pressed", hv)
		var d := int(delays[i])
		chip.tooltip_text = "%s\n%s\nGlisser sur une autre case pour changer l'ordre." % [t.get("label", tid),
				("achevée dans %d mois environ" % d) if d >= 0 else "le Savoir manque"]
		chip.pressed.connect(func() -> void: tech_picked.emit(tid))
		var when := UiTheme.dim(("%d m" % d) if d >= 0 else "?", 11)
		when.mouse_filter = Control.MOUSE_FILTER_IGNORE
		when.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		when.offset_left = 26
		when.offset_top = -15
		chip.add_child(when)
		var rm := Button.new()
		rm.flat = true
		rm.text = "×"
		rm.focus_mode = Control.FOCUS_NONE
		rm.tooltip_text = "Retirer de la file (et ce qui en dépend)"
		rm.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		rm.offset_left = -24
		rm.offset_right = -2
		rm.offset_top = -12
		rm.offset_bottom = 12
		rm.pressed.connect(func() -> void: remove_requested.emit(tid))
		chip.add_child(rm)
		_row.add_child(chip)
		chips.append(chip)
