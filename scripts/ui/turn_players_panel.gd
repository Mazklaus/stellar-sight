class_name TurnPlayersPanel
extends PanelContainer
## Partie en réseau au tour par tour : la liste des joueurs, à côté du cadran, avec qui a déjà
## terminé son tour (✓) et qui joue encore. Lue dans GameClock.net_players (rempli par NetSession).

var _clock: Node
var _rows: VBoxContainer
var _shown := ""


func _ready() -> void:
	_clock = get_node_or_null("/root/GameClock")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, Color(0, 0, 0, 0), 8, 0))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows)
	visible = false


## Faut-il montrer la liste ? (réseau, tour par tour, au moins deux joueurs, tour pas en cours)
func wanted() -> bool:
	if _clock == null or _clock.driver == null or _clock.net_players.size() < 2:
		return false
	return _clock.is_turn_based() and _clock.paused


func _process(_delta: float) -> void:
	var want := wanted()
	var key := str(_clock.net_players) if want else ""
	if key == _shown:
		return
	_shown = key
	visible = want
	for c in _rows.get_children():
		c.queue_free()
	if not want:
		return
	var done := 0
	for p: Dictionary in _clock.net_players:
		if p["ready"]:
			done += 1
	var head := UiTheme.dim("FIN DE TOUR · %d/%d" % [done, _clock.net_players.size()], 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(head)
	for p: Dictionary in _clock.net_players:
		_rows.add_child(_row(p))


func _row(p: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = p["color"]
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	var name := Label.new()
	name.text = String(p["name"]) + (" (vous)" if p["me"] else "")
	name.add_theme_font_size_override("font_size", 14)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var state := Label.new()
	state.text = "✓ terminé" if p["ready"] else "joue…"
	state.add_theme_font_size_override("font_size", 13)
	state.add_theme_color_override("font_color", UiTheme.GOOD if p["ready"] else UiTheme.TEXT_DIM)
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(state)
	return row
