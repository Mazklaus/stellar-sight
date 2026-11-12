extends Node
## Horloge du jeu (autoload « GameClock ») : le pilote de la simulation.
## Elle transforme le temps réel en ticks à pas fixe et appelle Simulation.step().
## Elle ne contient aucun état de partie : pause et vitesse sont des réglages locaux.
## En multijoueur, une NetSession prend la main (driver) : elle fait avancer la simulation au rythme
## de l'hôte, et pause et vitesse deviennent des demandes partagées (voir NetSession).
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
## Minuteurs de tour en réseau (l'hôte les fait respecter) : aucun ; « fixe » : chaque tour dure au plus
## s secondes ; « dernier » : quand un seul joueur n'a pas terminé, il a s secondes.
const TURN_TIMERS: Array[Dictionary] = [
	{"id": "", "label": "Aucun minuteur", "mode": "", "s": 0},
	{"id": "fixe-60", "label": "1 min par tour", "mode": "fixe", "s": 60},
	{"id": "fixe-120", "label": "2 min par tour", "mode": "fixe", "s": 120},
	{"id": "fixe-180", "label": "3 min par tour", "mode": "fixe", "s": 180},
	{"id": "fixe-300", "label": "5 min par tour", "mode": "fixe", "s": 300},
	{"id": "dernier-30", "label": "Dernier joueur : 30 s", "mode": "dernier", "s": 30},
	{"id": "dernier-60", "label": "Dernier joueur : 1 min", "mode": "dernier", "s": 60},
	{"id": "dernier-120", "label": "Dernier joueur : 2 min", "mode": "dernier", "s": 120},
]
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
## Multijoueur : la session qui pilote la simulation à la place de l'horloge locale (null en solo).
## Elle doit offrir clock_process(delta), request_pause(bool), request_speed(int), request_toggle()
## et day_fraction().
var driver: Object = null
## Multijoueur au tour par tour : le joueur local a terminé son tour et attend les autres.
var net_ready := false
## Multijoueur au tour par tour : noms des joueurs qui n'ont pas encore terminé leur tour.
var net_waiting: Array[String] = []
## Multijoueur au tour par tour : les joueurs de la partie et où ils en sont :
## [{"name", "color" (Color), "ready" (tour terminé), "me" (le joueur local)}].
var net_players: Array[Dictionary] = []
## Minuteur de tour choisi pour les parties en réseau (TURN_TIMERS), gardé dans la sauvegarde.
var turn_timer := ""
## Multijoueur : instant (Time.get_ticks_msec) où le minuteur force la fin du tour, -1 sans minuteur.
var net_timer_end_ms := -1


static func timer_info(id: String) -> Dictionary:
	for t in TURN_TIMERS:
		if t["id"] == id:
			return t
	return TURN_TIMERS[0]


## Secondes avant que le minuteur force la fin du tour, -1 s'il ne court pas.
func timer_left() -> int:
	if net_timer_end_ms < 0 or driver == null:
		return -1
	return maxi(0, ceili((net_timer_end_ms - Time.get_ticks_msec()) / 1000.0))


## Branche l'horloge sur une simulation (nouvelle partie ou partie chargée). Le jeu repart en pause.
func attach(sim: Simulation) -> void:
	if simulation and simulation.ticked.is_connected(_on_ticked):
		simulation.ticked.disconnect(_on_ticked)
	simulation = sim
	if simulation:
		simulation.ticked.connect(_on_ticked)
	_accumulator = 0.0
	_turn_target = -1
	_set_running(false)
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
	if driver != null:
		if mode != MODE_TURNS or _turn_target >= 0 or net_ready:
			return false
		driver.request_toggle()
		return true
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
	if driver != null:
		driver.clock_process(delta)
		return
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
		if paused:
			return  # tour interrompu pendant ce jour (bataille engagée)
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
	if driver != null:
		return driver.day_fraction()
	if paused or simulation == null:
		return 0.0
	return clampf(_accumulator / _seconds_per_day(), 0.0, 1.0)


func _seconds_per_day() -> float:
	return TURN_SECONDS_PER_DAY if mode == MODE_TURNS else SECONDS_PER_DAY[speed_index]


## Interrompt le tour en cours de résolution (une bataille vient de s'engager) : le jeu s'arrête
## pour laisser le joueur choisir sa tactique ou sonner la retraite ; le prochain « Fin de tour »
## joue le reste du tour (le découpage en tours ne change pas). Sans effet hors tour par tour.
func interrupt_turn() -> bool:
	if mode != MODE_TURNS or _turn_target < 0:
		return false
	if driver != null:
		# En réseau, la pause est commune : tout le monde s'arrête au même jour.
		driver.request_pause(true)
		return true
	_finish_turn()
	return true


func _finish_turn() -> void:
	_turn_target = -1
	_set_running(false)
	turn_started.emit(turn())


func _on_ticked(tick: int) -> void:
	day_passed.emit(tick)


## Pause ou reprise. Au tour par tour, reprendre ne fait que continuer un tour déjà lancé
## (après un menu, par exemple) : seul end_turn() lance un nouveau tour.
func set_paused(value: bool) -> void:
	if driver != null:
		if value != paused:
			driver.request_pause(value)
		return
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
	if driver != null:
		driver.request_toggle()
		return
	if mode == MODE_TURNS:
		if paused and _turn_target < 0:
			end_turn()
		else:
			set_paused(not paused)
		return
	set_paused(not paused)


func set_speed(index: int) -> void:
	if driver != null:
		driver.request_speed(index)
		return
	var clamped := clampi(index, 0, SECONDS_PER_DAY.size() - 1)
	if clamped == speed_index:
		return
	speed_index = clamped
	speed_changed.emit(speed_index)


## Multijoueur : la session impose la pause, la vitesse et la façon de jouer partagées (affichage
## seulement). net_mode < 0 laisse le mode tel quel ; target : fin du tour en cours de résolution (-1 : aucun).
func net_sync(is_paused: bool, speed: int, net_mode := -1, days := 0, target := -1) -> void:
	if net_mode >= 0:
		if days > 0:
			turn_days = days
		var was_resolving := _turn_target >= 0
		_turn_target = target if net_mode == MODE_TURNS else -1
		if net_mode != mode:
			mode = net_mode
			mode_changed.emit(mode)
		if was_resolving and _turn_target < 0 and is_paused and day % turn_days == 0:
			turn_started.emit(turn())
	if paused != is_paused:
		paused = is_paused
		pause_changed.emit(paused)
	var clamped := clampi(speed, 0, SECONDS_PER_DAY.size() - 1)
	if clamped != speed_index:
		speed_index = clamped
		speed_changed.emit(speed_index)


## Réglages à ranger dans une sauvegarde (voir SaveGame.save_state).
func settings() -> Dictionary:
	var out := {"mode": "turns" if mode == MODE_TURNS else "realtime", "turn_days": turn_days}
	if turn_timer != "":
		out["timer"] = turn_timer
	return out


## Réapplique des réglages lus dans une sauvegarde ; vide = temps réel (anciennes sauvegardes).
func apply_settings(d: Dictionary) -> void:
	var days := int(d.get("turn_days", DEFAULT_TURN_DAYS))
	set_mode(MODE_TURNS if d.get("mode", "") == "turns" else MODE_REALTIME, maxi(days, 1))
	turn_timer = String(timer_info(String(d.get("timer", "")))["id"])


func date_string() -> String:
	return GameCalendar.date_string(day)
