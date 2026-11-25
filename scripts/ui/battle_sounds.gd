class_name BattleSounds
extends Node
## Points d'accroche du son des vues de bataille (étude visuel des combats, prop. 37). Les vues appellent
## play(repère, position) quand un événement du replay passe (tir, impact, explosion, phase, déroute…) ;
## le son joue si un fichier existe à <dir><repère>.<ext> (bloc "sounds" de data/battle_visuals.json),
## sinon rien. Le signal cue(repère, position) part dans tous les cas : un futur mixeur (spatialisation,
## musique qui suit la bataille) s'y branche sans toucher aux vues. Les voix sortent sur le bus Combat
## (étude du son, A1), réglable dans les Options.

signal cue(id: String, at: Vector2)

const MIN_GAP_MS := 60  # un même repère ne rejoue pas plus vite (salves serrées)

static var _paths := {}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var muted := false
var _crowd: AudioStreamPlayer
var _crowd_gain := 0.0
var _recent: Array = []
var heard: Array = []   # derniers repères émis (tests, banc)


static func cfg() -> Dictionary:
	return GameData.battle_visuals().get("sounds", {})


## Fichier du repère, ou "" s'il n'y en a pas encore.
static func path_of(id: String) -> String:
	if _paths.has(id):
		return _paths[id]
	var out := ""
	for ext in cfg().get("ext", ["ogg", "wav"]):
		var p := "%s%s.%s" % [String(cfg().get("dir", "res://assets/sounds/battle/")), id, String(ext)]
		if ResourceLoader.exists(p):
			out = p
			break
	_paths[id] = out
	return out


## Réglages du son des batailles (étude du son, bloc H) : bloc "battle" de data/audio.json.
static func mix() -> Dictionary:
	return Son.data().get("battle", {})


## Esquisse d'un repère sans fichier : la sienne, sinon celle de sa famille (tir_<arme> -> tir).
static func recipe_of(id: String) -> Dictionary:
	var cues: Dictionary = mix().get("cues", {})
	if cues.has(id):
		return cues[id]
	return cues.get(id.get_slice("_", 0), {})


## Panoramique d'une position dans une vue de cette largeur (H2), de -1 à 1.
static func pan_of(at: Vector2, width: float) -> float:
	if width <= 1.0 or at == Vector2.ZERO:
		return 0.0
	return clampf((at.x - width * 0.5) / (width * 0.5), -1.0, 1.0) * float(mix().get("pan", 0.7))


## H4 : force de la rumeur de bataille (0 à 1) pour cette cadence de tirs par seconde.
static func crowd_level(per_second: float) -> float:
	var c: Dictionary = mix().get("crowd", {})
	var lo := float(c.get("rate", 8))
	if per_second < lo:
		return 0.0
	return clampf(0.4 + 0.6 * (per_second - lo) / maxf(1.0, float(c.get("full", 30)) - lo), 0.0, 1.0)


## H4 : ce repère joue-t-il encore un à un quand la rumeur a pris le relais ?
static func kept(id: String) -> bool:
	return (mix().get("crowd", {}).get("keep", []) as Array).has(id)


func _ready() -> void:
	MapSound.build_voice_buses("CombatV%d", int(cfg().get("voices", 12)), "Combat")
	for i in int(cfg().get("voices", 12)):
		var p := AudioStreamPlayer.new()
		p.volume_db = float(cfg().get("volume_db", -6.0))
		if AudioServer.get_bus_index("CombatV%d" % i) >= 0:
			p.bus = StringName("CombatV%d" % i)
		elif AudioServer.get_bus_index("Combat") >= 0:
			p.bus = &"Combat"
		add_child(p)
		_players.append(p)
	_crowd = AudioStreamPlayer.new()
	if AudioServer.get_bus_index("Combat") >= 0:
		_crowd.bus = &"Combat"
	_crowd.volume_db = -80.0
	add_child(_crowd)
	set_process(true)


func _process(delta: float) -> void:
	# Cadence des tirs sur la dernière seconde, puis rumeur qui la suit en douceur.
	var now := Time.get_ticks_msec()
	while not _recent.is_empty() and now - int(_recent[0]) > 1000:
		_recent.pop_front()
	var want := 0.0 if muted else crowd_level(float(_recent.size()))
	_crowd_gain = move_toward(_crowd_gain, want, delta / 0.8)
	if _crowd_gain > 0.0:
		if not _crowd.playing:
			_crowd.stream = SoundSynth.bed(mix().get("crowd", {}).get("bed", {}))
			_crowd.play()
		_crowd.volume_db = linear_to_db(maxf(0.0001, _crowd_gain)) + float(mix().get("crowd", {}).get("vol", -14.0))
	elif _crowd.playing:
		_crowd.stop()


func play(id: String, at := Vector2.ZERO) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, -100000)) < MIN_GAP_MS:
		return
	_last[id] = now
	heard.append(id)
	if heard.size() > 64:
		heard.pop_front()
	cue.emit(id, at)
	if muted or _players.is_empty():
		return
	if not kept(id):
		_recent.append(now)
		if _crowd_gain > 0.3:
			return  # la rumeur porte la bataille, les tirs un à un se taisent
	var hush: Dictionary = mix().get("hush", {})
	if (hush.get("cues", []) as Array).has(id) and is_inside_tree():
		# H5 : tout se tait un instant avant un grand coup.
		for q in _players:
			q.stop()
		await get_tree().create_timer(float(hush.get("pause", 0.5))).timeout
		if not is_inside_tree() or muted:
			return
	var path := path_of(id)
	var stream: AudioStream = load(path) if path != "" else null
	var vol := float(cfg().get("volume_db", -6.0))
	if stream == null:
		var recipe := recipe_of(id)
		if recipe.is_empty():
			return
		stream = SoundSynth.stream(recipe)
		vol = float(mix().get("vol", -10.0))
	var p := _players[_next]
	var bus := AudioServer.get_bus_index("CombatV%d" % _next)
	if bus >= 0:
		var parent := get_parent() as Control
		(AudioServer.get_bus_effect(bus, 0) as AudioEffectPanner).pan = pan_of(at, parent.size.x if parent != null else 0.0)
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = vol
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()
