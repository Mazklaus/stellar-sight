class_name GalaxyCamera
extends Camera2D
## Caméra de la carte : molette pour zoomer vers le curseur,
## clic droit ou molette enfoncée pour glisser, ZQSD (WASD en QWERTY) ou flèches pour se déplacer.

const MIN_ZOOM := 0.12
const MAX_ZOOM := 3.0
const ZOOM_STEP := 1.12
const PAN_SPEED := 900.0

var _dragging := false


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(ZOOM_STEP, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(1.0 / ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		position -= motion.relative / zoom


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	# Touches physiques : la même position sur un clavier AZERTY (ZQSD) ou QWERTY (WASD).
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x


## Zoome en gardant fixe le point du monde situé sous screen_pos.
func zoom_at(factor: float, screen_pos: Vector2) -> void:
	var half_view := get_viewport_rect().size * 0.5
	var offset_on_screen := screen_pos - half_view
	var world_under_cursor := position + offset_on_screen / zoom.x
	var new_zoom := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
	position = world_under_cursor - offset_on_screen / new_zoom
