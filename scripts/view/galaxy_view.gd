class_name GalaxyView
extends Node2D
## Affichage 2D de la galaxie. Ne modifie jamais la simulation : elle ne fait que la lire.
## C'est cette couche, et elle seule, qui sera remplacée lors du passage en 2,5D.

const STAR_COLORS := {
	"yellow": Color(1.0, 0.9, 0.55),
	"red": Color(1.0, 0.5, 0.35),
	"white": Color(0.92, 0.95, 1.0),
	"blue_giant": Color(0.55, 0.7, 1.0),
	"neutron": Color(0.7, 1.0, 0.95),
	"black_hole": Color(0.55, 0.3, 0.85),
}
const LANE_COLOR := Color(0.55, 0.7, 1.0)
const SELECT_COLOR := Color(1.0, 0.82, 0.3)
const LABEL_MIN_ZOOM := 0.5
const LABEL_FONT_SIZE := 13

var galaxy: Galaxy
var selected_id := -1
var hovered_id := -1

var _background := PackedVector2Array()
var _font: Font
var _last_zoom := -1.0


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_galaxy(value: Galaxy) -> void:
	galaxy = value
	selected_id = -1
	hovered_id = -1
	_make_background()
	queue_redraw()


func _process(_delta: float) -> void:
	# Les tailles sont exprimées en pixels écran : on redessine quand le zoom change.
	var z := _zoom()
	if not is_equal_approx(z, _last_zoom):
		_last_zoom = z
		queue_redraw()


func _zoom() -> float:
	var cam := get_viewport().get_camera_2d()
	return cam.zoom.x if cam else 1.0


func _make_background() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = galaxy.seed_value + 7
	_background = PackedVector2Array()
	for _i in 900:
		_background.append(Vector2(rng.randf_range(-3200.0, 3200.0), rng.randf_range(-3200.0, 3200.0)))


func _draw() -> void:
	if galaxy == null:
		return
	var px := 1.0 / _zoom()  # un pixel écran, en unités du monde

	for p in _background:
		draw_circle(p, 1.1 * px, Color(1, 1, 1, 0.22))

	for lane in galaxy.lanes:
		var a := galaxy.systems[lane.x].position
		var b := galaxy.systems[lane.y].position
		var lit := lane.x == selected_id or lane.y == selected_id
		var color := Color(LANE_COLOR, 0.75 if lit else 0.22)
		draw_line(a, b, color, (2.0 if lit else 1.0) * px, true)

	for s in galaxy.systems:
		_draw_system(s, px)

	var show_all_labels := _zoom() >= LABEL_MIN_ZOOM
	for s in galaxy.systems:
		if show_all_labels or s.id == selected_id or s.id == hovered_id:
			_draw_label(s, px)


func _draw_system(s: StarSystem, px: float) -> void:
	var color: Color = STAR_COLORS.get(s.star_type, Color.WHITE)
	var r := (6.5 if s.star_type == "blue_giant" else 4.5) * px
	draw_circle(s.position, r * 2.8, Color(color, 0.12))
	if s.star_type == "black_hole":
		draw_circle(s.position, r, Color.BLACK)
		draw_arc(s.position, r * 1.3, 0.0, TAU, 24, color, 1.5 * px, true)
	else:
		draw_circle(s.position, r, color)
	if s.id == hovered_id and s.id != selected_id:
		draw_arc(s.position, r * 2.4, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 1.5 * px, true)
	if s.id == selected_id:
		draw_arc(s.position, r * 2.8, 0.0, TAU, 40, SELECT_COLOR, 2.0 * px, true)


func _draw_label(s: StarSystem, px: float) -> void:
	# On annule le zoom localement pour que le texte reste net et de taille constante.
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var color := SELECT_COLOR if s.id == selected_id else Color(0.85, 0.88, 0.95, 0.85)
	draw_string(_font, Vector2(10, 4), s.system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
