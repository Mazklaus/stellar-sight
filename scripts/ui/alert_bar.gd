class_name AlertBar
extends PanelContainer
## Panneau de droite réduit (refonte, A4) : une barre étroite qui ne garde que ce qui demande l'attention
## du joueur. Chaque pastille porte un pictogramme et un compte ; un clic mène à ce qu'elle signale.
## Elle lit l'état et n'émet que des demandes.

signal alert_requested(kind: String, arg: int)

const WIDTH := 52.0
## Sorte, pictogramme, couleur.
const KINDS := {
	"decisions": ["chronicles", Color(0.95, 0.78, 0.45)],
	"battle": ["armies", Color(0.93, 0.42, 0.38)],
	"war": ["diplomacy", Color(0.95, 0.55, 0.35)],
	"routes": ["trade", Color(0.95, 0.62, 0.3)],
	"quest": ["victory", Color(0.45, 0.8, 0.95)],
}

var _state: GameState
var _player := 0
var _box: VBoxContainer
var _sig := "-"
## Boutons affichés, par sorte (pour les tests).
var buttons := {}


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 0.72), UiTheme.LINE, 4, 1))
	custom_minimum_size = Vector2(WIDTH, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)


func set_state(state: GameState, player: int) -> void:
	_state = state
	_player = player
	_sig = "-"
	refresh()


## Ce qui demande l'attention de l'empire : [{kind, count, text, arg}], du plus pressant au moins pressant.
static func alerts(state: GameState, player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or state.get_empire(player) == null:
		return out
	var waiting := Events.inbox(state, player).size()
	if Deeds.enabled(state):
		waiting += Deeds.inbox(state, player).size()
	if waiting > 0:
		out.append({"kind": "decisions", "count": waiting, "arg": -1,
				"text": "%d décision%s en attente" % [waiting, "s" if waiting > 1 else ""]})
	var fights: Array[int] = []
	for sid in state.battles:
		if Espionage.battle_sides(state.battles[sid]).has(player):
			fights.append(int(sid))
	for sid in state.sieges:
		if state.system_owner(int(sid)) == player and not fights.has(int(sid)):
			fights.append(int(sid))
	fights.sort()
	if not fights.is_empty():
		var names := PackedStringArray()
		for sid in fights:
			names.append(state.galaxy.get_system(sid).system_name)
		out.append({"kind": "battle", "count": fights.size(), "arg": fights[0],
				"text": "Combat ou siège : %s" % ", ".join(names)})
	# Bêta-test (2.4) : chaque guerre en cours, avec son score ; un clic mène aux conditions de paix de la
	# guerre la plus mal engagée.
	var me := state.get_empire(player)
	if not me.wars.is_empty():
		var foes: Array = me.wars.duplicate()
		foes.sort()
		var worst := -1
		var worst_score := 0
		var lines := PackedStringArray()
		for o in foes:
			var oe := state.get_empire(int(o))
			if oe == null or oe.eliminated:
				continue
			var sc := Diplomacy.war_score(state, player, int(o))
			var line := "%s : score %+d" % [oe.short_name(), sc]
			# 2.2 (R2) : la jauge d'occupation, systèmes encore libres de chaque camp.
			if WarPeace.occ_on(state):
				line += ", systèmes libres : vous %s, lui %s" % [free_gauge(state, player), free_gauge(state, int(o))]
			if not WarPeace.uncond_of(state, player, int(o)).is_empty():
				line += ", il se rend sans conditions"
				sc = -1000  # le clic mène d'abord aux termes à fixer
			elif not WarPeace.uncond_of(state, int(o), player).is_empty():
				line += ", tous vos systèmes sont occupés"
				sc = -999
			lines.append(line)
			if worst < 0 or sc < worst_score:
				worst = int(o)
				worst_score = sc
		if worst >= 0:
			out.append({"kind": "war", "count": lines.size(), "arg": worst,
					"text": "En guerre. %s\nClic : conditions de paix avec %s." % ["\n".join(lines) if lines.size() > 1 else lines[0], state.get_empire(worst).short_name()]})
	var blocked := 0
	for r: Dictionary in Trade.routes_of(state, player):
		if bool(r.get("blocked", false)):
			blocked += 1
	if blocked > 0:
		out.append({"kind": "routes", "count": blocked, "arg": -1,
				"text": "%d route%s commerciale%s bloquée%s" % [blocked, "s" if blocked > 1 else "", "s" if blocked > 1 else "", "s" if blocked > 1 else ""]})
	if Quests.enabled(state):
		var quests := Quests.of(state, player, true).size()
		if quests > 0:
			out.append({"kind": "quest", "count": quests, "arg": -1,
					"text": "%d quête%s en cours" % [quests, "s" if quests > 1 else ""]})
	return out


func refresh() -> void:
	if _box == null:
		return
	var list := alerts(_state, _player)
	var sig := str(list)
	if sig == _sig:
		return
	_sig = sig
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	buttons.clear()
	self_modulate.a = 0.0 if list.is_empty() else 1.0
	for a: Dictionary in list:
		var kind := String(a["kind"])
		var b := Button.new()
		b.theme_type_variation = &"BarButton"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(WIDTH - 8.0, 46)
		b.tooltip_text = String(a["text"])
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", -3)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var glyph := Widgets.IconButton.new(String(KINDS[kind][0]), 24)
		glyph.glyph_color = KINDS[kind][1]
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(glyph)
		var count := Label.new()
		count.theme_type_variation = &"Numbers"
		count.text = str(a["count"])
		count.add_theme_font_size_override("font_size", 13)
		count.add_theme_color_override("font_color", KINDS[kind][1])
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(count)
		var arg := int(a["arg"])
		b.pressed.connect(func() -> void: alert_requested.emit(kind, arg))
		_box.add_child(b)
		buttons[kind] = b
	reset_size()


## « a sur b » : systèmes de eid que personne n'occupe, sur ceux qu'il possède (bêta-test 2.2, R2).
static func free_gauge(state: GameState, eid: int) -> String:
	return "%d sur %d" % [WarPeace.free_systems(state, eid).size(), EmpireReport.owned_systems(state, eid).size()]
