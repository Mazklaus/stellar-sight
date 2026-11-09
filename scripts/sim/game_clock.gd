extends Node
## Horloge du jeu (autoload « GameClock »). Temps réel pausable :
## la simulation avance par jours de jeu, à pas fixe, quelle que soit la cadence d'affichage.
## Un jour = un tick de simulation. En multijoueur, seul l'hôte fera avancer cette horloge.

signal day_passed(day: int)
signal speed_changed(speed_index: int)
signal pause_changed(paused: bool)

## Secondes réelles par jour de jeu, pour les vitesses 1 à 5.
const SECONDS_PER_DAY: Array[float] = [1.0, 0.5, 0.25, 0.1, 0.04]
const START_YEAR := 2400
const DAYS_PER_MONTH := 30
const DAYS_PER_YEAR := 360
const MAX_DAYS_PER_FRAME := 8

var day: int = 0
var speed_index: int = 1
var paused: bool = true

var _accumulator: float = 0.0


func _process(delta: float) -> void:
	if paused:
		return
	_accumulator += delta
	var step := SECONDS_PER_DAY[speed_index]
	var processed := 0
	while _accumulator >= step and processed < MAX_DAYS_PER_FRAME:
		_accumulator -= step
		processed += 1
		day += 1
		day_passed.emit(day)
	if processed >= MAX_DAYS_PER_FRAME:
		# La machine n'arrive pas à suivre : on ralentit plutôt que d'accumuler du retard.
		_accumulator = 0.0


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


func reset() -> void:
	day = 0
	_accumulator = 0.0
	set_paused(true)
	day_passed.emit(day)


func date_string() -> String:
	@warning_ignore("integer_division")
	var year := START_YEAR + day / DAYS_PER_YEAR
	@warning_ignore("integer_division")
	var month := (day % DAYS_PER_YEAR) / DAYS_PER_MONTH + 1
	var day_of_month := day % DAYS_PER_MONTH + 1
	return "%02d/%02d/%d" % [day_of_month, month, year]
