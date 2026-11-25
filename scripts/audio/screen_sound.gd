class_name ScreenSound
extends Node
## Les lieux des écrans d'empire (étude du son, bloc C ; réglages : bloc "screens" de data/audio.json).
## Chaque onglet est un lieu : la salle des comptes, la rue, la cale sèche, l'hémicycle. Ouvrir un écran
## installe son lieu, changer d'onglet fond un lieu dans l'autre, fermer rend la carte. Une donnée du
## jeu agite le lieu (stabilité pour la rue, dette pour la chambre forte, flottes en route pour le pont).
## place_of() et agitation() sont des fonctions pures (tests).

var screens: EmpireScreens

var _players: Array[AudioStreamPlayer] = []
var _gains := [0.0, 0.0]
var _sounds := ["", ""]
var _live := -1
var _clock := 0.0
var _level := 0.4


static func cfg() -> Dictionary:
	return Son.data().get("screens", {})


## [son, donnée] de l'adresse d'un onglet ; ["", ""] si l'onglet n'a pas de lieu.
static func place_of(addr: String) -> Array:
	var places: Dictionary = cfg().get("places", {})
	if places.has(addr):
		return places[addr]
	var screen := UiDomains.screen_of(addr)
	if not addr.contains(":") and UiDomains.DEFAULT_SUB.has(screen):
		return places.get("%s:%s" % [screen, UiDomains.DEFAULT_SUB[screen]], ["", ""])
	return places.get(screen, ["", ""])


## Agitation du lieu, de 0 (calme) à 1, d'après la donnée du jeu qui le fait varier.
static func agitation(state: GameState, player: int, vary: String) -> float:
	var rest := float(cfg().get("rest", 0.4))
	if state == null or vary == "":
		return rest
	var e := state.get_empire(player)
	if e == null:
		return rest
	match vary:
		"stability":
			var ids := Stability.systems_of(state, player)
			if ids.is_empty():
				return rest
			var sum := 0
			for sid in ids:
				sum += Stability.value(state, sid)
			return clampf(1.0 - float(sum) / float(ids.size()) / 100.0, 0.0, 1.0)
		"corruption":
			return clampf(float(Admin.average_corruption(state, player)) / 100.0, 0.0, 1.0)
		"debt":
			var d := Finance.debt(state, player)
			return clampf(float(d) / 2000.0, 0.0, 1.0) if d > 0 else 0.1
		"deficit":
			return 1.0 if e.starving or e.blackout else 0.3
		"fleets":
			var all := 0
			var moving := 0
			for fid: int in state.fleets:
				var f: Fleet = state.fleets[fid]
				if f.owner == player:
					all += 1
					moving += 1 if f.is_moving() else 0
			return float(moving) / float(all) if all > 0 else 0.0
		"routes":
			return clampf(float(Trade.routes_of(state, player).size()) / 10.0, 0.0, 1.0)
		"colonies":
			var n := 0
			for pid: int in state.colonies:
				n += 1 if (state.colonies[pid] as Colony).owner == player else 0
			return clampf(float(n) / 20.0, 0.0, 1.0)
	return rest


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = StringName(String(cfg().get("bus", "Ecran")))
		add_child(p)
		_players.append(p)


func _process(delta: float) -> void:
	var c := cfg()
	_clock -= delta
	if _clock <= 0.0:
		_clock = 0.25
		var addr := UiDomains.address(screens) if screens != null and screens.is_open() else ""
		var place := place_of(addr) if addr != "" else ["", ""]
		enter(String(place[0]))
		if String(place[0]) != "":
			_level = agitation(screens._state, screens._player, String(place[1]))
	var rate := delta / maxf(0.05, float(c.get("fade", 0.8)))
	var top := db_to_linear(float(c.get("vol", -8.0))) * lerpf(float(c.get("calm", 0.55)), 1.0, _level)
	for i in 2:
		_gains[i] = move_toward(float(_gains[i]), 1.0 if i == _live else 0.0, rate)
		var p := _players[i]
		if _gains[i] <= 0.0 and i != _live:
			if p.playing:
				p.stop()
			_sounds[i] = ""
			continue
		p.volume_db = linear_to_db(maxf(0.0001, float(_gains[i]) * top))
		p.pitch_scale = pow(2.0, (float(_level) - 0.5) * float(c.get("pitch", 0.6)) / 12.0)


## Installe un lieu ("" : aucun, l'écran est fermé). Le lieu d'avant s'efface en fondu.
func enter(sound: String) -> void:
	if _live >= 0 and _sounds[_live] == sound:
		return
	if sound == "":
		_live = -1
		return
	var stream := MapSound.stream_for("lieu_" + sound, String(cfg().get("dir", "ecran")))
	if stream == null:
		_live = -1
		return
	var at := 0 if _live != 0 else 1
	_live = at
	_sounds[at] = sound
	_gains[at] = 0.0
	var p := _players[at]
	p.stream = stream
	p.volume_db = -80.0
	p.play(randf() * stream.get_length())


## Lieu installé ("" si aucun).
func place() -> String:
	return String(_sounds[_live]) if _live >= 0 else ""
