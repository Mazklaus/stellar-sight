class_name SoundDirector
extends Node
## Chef d'orchestre du son, posé sous la racine par Son.setup(). Il tient les voix (un petit lot
## d'AudioStreamPlayer qui tournent), donne leur son aux boutons de l'interface à mesure qu'ils entrent
## dans l'arbre, suit le cadran du temps et coupe le son quand la fenêtre n'a plus la main.

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
## Clic de bouton en attente : il cède la place à un repère plus parlant joué dans la même image
## (ouverture d'écran, pause, cran de vitesse), pour ne pas doubler les sons.
var _pending := ""
var _spoke_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in int(Son.data().get("voices", 12)):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_on_node_added)
	_adopt(get_tree().root)
	var clock := get_node_or_null("/root/GameClock")
	if clock != null:
		clock.pause_changed.connect(_on_pause.bind(clock))
		clock.speed_changed.connect(_on_speed)
		clock.turn_started.connect(func(_t: int) -> void: Son.cue("tour_pret"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Son.set_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Son.set_focused(true)


func _adopt(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_adopt(c)


func _on_node_added(n: Node) -> void:
	if not (n is BaseButton) or n.has_meta(&"son_pose"):
		return
	n.set_meta(&"son_pose", true)
	var b := n as BaseButton
	b.pressed.connect(_on_button.bind(b))
	b.mouse_entered.connect(_on_hover.bind(b))


func _on_button(b: BaseButton) -> void:
	var id := Son.button_cue(b)
	if id == "" or _spoke_frame == Engine.get_process_frames():
		return
	if _pending == "":
		_flush.call_deferred()
	_pending = id


func _flush() -> void:
	var id := _pending
	_pending = ""
	if id != "":
		Son.cue(id)


func _on_hover(b: BaseButton) -> void:
	if SoundSettings.hover and not b.disabled and not (b.has_meta("son") and String(b.get_meta("son")) == ""):
		Son.cue(String(Son.data().get("buttons", {}).get("hover", "")))


func _on_pause(paused: bool, clock: Node) -> void:
	if clock.is_turn_based():
		if not paused and clock.is_resolving_turn():
			Son.cue("tour_fin")
		return
	Son.cue("temps_pause" if paused else "temps_reprise")


func _on_speed(index: int) -> void:
	var semis: Array = Son.data().get("speed_semitones", [0])
	Son.cue("temps_vitesse", float(semis[clampi(index, 0, semis.size() - 1)]))


func play_cue(id: String, semis := 0.0) -> void:
	var def := Son.cue_def(id)
	if def.is_empty():
		return
	var buttons: Dictionary = Son.data().get("buttons", {})
	if not buttons.values().has(id):
		_pending = ""
		_spoke_frame = Engine.get_process_frames()
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, -100000)) < int(def.get("gap", 0)):
		return
	_last[id] = now
	var stream := Son.stream_of(id, semis)
	if stream == null:
		return
	var spread := float(def.get("pitch", 0.0))
	play(stream, String(def.get("bus", "Interface")), float(def.get("vol", 0.0)), 1.0 + randf_range(-spread, spread))


func play(stream: AudioStream, bus: String, vol_db := 0.0, pitch := 1.0) -> void:
	if _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.bus = StringName(bus) if AudioServer.get_bus_index(bus) >= 0 else &"Master"
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()
