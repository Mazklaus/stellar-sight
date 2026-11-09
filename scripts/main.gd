extends Node2D
## Point d'entrée du prototype : crée la galaxie, la vue, la caméra et l'interface,
## et relie les entrées du joueur à l'horloge et à la sélection.

const SYSTEM_COUNT := 150
const GALAXY_RADIUS := 1800.0
const PICK_RADIUS_PX := 14.0
const START_ZOOM := 0.22

var galaxy: Galaxy

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
	_new_galaxy(randi())


func _new_galaxy(seed_value: int) -> void:
	galaxy = GalaxyGenerator.generate(seed_value, SYSTEM_COUNT, GALAXY_RADIUS)
	_view.set_galaxy(galaxy)
	_hud.set_galaxy_info(seed_value, galaxy.systems.size())
	_hud.show_system(null, galaxy)
	_camera.position = Vector2.ZERO
	_camera.zoom = Vector2(START_ZOOM, START_ZOOM)
	GameClock.reset()


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
		var id := _pick_system()
		_view.selected_id = id
		_view.queue_redraw()
		_hud.show_system(galaxy.get_system(id), galaxy)
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		GameClock.toggle_pause()
	elif key.keycode == KEY_R:
		_new_galaxy(randi())
	elif key.keycode == KEY_ESCAPE:
		_view.selected_id = -1
		_view.queue_redraw()
		_hud.show_system(null, galaxy)
	else:
		# Touches physiques 1 à 5 (rangée du haut, même sur AZERTY) ou pavé numérique.
		var speed := _speed_from_key(key)
		if speed >= 0:
			GameClock.set_speed(speed)


func _speed_from_key(key: InputEventKey) -> int:
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_5:
		return key.physical_keycode - KEY_1
	if key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_5:
		return key.keycode - KEY_KP_1
	return -1


func _pick_system() -> int:
	return galaxy.find_nearest(get_global_mouse_position(), PICK_RADIUS_PX / _camera.zoom.x)
