class_name NetSession
extends Node
## Session multijoueur : le transport (ENet, UDP) autour du cœur Lockstep, et l'horloge partagée.
##
## L'hôte ouvre sa partie en cours ; un client s'y connecte par adresse. À l'arrivée d'un joueur, la
## partie se met en pause, l'hôte lui confie le premier empire tenu par l'IA (ordre « seat ») et lui
## envoie l'instantané complet (GameState.to_snapshot, compressé). Au départ d'un joueur, son empire
## repasse à l'IA (intérim) et l'hôte sauvegarde automatiquement.
##
## Une fois branchée (GameClock.driver), la session remplace l'horloge locale : elle fait avancer la
## simulation au rythme de l'hôte, et la pause et la vitesse sont partagées (tout le monde peut mettre
## en pause ; reprend celui qui a mis en pause ou l'hôte ; seul l'hôte règle la vitesse).
##
## Les messages sont des dictionnaires encodés par var_to_bytes (sans objets : rien d'exécutable).

signal notice(text: String, tone: String)
## Client : l'hôte a accepté ; state est la partie à rejoindre, empire_id l'empire confié.
signal joined(state: GameState, empire_id: int)
## Client : connexion refusée ou perdue avant d'entrer.
signal join_failed(reason: String)
## La session s'est terminée (hôte parti, réseau fermé).
signal ended(reason: String)
## Les joueurs connectés ont changé (noms, empires).
signal players_changed
## Pause ou vitesse partagées ont changé.
signal clock_changed

enum { NONE, HOST, CLIENT }

const DEFAULT_PORT := 24570
## Joueurs humains au plus (l'hôte compris) : autant que d'empires (GameState.MAX_EMPIRES).
const MAX_PLAYERS := 12
const MAX_DAYS_PER_FRAME := 8
## Marge ajoutée à la demi-latence pour fixer le délai des ordres.
const DELAY_MARGIN_MS := 60.0
## Niveau de l'IA qui tient l'empire d'un joueur parti.
const INTERIM_AI := "normal"
const AUTOSAVE_PATH := "user://saves/multi_auto.json"
## Le script de l'horloge, pour ses constantes (l'autoload GameClock n'est pas nommable ici : la
## session doit aussi se compiler dans les outils lancés avec -s, où il n'existe pas encore).
const Clock := preload("res://scripts/sim/game_clock.gd")
const DESYNC_DIR := "user://desync"

var role := NONE
var core: Lockstep
var player_name := "Joueur"
## Pair -> nom (l'hôte compris, sous Lockstep.HOST).
var names := {}
var my_empire := -1
## Horloge partagée.
var paused := true
var speed := 1
## Nom de celui qui a mis en pause ("" : personne, ou pause d'arrivée).
var paused_by := ""
var delay := 1

var _peer: ENetMultiplayerPeer
var _accum := 0.0
## Hôte : pause demandée, on joue jusqu'au premier jour sans trame scellée.
var _pausing := false
var _pauser := -1
## Hôte : arrivées et départs à traiter dès que tout le monde est arrêté.
var _joins: Array[int] = []
var _leaves: Array[int] = []
var _stall_told := false
var _delay_timer := 0.0


func is_active() -> bool:
	return role != NONE


func is_host() -> bool:
	return role == HOST


# --- Ouverture ---------------------------------------------------------------------------------

## Ouvre la partie en cours au réseau. Le joueur local garde son empire.
func host(sim: Simulation, empire_id: int, port := DEFAULT_PORT) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		return err
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	role = HOST
	core = Lockstep.new(sim, true)
	core.seats[Lockstep.HOST] = empire_id
	core.desync_detected.connect(_on_desync)
	names = {Lockstep.HOST: player_name}
	my_empire = empire_id
	speed = _clock().speed_index
	paused = true
	_attach_clock()
	players_changed.emit()
	return OK


## Se connecte à une partie. La réponse arrive par joined ou join_failed.
func join(address: String, port := DEFAULT_PORT) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	_peer.peer_connected.connect(func(id: int) -> void:
		if id == Lockstep.HOST:
			_send(Lockstep.HOST, {"k": "hello", "v": GameVersion.fingerprint(), "n": player_name}))
	_peer.peer_disconnected.connect(func(id: int) -> void:
		if id == Lockstep.HOST:
			# Pas pendant poll() : fermer le pair au milieu de sa propre boucle le ferait planter.
			_end.call_deferred("l'hôte a quitté la partie" if core else "connexion perdue"))
	role = CLIENT
	return OK


## Ferme la session (sans prévenir les autres : ENet le leur signale).
func close() -> void:
	if _peer:
		_peer.close()
	_peer = null
	role = NONE
	core = null
	names = {}
	my_empire = -1
	_joins.clear()
	_leaves.clear()
	_pausing = false
	if _clock().driver == self:
		_clock().driver = null


func _end(reason: String) -> void:
	if role == NONE:
		return
	var was_in := core != null
	close()
	if was_in:
		ended.emit(reason)
	else:
		join_failed.emit(reason)


## Adresses locales de cette machine (IPv4), à donner aux autres joueurs.
static func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# --- Ordres et horloge (appelés par le jeu) ----------------------------------------------------

## Un ordre du joueur local. Renvoie la raison d'un refus immédiat, "" sinon (il s'appliquera au
## jour que l'hôte lui donnera).
func submit(cmd: Dictionary) -> String:
	if core == null:
		return "pas de partie en réseau"
	var why := SimCommands.validate(core.sim.state, cmd)
	if why != "":
		return why
	if role == HOST:
		why = core.request(Lockstep.HOST, cmd)
		_flush()
		return why
	_send(Lockstep.HOST, {"k": "order", "c": cmd})
	return ""


## Espace, cadran : demande de pause ou de reprise, pour tout le monde.
func request_pause(value: bool) -> void:
	if role == HOST:
		_host_pause(Lockstep.HOST, value)
	elif core:
		_send(Lockstep.HOST, {"k": "pause", "p": value})


func request_speed(index: int) -> void:
	if role == HOST:
		speed = clampi(index, 0, Clock.SECONDS_PER_DAY.size() - 1)
		_update_delay()
		_broadcast_clock()
	elif core:
		notice.emit("Seul l'hôte règle la vitesse.", "")


## Fraction du jour en cours, pour animer les flottes.
func day_fraction() -> float:
	if paused or core == null or not core.can_step():
		return 0.0
	return clampf(_accum / _seconds_per_day(), 0.0, 1.0)


## Appelé à chaque image par GameClock (driver) : réseau, puis avance de la simulation.
func clock_process(delta: float) -> void:
	_poll()
	if core == null:
		return
	if role == HOST:
		_host_clock(delta)
	else:
		_client_clock(delta)
	_flush()


func _process(_delta: float) -> void:
	# Hors partie (connexion en cours), on écoute quand même le réseau.
	if _peer and _clock().driver != self:
		_poll()


## L'horloge du jeu (autoload).
func _clock() -> Node:
	return get_node("/root/GameClock")


func _seconds_per_day() -> float:
	return Clock.SECONDS_PER_DAY[speed]


func _attach_clock() -> void:
	_clock().driver = self
	_clock().net_sync(paused, speed)


func _host_clock(delta: float) -> void:
	_delay_timer += delta
	if _delay_timer > 1.0:
		_delay_timer = 0.0
		_update_delay()
	if _pausing:
		# Tout le monde s'arrête au premier jour sans trame scellée : on y va.
		var n := 0
		while core.can_step() and n < MAX_DAYS_PER_FRAME:
			core.step()
			n += 1
		if not core.can_step():
			_pausing = false
			paused = true
			_broadcast_clock()
			_after_stop()
		return
	if paused:
		core.flush_paused()
		return
	_accum += delta
	var step := _seconds_per_day()
	var n := 0
	while _accum >= step and n < MAX_DAYS_PER_FRAME:
		if not core.host_may_step():
			_accum = minf(_accum, step)
			if not _stall_told:
				_stall_told = true
				notice.emit("%s ralentit la partie (machine ou connexion lente)." % names.get(core.slowest(), "Un joueur"), "")
			return
		_stall_told = false
		_accum -= step
		n += 1
		core.seal_until(core.tick() + delay)
		core.step()
	if n >= MAX_DAYS_PER_FRAME:
		_accum = 0.0


func _client_clock(delta: float) -> void:
	if not paused:
		_accum += delta
	var step := _seconds_per_day()
	var n := 0
	while core.can_step() and n < MAX_DAYS_PER_FRAME:
		# On suit le rythme de l'hôte ; on rattrape si l'on est en retard ou s'il s'est arrêté.
		if _accum >= step:
			_accum -= step
		elif not (paused or core.lead() > delay + 1):
			break
		core.step()
		n += 1
	if not core.can_step():
		_accum = minf(_accum, step)


## Délai des ordres : la demi-latence du joueur le plus lointain, plus une marge, en jours.
func _update_delay() -> void:
	var rtt := 0.0
	for id in core.acks:
		var p := _peer.get_peer(id)
		if p:
			rtt = maxf(rtt, p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	var d := clampi(ceili((rtt * 0.5 + DELAY_MARGIN_MS) / (_seconds_per_day() * 1000.0)) + 1, 1, 8)
	if d != delay:
		delay = d
		_broadcast_clock()
	core.delay = delay
	core.max_lead = delay + 4


# --- Hôte : pause, arrivées, départs -----------------------------------------------------------

func _host_pause(by: int, value: bool) -> void:
	if value:
		if paused or _pausing:
			return
		_pausing = true
		_pauser = by
		paused_by = String(names.get(by, ""))
		_broadcast_clock()
		return
	if not (paused or _pausing):
		return
	if by != Lockstep.HOST and _pauser >= 0 and by != _pauser and names.has(_pauser):
		_send(by, {"k": "notice", "t": "Seul %s ou l'hôte peut reprendre." % names[_pauser], "o": ""})
		return
	if not _joins.is_empty() or not _leaves.is_empty():
		return  # une arrivée ou un départ est en cours de traitement
	_pausing = false
	paused = false
	_pauser = -1
	paused_by = ""
	_accum = 0.0
	core.seal_until(core.tick() + delay)
	_broadcast_clock()


## Tout le monde est arrêté au même jour : on traite arrivées et départs.
func _after_stop() -> void:
	for id in _leaves:
		var e: int = core.seats.get(id, -1)
		core.remove_peer(id)
		if e >= 0:
			core.request(Lockstep.HOST, SimCommands.seat(e, INTERIM_AI))
		var who := String(names.get(id, "Un joueur"))
		names.erase(id)
		core.flush_paused()
		var saved := SaveGame.save_state(core.sim.state, AUTOSAVE_PATH, _clock().settings()) == OK
		_announce("%s a quitté la partie : l'IA tient son empire en attendant.%s" % [who, " Sauvegarde automatique faite." if saved else ""], "bad")
	_leaves.clear()
	for id in _joins:
		_welcome(id)
	_joins.clear()
	players_changed.emit()
	_flush()


func _welcome(id: int) -> void:
	var empire := _free_empire()
	if empire < 0:
		_send(id, {"k": "refuse", "r": "plus aucun empire libre dans cette partie"})
		_flush()
		_peer.disconnect_peer(id, false)
		names.erase(id)
		return
	core.request(Lockstep.HOST, SimCommands.seat(empire, ""))
	core.flush_paused()
	_flush()
	var snap := var_to_bytes(core.sim.state.to_snapshot()).compress(FileAccess.COMPRESSION_GZIP)
	core.add_peer(id, empire)
	_send(id, {"k": "welcome", "e": empire, "s": snap, "t": core.tick(), "names": names,
			"clock": _clock_msg()})
	var e := core.sim.state.get_empire(empire)
	_announce("%s rejoint la partie et prend la tête de %s." % [names[id], e.display_name()], "good")


## Premier empire encore en vie, tenu par l'IA et sans joueur.
func _free_empire() -> int:
	var taken := core.seats.values()
	for e in core.sim.state.empires:
		if e.is_ai() and not e.eliminated and not taken.has(e.id):
			return e.id
	return -1


func _on_peer_connected(_id: int) -> void:
	pass  # on attend son « hello »


func _on_peer_disconnected(id: int) -> void:
	if role != HOST:
		return
	_joins.erase(id)
	if core.seats.has(id):
		_leaves.append(id)
		_host_pause(Lockstep.HOST, true)
		if paused:
			_after_stop()
	else:
		names.erase(id)


func _on_desync(peer: int, tick: int) -> void:
	_host_pause(Lockstep.HOST, true)
	DirAccess.make_dir_recursive_absolute(DESYNC_DIR)
	var path := "%s/hote_jour_%d.json" % [DESYNC_DIR, core.tick()]
	SaveGame.save_state(core.sim.state, path)
	_send(peer, {"k": "desync", "t": tick})
	_announce("Désynchronisation avec %s au %s : la partie est en pause. États enregistrés dans %s." % [
			names.get(peer, "un joueur"), GameCalendar.date_string(tick), DESYNC_DIR], "bad")


func _announce(text: String, tone: String) -> void:
	notice.emit(text, tone)
	_send(0, {"k": "notice", "t": text, "o": tone})


func _clock_msg() -> Dictionary:
	return {"k": "clock", "p": paused or _pausing, "s": speed, "b": paused_by, "d": delay}


func _broadcast_clock() -> void:
	_clock().net_sync(paused or _pausing, speed)
	clock_changed.emit()
	_send(0, _clock_msg())


# --- Réseau ------------------------------------------------------------------------------------

func _poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	while _peer and _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var data := _peer.get_packet()
		var msg: Variant = bytes_to_var(data)
		if msg is Dictionary:
			if role == HOST:
				_host_message(from, msg)
			else:
				_client_message(msg)


func _host_message(from: int, msg: Dictionary) -> void:
	match String(msg.get("k", "")):
		"hello":
			if String(msg.get("v", "")) != GameVersion.fingerprint():
				_send(from, {"k": "refuse", "r": "versions du jeu différentes (la vôtre : %s, l'hôte : %s)" % [msg.get("v", "?"), GameVersion.fingerprint()]})
				_flush()
				return
			if _clock().is_turn_based():
				_send(from, {"k": "refuse", "r": "le tour par tour en réseau n'est pas encore prêt"})
				_flush()
				return
			names[from] = String(msg.get("n", "Joueur")).substr(0, 24)
			_joins.append(from)
			_host_pause(Lockstep.HOST, true)
			paused_by = ""
			if paused and not _pausing:
				_after_stop()
		"order":
			if not core.seats.has(from) or not msg.get("c") is Dictionary:
				return
			var why := core.request(from, msg["c"])
			if why != "":
				_send(from, {"k": "notice", "t": "Ordre refusé : %s" % why, "o": "bad"})
		"ack":
			if core.seats.has(from):
				core.host_receive_ack(from, int(msg.get("t", 0)), String(msg.get("h", "")))
		"pause":
			if core.seats.has(from):
				_host_pause(from, bool(msg.get("p", true)))


func _client_message(msg: Dictionary) -> void:
	match String(msg.get("k", "")):
		"welcome":
			var raw: PackedByteArray = msg.get("s", PackedByteArray())
			var snap: Variant = bytes_to_var(raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP))
			var state := GameState.from_dict(snap) if snap is Dictionary else null
			if state == null:
				_end("partie reçue illisible (%s)" % GameState.last_error)
				return
			my_empire = int(msg["e"])
			names = msg.get("names", {})
			joined.emit(state, my_empire)  # le jeu crée sa Simulation et appelle bind()
			_client_message(msg.get("clock", {}))
			players_changed.emit()
		"refuse":
			_end(String(msg.get("r", "refusé par l'hôte")))
		"frame":
			if core:
				core.receive_frame(int(msg["t"]), msg.get("c", []), bool(msg.get("s", false)))
		"clock":
			paused = bool(msg.get("p", true))
			speed = clampi(int(msg.get("s", 1)), 0, Clock.SECONDS_PER_DAY.size() - 1)
			paused_by = String(msg.get("b", ""))
			delay = int(msg.get("d", 1))
			if core:
				_clock().net_sync(paused, speed)
			clock_changed.emit()
		"notice":
			notice.emit(String(msg.get("t", "")), String(msg.get("o", "")))
		"desync":
			if core:
				DirAccess.make_dir_recursive_absolute(DESYNC_DIR)
				SaveGame.save_state(core.sim.state, "%s/client_jour_%d.json" % [DESYNC_DIR, core.tick()])


## Client : branche la simulation créée par le jeu à partir de la partie reçue.
func bind(sim: Simulation) -> void:
	core = Lockstep.new(sim, false)
	_attach_clock()


func _send(to: int, msg: Dictionary) -> void:
	if _peer == null or (to != 0 and _peer.get_peer(to) == null and role == HOST):
		return
	_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	_peer.set_target_peer(to)
	_peer.put_packet(var_to_bytes(msg))


func _flush() -> void:
	if core == null:
		return
	for out in core.outbox:
		_send(int(out["to"]), out["msg"])
	core.outbox.clear()
