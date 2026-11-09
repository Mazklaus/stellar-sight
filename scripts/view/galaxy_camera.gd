class_name GalaxyCamera
extends Camera2D
## Caméra de la carte : molette pour zoomer vers le curseur,
## clic droit ou molette enfoncée pour glisser, ZQSD (WASD en QWERTY) ou flèches pour se déplacer.

const MIN_ZOOM := 0.12
const MAX_ZOOM := 3.0
const ZOOM_STEP := 1.12
const PAN_SPEED := 900.0

var _dragging := false
var _glide: Tween


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(ZOOM_STEP, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(1.0 / ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			stop_glide()
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
		stop_glide()
		position += dir.normalized() * PAN_SPEED * delta / zoom.x


## Zoome en gardant fixe le point du monde situé sous screen_pos.
func zoom_at(factor: float, screen_pos: Vector2) -> void:
	stop_glide()
	var half_view := get_viewport_rect().size * 0.5
	var offset_on_screen := screen_pos - half_view
	var world_under_cursor := position + offset_on_screen / zoom.x
	var new_zoom := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
	position = world_under_cursor - offset_on_screen / new_zoom


## Glisse en douceur vers une position du monde (et un zoom, si target_zoom > 0).
func glide_to(target: Vector2, target_zoom := -1.0, duration := 0.45) -> void:
	if _glide and _glide.is_valid():
		_glide.kill()
	_glide = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_glide.tween_property(self, "position", target, duration)
	if target_zoom > 0.0:
		var z := clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
		_glide.tween_property(self, "zoom", Vector2(z, z), duration)


## Arrête un glissement en cours (le joueur reprend la main).
func stop_glide() -> void:
	if _glide and _glide.is_valid():
		_glide.kill()
