class_name Simulation
extends RefCounted
## Le noyau de simulation : fait avancer un GameState tick par tick, de façon déterministe.
##
## Règles d'or :
## - Même état de départ + mêmes ordres appliqués aux mêmes ticks = même partie, à l'octet près.
## - Aucune notion de temps réel, d'affichage ou d'entrée ici : c'est GameClock qui décide
##   quand appeler step(), et la vue qui lit l'état.
## - L'aléatoire passe uniquement par state.rng.

signal ticked(tick: int)
signal command_applied(cmd: Dictionary)
signal command_rejected(cmd: Dictionary, reason: String)
signal chronicle_added(entry: Dictionary)

var state: GameState
## Ordres appliqués depuis le début de la session, avec le tick où ils l'ont été
## (clé "tick") et leur numéro d'ordre (clé "seq"). Suffit pour rejouer la partie.
var command_log: Array[Dictionary] = []

var _pending: Array[Dictionary] = []
var _next_seq := 0


func _init(initial_state: GameState) -> void:
	state = initial_state


## Soumet un ordre. Il sera appliqué à la prochaine frontière de tick
## (au prochain step(), ou dès flush_commands() si le jeu est en pause).
func submit(cmd: Dictionary) -> bool:
	var reason := SimCommands.validate(state, cmd)
	if reason != "":
		command_rejected.emit(cmd, reason)
		return false
	var queued := cmd.duplicate(true)
	queued["seq"] = _next_seq
	_next_seq += 1
	_pending.append(queued)
	return true


## Applique les ordres en attente au tick courant, sans faire avancer le temps.
## Permet de donner des ordres pendant la pause.
func flush_commands() -> void:
	if _pending.is_empty():
		return
	var batch := _pending
	_pending = []
	for cmd in batch:
		# L'état a pu changer depuis la soumission : on revalide au moment d'appliquer.
		var reason := SimCommands.validate(state, cmd)
		if reason != "":
			command_rejected.emit(cmd, reason)
			continue
		cmd["tick"] = state.tick
		SimCommands.apply(state, cmd)
		command_log.append(cmd)
		command_applied.emit(cmd)


func has_pending_commands() -> bool:
	return not _pending.is_empty()


## Avance d'un tick (un jour de jeu) : ordres en attente, puis chaque système, dans un ordre fixe.
func step() -> void:
	flush_commands()
	state.tick += 1
	for entry in EconomySystem.process(state):
		chronicle_added.emit(entry)
	for entry in FleetSystem.process(state):
		chronicle_added.emit(entry)
	for entry in ChronicleSystem.process(state):
		chronicle_added.emit(entry)
	ticked.emit(state.tick)


func advance(ticks: int) -> void:
	for _i in ticks:
		step()


## Rejoue un journal d'ordres sur un état de départ jusqu'au tick voulu.
## Sert aux tests, et plus tard aux rediffusions et à la reconnexion en multijoueur.
static func replay(initial_state: GameState, commands: Array[Dictionary], until_tick: int) -> Simulation:
	var sim := Simulation.new(initial_state)
	var i := 0
	while true:
		while i < commands.size() and int(commands[i]["tick"]) == sim.state.tick:
			var cmd: Dictionary = commands[i].duplicate(true)
			cmd.erase("tick")
			cmd.erase("seq")
			sim.submit(cmd)
			i += 1
		sim.flush_commands()
		if sim.state.tick >= until_tick:
			break
		sim.step()
	return sim
