class_name MusicPlayer
extends Node
## La musique du jeu (étude du son, bloc E ; réglages : bloc "music" de data/audio.json).
## Elle joue en permanence, au même niveau à tous les zooms. L'état de la partie choisit la famille
## de morceaux (menu, paix, tension, guerre, crise, victoire, défaite) ; les morceaux d'une famille
## s'enchaînent en fondu, et un changement d'état fond vers la nouvelle famille sans couper.
## Un état sans morceau prend ceux de son état de repli. Le réglage « Densité de la musique » peut
## ajouter des silences entre les morceaux.
## state_of() est une fonction pure (tests).

## Fournit {state, player, menu} : l'état de la partie, le joueur regardé, menu principal ouvert ?
var probe := Callable()

var _players: Array[AudioStreamPlayer] = []
var _gains := [0.0, 0.0]
var _live := -1
var _state := ""
var _wanted := ""
var _wanted_for := 0.0
var _piece := ""
var _wait := 0.0
var _clock := 0.0
var _fade := 4.0
static var _lists := {}


static func cfg() -> Dictionary:
	return Son.data().get("music", {})


## État musical de la partie : le premier qui s'applique dans l'ordre de priorité.
static func state_of(state: GameState, player: int, in_menu: bool) -> String:
	if in_menu or state == null:
		return "menu"
	var me := state.get_empire(player)
	if not state.winner.is_empty():
		return "victoire" if int(state.winner.get("empire", -1)) == player else "defaite"
	if me == null or me.eliminated:
		return "defaite"
	if not me.wars.is_empty():
		return "guerre"
	if Crisis.active(state):
		return "crise"
	for other: Empire in state.empires:
		if other.id != player and not other.eliminated and me.contacts.has(other.id) and Diplomacy.status(state, player, other.id) == "cold":
			return "tension"
	return "paix"


## Morceaux déposés pour un état (aucun tant que la musique n'est pas livrée).
static func pieces(id: String) -> Array:
	if _lists.has(id):
		return _lists[id]
	var out: Array = []
	var base := "%s%s/" % [String(Son.data().get("dir", "res://assets/sounds/")), String(cfg().get("dir", "musique"))]
	for i in range(1, 10):
		for ext in Son.data().get("ext", ["ogg", "wav"]):
			var p := "%s%s_%d.%s" % [base, id, i, String(ext)]
			if ResourceLoader.exists(p) or FileAccess.file_exists(p):
				out.append("%s_%d" % [id, i])
				break
	_lists[id] = out
	return out


## État dont on joue vraiment les morceaux : celui demandé, sinon son repli, de proche en proche.
static func playable(id: String) -> String:
	var by_id := {}
	for s: Dictionary in cfg().get("states", []):
		by_id[String(s["id"])] = s
	var guard := 0
	while id != "" and pieces(id).is_empty() and guard < 8:
		id = String(by_id.get(id, {}).get("fallback", ""))
		guard += 1
	return id


## Morceau suivant d'un état : au hasard, jamais deux fois de suite le même s'il y en a plusieurs.
static func next_piece(id: String, last: String, rng: RandomNumberGenerator = null) -> String:
	var list := pieces(id).duplicate()
	if list.size() > 1:
		list.erase(last)
	if list.is_empty():
		return ""
	return String(list[(rng.randi() if rng != null else randi()) % list.size()])


## Silence avant le morceau suivant, selon le réglage de densité.
static func gap(rng: RandomNumberGenerator = null) -> float:
	var d: Dictionary = cfg().get("density", {}).get(SoundSettings.density_id(), {})
	var g: Array = d.get("gap", [0, 0])
	var t := rng.randf() if rng != null else randf()
	return lerpf(float(g[0]), float(g[1]), t)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = StringName(String(cfg().get("bus", "Musique")))
		add_child(p)
		_players.append(p)


func _process(delta: float) -> void:
	var c := cfg()
	_clock -= delta
	if _clock <= 0.0:
		_clock = 0.5
		var info: Dictionary = probe.call() if probe.is_valid() else {}
		var want := playable(state_of(info.get("state"), int(info.get("player", 0)), bool(info.get("menu", true))))
		if want != _wanted:
			_wanted = want
			_wanted_for = 0.0
		_wanted_for += 0.5
		# Le menu, la victoire et la défaite prennent la main tout de suite ; le reste doit durer.
		var urgent := want in ["menu", "victoire", "defaite"] or _state in ["", "menu"]
		if want != _state and (urgent or _wanted_for >= float(c.get("hold", 6.0))):
			_state = want
			start(next_piece(_state, _piece), float(c.get("switch", 2.5)))
	var top := db_to_linear(float(c.get("vol", 0.0)))
	for i in 2:
		_gains[i] = move_toward(float(_gains[i]), 1.0 if i == _live else 0.0, delta / maxf(0.05, _fade))
		var p := _players[i]
		if _gains[i] <= 0.0 and i != _live:
			if p.playing:
				p.stop()
			continue
		p.volume_db = linear_to_db(maxf(0.0001, float(_gains[i]) * top))
	if _state == "":
		return
	# Fin du morceau en vue : le suivant entre en fondu, après le silence voulu par le réglage.
	if _live >= 0 and _players[_live].stream != null:
		var p := _players[_live]
		var left := p.stream.get_length() - p.get_playback_position()
		if not p.playing or left <= float(c.get("fade", 4.0)):
			_live = -1
			_wait = gap()
	elif _live < 0:
		_wait -= delta
		if _wait <= 0.0:
			start(next_piece(_state, _piece), float(c.get("fade", 4.0)))
			if _live < 0:
				_wait = 5.0  # rien à jouer : on regarde de nouveau dans cinq secondes


## Lance un morceau en fondu ("" : rien).
func start(piece: String, fade: float) -> void:
	if piece == "":
		return
	var stream := MapSound.stream_for(piece, String(cfg().get("dir", "musique")), false)
	if stream == null:
		return
	_fade = fade
	var at := 0 if _live != 0 else 1
	if _live < 0 and _gains[0] > _gains[1]:
		at = 1
	_live = at
	_piece = piece
	_gains[at] = 0.0
	var p := _players[at]
	p.stream = stream
	p.volume_db = -80.0
	p.play()


## Morceau en cours ("" si silence) et état musical.
func now() -> Dictionary:
	return {"state": _state, "piece": _piece if _live >= 0 else ""}
