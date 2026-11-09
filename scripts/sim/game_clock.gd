extends Node
## Horloge du jeu (autoload « GameClock ») : le pilote de la simulation en temps réel pausable.
## Elle transforme le temps réel en ticks à pas fixe et appelle Simulation.step().
## Elle ne contient aucun état de partie : pause et vitesse sont des réglages locaux.
## En multijoueur, seul l'hôte fera avancer la simulation ; les clients suivront ses ticks.

signal day_passed(day: int)
signal speed_changed(speed_index: int)
signal pause_changed(paused: bool)

## Secondes réelles par jour de jeu, pour les vitesses 1 à 5.
const SECONDS_PER_DAY: Array[float] = [1.0, 0.5, 0.25, 0.1, 0.04]
const MAX_DAYS_PER_FRAME := 8

var simulation: Simulation
var speed_index: int = 1
var paused: bool = true
## Jour de jeu courant (lecture seule : c'est le tick de la simulation).
var day: int:
	get:
		return simulation.state.tick if simulation else 0

var _accumulator: float = 0.0


## Branche l'horloge sur une simulation (nouvelle partie ou partie chargée). Le jeu repart en pause.
func attach(sim: Simulation) -> void:
	if simulation and simulation.ticked.is_connected(_on_ticked):
		simulation.ticked.disconnect(_on_ticked)
	simulation = sim
	if simulation:
		simulation.ticked.connect(_on_ticked)
	_accumulator = 0.0
	set_paused(true)
	day_passed.emit(day)


func _process(delta: float) -> void:
	if simulation == null:
		return
	if paused:
		# Les ordres donnés pendant la pause s'appliquent tout de suite, sans faire passer le temps.
		simulation.flush_commands()
		return
	_accumulator += delta
	var step := SECONDS_PER_DAY[speed_index]
	var processed := 0
	while _accumulator >= step and processed < MAX_DAYS_PER_FRAME:
		_accumulator -= step
		processed += 1
		simulation.step()
	if processed >= MAX_DAYS_PER_FRAME:
		# La machine n'arrive pas à suivre : on ralentit plutôt que d'accumuler du retard.
		_accumulator = 0.0
	if processed == 0:
		simulation.flush_commands()


## Fraction du jour en cours déjà écoulée (0 à 1), pour animer les flottes entre deux ticks.
func day_fraction() -> float:
	if paused or simulation == null:
		return 0.0
	return clampf(_accumulator / SECONDS_PER_DAY[speed_index], 0.0, 1.0)


func _on_ticked(tick: int) -> void:
	day_passed.emit(tick)


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	_accumulator = 0.0
	pause_changed.emit(paused)


func toggle_pause() -> void:
	set_paused(not paused)


func set_speed(index: int) -> void:
	var clamped := clampi(index, 0, SECONDS_PER_DAY.size() - 1)
	if clamped == speed_index:
		return
	speed_index = clamped
	speed_changed.emit(speed_index)


func date_string() -> String:
	return GameCalendar.date_string(day)
