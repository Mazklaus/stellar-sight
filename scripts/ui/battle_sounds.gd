class_name BattleSounds
extends Node
## Points d'accroche du son des vues de bataille (étude visuel des combats, prop. 37). Les vues appellent
## play(repère, position) quand un événement du replay passe (tir, impact, explosion, phase, déroute…) ;
## le son joue si un fichier existe à <dir><repère>.<ext> (bloc "sounds" de data/battle_visuals.json),
## sinon rien. Le signal cue(repère, position) part dans tous les cas : un futur mixeur (spatialisation,
## musique qui suit la bataille) s'y branche sans toucher aux vues.

signal cue(id: String, at: Vector2)

const MIN_GAP_MS := 60  # un même repère ne rejoue pas plus vite (salves serrées)

static var _paths := {}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var muted := false
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


func _ready() -> void:
	for i in int(cfg().get("voices", 12)):
		var p := AudioStreamPlayer.new()
		p.volume_db = float(cfg().get("volume_db", -6.0))
		add_child(p)
		_players.append(p)


func play(id: String, at := Vector2.ZERO) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, -100000)) < MIN_GAP_MS:
		return
	_last[id] = now
	heard.append(id)
	if heard.size() > 64:
		heard.pop_front()
	cue.emit(id, at)
	var path := path_of(id)
	if muted or path == "" or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = load(path)
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()
