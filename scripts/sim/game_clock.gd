extends Node
## Horloge du jeu (autoload « GameClock ») : le pilote de la simulation.
## Elle transforme le temps réel en ticks à pas fixe et appelle Simulation.step().
## Elle ne contient aucun état de partie : pause et vitesse sont des réglages locaux.
## En multijoueur, seul l'hôte fera avancer la simulation ; les clients suivront ses ticks.
##
## Deux façons de jouer, au choix à la création de la partie :
## - temps réel pausable (MODE_REALTIME) : le temps file, on met en pause quand on veut ;
## - tour par tour (MODE_TURNS) : le temps est arrêté pendant qu'on donne ses ordres, puis
##   « Fin de tour » fait passer turn_days jours d'un coup (en accéléré, pour voir les flottes
##   bouger) et le jeu s'arrête de nouveau au début du tour suivant.
## La simulation ne sait rien de ce choix : un tour n'est qu'une suite de ticks ordinaires.
## Une partie au tour par tour et une partie en temps réel restent donc parfaitement
## compatibles (mêmes règles, mêmes sauvegardes, même déterminisme).

signal day_passed(day: int)
signal speed_changed(speed_index: int)
signal pause_changed(paused: bool)
signal mode_changed(mode: int)
## Un tour vient de se terminer : le jeu est de nouveau arrêté, au début du tour « turn ».
signal turn_started(turn: int)

enum { MODE_REALTIME, MODE_TURNS }

## Secondes réelles par jour de jeu, pour les vitesses 1 à 5.
const SECONDS_PER_DAY: Array[float] = [1.0, 0.5, 0.25, 0.1, 0.04]
const MAX_DAYS_PER_FRAME := 8
## Durées de tour proposées (jours de jeu), et celle par défaut.
const TURN_LENGTHS: Array[int] = [5, 10, 30]
const DEFAULT_TURN_DAYS := 10
## Pendant la résolution d'un tour, les jours défilent à cette cadence (secondes réelles par jour).
const TURN_SECONDS_PER_DAY := 0.06

var simulation: Simulation
var speed_index: int = 1
var paused: bool = true
var mode: int = MODE_REALTIME
## Longueur d'un tour en jours de jeu (mode tour par tour seulement).
var turn_days: int = DEFAULT_TURN_DAYS
## Tick auquel le tour en cours de résolution s'arrêtera, ou -1 si aucun tour n'est en cours.
var _turn_target: int = -1
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
	_turn_target = -1
	set_paused(true)
	day_passed.emit(day)


## Choisit la façon de jouer. Le jeu s'arrête ; un tour en cours de résolution est abandonné
## (les jours déjà passés restent passés).
func set_mode(new_mode: int, days := -1) -> void:
	if days > 0:
		turn_days = days
	_turn_target = -1
	set_paused(true)
	if new_mode == mode:
		return
	mode = new_mode
	mode_changed.emit(mode)


func is_turn_based() -> bool:
	return mode == MODE_TURNS


## Numéro du tour en cours (1 au premier jour). Les tours sont calés sur des multiples
## de turn_days, pour qu'un chargement ou un changement de mode retombe sur le même découpage.
func turn() -> int:
	return day / turn_days + 1


## Le tour est-il en train de se jouer (les jours défilent) ?
func is_resolving_turn() -> bool:
	return _turn_target >= 0


## Termine le tour : les ordres s'appliquent et les jours défilent jusqu'au début du tour suivant.
## Sans effet en temps réel ou si un tour est déjà en cours de résolution.
## En multijoueur, l'hôte l'appellera quand tous les joueurs auront terminé leur tour
## (tours simultanés, comme Endless Space 2).
func end_turn() -> bool:
	if mode != MODE_TURNS or simulation == null or _turn_target >= 0:
		return false
	_turn_target = turn() * turn_days
	_set_running(true)
	return true


## Fraction du tour en cours déjà jouée (0 à 1), pour l'affichage.
func turn_progress() -> float:
	if _turn_target < 0:
		return 0.0
	return clampf(1.0 - float(_turn_target - day) / float(turn_days), 0.0, 1.0)


func _process(delta: float) -> void:
	if simulation == null:
		return
	if paused:
		# Les ordres donnés pendant la pause s'appliquent tout de suite, sans faire passer le temps.
		simulation.flush_commands()
		return
	_accumulator += delta
	var step := _seconds_per_day()
	var processed := 0
	while _accumulator >= step and processed < MAX_DAYS_PER_FRAME:
		_accumulator -= step
		processed += 1
		simulation.step()
		if _turn_target >= 0 and day >= _turn_target:
			_finish_turn()
			return
	if processed >= MAX_DAYS_PER_FRAME:
		# La machine n'arrive pas à suivre : on ralentit plutôt que d'accumuler du retard.
		_accumulator = 0.0
	if processed == 0:
		simulation.flush_commands()


## Fraction du jour en cours déjà écoulée (0 à 1), pour animer les flottes entre deux ticks.
func day_fraction() -> float:
	if paused or simulation == null:
		return 0.0
	return clampf(_accumulator / _seconds_per_day(), 0.0, 1.0)


func _seconds_per_day() -> float:
	return TURN_SECONDS_PER_DAY if mode == MODE_TURNS else SECONDS_PER_DAY[speed_index]


func _finish_turn() -> void:
	_turn_target = -1
	_set_running(false)
	turn_started.emit(turn())


func _on_ticked(tick: int) -> void:
	day_passed.emit(tick)


## Pause ou reprise. Au tour par tour, reprendre ne fait que continuer un tour déjà lancé
## (après un menu, par exemple) : seul end_turn() lance un nouveau tour.
func set_paused(value: bool) -> void:
	if not value and mode == MODE_TURNS and _turn_target < 0:
		return
	_set_running(not value)


func _set_running(running: bool) -> void:
	if paused == not running:
		return
	paused = not running
	_accumulator = 0.0
	pause_changed.emit(paused)


## Espace et le centre du cadran : pause / reprise en temps réel, fin de tour au tour par tour.
func toggle_pause() -> void:
	if mode == MODE_TURNS:
		if paused and _turn_target < 0:
			end_turn()
		else:
			set_paused(not paused)
		return
	set_paused(not paused)


func set_speed(index: int) -> void:
	var clamped := clampi(index, 0, SECONDS_PER_DAY.size() - 1)
	if clamped == speed_index:
		return
	speed_index = clamped
	speed_changed.emit(speed_index)


## Réglages à ranger dans une sauvegarde (voir SaveGame.save_state).
func settings() -> Dictionary:
	return {"mode": "turns" if mode == MODE_TURNS else "realtime", "turn_days": turn_days}


## Réapplique des réglages lus dans une sauvegarde ; vide = temps réel (anciennes sauvegardes).
func apply_settings(d: Dictionary) -> void:
	var days := int(d.get("turn_days", DEFAULT_TURN_DAYS))
	set_mode(MODE_TURNS if d.get("mode", "") == "turns" else MODE_REALTIME, maxi(days, 1))


func date_string() -> String:
	return GameCalendar.date_string(day)
