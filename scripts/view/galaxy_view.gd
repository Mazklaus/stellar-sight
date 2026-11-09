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
## Rayon du halo de territoire autour d'un système revendiqué, en unités du monde.
const TERRITORY_RADIUS := 85.0

var state: GameState
var galaxy: Galaxy
var selected_id := -1
var hovered_id := -1

var _background := PackedVector2Array()
var _font: Font
var _last_zoom := -1.0


func _ready() -> void:
	_font = ThemeDB.fallback_font


func set_state(value: GameState) -> void:
	state = value
	galaxy = value.galaxy if value else null
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

	_draw_territory()

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


## Territoire : une zone à la couleur de l'empire autour de ses systèmes et le long de ses routes.
## Couleur opaque (fond teinté) plutôt que transparente : les zones qui se chevauchent
## se fondent en une seule tache au lieu de s'assombrir par endroits.
func _draw_territory() -> void:
	if state == null:
		return
	var bg: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.BLACK)
	for lane in galaxy.lanes:
		var oa := state.system_owner(lane.x)
		if oa != -1 and oa == state.system_owner(lane.y):
			var tint := bg.lerp(state.get_empire(oa).color(), 0.13)
			draw_line(galaxy.systems[lane.x].position, galaxy.systems[lane.y].position, tint, TERRITORY_RADIUS * 1.1)
	for s in galaxy.systems:
		var owner := state.get_empire(state.system_owner(s.id))
		if owner:
			draw_circle(s.position, TERRITORY_RADIUS, bg.lerp(owner.color(), 0.13))


func _draw_system(s: StarSystem, px: float) -> void:
	var color: Color = STAR_COLORS.get(s.star_type, Color.WHITE)
	var r := (6.5 if s.star_type == "blue_giant" else 4.5) * px
	_draw_claims(s, r, px)
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


## Anneau à la couleur du propriétaire (pointillé tant qu'une fondation est en cours),
## et un losange pour une capitale.
func _draw_claims(s: StarSystem, r: float, px: float) -> void:
	if state == null:
		return
	var owner := state.get_empire(state.system_owner(s.id))
	if owner == null:
		return
	var established := false
	var capital := false
	for pid in s.planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c and c.is_established():
			established = true
		if owner.capital_planet == pid:
			capital = true
	var col := owner.color()
	if established:
		draw_arc(s.position, r * 1.9, 0.0, TAU, 32, col, 2.0 * px, true)
	else:
		for i in 8:
			var a := TAU * i / 8.0
			draw_arc(s.position, r * 1.9, a, a + TAU / 16.0, 4, col, 2.0 * px, true)
	if capital:
		var d := r * 1.2
		var top := s.position + Vector2(0, -r * 3.2)
		draw_colored_polygon(PackedVector2Array([top + Vector2(0, -d), top + Vector2(d * 0.7, 0), top + Vector2(0, d), top + Vector2(-d * 0.7, 0)]), col)


func _draw_label(s: StarSystem, px: float) -> void:
	# On annule le zoom localement pour que le texte reste net et de taille constante.
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var color := SELECT_COLOR if s.id == selected_id else Color(0.85, 0.88, 0.95, 0.85)
	draw_string(_font, Vector2(10, 4), s.system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
