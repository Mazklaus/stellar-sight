extends Node2D
## Point d'entrée : crée la simulation, la vue, la caméra et l'interface,
## et traduit les entrées du joueur en réglages d'horloge, en sélection ou en ordres.
## Rien ici ne modifie l'état de partie directement : tout passe par Simulation.submit().

const SYSTEM_COUNT := 150
const GALAXY_RADIUS := 1800.0
const PICK_RADIUS_PX := 14.0
const START_ZOOM := 0.22
## Zoom de départ, centré sur le système d'origine du joueur.
const HOME_ZOOM := 0.45
## Identifiant du joueur local. En multijoueur, chaque machine aura le sien.
const LOCAL_PLAYER := 0

var simulation: Simulation
## Fichier de sauvegarde rapide (F5 / F9). Les tests le redirigent ailleurs.
var save_path := SaveGame.QUICKSAVE_PATH
## Faction du joueur local pour les nouvelles parties (le choix en début de partie viendra avec les factions jouables).
var player_faction := "ossarane"
## Raccourci vers la galaxie de la partie en cours.
var galaxy: Galaxy:
	get:
		return simulation.state.galaxy if simulation else null

var _view: GalaxyView
var _camera: GalaxyCamera
var _hud: Hud


func _ready() -> void:
	randomize()
	_view = GalaxyView.new()
	add_child(_view)
	_camera = GalaxyCamera.new()
	add_child(_camera)
	_camera.make_current()
	_hud = Hud.new()
	add_child(_hud)
	_hud.rename_requested.connect(_on_rename_requested)
	_hud.colonize_requested.connect(func(planet_id: int, kind: String) -> void:
		simulation.submit(SimCommands.colonize(LOCAL_PLAYER, planet_id, kind)))
	_hud.build_requested.connect(func(planet_id: int, building_id: String) -> void:
		simulation.submit(SimCommands.build(LOCAL_PLAYER, planet_id, building_id)))
	new_game(randi())


func new_game(seed_value: int) -> void:
	_start(GameState.create(seed_value, SYSTEM_COUNT, GALAXY_RADIUS, player_faction))
	# On commence chez soi : caméra sur le système d'origine, fiche ouverte.
	var me := simulation.state.get_empire(LOCAL_PLAYER)
	if me:
		var home := galaxy.get_planet(me.capital_planet).system_id
		_camera.position = galaxy.get_system(home).position
		_camera.zoom = Vector2(HOME_ZOOM, HOME_ZOOM)
		_select(home)
	else:
		_camera.position = Vector2.ZERO
		_camera.zoom = Vector2(START_ZOOM, START_ZOOM)


func save_game() -> void:
	if SaveGame.save_state(simulation.state, save_path) == OK:
		_hud.notify("Partie sauvegardée (%s)" % GameCalendar.date_string(simulation.state.tick))
	else:
		_hud.notify("Échec de la sauvegarde : %s" % SaveGame.last_error)


func load_game() -> void:
	var state := SaveGame.load_state(save_path)
	if state == null:
		_hud.notify("Chargement impossible : %s" % SaveGame.last_error)
		return
	_start(state)
	_hud.notify("Partie chargée (%s)" % GameCalendar.date_string(state.tick))


func _start(state: GameState) -> void:
	simulation = Simulation.new(state)
	simulation.command_applied.connect(_on_command_applied)
	simulation.command_rejected.connect(func(_cmd: Dictionary, reason: String) -> void:
		_hud.notify("Ordre refusé : %s" % reason))
	simulation.chronicle_added.connect(_hud.show_chronicle)
	simulation.ticked.connect(func(_tick: int) -> void:
		_view.queue_redraw()
		_hud.refresh())
	_view.set_state(state)
	_hud.set_state(state, LOCAL_PLAYER)
	_hud.set_galaxy_info(state.seed_value, state.galaxy.systems.size())
	_hud.show_system(null, state)
	_hud.show_chronicle(state.chronicle.back() if not state.chronicle.is_empty() else {})
	GameClock.attach(simulation)


func _on_rename_requested(system_id: int, new_name: String) -> void:
	simulation.submit(SimCommands.rename_system(LOCAL_PLAYER, system_id, new_name))


func _on_command_applied(_cmd: Dictionary) -> void:
	_view.queue_redraw()
	_hud.refresh()
	if not simulation.state.chronicle.is_empty():
		_hud.show_chronicle(simulation.state.chronicle.back())


func _process(_delta: float) -> void:
	if galaxy == null:
		return
	var id := _pick_system()
	if id != _view.hovered_id:
		_view.hovered_id = id
		_view.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_select(_pick_system_at(mb.position))
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		GameClock.toggle_pause()
	elif key.keycode == KEY_R:
		new_game(randi())
	elif key.keycode == KEY_F5:
		save_game()
	elif key.keycode == KEY_F9:
		load_game()
	elif key.keycode == KEY_ESCAPE:
		_select(-1)
	else:
		# Touches physiques 1 à 5 (rangée du haut, même sur AZERTY) ou pavé numérique.
		var speed := _speed_from_key(key)
		if speed >= 0:
			GameClock.set_speed(speed)


func _select(id: int) -> void:
	_view.selected_id = id
	_view.queue_redraw()
	_hud.show_system(galaxy.get_system(id), simulation.state)


func _speed_from_key(key: InputEventKey) -> int:
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_5:
		return key.physical_keycode - KEY_1
	if key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_5:
		return key.keycode - KEY_KP_1
	return -1


func _pick_system() -> int:
	return galaxy.find_nearest(get_global_mouse_position(), PICK_RADIUS_PX / _camera.zoom.x)


## Système sous une position écran (celle d'un événement de clic, par exemple).
func _pick_system_at(screen_pos: Vector2) -> int:
	var world_pos := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return galaxy.find_nearest(world_pos, PICK_RADIUS_PX / _camera.zoom.x)
