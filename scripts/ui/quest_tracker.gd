class_name QuestTracker
extends PanelContainer
## Suivi des quêtes en haut à droite, sous la chronique (proposition 17) : les quêtes en cours de
## l'empire (titre, chapitre, avancement de chaque branche) et le retournement galactique. Un clic
## ouvre l'écran Chroniques sur l'onglet Quêtes. Caché quand il n'y a rien à suivre.

signal open_requested

const MAX_QUESTS := 3

var _state: GameState
var _player := 0
var _box: VBoxContainer
var _sig := "-"
var _allowed := true
var _empty := true


func _init() -> void:
	var st := UiTheme.box(Color(0.03, 0.04, 0.06, 0.72), UiTheme.LINE, 8, 0)
	st.border_width_left = 2
	st.border_color = Color(UiTheme.GOLD, 0.6)
	add_theme_stylebox_override("panel", st)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Ouvrir les quêtes (Chroniques, J)"
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 1)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	visible = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open_requested.emit()
		accept_event()


## Caché dans la vue système, sous un écran d'empire et en spectateur.
func set_allowed(on: bool) -> void:
	_allowed = on
	visible = _allowed and not _empty


func set_state(state: GameState, player: int) -> void:
	_state = state
	_player = player
	_sig = "-"
	refresh()


## Lignes à afficher : [[texte, couleur]...] ; vide s'il n'y a rien à suivre.
static func lines(state: GameState, player: int) -> Array:
	var out := []
	if state == null or not Quests.enabled(state):
		return out
	var cur := Quests.current(state)
	if not cur.is_empty():
		var d := Quests.gdef(String(cur["id"]))
		var extra := ""
		match String(cur["id"]):
			"passage":
				extra = "à %s" % state.galaxy.systems[Quests.passage_system(cur)].system_name
			"fleau":
				extra = "remède %d / %d" % [int(cur["pool"]), int(cur["target"])]
			"conclave":
				extra = "choix des camps" if String(cur["phase"]) == "choose" else "%d contre %d" % [int(cur["score"][0]), int(cur["score"][1])]
			"tombeaux":
				var n := 0
				for t: Dictionary in cur["tombs"]:
					n += int(t["alive"])
				extra = "%d tombeau%s éveillé%s" % [n, "x" if n > 1 else "", "s" if n > 1 else ""]
		out.append(["◆ %s : %s" % [String(d["title"]), extra], Color(0.78, 0.62, 0.95)])
	var shown := 0
	for id in Quests.of(state, player, true):
		if shown >= MAX_QUESTS:
			break
		shown += 1
		var q: Dictionary = state.quests[id]
		out.append([Quests.title(state, q), UiTheme.GOLD if Quests.is_credo(q) else UiTheme.TEXT])
		if int(q["wait"]) > state.tick:
			out.append(["   suite dans %d jours" % (int(q["wait"]) - state.tick), Color(UiTheme.TEXT, 0.55)])
			continue
		var brs: Array = Quests.chapter(q)["branches"]
		for b in brs.size():
			var p := Quests.progress(state, q, b)
			var prog := ("  %d/%d" % [int(p[0]), int(p[1])]) if not p.is_empty() else ""
			out.append(["   %s%s" % [String(brs[b]["label"]), prog], Color(UiTheme.TEXT, 0.7)])
	return out


func refresh() -> void:
	var ls := lines(_state, _player)
	var sig := str(ls)
	if sig == _sig:
		return
	_sig = sig
	for c in _box.get_children():
		c.queue_free()
	_empty = ls.is_empty()
	if _empty:
		visible = false
		return
	var head := UiTheme.section("Quêtes")
	head.add_theme_color_override("font_color", UiTheme.GOLD)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(head)
	for l in ls:
		var lab := UiTheme.dim(String(l[0]), 13)
		lab.add_theme_color_override("font_color", l[1])
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.clip_text = true
		_box.add_child(lab)
	visible = _allowed
