class_name Lockstep
extends RefCounted
## Cœur du multijoueur en lockstep, sans réseau ni horloge : qui a le droit de jouer quel jour, avec
## quels ordres. NetSession l'alimente en messages et décide quand avancer ; les tests le branchent
## directement sur un autre Lockstep.
##
## Principe (étude du multijoueur, lot 2) : chaque machine fait tourner toute la partie. Seuls les
## ordres des humains voyagent, et l'hôte, seul arbitre, les range dans des « trames » :
##   trame J = les ordres à appliquer au début du jour J (state.tick == J), puis le droit de passer à J+1.
## Une trame est « scellée » quand plus rien n'y sera ajouté. Une machine n'avance du jour J au jour
## J+1 que si la trame J est scellée : toutes appliquent donc les mêmes ordres au même jour.
## L'IA, l'économie et les combats se calculent seuls à l'identique (déterminisme).
##
## Pendant une pause, tout le monde s'arrête au même jour Q (le premier sans trame scellée) ; les
## ordres donnés en pause arrivent par morceaux de la trame Q, appliqués aussitôt, et la reprise la scelle.
##
## Les messages sortants s'accumulent dans `outbox` : [{"to": id du pair (0 = tous), "msg": {...}}].

## Identifiant de l'hôte (convention de Godot pour le serveur).
const HOST := 1
## Une somme de contrôle tous les CHECK_DAYS jours (environ un mois).
const CHECK_DAYS := 30

## Hôte : la somme de contrôle d'un pair diffère de la sienne pour ce jour.
signal desync_detected(peer: int, tick: int)

var sim: Simulation
var is_host := false
## Délai d'exécution des ordres, en jours : l'hôte scelle les trames jusqu'à (jour courant + delay).
var delay := 1
## Avance maximale de l'hôte sur le client le plus lent, en jours, au-delà de laquelle il attend.
var max_lead := 6
var outbox: Array[Dictionary] = []

## Trames reçues ou émises : jour -> {"cmds": [...], "sealed": bool, "applied": nombre déjà appliqué}.
var _frames := {}
## Dernier jour dont la trame est scellée (-1 : aucune).
var sealed_until := -1

# --- Hôte seulement ---
## Ordres reçus, en attente de la prochaine trame.
var _pending: Array[Dictionary] = []
## Pair -> empire qu'il dirige (l'hôte compris : HOST -> son empire).
var seats := {}
## Pair -> dernier jour atteint (accusé de réception).
var acks := {}
## Sommes de contrôle : jour -> {pair: somme} (celle de l'hôte sous HOST).
var _hashes := {}


func _init(simulation: Simulation, host := false) -> void:
	sim = simulation
	is_host = host
	if is_host:
		# L'hôte part du jour courant : tout ce qui précède est déjà joué.
		sealed_until = sim.state.tick - 1


func tick() -> int:
	return sim.state.tick


## Le jour courant a-t-il sa trame scellée (le droit d'avancer) ?
func can_step() -> bool:
	var f: Dictionary = _frames.get(tick(), {})
	return f.get("sealed", false)


## Jours d'avance disponibles (trames scellées au-delà du jour courant).
func lead() -> int:
	return sealed_until - tick() + 1


## Avance d'un jour : applique ce qui reste de la trame, fait un pas, relève la somme de contrôle.
func step() -> bool:
	if not can_step():
		return false
	_apply_frame(tick())
	_frames.erase(tick())
	sim.step()
	var t := tick()
	if t % CHECK_DAYS == 0:
		_record_hash(HOST if is_host else 0, t, sim.state.checksum())
	if not is_host:
		var msg := {"k": "ack", "t": t}
		if t % CHECK_DAYS == 0:
			msg["h"] = _hashes[t][0]
			_hashes.erase(t)
		outbox.append({"to": HOST, "msg": msg})
	return true


## Reçoit un morceau de trame (des deux côtés ; l'hôte se l'envoie à lui-même).
func receive_frame(t: int, cmds: Array, sealed: bool) -> void:
	if t < tick():
		return  # déjà joué (ne devrait pas arriver)
	var f: Dictionary = _frames.get(t, {"cmds": [], "sealed": false, "applied": 0})
	for c in cmds:
		f["cmds"].append(c)
	if sealed:
		f["sealed"] = true
		sealed_until = maxi(sealed_until, t)
	_frames[t] = f
	if t == tick():
		_apply_frame(t)  # en pause, les ordres s'appliquent tout de suite


func _apply_frame(t: int) -> void:
	var f: Dictionary = _frames.get(t, {})
	if f.is_empty():
		return
	var cmds: Array = f["cmds"]
	var start: int = f["applied"]
	for i in range(start, cmds.size()):
		sim.submit((cmds[i] as Dictionary).duplicate(true))
	f["applied"] = cmds.size()
	sim.flush_commands()


# --- Hôte ------------------------------------------------------------------------------------

## Un pair (ou l'hôte lui-même) demande un ordre. Renvoie la raison d'un refus, "" s'il est accepté.
## Un joueur ne commande que son empire ; « seat » (qui dirige quel empire) est réservé à l'hôte.
func request(peer: int, cmd: Dictionary) -> String:
	if not is_host:
		return "seul l'hôte range les ordres"
	var clean := cmd.duplicate(true)
	clean.erase("seq")
	clean.erase("tick")
	if String(clean.get("type", "")) == "seat":
		if peer != HOST:
			return "ordre réservé à l'hôte"
	elif not seats.has(peer) or int(clean.get("player", -1)) != int(seats[peer]):
		return "cet empire n'est pas le vôtre"
	_pending.append(clean)
	return ""


## Scelle les trames jusqu'au jour `until` ; les ordres en attente vont dans la première.
func seal_until(until: int) -> void:
	while sealed_until < until:
		var t := sealed_until + 1
		_emit_frame(t, _pending, true)
		_pending = []


## En pause, au jour Q : envoie les ordres en attente comme un morceau de la trame Q, non scellée.
func flush_paused() -> void:
	if _pending.is_empty() or sealed_until >= tick():
		return
	_emit_frame(tick(), _pending, false)
	_pending = []


func _emit_frame(t: int, cmds: Array, sealed: bool) -> void:
	outbox.append({"to": 0, "msg": {"k": "frame", "t": t, "c": cmds, "s": sealed}})
	receive_frame(t, cmds.duplicate(true), sealed)


## L'hôte peut-il avancer sans distancer le client le plus lent ?
func host_may_step() -> bool:
	return slowest() < 0 or tick() < int(acks[slowest()]) + max_lead


## Pair le plus en retard (-1 : aucun client).
func slowest() -> int:
	var best := -1
	for p in acks:
		if best < 0 or int(acks[p]) < int(acks[best]):
			best = p
	return best


## Message d'un client (accusé de réception et somme de contrôle).
func host_receive_ack(peer: int, t: int, h := "") -> void:
	acks[peer] = maxi(int(acks.get(peer, 0)), t)
	if h != "":
		_record_hash(peer, t, h)


func _record_hash(peer: int, t: int, h: String) -> void:
	var by: Dictionary = _hashes.get(t, {})
	by[peer] = h
	_hashes[t] = by
	if not is_host:
		return
	# On compare dès que l'hôte et ce pair ont tous deux leur somme pour ce jour.
	if by.has(HOST):
		for p in by:
			if p != HOST and by[p] != by[HOST]:
				desync_detected.emit(p, t)
				by.erase(p)  # signalé une fois
		if by.size() == 1 and t < tick() - CHECK_DAYS * 3:
			_hashes.erase(t)


## Ajoute un client qui dirigera `empire_id` et part de l'état courant.
func add_peer(peer: int, empire_id: int) -> void:
	seats[peer] = empire_id
	acks[peer] = tick()


func remove_peer(peer: int) -> void:
	seats.erase(peer)
	acks.erase(peer)


## Morceaux de la trame courante déjà appliqués (l'état envoyé à un nouveau venu les contient déjà).
func open_frame_for_newcomer() -> Dictionary:
	return {"t": tick(), "sealed_until": sealed_until}
