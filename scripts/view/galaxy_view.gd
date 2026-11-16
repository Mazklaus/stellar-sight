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


const BATTLE_COLOR := Color(1.0, 0.42, 0.36)
const GROUND_BATTLE_COLOR := Color(0.95, 0.68, 0.32)


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


## Propriétaire du système tel que le joueur le connaît : réel s'il le voit (ou sans brouillard),
## sinon celui de sa dernière observation (voir Intel).
func owner_of(id: int) -> int:
	if is_seen(id):
		return state.system_owner(id)
	var m := Intel.known(state, viewer, id)
	return -1 if m.is_empty() else int(m["info"]["owner"])


## Revendication d'une planète telle que le joueur la connaît (voir Intel.colony_of).
func colony_of(pid: int) -> Colony:
	if not fog:
		return state.colonies.get(pid)
	return Intel.colony_of(state, viewer, pid)


## Couleur d'un empire sur la carte : atténuée pour un système connu par une ancienne observation.
func _owner_color(owner: Empire, id: int) -> Color:
	return owner.color() if is_seen(id) else owner.color().darkened(0.4)


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
	_draw_terrain(px)

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
	_draw_portals(px)

	for s in galaxy.systems:
		if is_explored(s.id):
			_draw_system(s, px)
			_draw_occupation(s, px)
		elif is_known(s.id):
			_draw_unknown_system(s, px)

	_draw_fleets(px)
	_draw_conflicts(px)
	_draw_lairs(px)
	_draw_minors(px)
	_draw_wonders(px)
	_draw_quests(px)
	_draw_crisis(px)
	_draw_convoys(px)

	if lens == "economy" and state != null:
		# Lentille économique : tout s'assombrit sauf les systèmes du joueur, qui affichent leur bilan.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			if owner_of(s.id) == viewer:
				_draw_system(s, px)
				_draw_label(s, px, true)
				_draw_yields(s, px)
		return
	if lens == "stability" and state != null:
		# Lentille de stabilité : vos systèmes cerclés à la couleur de leur palier, avec leur stabilité ;
		# les mondes libres (Sans-Bannière) en gris.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			var o := owner_of(s.id)
			if o == viewer or (o == GameState.NPC_ID and is_explored(s.id)):
				_draw_system(s, px)
				_draw_label(s, px, true)
				_draw_stability(s, px, o == viewer)
		_draw_lairs(px)
		return
	if lens == "corruption" and state != null:
		# Mode Corruption de la lentille de stabilité (Administration) : vos systèmes cerclés selon leur
		# corruption, avec sa valeur et leur siège ; les non intégrés en pointillé, les sièges marqués.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			if owner_of(s.id) == viewer:
				_draw_system(s, px)
				_draw_label(s, px, true)
				_draw_corruption(s, px)
		return
	if lens == "fiscal" and state != null:
		# Mode Fiscalité de la lentille de stabilité : franchises fiscales (or), grèves fiscales (rouge),
		# fuite fiscale de la corruption ; la cote de crédit sur la capitale.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			if owner_of(s.id) == viewer:
				_draw_system(s, px)
				_draw_label(s, px, true)
				_draw_fiscal(s, px)
		return
	if lens == "politics" and state != null:
		# Lentille politique : vos systèmes cerclés à la couleur du courant qui domine leur opinion,
		# trait plein s'ils sont représentés au pouvoir, pointillé sinon.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			if owner_of(s.id) == viewer:
				_draw_system(s, px)
				_draw_label(s, px, true)
				_draw_politics(s, px)
		return
	if lens == "peoples" and state != null:
		# Lentille des peuples : vos systèmes cerclés de la part de chaque espèce, et la majoritaire.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			if owner_of(s.id) == viewer:
				_draw_system(s, px)
				_draw_label(s, px, true)
				_draw_peoples(s, px)
		_draw_convoys(px)
		return
	if lens == "faith" and state != null:
		# Lentille de la foi : vos systèmes cerclés de la part de chaque croyance, la majoritaire, et
		# les mondes saints des systèmes explorés.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			if owner_of(s.id) == viewer:
				_draw_system(s, px)
				_draw_label(s, px, true)
				_draw_faith(s, px)
		_draw_holy_worlds(px)
		return
	if lens == "amph" and state != null:
		# Lentille de l'Amphictyonie : les systèmes explorés des empires, cerclés d'or pour les membres,
		# de rouge pour les hors-la-loi, de gris pour ceux qui restent dehors ; les voix à la capitale.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			var o := owner_of(s.id)
			if o < 0 or GameState.is_npc(o) or not is_explored(s.id):
				continue
			_draw_system(s, px)
			_draw_label(s, px, true)
			_draw_amph(s, px, o)
		return
	if lens == "war" and state != null:
		# Lentille de guerre : les systèmes des empires en guerre avec vous (cercle rouge), vos
		# revendications (pointillé or), les systèmes occupés hachurés à la couleur de l'occupant.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			var o := owner_of(s.id)
			if o < 0 or GameState.is_npc(o) or not is_explored(s.id):
				continue
			_draw_system(s, px)
			_draw_label(s, px, true)
			_draw_war(s, px, o)
		return
	if lens == "borders" and state != null:
		# Lentille des frontières : votre droit de passage chez chaque voisin (vert : vos flottes de guerre
		# passent, ambre : vos vaisseaux sans armes seulement, rouge : frontière close), vos systèmes en
		# blanc, et les intrus repérés chez vous marqués d'un losange rouge.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			var o := owner_of(s.id)
			if o < 0 or GameState.is_npc(o) or not is_explored(s.id):
				continue
			_draw_system(s, px)
			_draw_label(s, px, true)
			_draw_borders(s, px, o)
		return
	if lens == "culture" and state != null:
		# Lentille du rayonnement : chez chaque empire exploré, le palier de votre culture ; chez vous,
		# la culture étrangère dominante et les systèmes en route vers une défection.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			var o := owner_of(s.id)
			if o < 0 or GameState.is_npc(o) or not is_explored(s.id):
				continue
			_draw_system(s, px)
			_draw_label(s, px, true)
			_draw_culture(s, px, o)
		return
	if lens == "ports" and state != null:
		# Réseau des spatioports : desserte de vos systèmes (vert, jaune, orange, rouge pour une
		# enclave), ports (anneaux selon le niveau, barrés s'ils sont bloqués) et systèmes couverts.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		_draw_ports(px)
		return
	if lens == "private" and state != null:
		# Mode Économie privée de la lentille du commerce : stations minières (losange orange),
		# stations touristiques (rose), zones militaires (anneau rouge), repaires (croix), filiales
		# (carré bleu), et les cargos du privé en route sur les routes commerciales.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		_draw_private(px)
		return
	if lens == "trade" and state != null:
		# Lentille du commerce : vos routes (couleur du palier du traité, verte pour une route
		# intérieure, rouge si bloquée) et le risque pirate des systèmes traversés.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		_draw_trade(px)
		return
	var show_all_labels := _zoom() >= LABEL_MIN_ZOOM
	var show_dots := _zoom() >= PLANET_DOTS_MIN_ZOOM
	for s in galaxy.systems:
		if not is_explored(s.id):
			continue
		var key := s.id == selected_id or s.id == hovered_id or (state != null and owner_of(s.id) >= 0)
		if show_all_labels or key:
			_draw_label(s, px, show_dots or key)


const TRADE_TIER_COLORS := [Color(0.6, 0.6, 0.6), Color(0.75, 0.62, 0.35), Color(0.95, 0.8, 0.35), Color(0.55, 0.9, 1.0)]
const TRADE_INTERNAL_COLOR := Color(0.5, 0.88, 0.55)


func _draw_trade(px: float) -> void:
	var shown := {}
	var routes := Trade.routes_of(state, viewer)
	for r in routes:
		var p: Array = r["path"]
		var col: Color = TRADE_INTERNAL_COLOR if String(r["kind"]) != "ext" else TRADE_TIER_COLORS[clampi(int(r["tier"]), 0, 3)]
		if bool(r.get("blocked", false)):
			col = BATTLE_COLOR
		var w := (2.5 if int(r["from"]) == viewer else 1.5) * px
		for i in range(p.size() - 1):
			var a := galaxy.systems[int(p[i])].position
			var b := galaxy.systems[int(p[i + 1])].position
			draw_line(a, b, Color(col, 0.85), w, true)
			# Sens de la route : une pointe au milieu de chaque saut.
			var m := (a + b) * 0.5
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([m + d * 5.0 * px, m - d * 3.0 * px + n * 3.5 * px, m - d * 3.0 * px - n * 3.5 * px]), col)
		for sid in p:
			shown[int(sid)] = true
	for s in galaxy.systems:
		if owner_of(s.id) == viewer:
			shown[s.id] = true
	for sid in shown:
		var s: StarSystem = galaxy.systems[sid]
		if not is_explored(s.id):
			continue
		_draw_system(s, px)
		_draw_label(s, px, true)
		var risk := Trade.risk_at(state, s.id)
		if risk > 0:
			var f := clampf(float(risk) / float(Trade.data()["piracy"]["risk_max"]), 0.0, 1.0)
			draw_arc(s.position, 13.0 * px, -PI / 2.0, -PI / 2.0 + TAU * f, 24, Color(0.95, 0.45, 0.3, 0.9), 2.2 * px, true)
	_draw_lairs(px)


func _draw_ports(px: float) -> void:
	if state.ports.is_empty():
		return
	var shown := {}
	for s in galaxy.systems:
		if owner_of(s.id) == viewer:
			shown[s.id] = true
	for sid in Ports.nodes_of(state, viewer):
		shown[sid] = true
	for sid in shown:
		var s: StarSystem = galaxy.systems[sid]
		if not is_explored(s.id):
			continue
		_draw_system(s, px)
		_draw_label(s, px, true)
		draw_set_transform(s.position, 0.0, Vector2(px, px))
		var parts := PackedStringArray()
		if owner_of(s.id) == viewer:
			var cs := Ports.system_state(state, viewer, s.id)
			draw_circle(Vector2.ZERO, 9.0, Color(PortsUi.STATE_COLORS[cs], 0.55))
			parts.append("%d %%" % Ports.system_pct(state, viewer, s.id))
		var n := Ports.node(state, viewer, s.id)
		if not n.is_empty():
			var lvl := int(n["l"])
			var col := Color(0.55, 0.85, 1.0) if int(n.get("lk", 0)) == 1 else Color(0.85, 0.33, 0.31)
			for i in maxi(1, lvl):
				draw_arc(Vector2.ZERO, 13.0 + 4.0 * i, 0.0, TAU, 32, col, 2.0, true)
			if int(n.get("bk", 0)) == 1:
				draw_line(Vector2(-16, -16), Vector2(16, 16), Color(0.86, 0.33, 0.31), 2.6, true)
			parts.append("%s, portée %d" % [Ports.level_label(lvl), int(n["r"])])
		if not parts.is_empty():
			var text := " · ".join(parts)
			var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 24), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
			draw_string(_font, Vector2(-tw * 0.5, 38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.9, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


const PRIVATE_MINE_COLOR := Color(0.95, 0.62, 0.25)
const PRIVATE_RESORT_COLOR := Color(0.95, 0.5, 0.8)
const PRIVATE_BRANCH_COLOR := Color(0.45, 0.75, 1.0)


func _draw_private(px: float) -> void:
	if state.private.is_empty():
		return
	var shown := {}
	for s in galaxy.systems:
		if owner_of(s.id) == viewer:
			shown[s.id] = true
	# Cargos : un point par route envoyée, qui avance d'un saut par jour (repère visuel seulement).
	for r in Trade.sent_by(state, viewer):
		var p: Array = r["path"]
		if p.size() < 2:
			continue
		for i in range(p.size() - 1):
			draw_line(galaxy.systems[int(p[i])].position, galaxy.systems[int(p[i + 1])].position, Color(0.75, 0.62, 0.35, 0.35), 1.2 * px, true)
		var steps := (p.size() - 1) * 4
		var k := posmod(state.tick + int(r.get("to", 0)), steps)
		@warning_ignore("integer_division")
		var seg := k / 4
		var t := float(k % 4) / 4.0
		var pos := galaxy.systems[int(p[seg])].position.lerp(galaxy.systems[int(p[seg + 1])].position, t)
		draw_circle(pos, 3.2 * px, Color(0.98, 0.86, 0.5))
		for sid in p:
			shown[int(sid)] = true
	for sid in shown:
		var s: StarSystem = galaxy.systems[sid]
		if not is_explored(s.id):
			continue
		_draw_system(s, px)
		_draw_label(s, px, true)
		draw_set_transform(s.position, 0.0, Vector2(px, px))
		var parts := PackedStringArray()
		if Private.in_zone(state, s.id):
			draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 28, Color(0.86, 0.33, 0.31), 2.4, true)
			parts.append("zone militaire")
		var mines := 0
		for pid in s.planet_ids:
			var st := Private.station(state, pid)
			if st.is_empty() or int(st["o"]) != viewer:
				continue
			if String(st["k"]) == "mine":
				mines += 1
			else:
				draw_circle(Vector2(-14, -12), 4.0, PRIVATE_RESORT_COLOR)
				parts.append("tourisme %d" % Private.resort_income(state, pid))
		if mines > 0:
			draw_colored_polygon(PackedVector2Array([Vector2(14, -17), Vector2(18, -12), Vector2(14, -7), Vector2(10, -12)]), PRIVATE_MINE_COLOR)
			parts.append("%d mine%s" % [mines, "s" if mines > 1 else ""])
		for pid in s.planet_ids:
			if (state.private.get("br", {}) as Dictionary).has(str(pid)):
				draw_rect(Rect2(Vector2(-4, -22), Vector2(8, 8)), PRIVATE_BRANCH_COLOR)
				parts.append("filiale")
				break
		if PrivateBridges.has_den(state, s.id) and (owner_of(s.id) == viewer):
			draw_line(Vector2(-6, 10), Vector2(6, 22), Color(0.86, 0.33, 0.31), 2.4, true)
			draw_line(Vector2(6, 10), Vector2(-6, 22), Color(0.86, 0.33, 0.31), 2.4, true)
			parts.append("syndicat")
		if not parts.is_empty():
			var text := " · ".join(parts)
			var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 24), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
			draw_string(_font, Vector2(-tw * 0.5, 38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.82, 0.6))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_lairs(px)


## Combats visibles : deux lames croisées au-dessus d'un système en bataille, un anneau rouge
## en pointillés autour d'un système assiégé.
func _draw_conflicts(px: float) -> void:
	if state == null:
		return
	for k in state.sieges:
		var sid := int(k)
		if fog and not _seen.has(sid):
			continue
		var c := galaxy.systems[sid].position
		var r := 15.0 * px
		var n := 16
		for i in n:
			if i % 2 == 0:
				draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 4, Color(BATTLE_COLOR, 0.85), 1.6 * px, true)
	for k in state.battles:
		var sid := int(k)
		if fog and not _seen.has(sid):
			continue
		var c := galaxy.systems[sid].position + Vector2(0, -17.0) * px
		var s := 6.0 * px
		draw_circle(c, s * 1.6, Color(0.02, 0.03, 0.05, 0.85))
		draw_arc(c, s * 1.6, 0.0, TAU, 20, BATTLE_COLOR, 1.2 * px, true)
		draw_line(c + Vector2(-s, -s), c + Vector2(s, s), BATTLE_COLOR, 1.8 * px, true)
		draw_line(c + Vector2(s, -s), c + Vector2(-s, s), BATTLE_COLOR, 1.8 * px, true)
	# Batailles au sol (combat au sol complet) : un chevron sous le système.
	for k in state.ground.get("b", {}):
		var sid := int(k)
		if fog and not _seen.has(sid):
			continue
		var c := galaxy.systems[sid].position + Vector2(0, 18.0) * px
		var s := 6.0 * px
		draw_circle(c, s * 1.6, Color(0.02, 0.03, 0.05, 0.85))
		draw_arc(c, s * 1.6, 0.0, TAU, 20, GROUND_BATTLE_COLOR, 1.2 * px, true)
		for j in 2:
			var y := (j * 4.0 - 3.0) * px
			draw_polyline(PackedVector2Array([c + Vector2(-s, y - s * 0.4), c + Vector2(0, y + s * 0.4), c + Vector2(s, y - s * 0.4)]), GROUND_BATTLE_COLOR, 1.6 * px, true)


## Territoire : une zone à la couleur de l'empire autour de ses systèmes et le long de ses routes.
## Couleur opaque (fond teinté) plutôt que transparente : les zones qui se chevauchent
## se fondent en une seule tache au lieu de s'assombrir par endroits.
func _draw_territory() -> void:
	if state == null:
		return
	var bg: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.BLACK)
	for lane in galaxy.lanes:
		var oa := owner_of(lane.x)
		if oa != -1 and oa == owner_of(lane.y) and is_explored(lane.x) and is_explored(lane.y):
			var faded := not (is_seen(lane.x) and is_seen(lane.y))
			var tint := bg.lerp(state.get_empire(oa).color(), 0.08 if faded else 0.13)
			draw_line(galaxy.systems[lane.x].position, galaxy.systems[lane.y].position, tint, TERRITORY_RADIUS * 1.1)
	for s in galaxy.systems:
		var owner := state.get_empire(owner_of(s.id))
		if owner and is_explored(s.id):
			draw_circle(s.position, TERRITORY_RADIUS, bg.lerp(owner.color(), 0.13 if is_seen(s.id) else 0.08))


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


# --- Terrain (voir Terrain) -------------------------------------------------------------------------

## Nappes translucides derrière les étoiles : nébuleuses (connues dès le début, comme dans Stellaris),
## autres terrains de zone une fois explorés, tempêtes (nuage, éclairs et flèche du prochain saut),
## noms des nébuleuses. Pas de lentille dédiée : le terrain s'affiche toujours, discret.
func _draw_terrain(px: float) -> void:
	if state == null or not Terrain.active(state):
		return
	for s in galaxy.systems:
		var z := s.terrain
		if z == "":
			continue
		var nebula := z == "nebuleuse" or z == "nebuleuse_ionisee"
		if not nebula and not is_explored(s.id):
			continue
		var rgb: Array = Terrain.def(z).get("map", [0.5, 0.5, 0.5])
		var col := Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
		var h := absi(hash([s.id, "nappe"]))
		for i in 4:
			var ang := float((h >> (i * 4)) % 16) / 16.0 * TAU
			var off := Vector2.from_angle(ang) * (18.0 + float((h >> (i * 3)) % 20))
			draw_circle(s.position + off, 58.0 + float((h >> (i * 5)) % 30), Color(col, 0.055 if nebula else 0.07))
		if z == "asteroides" or z == "cimetiere":
			for i in 7:
				var a2 := float((h >> i) % 64) / 64.0 * TAU
				draw_circle(s.position + Vector2.from_angle(a2) * (22.0 + float((h >> (i + 2)) % 18)), 1.6 * px, Color(col, 0.6))
		elif z == "nebuleuse_ionisee" or z == "plasma":
			var a3 := float(h % 360) / 360.0 * TAU
			var p0 := s.position + Vector2.from_angle(a3) * 30.0
			draw_polyline(PackedVector2Array([p0, p0 + Vector2(6, 9), p0 + Vector2(1, 12), p0 + Vector2(8, 22)]), Color(col.lightened(0.4), 0.55), 1.3 * px)
	for r: Array in state.terrain.get("rg", []):
		var ids: Array = r[1]
		var c := Vector2.ZERO
		for sid in ids:
			c += galaxy.systems[int(sid)].position
		c /= maxf(1.0, float(ids.size()))
		draw_set_transform(c + Vector2(0, 46), 0.0, Vector2(px, px))
		var nm := String(r[0])
		var w := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(_font, Vector2(-w * 0.5, 0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.7, 0.95, 0.42))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for st: Dictionary in Terrain.storms(state):
		var cov := Terrain.storm_systems(state, st)
		var known := false
		for sid in cov:
			if is_explored(sid):
				known = true
		if not known:
			continue
		var rgb2: Array = Terrain.def(String(st["k"])).get("map", [0.6, 0.8, 1.0])
		var sc := Color(float(rgb2[0]), float(rgb2[1]), float(rgb2[2]))
		for sid in cov:
			draw_circle(galaxy.systems[sid].position, 48.0, Color(sc, 0.06))
		var cp := galaxy.systems[int(st["c"])].position
		for i in 3:
			draw_arc(cp, 26.0 + i * 12.0, float(i) * 1.7, float(i) * 1.7 + 4.2, 24, Color(sc, 0.5 - i * 0.12), 2.0 * px, true)
		var np := galaxy.systems[int(st["nx"])].position
		if np != cp:
			var dir := (np - cp).normalized()
			var tip := cp + dir * minf(cp.distance_to(np) * 0.6, 70.0)
			draw_line(cp + dir * 30.0, tip, Color(sc, 0.6), 1.6 * px, true)
			draw_line(tip, tip - dir.rotated(0.5) * 9.0 * px * 1.5, Color(sc, 0.6), 1.6 * px, true)
			draw_line(tip, tip - dir.rotated(-0.5) * 9.0 * px * 1.5, Color(sc, 0.6), 1.6 * px, true)


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
		_draw_supply_zone(state.fleets[selected_fleet], px)
		_draw_route(state.fleets[selected_fleet], px)
	for fid in _fleet_pos:
		_draw_fleet_icon(state.fleets[fid], _fleet_pos[fid], px)
	if fog:
		_draw_ghosts(px)


## Silhouettes : flottes étrangères perdues de vue, dessinées en creux là où on les a vues (voir Intel).
func _draw_ghosts(px: float) -> void:
	var stacked := {}
	for g in Intel.ghosts(state, viewer):
		var sid := int(g["sys"])
		if not is_explored(sid):
			continue
		var k := int(stacked.get(sid, 0))
		stacked[sid] = k + 1
		var pos: Vector2 = galaxy.systems[sid].position + Vector2(-16.0 - k * 13.0, 10.0) * px
		var owner := state.get_empire(int(g["owner"]))
		var col := Color(owner.color() if owner else Color.GRAY, 0.55)
		var s := (7.0 if int(g["ships"]) > 1 else 6.0) * px
		var dir := Vector2.LEFT
		var side := dir.orthogonal()
		var pts := PackedVector2Array([pos + dir * s, pos - dir * s * 0.7 + side * s * 0.75, pos - dir * s * 0.25,
				pos - dir * s * 0.7 - side * s * 0.75, pos + dir * s])
		draw_polyline(pts, col, 1.3 * px, true)


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
	# Médaillon d'or : un héros commande cette flotte.
	if not Heroes.at_post(state, "fleet", f.id, f.owner).is_empty():
		var m := pos + Vector2(0, -s * 1.35)
		draw_circle(m, 3.2 * px, Color(0.02, 0.03, 0.05, 0.9))
		draw_circle(m, 2.4 * px, Color(0.95, 0.78, 0.36))


const SUPPLY_COLOR := Color(0.45, 0.85, 0.55)


## Logistique : zone de ravitaillement de la flotte sélectionnée (une des vôtres, armée) : un halo
## vert sur chaque système connu de la zone, plus pâle sur ses bords. Pas de lentille de plus.
func _draw_supply_zone(f: Fleet, px: float) -> void:
	if f.owner != viewer or not Logistics.applies(state, f):
		return
	var z := Logistics.zone(state, f.owner)
	for sid in z:
		if not is_known(int(sid)):
			continue
		var p: Vector2 = galaxy.systems[int(sid)].position
		var edge := int(z[sid]) == 0
		draw_circle(p, 26.0 * px, Color(SUPPLY_COLOR, 0.07 if edge else 0.13))
		draw_arc(p, 26.0 * px, 0.0, TAU, 28, Color(SUPPLY_COLOR, 0.32 if edge else 0.55), 1.5 * px, true)


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
	# Frontières : le trajet passe par un espace interdit (intrusion).
	var col := SELECT_COLOR
	if f.owner == viewer and Borders.route_warning(state, f, f.path) != "":
		text += " · intrusion"
		col = BORDER_CLOSED_COLOR
	# Logistique : destination hors de la zone de ravitaillement.
	if f.owner == viewer and Logistics.route_warning(state, f, f.path) != "":
		text += " · hors ravitaillement"
		col = BORDER_GUARDED_COLOR if col == SELECT_COLOR else col
	draw_rect(Rect2(Vector2(14, -8), Vector2(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
	draw_string(_font, Vector2(19, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Anneau à la couleur du propriétaire (pointillé tant qu'une fondation est en cours),
## et un losange pour une capitale.
func _draw_claims(s: StarSystem, r: float, px: float) -> void:
	if state == null:
		return
	var owner := state.get_empire(owner_of(s.id))
	if owner == null:
		return
	var established := false
	var capital := false
	for pid in s.planet_ids:
		var c: Colony = colony_of(pid)
		if c and c.is_established():
			established = true
		if owner.capital_planet == pid:
			capital = true
	var col := _owner_color(owner, s.id)
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
	var owner := state.get_empire(owner_of(s.id)) if state else null
	var w := _font.get_string_size(s.system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
	var tag := Rect2(Vector2(-w * 0.5 - 7, -34), Vector2(w + 14, 19))
	draw_rect(tag, Color(0.02, 0.03, 0.05, 0.78 if not selected else 0.92))
	if selected:
		draw_rect(Rect2(tag.position + Vector2(0, tag.size.y - 2), Vector2(tag.size.x, 2)), SELECT_COLOR)
	elif owner:
		draw_rect(Rect2(tag.position + Vector2(0, tag.size.y - 1), Vector2(tag.size.x, 1)), _owner_color(owner, s.id))
	var col := Color(0.92, 0.94, 0.97) if selected or s.id == hovered_id else Color(0.85, 0.88, 0.93, 0.85)
	draw_string(_font, Vector2(-w * 0.5, -20), s.system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, col)
	# Pastilles des planètes sous l'étiquette, entre elle et l'étoile.
	var n := s.planet_count if dots else 0
	for i in n:
		var pos := Vector2((i - (n - 1) * 0.5) * 9.0, -9)
		var c: Colony = colony_of(s.planet_ids[i]) if state else null
		if c:
			draw_circle(pos, 3.0, _owner_color(state.get_empire(c.owner), s.id))
		else:
			draw_arc(pos, 2.6, 0.0, TAU, 12, Color(1, 1, 1, 0.55), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Lentille économique : bilan mensuel du système (toutes ses revendications), sous l'étoile.
## Repaires pirates connus : deux sabres croisés rouges au-dessus de l'étoile.
func _draw_lairs(px: float) -> void:
	_draw_nests(px)
	if state == null or state.lairs.is_empty():
		return
	var col := Color(String(GameData.pirates()["npc"]["color"])).lightened(0.15)
	for sid in Pirates.lair_ids(state):
		if not is_explored(sid):
			continue
		draw_set_transform(galaxy.systems[sid].position + Vector2(0, -20.0 * px), 0.0, Vector2(px, px))
		draw_circle(Vector2.ZERO, 8.5, Color(0.08, 0.02, 0.02, 0.85))
		draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, col, 1.4, true)
		draw_line(Vector2(-5, 5), Vector2(5, -5), col, 2.0, true)
		draw_line(Vector2(-5, -5), Vector2(5, 5), col, 2.0, true)
		draw_line(Vector2(-6, 1), Vector2(-1, 6), col, 1.4, true)
		draw_line(Vector2(6, 1), Vector2(1, 6), col, 1.4, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Ports francs : une ancre dorée.
	var gold := Color(0.9, 0.76, 0.4)
	for sid in Pirates.port_ids(state):
		if not is_explored(sid):
			continue
		draw_set_transform(galaxy.systems[sid].position + Vector2(0, -20.0 * px), 0.0, Vector2(px, px))
		draw_circle(Vector2.ZERO, 8.5, Color(0.08, 0.06, 0.02, 0.85))
		draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, gold, 1.4, true)
		draw_line(Vector2(0, -5), Vector2(0, 5), gold, 1.6, true)
		draw_line(Vector2(-3, -3), Vector2(3, -3), gold, 1.4, true)
		draw_arc(Vector2(0, 1), 4.5, 0.2, PI - 0.2, 10, gold, 1.4, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Peuples mineurs (voir Minors, prop. 34) : un losange à la couleur du peuple au-dessus de son système,
## cerclé d'or si vous êtes son suzerain, de rouge si vous êtes en guerre avec lui.
func _draw_minors(px: float) -> void:
	if state == null or state.minors.is_empty():
		return
	for id in Minors.ids(state):
		var sid := Minors.system_of(state, id)
		if sid < 0 or not is_explored(sid):
			continue
		var col := Color(String(Minors.kind_def(Minors.kind_of(state, id)).get("color", "#b0b0b0")))
		draw_set_transform(galaxy.systems[sid].position + Vector2(18.0, 6.0) * px, 0.0, Vector2(px, px))
		var pts := PackedVector2Array([Vector2(0, -8), Vector2(7, 0), Vector2(0, 8), Vector2(-7, 0)])
		draw_colored_polygon(pts, Color(0.04, 0.04, 0.06, 0.9))
		var ring := col
		if Minors.suzerain(state, id) == viewer:
			ring = Color(0.95, 0.8, 0.35)
		elif Minors.at_war_with(state, id, viewer):
			ring = Color(0.9, 0.3, 0.25)
		pts.append(Vector2(0, -8))
		draw_polyline(pts, ring, 1.6, true)
		if Minors.is_pre(state, id):
			draw_circle(Vector2.ZERO, 2.2, col)
		else:
			draw_line(Vector2(-3, 0), Vector2(3, 0), col, 1.6, true)
			draw_line(Vector2(0, -3), Vector2(0, 3), col, 1.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Merveilles (voir Wonders, prop. 28) : une petite pyramide à degrés à gauche de l'étoile, dorée pour
## une merveille achevée, grise pour une ruine.
func _draw_wonders(px: float) -> void:
	if state == null or state.wonders.is_empty():
		return
	var marks := {}
	for row in Wonders.held(state):
		marks[galaxy.get_planet(int(row[1])).system_id] = Color(0.95, 0.8, 0.4)
	var r: Dictionary = state.wonders.get("ruins", {})
	for wid in r:
		var sid := galaxy.get_planet(int(r[wid])).system_id
		if not marks.has(sid):
			marks[sid] = Color(0.6, 0.6, 0.62)
	for sid in marks:
		if not is_explored(int(sid)):
			continue
		var col: Color = marks[sid]
		draw_set_transform(galaxy.systems[int(sid)].position + Vector2(-19.0, 6.0) * px, 0.0, Vector2(px, px))
		draw_rect(Rect2(-7, 1, 14, 4), Color(0.04, 0.04, 0.06, 0.9))
		for k in 3:
			var w := 6.0 - k * 2.0
			draw_rect(Rect2(-w, 2.5 - k * 3.0, w * 2.0, 2.5), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Portails de saut (voir Portals), dessinés en permanence sans lentille : trous de ver en ligne
## ondulée violette (destination connue) ou tourbillon seul, corridors de relais surlignés en vert d'eau,
## anneau sur les systèmes à portail (gris pointillé pour une ruine, doré pour un portail libre).
func _draw_portals(px: float) -> void:
	if state == null or state.portals.is_empty():
		return
	var g := galaxy
	var drawn := {}
	for a in g.wormholes:
		var ia := int(a)
		var ib := int(g.wormholes[a])
		if drawn.has(ia) or not is_explored(ia):
			continue
		drawn[ia] = true
		drawn[ib] = true
		var pa := g.systems[ia].position
		var known := viewer < 0 or Portals.known_pair(state, viewer, Portals.pair_index(state, ia))
		var col := Color(0.72, 0.5, 1.0, 0.55)
		if known and is_explored(ib):
			var pb := g.systems[ib].position
			var pts := PackedVector2Array()
			var dir := pb - pa
			var nrm := Vector2(-dir.y, dir.x).normalized()
			var steps := 40
			for i in steps + 1:
				var t := float(i) / steps
				pts.append(pa + dir * t + nrm * sin(t * TAU * 6.0) * 5.0 * px)
			draw_polyline(pts, col, 1.4 * px, true)
			_draw_swirl(pb, px, col)
		_draw_swirl(pa, px, col)
	if not g.relays.is_empty():
		for lane in g.lanes:
			if g.relays.has(lane.x) and g.relays.has(lane.y) and is_explored(lane.x) and is_explored(lane.y):
				draw_line(g.systems[lane.x].position, g.systems[lane.y].position, Color(0.35, 0.95, 0.75, 0.6), 2.6 * px, true)
	for sid in g.portal_gates:
		if not is_explored(int(sid)):
			continue
		var free := state.system_owner(int(sid)) < 0
		draw_arc(g.systems[int(sid)].position, 15.0 * px, 0.0, TAU, 28, Color(0.95, 0.8, 0.35, 0.9) if free else Color(0.62, 0.55, 1.0, 0.9), 2.0 * px, true)
	var ruins: Dictionary = state.portals.get("ruins", {})
	for k in ruins:
		if int(ruins[k]) == 0 and is_explored(int(k)):
			var c := g.systems[int(k)].position
			for i in 8:
				var a0 := TAU * i / 8.0
				draw_arc(c, 15.0 * px, a0, a0 + TAU / 16.0, 4, Color(0.6, 0.6, 0.62, 0.8), 1.6 * px, true)


func _draw_swirl(p: Vector2, px: float, col: Color) -> void:
	for k in 3:
		var r := (5.0 + k * 3.5) * px
		draw_arc(p + Vector2(0, 0), r, k * 1.3, k * 1.3 + PI * 1.4, 12, col, 1.3 * px, true)


## Convois de réfugiés (voir Movements) : un cercle bleu pâle sous l'étoile, avec leur nombre.
func _draw_convoys(px: float) -> void:
	if state == null or state.moves.is_empty() or not state.moves.has("convoys"):
		return
	var col := Color(0.62, 0.8, 0.95)
	var seen := {}
	for cv: Dictionary in Movements.convoys(state):
		var sid := int(cv["sid"])
		if seen.has(sid) or (fog and not _seen.has(sid)):
			continue
		seen[sid] = true
		var n := 0
		for x: Dictionary in Movements.convoys_at(state, sid):
			n += int(x["n"])
		draw_set_transform(galaxy.systems[sid].position + Vector2(-20.0, 16.0) * px, 0.0, Vector2(px, px))
		draw_circle(Vector2.ZERO, 8.5, Color(0.02, 0.05, 0.09, 0.9))
		draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, col, 1.4, true)
		# Trois silhouettes : une famille en route.
		for c in [Vector2(-3.4, 1.0), Vector2(0, -0.6), Vector2(3.4, 1.0)]:
			draw_circle(c + Vector2(0, -2.2), 1.4, col)
			draw_line(c + Vector2(0, -0.6), c + Vector2(0, 3.6), col, 1.6, true)
		draw_string(_font, Vector2(10, 4), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Nids de la Faune (voir Fauna) : trois œufs verts au-dessus du système exploré.
func _draw_nests(px: float) -> void:
	if state == null or not Fauna.active(state):
		return
	var col := Color(String(GameData.creatures()["npc"]["color"]))
	for sid in Fauna.nest_ids(state):
		if not is_explored(sid):
			continue
		draw_set_transform(galaxy.systems[sid].position + Vector2(0, -20.0 * px), 0.0, Vector2(px, px))
		draw_circle(Vector2.ZERO, 8.5, Color(0.02, 0.07, 0.05, 0.85))
		draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, col, 1.4, true)
		for c in [Vector2(-3.2, 2.0), Vector2(3.2, 2.0), Vector2(0, -2.8)]:
			draw_circle(c, 2.4, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_guardians(px)


## Gardiens éveillés (voir Guardians) : un crâne pâle à gauche du système exploré.
func _draw_guardians(px: float) -> void:
	var bone := Color(0.93, 0.89, 0.8)
	for gid in Guardians.ids(state):
		if String(Guardians.list(state)[gid]["status"]) != "awake":
			continue
		var sid := Guardians.fleet_system(state, gid)
		if sid < 0 or not is_explored(sid):
			continue
		var off := Vector2(-20.0, 0.0) * px  # à gauche de l'étoile : le nom est au-dessus, les flottes à droite
		draw_set_transform(galaxy.systems[sid].position + off, 0.0, Vector2(px, px))
		draw_circle(Vector2.ZERO, 8.5, Color(0.1, 0.02, 0.04, 0.9))
		draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, Color(0.85, 0.2, 0.25), 1.4, true)
		draw_circle(Vector2(0, -1), 4.6, bone)
		draw_rect(Rect2(-2.6, 2.2, 5.2, 3.0), bone)
		draw_circle(Vector2(-1.8, -1.2), 1.3, Color(0.1, 0.02, 0.04))
		draw_circle(Vector2(1.8, -1.2), 1.3, Color(0.1, 0.02, 0.04))
		draw_line(Vector2(0, 2.4), Vector2(0, 5.0), Color(0.1, 0.02, 0.04), 0.8)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Crise de fin de partie (voir Crisis, prop. 17 et 30) : un anneau magenta autour des systèmes tombés,
## et ses points faibles, connus de tous, en losange sous l'étoile (plein pour le cœur).
func _draw_crisis(px: float) -> void:
	if state == null or state.crisis.is_empty():
		return
	# Étoiles éteintes par la Nuit lente (ou qui se rallument) : un voile sombre.
	var dark := (Crisis.cur(state).get("dark", {}) as Dictionary).keys() + (state.crisis.get("dark_after", {}) as Dictionary).keys()
	for sid in dark:
		var dp: Vector2 = galaxy.systems[int(sid)].position
		draw_circle(dp, 13.0 * px, Color(0.03, 0.02, 0.08, 0.72))
		draw_arc(dp, 13.0 * px, 0.0, TAU, 24, Color(0.45, 0.35, 0.75, 0.6), 1.2 * px, true)
	if not Crisis.active(state):
		return
	var col := Color(String(GameData.crises()["npc"]["color"]))
	for sid in Crisis.held(state):
		var p: Vector2 = galaxy.systems[int(sid)].position
		draw_arc(p, 15.0 * px, 0.0, TAU, 28, Color(col, 0.85), 2.2 * px, true)
		draw_arc(p, 18.5 * px, 0.0, TAU, 28, Color(col, 0.35), 1.2 * px, true)
	for f in Crisis.stations(state):
		var heart := Crisis.role_of(state, f.id) == Crisis.ROLE_HEART
		draw_set_transform(galaxy.systems[f.system_id].position + Vector2(-20.0, 16.0) * px, 0.0, Vector2(px, px))
		var r := 9.0 if heart else 7.0
		var pts := PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
		draw_colored_polygon(pts, col if heart else Color(0.12, 0.02, 0.08, 0.9))
		pts.append(Vector2(0, -r))
		draw_polyline(pts, col.lightened(0.3), 1.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Quêtes galactiques (voir Quests) : l'artéfact du Passage (losange violet, et ses deux prochaines
## étapes en pointillés), les Phares du Conclave (couleur du camp qui les tient), les tombeaux éveillés.
func _draw_quests(px: float) -> void:
	if state == null or state.galactic.is_empty():
		return
	var cur := Quests.current(state)
	if cur.is_empty():
		return
	match String(cur["id"]):
		"passage":
			var path: Array = cur["path"]
			var step := int(cur["step"])
			var vio := Color(0.78, 0.6, 0.98)
			for i in range(step + 1, mini(step + 3, path.size())):
				var a: Vector2 = galaxy.systems[int(path[i - 1])].position
				var b: Vector2 = galaxy.systems[int(path[i])].position
				draw_dashed_line(a, b, Color(vio, 0.5), 1.5 * px, 6.0 * px, true)
			if not is_known(int(path[step])):
				return
			var sp: Vector2 = galaxy.systems[int(path[step])].position
			draw_set_transform(sp + Vector2(0, 22.0 * px), 0.0, Vector2(px, px))
			var pts := PackedVector2Array([Vector2(0, -9), Vector2(7, 0), Vector2(0, 9), Vector2(-7, 0)])
			draw_colored_polygon(pts, Color(0.12, 0.06, 0.2, 0.9))
			pts.append(Vector2(0, -9))
			draw_polyline(pts, vio, 1.6, true)
			draw_circle(Vector2.ZERO, 2.2, vio)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"conclave":
			var camps: Array = Quests.gdef("conclave")["camps"]
			for sid in cur.get("phares", []):
				if not is_known(int(sid)):
					continue
				var held := Quests.phare_holders(state, cur, int(sid))
				var col := Color(0.7, 0.72, 0.76)
				if held.size() == 1:
					col = Color(String(camps[int(held[0])]["color"]))
				draw_set_transform(galaxy.systems[int(sid)].position + Vector2(0, 22.0 * px), 0.0, Vector2(px, px))
				draw_circle(Vector2.ZERO, 8.5, Color(0.06, 0.05, 0.02, 0.85))
				draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, col, 1.4, true)
				draw_colored_polygon(PackedVector2Array([Vector2(-2.5, 5), Vector2(2.5, 5), Vector2(1.5, -3), Vector2(-1.5, -3)]), col)
				draw_circle(Vector2(0, -5), 2.2, Color(col, 0.9))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"tombeaux":
			var green := Color(0.55, 0.9, 0.6)
			for t: Dictionary in cur.get("tombs", []):
				if int(t["alive"]) == 0 or not is_known(int(t["sid"])):
					continue
				draw_set_transform(galaxy.systems[int(t["sid"])].position + Vector2(0, 22.0 * px), 0.0, Vector2(px, px))
				draw_circle(Vector2.ZERO, 8.5, Color(0.02, 0.07, 0.03, 0.85))
				draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, green, 1.4, true)
				draw_arc(Vector2(0, -0.5), 4.5, PI, TAU, 10, green, 1.4, true)
				draw_line(Vector2(-4.5, -0.5), Vector2(-4.5, 4.5), green, 1.4, true)
				draw_line(Vector2(4.5, -0.5), Vector2(4.5, 4.5), green, 1.4, true)
				draw_line(Vector2(-4.5, 4.5), Vector2(4.5, 4.5), green, 1.4, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_stability(s: StarSystem, px: float, mine: bool) -> void:
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var col := Stability.tier_color(state, s.id) if mine else Color(0.62, 0.64, 0.68)
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, col, 2.4, true)
	var text := ""
	if mine and Stability.applies(state, viewer):
		text = "%d · %s" % [Stability.value(state, s.id), Stability.tier_label(state, s.id)]
		if Stability.active_decree(state, s.id) != "":
			text += " ✦"
	elif not mine:
		text = "Monde libre"
	if text != "":
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 16), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
		draw_string(_font, Vector2(-tw * 0.5, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Mode Corruption : couleur selon la corruption, « siège » sur la capitale et les Préfectures.
func _draw_corruption(s: StarSystem, px: float) -> void:
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var cor := Admin.corruption(state, s.id)
	var col := AdminUi.corruption_color(cor)
	if Admin.is_integrated(state, s.id):
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, col, 2.4, true)
	else:
		for i in 8:
			draw_arc(Vector2.ZERO, 13.0, i * TAU / 8.0, i * TAU / 8.0 + TAU / 16.0, 4, col, 2.4, true)
	var seat := Admin.seat_of(state, s.id)
	var text := "%d %%" % cor
	if seat == s.id:
		text += " · siège"
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 28, Color(0.95, 0.78, 0.36), 1.4, true)
	elif seat < 0:
		text += " · enclave"
	if not Admin.is_integrated(state, s.id):
		text += " · non intégré"
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 16), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
	draw_string(_font, Vector2(-tw * 0.5, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Mode Fiscalité : franchise, grève, fuite fiscale ; cote et dette sur la capitale.
func _draw_fiscal(s: StarSystem, px: float) -> void:
	if state.finance.is_empty():
		return
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var parts := PackedStringArray()
	var col := Color(0.55, 0.58, 0.62)
	if Finance.has_franchise(state, s.id):
		col = Color(0.92, 0.78, 0.36)
		parts.append("franchise")
	var leak := Finance.leak_pct(state, viewer, s.id)
	if leak > 0:
		parts.append("fuite %d %%" % leak)
		if col == Color(0.55, 0.58, 0.62):
			col = Color(0.88, 0.57, 0.23)
	if Finance.on_strike(state, s.id):
		col = Color(0.86, 0.33, 0.31)
		parts.append("grève")
	if FactionTraits.capital_system(state, viewer) == s.id:
		var g := Finance.grade(state, viewer)
		parts.append("cote %s · dette %d / %d" % [g, Finance.debt(state, viewer), Finance.cap(state, viewer)])
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, col, 2.4, true)
	if not parts.is_empty():
		var text := " · ".join(parts)
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 16), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
		draw_string(_font, Vector2(-tw * 0.5, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Lentille de l'Amphictyonie : statut du propriétaire, et ses voix sur son système capitale.
func _draw_amph(s: StarSystem, px: float, o: int) -> void:
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var col := Color(0.86, 0.36, 0.33) if Amphictyony.outlaw(state, o) else (Color(0.92, 0.76, 0.36) if Amphictyony.is_member(state, o) else Color(0.55, 0.58, 0.62))
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, col, 2.4, true)
	if FactionTraits.capital_system(state, o) == s.id:
		var text := "Hors de l'Amphictyonie"
		if Amphictyony.outlaw(state, o):
			text = "Hors-la-loi"
		if Amphictyony.is_member(state, o):
			text = ("%d voix" % Amphictyony.weight(state, o)) + (" · hors-la-loi" if Amphictyony.outlaw(state, o) else "")
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 16), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
		draw_string(_font, Vector2(-tw * 0.5, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Lentille du rayonnement : palier de la culture du joueur chez le propriétaire, ou défection en cours.
func _draw_culture(s: StarSystem, px: float, o: int) -> void:
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var text := ""
	var col := Color(0.85, 0.88, 0.92)
	if o == viewer:
		var top := Culture.top_influencer(state, viewer)
		if int(top[1]) >= 0:
			col = Culture.tier_color(int(top[0]))
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, col, 1.6, true)
		if FactionTraits.capital_system(state, o) == s.id and int(top[1]) >= 0:
			text = "Chez vous : %s (%s)" % [state.get_empire(int(top[1])).short_name(), Culture.tier_label(int(top[0]))]
	else:
		var t := Culture.tier(state, viewer, o)
		col = Culture.tier_color(t)
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, col, 1.4 + 0.5 * t, true)
		if FactionTraits.capital_system(state, o) == s.id:
			text = "%s · %d %%" % [Culture.tier_label(t), Culture.ratio_pct(state, viewer, o)]
	for d in CultureLife.defections_of(state, viewer):
		if int(d[0]) == s.id:
			draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 28, Color(0.95, 0.5, 0.9), 2.0, true)
			text = "Défection : %d mois" % int(int(d[2]) / 30.0)
	if text != "":
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 16), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
		draw_string(_font, Vector2(-tw * 0.5, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


const BORDER_OPEN_COLOR := Color(0.45, 0.85, 0.5)
const BORDER_GUARDED_COLOR := Color(0.92, 0.72, 0.35)
const BORDER_CLOSED_COLOR := Color(0.88, 0.33, 0.3)


## Lentille des frontières : accès du joueur chez le propriétaire, intrus chez le joueur.
func _draw_borders(s: StarSystem, px: float, o: int) -> void:
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	if o == viewer:
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, Color(0.85, 0.88, 0.92), 1.6, true)
		var n := 0
		for it in Borders.intrusions_in(state, viewer):
			var f: Fleet = state.fleets.get(int(it[0]))
			if f != null and f.system_id == s.id:
				n += 1
		if n > 0:
			var pts := PackedVector2Array([Vector2(0, 17), Vector2(6, 23), Vector2(0, 29), Vector2(-6, 23)])
			draw_colored_polygon(pts, BORDER_CLOSED_COLOR)
			draw_string(_font, Vector2(9, 28), "intrus" if n == 1 else "%d intrus" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, BORDER_CLOSED_COLOR)
	elif viewer >= 0:
		var col := BORDER_GUARDED_COLOR
		if Borders.grants(state, o, viewer):
			col = BORDER_OPEN_COLOR
		elif not Borders.civil_ok(state, o, viewer):
			col = BORDER_CLOSED_COLOR
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, col, 2.4, true)
		if FactionTraits.capital_system(state, o) == s.id:
			var text := Borders.policy_label(Borders.policy(state, o, viewer))
			if Borders.grants(state, o, viewer):
				text = "Libre-passage"
			var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 16), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
			draw_string(_font, Vector2(-tw * 0.5, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Lentille de guerre : ennemi, revendication, occupation.
func _draw_war(s: StarSystem, px: float, o: int) -> void:
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var me := state.get_empire(viewer)
	if me != null and me.wars.has(o):
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, Color(0.86, 0.33, 0.3), 2.4, true)
	if state.wars_on and viewer >= 0 and Wars.has_claim(state, viewer, s.id):
		for k in 10:
			draw_arc(Vector2.ZERO, 17.0, TAU * k / 10.0, TAU * (k + 0.5) / 10.0, 4, Color(0.95, 0.8, 0.35), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_occupation(s, px)


## Système occupé : hachures à la couleur de l'occupant (aussi sur la carte ordinaire).
func _draw_occupation(s: StarSystem, px: float) -> void:
	if state == null or not state.wars_on:
		return
	var occ := WarPeace.occupier(state, s.id)
	if occ < 0 or not is_explored(s.id):
		return
	var e := state.get_empire(occ)
	if e == null:
		return
	var col := Color(e.color(), 0.9)
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var r := 15.0
	draw_circle(Vector2.ZERO, r, Color(col, 0.18))
	for i in range(-3, 4):
		var x := i * 4.5
		var h := sqrt(maxf(0.0, r * r - x * x)) * 0.9
		draw_line(Vector2(x - h * 0.4, h), Vector2(x + h * 0.4, -h), col, 1.8, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Lentille politique : courant dominant du système et représentation.
func _draw_politics(s: StarSystem, px: float) -> void:
	var op := Politics.opinion(state, s.id)
	if op.is_empty() or not Politics.applies(state, viewer):
		return
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var top := Politics._argmax(op)
	var col := Politics.color(top)
	var part := Politics.stability_part(state, s.id, viewer)
	if part.is_empty() or int(part[1]) >= 0:
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, col, 2.4, true)
	else:
		for k in 12:
			draw_arc(Vector2.ZERO, 13.0, TAU * k / 12.0, TAU * (k + 0.55) / 12.0, 4, col, 2.4, true)
	@warning_ignore("integer_division")
	var text := "%s %d %%" % [Politics.short(state, viewer, top), (int(op[top]) + 5) / 10]
	if not part.is_empty():
		text += "  %+d" % int(part[1])
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 16), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
	draw_string(_font, Vector2(-tw * 0.5, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.lightened(0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Habitants de chaque espèce dans un système (colonies du joueur regardé).
func system_peoples(sid: int) -> Dictionary:
	var out := {}
	for pid in galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != viewer:
			continue
		var cnt := Peoples.counts(state, c)
		for fid in cnt:
			out[fid] = int(out.get(fid, 0)) + int(cnt[fid])
	return out


func _draw_peoples(s: StarSystem, px: float) -> void:
	var cnt := system_peoples(s.id)
	var total := 0
	for fid in cnt:
		total += int(cnt[fid])
	if total <= 0:
		return
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var keys := cnt.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(cnt[a]) > int(cnt[b]) or (int(cnt[a]) == int(cnt[b]) and a < b))
	var start := -PI * 0.5
	for fid: String in keys:
		var span := TAU * float(cnt[fid]) / float(total)
		var col := Color.html(String(GameData.faction(fid).get("color", "#cccccc")))
		draw_arc(Vector2.ZERO, 13.0, start, start + span, maxi(4, int(28.0 * span / TAU)), col, 3.0, true)
		start += span
	var top: String = keys[0]
	@warning_ignore("integer_division")
	var text := "%s %d %%" % [Peoples.label(top), int(cnt[top]) * 100 / total]
	if keys.size() > 1:
		text += "  +%d" % (keys.size() - 1)
	var tcol := Color.html(String(GameData.faction(top).get("color", "#cccccc")))
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 16), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
	draw_string(_font, Vector2(-tw * 0.5, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tcol.lightened(0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Fidèles de chaque croyance dans un système (colonies du joueur regardé ; "" = cultes natals).
func system_faiths(sid: int) -> Dictionary:
	var out := {}
	for pid in galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != viewer:
			continue
		var cnt := Faiths.visible_counts(state, c, viewer)
		for fid in cnt:
			out[fid] = int(out.get(fid, 0)) + int(cnt[fid])
	return out


func _draw_faith(s: StarSystem, px: float) -> void:
	var cnt := system_faiths(s.id)
	var total := 0
	for fid in cnt:
		total += int(cnt[fid])
	if total <= 0:
		return
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	var keys := cnt.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(cnt[a]) > int(cnt[b]) or (int(cnt[a]) == int(cnt[b]) and a < b))
	var start := -PI * 0.5
	for fid: String in keys:
		var span := TAU * float(cnt[fid]) / float(total)
		var col := Color(0.45, 0.45, 0.42) if fid == Faiths.NATIVE else Faiths.color_of(state, fid)
		draw_arc(Vector2.ZERO, 13.0, start, start + span, maxi(4, int(28.0 * span / TAU)), col, 3.0, true)
		start += span
	var top: String = keys[0]
	@warning_ignore("integer_division")
	var text := "%s %d %%" % [Faiths.name_of(state, top), int(cnt[top]) * 100 / total]
	var tcol := Color(0.7, 0.7, 0.66) if top == Faiths.NATIVE else Faiths.color_of(state, top).lightened(0.2)
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_rect(Rect2(Vector2(-tw * 0.5 - 5, 16), Vector2(tw + 10, 18)), Color(0.02, 0.03, 0.05, 0.9))
	draw_string(_font, Vector2(-tw * 0.5, 30), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tcol)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Mondes saints des systèmes explorés : une étoile dorée à huit branches.
func _draw_holy_worlds(px: float) -> void:
	if not state.faith_on:
		return
	var e := state.get_empire(viewer)
	for fid in Faiths.ids(state):
		var sid := galaxy.get_planet(int(Faiths.faith(state, fid)["holy"])).system_id
		if e != null and not e.explored.has(sid) and owner_of(sid) != viewer:
			continue
		var s := galaxy.systems[sid]
		draw_set_transform(s.position, 0.0, Vector2(px, px))
		var col := Faiths.color_of(state, fid).lightened(0.3)
		var pts := PackedVector2Array()
		for i in 16:
			var r := 20.0 if i % 2 == 0 else 9.0
			var a := -PI / 2.0 + i * PI / 8.0
			pts.append(Vector2(cos(a), sin(a)) * r + Vector2(0, -26))
		draw_colored_polygon(pts, Color(col, 0.85))
		var text := Faiths.name_of(state, fid)
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_font, Vector2(-tw * 0.5, -50), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
