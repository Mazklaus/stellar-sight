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
const SELECT_COLOR := Color(0.38, 0.86, 0.92)
const LABEL_MIN_ZOOM := 0.5
const LABEL_FONT_SIZE := 13
## Zoom à partir duquel tous les systèmes montrent leurs pastilles de planètes.
const PLANET_DOTS_MIN_ZOOM := 0.8
## Rayon du halo de territoire autour d'un système revendiqué, en unités du monde.
const TERRITORY_RADIUS := 85.0

var state: GameState
var galaxy: Galaxy
var selected_id := -1
var hovered_id := -1
## Joueur dont on montre le point de vue (lentille économique).
var viewer := 0
## Lentille : "" (normale) ou "economy" (bilan mensuel de chaque système du joueur).
var lens := ""
## Flotte sélectionnée (-1 si aucune) : mise en valeur, avec son trajet.
var selected_fleet := -1
## Brouillard de guerre actif (désactivable pour le débogage et certaines captures).
var fog := true
## Fraction de jour écoulée, fournie par l'horloge, pour animer les flottes entre deux ticks.
var day_fraction := 0.0

## Systèmes vus en ce moment par le joueur, recalculés à chaque dessin.
var _seen := {}
## Position (monde) de chaque flotte dessinée, pour la sélection au clic.
var _fleet_pos := {}

var _background := PackedVector2Array()
var _font: Font
var _last_zoom := -1.0


func _ready() -> void:
	_font = UiTheme.body_font()


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
	# Flottes en mouvement : on redessine à chaque image pour un déplacement fluide.
	if day_fraction > 0.0 and state != null:
		for fid in state.fleets:
			if state.fleets[fid].is_moving():
				queue_redraw()
				break


# --- Brouillard de guerre -----------------------------------------------------------------------

## Le joueur a exploré ce système (ou le brouillard est désactivé).
func is_explored(id: int) -> bool:
	return not fog or state == null or Fleets.is_explored(state, viewer, id)


## Le joueur connaît la position de ce système (exploré, ou relié à un système exploré).
func is_known(id: int) -> bool:
	return not fog or state == null or Fleets.is_known(state, viewer, id)


## Le joueur voit ce système en ce moment.
func is_seen(id: int) -> bool:
	return not fog or state == null or _seen.has(id)


## Système connu le plus proche d'une position du monde (-1 si aucun à moins de max_distance).
func pick_system(world_pos: Vector2, max_distance: float) -> int:
	var best := -1
	var best_d := max_distance * max_distance
	for s in galaxy.systems:
		var d := s.position.distance_squared_to(world_pos)
		if d <= best_d and is_known(s.id):
			best_d = d
			best = s.id
	return best


## Flotte dessinée la plus proche d'une position du monde (-1 si aucune à moins de max_distance).
func pick_fleet(world_pos: Vector2, max_distance: float) -> int:
	var best := -1
	var best_d := max_distance * max_distance
	var positions := fleet_positions()
	for fid in positions:
		var d: float = (positions[fid] as Vector2).distance_squared_to(world_pos)
		if d <= best_d and state.fleets.has(fid):
			best_d = d
			best = fid
	return best


## Position (monde) d'une flotte, telle que dessinée.
func fleet_world_position(fid: int) -> Vector2:
	return fleet_positions().get(fid, Vector2.ZERO)


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
	_seen = Fleets.visible_systems(state, viewer) if state != null and fog else {}

	_draw_territory()

	for p in _background:
		draw_circle(p, 1.1 * px, Color(1, 1, 1, 0.22))

	for lane in galaxy.lanes:
		var ea := is_explored(lane.x)
		var eb := is_explored(lane.y)
		if not ea and not eb:
			continue  # route inconnue : dans le brouillard
		var a := galaxy.systems[lane.x].position
		var b := galaxy.systems[lane.y].position
		var lit := lane.x == selected_id or lane.y == selected_id
		var alpha := 0.75 if lit else (0.22 if ea and eb else 0.1)
		draw_line(a, b, Color(LANE_COLOR, alpha), (2.0 if lit else 1.0) * px, true)

	for s in galaxy.systems:
		if is_explored(s.id):
			_draw_system(s, px)
		elif is_known(s.id):
			_draw_unknown_system(s, px)

	_draw_fleets(px)

	if lens == "economy" and state != null:
		# Lentille économique : tout s'assombrit sauf les systèmes du joueur, qui affichent leur bilan.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			if state.system_owner(s.id) == viewer:
				_draw_system(s, px)
				_draw_label(s, px, true)
				_draw_yields(s, px)
		return
	var show_all_labels := _zoom() >= LABEL_MIN_ZOOM
	var show_dots := _zoom() >= PLANET_DOTS_MIN_ZOOM
	for s in galaxy.systems:
		if not is_explored(s.id):
			continue
		var key := s.id == selected_id or s.id == hovered_id or (state != null and state.system_owner(s.id) >= 0)
		if show_all_labels or key:
			_draw_label(s, px, show_dots or key)


## Territoire : une zone à la couleur de l'empire autour de ses systèmes et le long de ses routes.
## Couleur opaque (fond teinté) plutôt que transparente : les zones qui se chevauchent
## se fondent en une seule tache au lieu de s'assombrir par endroits.
func _draw_territory() -> void:
	if state == null:
		return
	var bg: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.BLACK)
	for lane in galaxy.lanes:
		var oa := state.system_owner(lane.x)
		if oa != -1 and oa == state.system_owner(lane.y) and is_explored(lane.x) and is_explored(lane.y):
			var tint := bg.lerp(state.get_empire(oa).color(), 0.13)
			draw_line(galaxy.systems[lane.x].position, galaxy.systems[lane.y].position, tint, TERRITORY_RADIUS * 1.1)
	for s in galaxy.systems:
		var owner := state.get_empire(state.system_owner(s.id))
		if owner and is_explored(s.id):
			draw_circle(s.position, TERRITORY_RADIUS, bg.lerp(owner.color(), 0.13))


func _draw_system(s: StarSystem, px: float) -> void:
	var color: Color = STAR_COLORS.get(s.star_type, Color.WHITE)
	if not is_seen(s.id):
		color = color.darkened(0.35)  # exploré mais hors de vue : dernières observations
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


## Système connu mais inexploré : une petite lueur grise, sans nom ni planètes.
func _draw_unknown_system(s: StarSystem, px: float) -> void:
	draw_circle(s.position, 7.0 * px, Color(0.6, 0.65, 0.75, 0.08))
	draw_circle(s.position, 2.2 * px, Color(0.7, 0.74, 0.82, 0.55))
	if s.id == hovered_id or s.id == selected_id:
		draw_arc(s.position, 9.0 * px, 0.0, TAU, 24, SELECT_COLOR if s.id == selected_id else Color(1, 1, 1, 0.5), 1.5 * px, true)


# --- Flottes ------------------------------------------------------------------------------------

## Flottes visibles : un chevron à la couleur de l'empire, pointé dans le sens de la marche.
## À l'arrêt, les flottes d'un même système s'alignent à droite de l'étoile.
## La flotte sélectionnée montre son trajet et le délai d'arrivée.
func _draw_fleets(px: float) -> void:
	_fleet_pos = fleet_positions(px)
	if selected_fleet >= 0 and _fleet_pos.has(selected_fleet):
		_draw_route(state.fleets[selected_fleet], px)
	for fid in _fleet_pos:
		_draw_fleet_icon(state.fleets[fid], _fleet_pos[fid], px)


## Position (monde) de chaque flotte visible par le joueur, telle qu'elle est dessinée.
func fleet_positions(px := -1.0) -> Dictionary:
	var out := {}
	if state == null:
		return out
	if px < 0.0:
		px = 1.0 / _zoom()
		if fog:
			_seen = Fleets.visible_systems(state, viewer)
	var stacked := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if fog and not Fleets.fleet_visible(state, viewer, f, _seen):
			continue
		var pos: Vector2
		if f.is_moving():
			pos = Fleets.position(state, f, day_fraction)
		else:
			var k := int(stacked.get(f.system_id, 0))
			stacked[f.system_id] = k + 1
			pos = galaxy.systems[f.system_id].position + Vector2(16.0 + k * 13.0, 10.0) * px
		out[fid] = pos
	return out


func _draw_fleet_icon(f: Fleet, pos: Vector2, px: float) -> void:
	var col := state.get_empire(f.owner).color()
	var dir := Vector2.RIGHT
	if f.is_moving():
		dir = (galaxy.systems[f.path[0]].position - galaxy.systems[f.system_id].position).normalized()
	var side := dir.orthogonal()
	var s := (7.0 if f.ships.size() > 1 else 6.0) * px
	var tip := pos + dir * s
	var pts := PackedVector2Array([tip, pos - dir * s * 0.7 + side * s * 0.75, pos - dir * s * 0.25, pos - dir * s * 0.7 - side * s * 0.75])
	if f.id == selected_fleet:
		draw_circle(pos, s * 1.9, Color(SELECT_COLOR, 0.18))
		draw_arc(pos, s * 1.9, 0.0, TAU, 24, SELECT_COLOR, 1.5 * px, true)
	draw_colored_polygon(pts, Color(0.02, 0.03, 0.05, 0.85))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(pos + (p - pos) * 0.78)
	draw_colored_polygon(inner, col)
	if f.ships.size() > 1:
		draw_set_transform(pos, 0.0, Vector2(px, px))
		draw_string(_font, Vector2(8, 12), str(f.ships.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Trajet de la flotte sélectionnée : pointillés jusqu'à destination, et le délai.
func _draw_route(f: Fleet, px: float) -> void:
	if not f.is_moving():
		return
	var pts := PackedVector2Array([_fleet_pos[f.id]])
	for sid in f.path:
		pts.append(galaxy.systems[sid].position)
	for i in range(pts.size() - 1):
		draw_dashed_line(pts[i], pts[i + 1], Color(SELECT_COLOR, 0.8), 1.6 * px, 7.0 * px, true)
	var end := pts[-1]
	draw_arc(end, 11.0 * px, 0.0, TAU, 24, Color(SELECT_COLOR, 0.8), 1.5 * px, true)
	draw_set_transform(end, 0.0, Vector2(px, px))
	var text := "%d j" % Fleets.eta_days(state, f)
	draw_rect(Rect2(Vector2(14, -8), Vector2(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
	draw_string(_font, Vector2(19, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SELECT_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


## Étiquette du système : son nom dans un petit cartouche sombre, une pastille par planète dessous
## (pleine si la planète est revendiquée, à la couleur de son propriétaire).
func _draw_label(s: StarSystem, px: float, dots := true) -> void:
	# On annule le zoom localement pour que le texte reste net et de taille constante.
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var selected := s.id == selected_id
	var owner := state.get_empire(state.system_owner(s.id)) if state else null
	var w := _font.get_string_size(s.system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
	var tag := Rect2(Vector2(-w * 0.5 - 7, -34), Vector2(w + 14, 19))
	draw_rect(tag, Color(0.02, 0.03, 0.05, 0.78 if not selected else 0.92))
	if selected:
		draw_rect(Rect2(tag.position + Vector2(0, tag.size.y - 2), Vector2(tag.size.x, 2)), SELECT_COLOR)
	elif owner:
		draw_rect(Rect2(tag.position + Vector2(0, tag.size.y - 1), Vector2(tag.size.x, 1)), owner.color())
	var col := Color(0.92, 0.94, 0.97) if selected or s.id == hovered_id else Color(0.85, 0.88, 0.93, 0.85)
	draw_string(_font, Vector2(-w * 0.5, -20), s.system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, col)
	# Pastilles des planètes sous l'étiquette, entre elle et l'étoile.
	var n := s.planet_count if dots else 0
	for i in n:
		var pos := Vector2((i - (n - 1) * 0.5) * 9.0, -9)
		var c: Colony = state.colonies.get(s.planet_ids[i]) if state else null
		if c:
			draw_circle(pos, 3.0, state.get_empire(c.owner).color())
		else:
			draw_arc(pos, 2.6, 0.0, TAU, 12, Color(1, 1, 1, 0.55), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Lentille économique : bilan mensuel du système (toutes ses revendications), sous l'étoile.
func _draw_yields(s: StarSystem, px: float) -> void:
	var net := EmpireReport.system_net(state, viewer, s.id)
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var parts: Array[Dictionary] = []
	for r in GameData.resource_ids():
		var v := int(net.get(r, 0))
		if v != 0:
			parts.append({"r": r, "text": "%+d" % v, "v": v})
	var widths: Array[float] = []
	var total := 0.0
	for part in parts:
		var tw := _font.get_string_size(part["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
		widths.append(tw)
		total += tw
	var x := -total * 0.5
	if not parts.is_empty():
		draw_rect(Rect2(Vector2(x - 6, 16), Vector2(total + 8, 18)), Color(0.02, 0.03, 0.05, 0.9))
	for i in parts.size():
		var part: Dictionary = parts[i]
		draw_circle(Vector2(x + 4, 25), 3.5, ResourceIcon.color_of(part["r"]))
		draw_string(_font, Vector2(x + 10, 30), part["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				UiTheme.delta_color(int(part["v"])))
		x += widths[i]
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
