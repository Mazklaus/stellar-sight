class_name ChatPanel
extends VBoxContainer
## Discussion entre joueurs d'une partie en réseau (NetSession.send_chat / chat_received).
## Deux usages :
## - au salon (overlay = false) : historique et saisie toujours visibles ;
## - en partie (overlay = true) : les derniers messages s'affichent un moment puis s'effacent ;
##   Entrée ouvre la saisie (open_input), Entrée envoie, Échap referme. « Équipe » réserve le
##   message aux coéquipiers.

const FADE_SECONDS := 10.0
const OVERLAY_LINES := 6

var session: NetSession
var overlay := false
var _log: RichTextLabel
var _input_row: HBoxContainer
var _input: LineEdit
var _team: CheckBox
var _shown_until := 0.0


func _init(overlay_ := false, log_height := 120) -> void:
	overlay = overlay_
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = overlay
	_log.selection_enabled = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE if overlay else Control.MOUSE_FILTER_STOP
	_log.custom_minimum_size = Vector2(0, 0 if overlay else log_height)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL if not overlay else Control.SIZE_SHRINK_END
	_log.add_theme_font_size_override("normal_font_size", 14)
	if overlay:
		var st := UiTheme.box(Color(0.02, 0.025, 0.04, 0.72), Color(1, 1, 1, 0.0), 8, 0)
		_log.add_theme_stylebox_override("normal", st)
	add_child(_log)
	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 6)
	add_child(_input_row)
	_input = LineEdit.new()
	_input.placeholder_text = "Message aux joueurs…"
	_input.max_length = NetSession.CHAT_MAX
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_submit)
	_input.gui_input.connect(_on_input_key)
	_input_row.add_child(_input)
	_team = CheckBox.new()
	_team.text = "Équipe"
	_team.focus_mode = Control.FOCUS_NONE
	_team.tooltip_text = "Message réservé à votre équipe."
	_team.visible = false
	_input_row.add_child(_team)
	_input_row.visible = not overlay


## Branche le panneau sur une session (ou le débranche avec null) et reprend son historique.
func bind(s: NetSession) -> void:
	if session and session.chat_received.is_connected(_on_chat):
		session.chat_received.disconnect(_on_chat)
	session = s
	if session:
		session.chat_received.connect(_on_chat)
	refresh()


## Montre la case « Équipe » (partie avec équipes).
func set_team_available(on: bool) -> void:
	_team.visible = on
	if not on:
		_team.button_pressed = false


func refresh() -> void:
	_log.clear()
	if session == null:
		_update_visibility()
		return
	var entries := session.chat_log
	var first := maxi(0, entries.size() - (OVERLAY_LINES if not _input_row.visible else OVERLAY_LINES * 2)) if overlay else 0
	for i in range(first, entries.size()):
		_log.append_text(line_bbcode(entries[i]) + ("\n" if i < entries.size() - 1 else ""))
	_update_visibility()


static func line_bbcode(e: Dictionary) -> String:
	var name := String(e.get("n", "?")).replace("[", "(")
	var text := String(e.get("t", "")).replace("[", "[lb]")
	var tag := "[color=#%s][équipe][/color] " % UiTheme.GOOD.to_html(false) if bool(e.get("e", false)) else ""
	return "%s[color=#%s]%s[/color] : %s" % [tag, UiTheme.ACCENT.to_html(false), name, text]


## Le joueur local a-t-il des coéquipiers dans la partie ?
func has_team() -> bool:
	if session == null or session.core == null:
		return false
	var st := session.core.sim.state
	for e in st.empires:
		if e.id != session.my_empire and Diplomacy.team_of(st, session.my_empire, e.id) > 0:
			return true
	return false


func is_input_open() -> bool:
	return _input_row.visible and (not overlay or _input.has_focus())


## En partie : ouvre la saisie (Entrée).
func open_input() -> void:
	set_team_available(has_team())
	_input_row.visible = true
	refresh()
	_input.grab_focus()


func close_input() -> void:
	_input.release_focus()
	if overlay:
		_input_row.visible = false
		_input.text = ""
	refresh()


func _on_submit(text: String) -> void:
	if session and text.strip_edges() != "":
		session.send_chat(text, _team.visible and _team.button_pressed)
	_input.text = ""
	if overlay:
		close_input()


func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE and overlay:
		close_input()
		accept_event()


func _on_chat(_entry: Dictionary) -> void:
	_shown_until = Time.get_ticks_msec() / 1000.0 + FADE_SECONDS
	refresh()


func _update_visibility() -> void:
	if not overlay:
		return
	var recent := Time.get_ticks_msec() / 1000.0 < _shown_until
	_log.visible = session != null and not session.chat_log.is_empty() and (recent or _input_row.visible)


func _process(_delta: float) -> void:
	if overlay:
		# En partie seulement (le salon a son propre panneau).
		var in_game := session != null and session.core != null
		if visible != in_game:
			visible = in_game
			if not in_game:
				close_input()
	if overlay and _log.visible and not _input_row.visible and Time.get_ticks_msec() / 1000.0 >= _shown_until:
		_update_visibility()
