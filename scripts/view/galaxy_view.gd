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
## Portée d'un système dans le champ des territoires, et des points semés le long des voies.
const TERRITORY_RADIUS := 95.0
const TERRITORY_LANE_REACH := 0.55
const TERRITORY_LANE_STEP := 55.0
## Côté de l'image du champ des territoires.
const TERRITORY_TEXTURE := 1024
const TERRITORY_FIELD_SHADER := preload("res://shaders/territory_field.gdshader")
const TERRITORY_SHADER := preload("res://shaders/territory.gdshader")
## Paliers de zoom (refonte, B1) : de loin les empires, à mi-distance les systèmes et les flottes,
## de près les silhouettes et les cargos.
const TIER_GALAXY := 0
const TIER_REGION := 1
const TIER_SYSTEM := 2
const TIER_REGION_ZOOM := 0.3
const TIER_SYSTEM_ZOOM := 1.4
## Zoom visé par les trois boutons de palier.
const TIER_JUMP: Array[float] = [0.2, 0.45, 1.8]
const TIER_NAMES: Array[String] = ["Galaxie", "Région", "Système"]
## Insignes de flotte (B2) : au plus quatre en éventail sous l'étoile, le reste derrière un « +N ».
const FAN_MAX := 4
const FAN_RADIUS := 30.0
const FAN_STEP := 0.7
## Calques de la carte (A3), cochés dans le sélecteur de lentilles.
const LAYERS: Array = [["routes", "Routes", "Vos routes commerciales, et leurs cargos vus de près"], ["fleets", "Flottes", "Les flottes et leurs insignes"],
		["names", "Noms", "Les noms des systèmes"], ["sites", "Curiosités", "Merveilles, mégastructures, fouilles, mondes vivants"],
		["terrain", "Terrains", "Nébuleuses, tempêtes et épaves"]]

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
## Calques affichés (voir LAYERS).
var layers := {"routes": true, "fleets": true, "names": true, "sites": true, "terrain": true}
## Territoires : image du champ, recalculée quand la carte connue change (voir _update_territory).
var _terr_sig := -1
var _terr_view: SubViewport
var _terr_field: ColorRect
var _terr_sprite: Sprite2D
## Flottes à l'arrêt masquées derrière un « +N », par système : {pos, ids}.
var _overflow := {}
## Des cargos circulent (palier Système) : la carte se redessine à chaque image.
var _cargo_live := false


const BATTLE_COLOR := Color(1.0, 0.42, 0.36)
const GROUND_BATTLE_COLOR := Color(0.95, 0.68, 0.32)


func _ready() -> void:
	_font = UiTheme.body_font()
	_build_territory()


func set_state(value: GameState) -> void:
	state = value
	galaxy = value.galaxy if value else null
	_terr_sig = -1
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
	if _cargo_live:
		queue_redraw()


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
	if not layers["fleets"]:
		return best
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


## Palier d'un zoom (voir TIER_*).
static func tier_of(z: float) -> int:
	if z < TIER_REGION_ZOOM:
		return TIER_GALAXY
	return TIER_SYSTEM if z >= TIER_SYSTEM_ZOOM else TIER_REGION


## Palier affiché.
func tier() -> int:
	return tier_of(_zoom())


func set_layer(id: String, on: bool) -> void:
	layers[id] = on
	queue_redraw()


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

	var t := tier()
	_draw_territory(px, t)
	if layers["terrain"]:
		_draw_terrain(px)
		_draw_wrecks(px)

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
	_draw_trade_layer(px, t)

	for s in galaxy.systems:
		if is_explored(s.id):
			_draw_system(s, px)
			_draw_occupation(s, px)
		elif is_known(s.id):
			_draw_unknown_system(s, px)

	if layers["fleets"]:
		_draw_fleets(px)
	_draw_conflicts(px)
	if t != TIER_GALAXY:
		# De loin, la carte ne garde que les empires, les fronts et la crise.
		_draw_lairs(px)
		_draw_minors(px)
		if layers["sites"]:
			_draw_wonders(px)
			_draw_oeuvres(px)
			_draw_megas(px)
			_draw_forge(px)
			_draw_living(px)
			_draw_archaeo(px)
			_draw_contact(px)
		_draw_quests(px)
		_draw_convoys(px)
	_draw_crisis(px)

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
	if lens == "psionics" and state != null:
		# Lentille psionique : vos systèmes selon le niveau de leurs espèces, Collèges (C), écrans (E),
		# Phare (P) et sa zone, et partout où vous avez exploré : l'ambre de songe et les mondes hantés.
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		for s in galaxy.systems:
			var mine := owner_of(s.id) == viewer
			var e := state.get_empire(viewer)
			if mine or (e != null and e.explored.has(s.id)):
				_draw_system(s, px)
				_draw_label(s, px, mine)
				_draw_psionics(s, px, mine)
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
	if lens == "sensors" and state != null:
		# Lentille Senseurs (second clic de la lentille de guerre, furtivité) : sur chaque système exploré,
		# le camouflage le plus fort que vos senseurs (et ceux de vos alliés) percent, de 0 à 5 ; rien
		# là où vous êtes aveugle. Les anneaux blancs marquent vos postes fixes (colonies, stations, balises).
		draw_rect(Rect2(-4000, -4000, 8000, 8000), Color(0.0, 0.01, 0.02, 0.72))
		var posts := {}
		for src in Stealth.sources(state, viewer):
			if int(src[3]) == 1:
				posts[int(src[0])] = true
		for s in galaxy.systems:
			if not is_explored(s.id):
				continue
			_draw_system(s, px)
			_draw_label(s, px, owner_of(s.id) == viewer)
			_draw_sensors(s, px, Stealth.coverage(state, viewer, s.id), posts.has(s.id))
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
	_draw_labels(px, t)
	_draw_empire_names(px)


## Étiquettes de la carte des empires. De loin, seules les capitales et le système choisi sont nommés ;
## plus près, une étiquette qui en recouvrirait une autre passe sous son étoile, ou s'efface.
func _draw_labels(px: float, t: int) -> void:
	var show_all := _zoom() >= LABEL_MIN_ZOOM
	var show_dots := _zoom() >= PLANET_DOTS_MIN_ZOOM
	var first: Array[StarSystem] = []
	var owned: Array[StarSystem] = []
	var rest: Array[StarSystem] = []
	for s in galaxy.systems:
		if not is_explored(s.id):
			continue
		var chosen := s.id == selected_id or s.id == hovered_id
		if chosen:
			first.append(s)
		elif not layers["names"]:
			continue
		elif t == TIER_GALAXY:
			if is_capital(s.id):
				owned.append(s)
		elif state != null and owner_of(s.id) >= 0:
			owned.append(s)
		elif show_all:
			rest.append(s)
	var placed: Array[Rect2] = []
	var z := _zoom()
	for group: Array in [first, owned, rest]:
		for s: StarSystem in group:
			var chosen := s.id == selected_id or s.id == hovered_id
			var key := chosen or (state != null and owner_of(s.id) >= 0)
			var w := _font.get_string_size(s.system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x + 14.0
			var at := s.position * z
			var box := Rect2(at.x - w * 0.5, at.y - 34.0, w, 21.0)
			var dy := 0.0
			if _overlaps(box, placed):
				box.position.y += 52.0
				dy = 52.0
				if _overlaps(box, placed):
					if not chosen:
						continue
					box.position.y -= 52.0
					dy = 0.0
			placed.append(box)
			var dots := dy == 0.0 and t != TIER_GALAXY and (show_dots or key) \
					and (not fog or state == null or Fleets.is_surveyed(state, viewer, s.id))
			_draw_label(s, px, dots, dy)


static func _overlaps(box: Rect2, placed: Array[Rect2]) -> bool:
	for r in placed:
		if r.intersects(box):
			return true
	return false


## Le système porte-t-il la capitale de son propriétaire connu ?
func is_capital(sid: int) -> bool:
	if state == null:
		return false
	var owner := state.get_empire(owner_of(sid))
	return owner != null and galaxy.systems[sid].planet_ids.has(owner.capital_planet)


## Nom de chaque empire en grandes lettres sur son territoire (B5b), au palier Galaxie ; il s'efface
## en fondu à l'approche du palier Région.
func _draw_empire_names(px: float) -> void:
	if state == null:
		return
	var z := _zoom()
	var alpha := 1.0 - smoothstep(TIER_REGION_ZOOM * 0.85, TIER_REGION_ZOOM * 1.2, z)
	if alpha <= 0.02:
		return
	var groups := {}
	for s in galaxy.systems:
		if not is_explored(s.id):
			continue
		var o := owner_of(s.id)
		if o < 0 or state.get_empire(o) == null:
			continue
		if not groups.has(o):
			groups[o] = []
		(groups[o] as Array).append(s.position)
	# Le vôtre d'abord, puis les plus grands ; un nom qui en recouvrirait un autre attend qu'on s'approche.
	var order := groups.keys()
	order.sort_custom(func(a: int, b: int) -> bool:
		if (a == viewer) != (b == viewer):
			return a == viewer
		var na := (groups[a] as Array).size()
		var nb := (groups[b] as Array).size()
		return na > nb or (na == nb and a < b))
	var placed: Array[Rect2] = []
	for o: int in order:
		var pts: Array = groups[o]
		var c := Vector2.ZERO
		for p: Vector2 in pts:
			c += p
		c /= float(pts.size())
		var mean := c
		# Le nom se pose sur le territoire : à mi-chemin du centre et du système le plus central.
		var core: Vector2 = pts[0]
		for p: Vector2 in pts:
			if p.distance_squared_to(mean) < core.distance_squared_to(mean):
				core = p
		var sxx := 0.0
		var syy := 0.0
		var sxy := 0.0
		for p: Vector2 in pts:
			var d := p - mean
			sxx += d.x * d.x
			syy += d.y * d.y
			sxy += d.x * d.y
		# Le nom suit le grand axe du territoire, sans jamais trop pencher.
		var angle := clampf(0.5 * atan2(2.0 * sxy, sxx - syy), -0.5, 0.5) if pts.size() > 1 else 0.0
		var spread := sqrt((sxx + syy) / float(pts.size()))
		var size := int(clampf(spread * z * 0.28, 12.0, 22.0))
		var text := " ".join(state.get_empire(o).display_name().to_upper().split(""))
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		c = mean.lerp(core, 0.5)
		# L'emblème au-dessus, le nom dessous, comme sur la carte de Stellaris.
		var er := clampf(size * 0.95, 13.0, 22.0)
		var h := size + absf(sin(angle)) * w + er * 2.0 + 6.0
		var box := Rect2(c.x * z - w * 0.5, c.y * z - h * 0.5, w, h)
		if _overlaps(box, placed):
			# Pas la place pour le nom : l'emblème seul, s'il tient.
			var small := Rect2(c.x * z - er, c.y * z - er, er * 2.0, er * 2.0)
			if not _overlaps(small, placed):
				placed.append(small)
				draw_set_transform(c, 0.0, Vector2(px, px))
				draw_emblem(self, Vector2.ZERO, er * 0.8, state.get_empire(o).faction_id, Color(1, 1, 1, 0.9 * alpha))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			continue
		placed.append(box)
		draw_set_transform(c, 0.0, Vector2(px, px))
		draw_emblem(self, Vector2(0, -er - 2.0), er, state.get_empire(o).faction_id, Color(1, 1, 1, 0.92 * alpha))
		draw_set_transform(c, angle * 0.5, Vector2(px, px))
		var base := size * 0.35 + size * 0.5 + 6.0
		draw_string_outline(_font, Vector2(-w * 0.5, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0.01, 0.02, 0.04, 0.7 * alpha))
		draw_string(_font, Vector2(-w * 0.5, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.85 * alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Nombre de motifs d'emblème.
const EMBLEM_MOTIFS := 8


## Motif et variante de l'emblème d'un peuple : tirés de son identifiant, donc toujours les mêmes.
static func emblem_of(faction_id: String) -> Vector2i:
	var h := absi(hash("emblem:" + faction_id))
	return Vector2i(h % EMBLEM_MOTIFS, (h / EMBLEM_MOTIFS) % 3)


## Emblème provisoire d'un peuple, en attendant les icônes dessinées : un cercle et un motif blanc
## (étoile, anneaux, croissant, chevrons, soleil, losanges, trident, hexagone) en trois variantes.
static func draw_emblem(on: CanvasItem, c: Vector2, r: float, faction_id: String, col: Color) -> void:
	var e := emblem_of(faction_id)
	var v := e.y
	on.draw_circle(c, r, Color(0.02, 0.03, 0.05, 0.55 * col.a))
	on.draw_arc(c, r, 0.0, TAU, 40, col, maxf(1.5, r * 0.11), true)
	var k := r * 0.62
	match e.x:
		0:  # étoile à 4, 5 ou 6 branches
			var n := 4 + v
			var pts := PackedVector2Array()
			for i in n * 2:
				pts.append(c + Vector2.from_angle(-PI * 0.5 + PI * i / n) * (k if i % 2 == 0 else k * 0.42))
			on.draw_colored_polygon(pts, col)
		1:  # anneaux emboîtés
			for i in 2 + (1 if v > 0 else 0):
				on.draw_arc(c, k * (1.0 - 0.33 * i), 0.0, TAU, 32, col, maxf(1.5, r * 0.1), true)
			if v == 2:
				on.draw_circle(c, k * 0.14, col)
		2:  # croissant, tourné selon la variante
			var a0 := [0.6, 2.2, 3.8][v] as float
			on.draw_arc(c, k * 0.8, a0, a0 + PI * 1.25, 28, col, k * 0.38, true)
			on.draw_circle(c + Vector2.from_angle(a0 + PI * 1.62) * k * 0.55, k * 0.16, col)
		3:  # chevrons empilés
			for i in 2 + v % 2:
				var y := (i - (1 + v % 2) * 0.5) * k * 0.55
				var up := -1.0 if v == 2 else 1.0
				on.draw_polyline(PackedVector2Array([c + Vector2(-k * 0.75, y + k * 0.3 * up), c + Vector2(0, y - k * 0.3 * up), c + Vector2(k * 0.75, y + k * 0.3 * up)]), col, maxf(2.0, r * 0.14), true)
		4:  # soleil : disque et rayons
			on.draw_circle(c, k * 0.4, col)
			var n := 6 + v * 2
			for i in n:
				var d := Vector2.from_angle(TAU * i / n)
				on.draw_line(c + d * k * 0.58, c + d * k, col, maxf(1.5, r * 0.1), true)
		5:  # losanges
			var n := 1 + v
			for i in n:
				var o := c + Vector2((i - (n - 1) * 0.5) * k * 0.72, 0)
				var s := k * (0.85 if n == 1 else 0.5)
				on.draw_colored_polygon(PackedVector2Array([o + Vector2(0, -s), o + Vector2(s * 0.6, 0), o + Vector2(0, s), o + Vector2(-s * 0.6, 0)]), col)
		6:  # trident
			var w := maxf(2.0, r * 0.14)
			on.draw_line(c + Vector2(0, -k), c + Vector2(0, k), col, w, true)
			var spread := k * (0.5 + 0.12 * v)
			on.draw_polyline(PackedVector2Array([c + Vector2(-spread, -k * 0.8), c + Vector2(-spread, -k * 0.05), c + Vector2(spread, -k * 0.05), c + Vector2(spread, -k * 0.8)]), col, w, true)
			on.draw_line(c + Vector2(-k * 0.35, k * 0.55), c + Vector2(k * 0.35, k * 0.55), col, w, true)
		_:  # hexagone, plein, creux ou pointé
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(c + Vector2.from_angle(PI / 6.0 + TAU * i / 6.0) * k)
			if v == 0:
				on.draw_colored_polygon(pts.slice(0, 6), col)
			else:
				on.draw_polyline(pts, col, maxf(2.0, r * 0.14), true)
				if v == 2:
					on.draw_circle(c, k * 0.3, col)


# --- Routes commerciales, toujours visibles (B4) ------------------------------------------------

## Vos routes actives en trait fin le long des voies, sans passer par la lentille du commerce : à la
## couleur du partenaire, rouges si elles sont bloquées. Au palier Système, de petits cargos les
## parcourent (un par tranche de valeur) ; ce sont des figurants, pas des unités. Une route bloquée
## garde ses cargos à l'arrêt devant le système en cause.
func _draw_trade_layer(px: float, t: int) -> void:
	_cargo_live = false
	if state == null or viewer < 0 or not layers["routes"] or lens == "trade" or lens == "private":
		return
	var now := Time.get_ticks_msec() / 1000.0
	var nth := 0
	for r: Dictionary in Trade.routes_of(state, viewer):
		nth += 1
		var path: Array = r["path"]
		if path.size() < 2:
			continue
		var blocked := bool(r.get("blocked", false))
		var other := int(r["to"]) if int(r["from"]) == viewer else int(r["from"])
		var partner := state.get_empire(other)
		var col: Color = partner.color() if partner else TRADE_INTERNAL_COLOR
		var line := BATTLE_COLOR if blocked else col
		var pts := PackedVector2Array()
		for sid in path:
			if not is_explored(int(sid)):
				break
			pts.append(galaxy.systems[int(sid)].position)
		if pts.size() < 2:
			continue
		var total := 0.0
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			# Décalé d'un rien sur le côté : la voie de saut reste lisible dessous.
			var n := (b - a).normalized().orthogonal() * 2.5 * px
			draw_line(a + n, b + n, Color(line, 0.42), 1.2 * px, true)
			total += a.distance_to(b)
		if blocked and t != TIER_GALAXY and r.has("at") and is_explored(int(r["at"])):
			var at := galaxy.systems[int(r["at"])].position + Vector2(-15.0, -13.0) * px
			draw_circle(at, 5.5 * px, Color(0.02, 0.03, 0.05, 0.9))
			draw_arc(at, 5.5 * px, 0.0, TAU, 16, BATTLE_COLOR, 1.3 * px, true)
			draw_line(at + Vector2(-3.4, 3.4) * px, at + Vector2(3.4, -3.4) * px, BATTLE_COLOR, 1.3 * px, true)
		if t != TIER_SYSTEM or total <= 0.0:
			continue
		_cargo_live = true
		var count := cargo_count(r)
		if blocked:
			var stop := path.find(r.get("at", -1))
			if stop <= 0 or stop >= pts.size():
				continue
			var from := pts[stop - 1]
			var dir := (pts[stop] - from).normalized()
			for i in count:
				_draw_cargo(pts[stop] - dir * (22.0 + 13.0 * i) * px, dir, col, px)
			continue
		for i in count:
			var u := fposmod(now * 26.0 / total + float(i) / float(count) + nth * 0.37, 1.0) * total
			for k in range(pts.size() - 1):
				var seg := pts[k].distance_to(pts[k + 1])
				if u <= seg or k == pts.size() - 2:
					var dir := (pts[k + 1] - pts[k]).normalized()
					_draw_cargo(pts[k] + dir * minf(u, seg) + dir.orthogonal() * 2.5 * px, dir, col, px)
					break
				u -= seg


## Nombre de cargos d'une route : un par tranche de valeur, quatre au plus.
static func cargo_count(r: Dictionary) -> int:
	return clampi(1 + absi(int(r.get("value", 0))) / 12, 1, 4)


func _draw_cargo(pos: Vector2, dir: Vector2, col: Color, px: float) -> void:
	var side := dir.orthogonal()
	var l := 5.0 * px
	var w := 2.2 * px
	var hull := PackedVector2Array([pos + dir * l, pos + dir * l * 0.4 + side * w, pos - dir * l + side * w,
			pos - dir * l - side * w, pos + dir * l * 0.4 - side * w])
	var back := PackedVector2Array()
	for p in hull:
		back.append(pos + (p - pos) * 1.45)
	draw_colored_polygon(back, Color(0.02, 0.03, 0.05, 0.9))
	draw_colored_polygon(hull, col)


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
## Territoires (B5a) : chaque empire occupe une zone continue aux bords arrondis, qui suit ses voies de
## saut, comme sur la carte de Stellaris. Le dessin est confié à deux shaders : le premier calcule, dans
## une image hors écran et seulement quand la carte connue change, à quel empire revient chaque point
## et à quelle distance il est du bord ; le second l'affiche derrière la carte.
func _draw_territory(px: float, t: int) -> void:
	if state == null or _terr_sprite == null:
		return
	_update_territory()
	var mat := _terr_sprite.material as ShaderMaterial
	mat.set_shader_parameter("px", px)
	mat.set_shader_parameter("fill", 0.5 if t == TIER_GALAXY else 0.36)
	mat.set_shader_parameter("rim", 0.2 if t == TIER_GALAXY else 0.24)


## Sites des territoires : [{pos, r, owner, seen}]. Un site par système connu (owner -1 s'il est sans
## maître connu), et des points le long des voies de saut, chacun rendu à l'extrémité la plus proche :
## le territoire suit les voies et s'arrête à mi-chemin d'un voisin.
func territory_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or galaxy == null:
		return out
	var code := {}
	for s in galaxy.systems:
		if not is_known(s.id):
			continue
		var o := -1
		if is_explored(s.id):
			o = owner_of(s.id)
			if o < 0 or state.get_empire(o) == null:
				o = -1
		code[s.id] = o
		out.append({"pos": s.position, "r": TERRITORY_RADIUS, "owner": o, "seen": is_seen(s.id)})
	for lane in galaxy.lanes:
		if not code.has(lane.x) or not code.has(lane.y):
			continue
		if code[lane.x] == -1 and code[lane.y] == -1:
			continue
		var a := galaxy.systems[lane.x].position
		var b := galaxy.systems[lane.y].position
		var n := int(a.distance_to(b) / TERRITORY_LANE_STEP)
		for i in range(1, n + 1):
			var k := float(i) / float(n + 1)
			var near: int = lane.x if k < 0.5 else lane.y
			out.append({"pos": a.lerp(b, k), "r": TERRITORY_RADIUS * TERRITORY_LANE_REACH, "owner": code[near], "seen": is_seen(near)})
	return out


func _update_territory() -> void:
	var sites := territory_sites()
	var sig := hash(str(sites))
	if sig == _terr_sig:
		return
	_terr_sig = sig
	var n := maxi(1, sites.size())
	var data := Image.create(n, 1, false, Image.FORMAT_RGBAF)
	var tints := Image.create(n, 1, false, Image.FORMAT_RGBA8)
	var extent := 600.0
	for i in sites.size():
		var e: Dictionary = sites[i]
		var p: Vector2 = e["pos"]
		extent = maxf(extent, maxf(absf(p.x), absf(p.y)) + TERRITORY_RADIUS + 80.0)
		data.set_pixel(i, 0, Color(p.x, p.y, float(e["r"]), float(e["owner"])))
		var owner := state.get_empire(int(e["owner"]))
		if owner:
			tints.set_pixel(i, 0, owner.color() if bool(e["seen"]) else owner.color().darkened(0.4))
	var mat := _terr_field.material as ShaderMaterial
	mat.set_shader_parameter("sites", ImageTexture.create_from_image(data))
	mat.set_shader_parameter("tints", ImageTexture.create_from_image(tints))
	mat.set_shader_parameter("count", sites.size())
	mat.set_shader_parameter("extent", extent)
	_terr_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_terr_sprite.scale = Vector2.ONE * (extent * 2.0 / float(TERRITORY_TEXTURE))


func _build_territory() -> void:
	_terr_view = SubViewport.new()
	_terr_view.size = Vector2i(TERRITORY_TEXTURE, TERRITORY_TEXTURE)
	_terr_view.transparent_bg = true
	_terr_view.disable_3d = true
	_terr_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_terr_view)
	_terr_field = ColorRect.new()
	_terr_field.size = Vector2(TERRITORY_TEXTURE, TERRITORY_TEXTURE)
	var field := ShaderMaterial.new()
	field.shader = TERRITORY_FIELD_SHADER
	_terr_field.material = field
	_terr_view.add_child(_terr_field)
	_terr_sprite = Sprite2D.new()
	_terr_sprite.texture = _terr_view.get_texture()
	_terr_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_terr_sprite.show_behind_parent = true
	var look := ShaderMaterial.new()
	look.shader = TERRITORY_SHADER
	_terr_sprite.material = look
	add_child(_terr_sprite)


func _draw_system(s: StarSystem, px: float) -> void:
	var color: Color = STAR_COLORS.get(s.star_type, Color.WHITE)
	if not is_seen(s.id):
		color = color.darkened(0.35)  # exploré mais hors de vue : dernières observations
	var r := (6.5 if s.star_type == "blue_giant" else 4.5) * px
	if lens == "" and tier() == TIER_GALAXY:
		# De loin, le territoire dit déjà à qui est le système : l'étoile se fait petite, seule la
		# capitale garde sa marque.
		r *= 0.6
		if is_capital(s.id):
			var cap := _owner_color(state.get_empire(owner_of(s.id)), s.id)
			var d := 5.0 * px
			draw_colored_polygon(PackedVector2Array([s.position + Vector2(0, -d), s.position + Vector2(d, 0), s.position + Vector2(0, d), s.position + Vector2(-d, 0)]), Color(0.02, 0.03, 0.05, 0.9))
			draw_arc(s.position, d * 1.5, 0.0, TAU, 20, cap, 1.6 * px, true)
	else:
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


## Prises de guerre (prop. 46) : champs d'épaves en éclats gris-rouille, Vaisseau-tombe en losange.
## Pas de lentille dédiée : comme le terrain, discret et toujours là.
func _draw_wrecks(px: float) -> void:
	if state == null or not Capture.full(state):
		return
	for k in Capture.sub(state, "fields"):
		var sid := int(k)
		if sid < 0 or sid >= galaxy.systems.size() or not is_explored(sid):
			continue
		@warning_ignore("integer_division")
		var n := mini(9, (Capture.sub(state, "fields")[k] as Array).size() / 3 + 1)
		var h := absi(hash([sid, "epaves"]))
		var pos := galaxy.systems[sid].position
		for i in n:
			var a := float((h >> (i * 2)) % 64) / 64.0 * TAU
			var off := Vector2.from_angle(a) * (16.0 + float((h >> (i + 3)) % 14))
			draw_rect(Rect2(pos + off - Vector2(1.4, 1.0) * px, Vector2(2.8, 2.0) * px), Color(0.72, 0.55, 0.42, 0.65))
	var tsid := CaptureTomb.system(state)
	if tsid >= 0 and tsid < galaxy.systems.size() and is_explored(tsid):
		var tp := galaxy.systems[tsid].position + Vector2(0, -28.0 * px)
		var d := 7.0 * px
		draw_colored_polygon(PackedVector2Array([tp + Vector2(0, -d), tp + Vector2(d, 0), tp + Vector2(0, d), tp + Vector2(-d, 0)]), Color(0.6, 0.3, 0.25, 0.85))


## Système connu mais inexploré : une petite lueur grise, sans nom ni planètes.
func _draw_unknown_system(s: StarSystem, px: float) -> void:
	draw_circle(s.position, 7.0 * px, Color(0.6, 0.65, 0.75, 0.08))
	draw_circle(s.position, 2.2 * px, Color(0.7, 0.74, 0.82, 0.55))
	if s.id == hovered_id or s.id == selected_id:
		draw_arc(s.position, 9.0 * px, 0.0, TAU, 24, SELECT_COLOR if s.id == selected_id else Color(1, 1, 1, 0.5), 1.5 * px, true)


# --- Flottes ------------------------------------------------------------------------------------

## Flottes visibles (refonte, B2). De loin, un tiret par flotte : les vôtres à gauche de l'étoile, les
## autres à droite. Plus près, un insigne dont la forme dit la nature (triangle : guerre, losange :
## éclaireur, cercle : civil), à la couleur du propriétaire, avec le nombre de vaisseaux ; au plus près,
## la silhouette du plus gros vaisseau. La flotte choisie montre son trajet et le délai d'arrivée.
func _draw_fleets(px: float) -> void:
	_fleet_pos = fleet_positions(px)
	var t := tier()
	if selected_fleet >= 0 and _fleet_pos.has(selected_fleet):
		_draw_supply_zone(state.fleets[selected_fleet], px)
		_draw_route(state.fleets[selected_fleet], px)
	for fid in _fleet_pos:
		if t == TIER_GALAXY:
			_draw_fleet_dash(state.fleets[fid], _fleet_pos[fid], px)
		else:
			_draw_fleet_icon(state.fleets[fid], _fleet_pos[fid], px, t)
	for sid: int in _overflow:
		var more: Dictionary = _overflow[sid]
		var text := "+%d" % (more["ids"] as Array).size()
		draw_set_transform(more["pos"], 0.0, Vector2(px, px))
		draw_rect(Rect2(-12, -9, 24, 18), Color(0.02, 0.03, 0.05, 0.9))
		draw_rect(Rect2(-12, -9, 24, 18), Color(0.75, 0.8, 0.88, 0.7), false, 1.0)
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_font, Vector2(-w * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.93, 0.97))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if fog and t != TIER_GALAXY:
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


## Position (monde) de chaque flotte visible par le joueur, telle qu'elle est dessinée. À l'arrêt, les
## flottes d'un système se rangent en éventail sous l'étoile, les vôtres d'abord ; au-delà de quatre,
## les suivantes attendent derrière un insigne « +N » (voir overflow_fleets).
func fleet_positions(px := -1.0) -> Dictionary:
	var out := {}
	_overflow = {}
	if state == null:
		return out
	if px < 0.0:
		px = 1.0 / _zoom()
		if fog:
			_seen = Fleets.visible_systems(state, viewer)
	var far := tier() == TIER_GALAXY
	var mine := {}
	var others := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if fog and not Fleets.fleet_visible(state, viewer, f, _seen):
			continue
		if f.is_moving():
			out[fid] = Fleets.position(state, f, day_fraction)
			continue
		var side: Dictionary = mine if f.owner == viewer else others
		if not side.has(f.system_id):
			side[f.system_id] = []
		(side[f.system_id] as Array).append(fid)
	var at := {}
	for sid: int in mine:
		at[sid] = true
	for sid: int in others:
		at[sid] = true
	for sid: int in at:
		var c := galaxy.systems[sid].position
		var left: Array = mine.get(sid, [])
		var right: Array = others.get(sid, [])
		if far:
			for i in left.size():
				out[left[i]] = c + Vector2(-9.0 - i * 5.0, 0.0) * px
			for i in right.size():
				out[right[i]] = c + Vector2(9.0 + i * 5.0, 0.0) * px
			continue
		var ids: Array = left + right
		var hidden: Array = []
		if ids.size() > FAN_MAX:
			hidden = ids.slice(FAN_MAX)
			ids = ids.slice(0, FAN_MAX)
			# La flotte choisie reste toujours sous les yeux.
			var k := hidden.find(selected_fleet)
			if k >= 0:
				hidden[k] = ids[FAN_MAX - 1]
				ids[FAN_MAX - 1] = selected_fleet
		var slots := ids.size() + (1 if not hidden.is_empty() else 0)
		for i in slots:
			var angle := PI * 0.5 + ((slots - 1) * 0.5 - i) * FAN_STEP
			var pos := c + Vector2.from_angle(angle) * FAN_RADIUS * px
			if i < ids.size():
				out[ids[i]] = pos
			else:
				_overflow[sid] = {"pos": pos, "ids": hidden}
	return out


## Flottes d'un système cachées derrière son insigne « +N ».
func overflow_fleets(sid: int) -> Array:
	return (_overflow[sid]["ids"] as Array).duplicate() if _overflow.has(sid) else []


## Système dont l'insigne « +N » se trouve sous cette position (-1 si aucun).
func pick_overflow(world_pos: Vector2, max_distance: float) -> int:
	if not layers["fleets"]:
		return -1
	fleet_positions()
	for sid: int in _overflow:
		if (_overflow[sid]["pos"] as Vector2).distance_to(world_pos) <= max_distance:
			return sid
	return -1


## Nature d'une flotte, qui donne la forme de son insigne : "war", "scout" ou "civil".
static func fleet_kind(f: Fleet) -> String:
	if Combat.is_armed(f):
		return "war"
	for sh in f.ships:
		if String(sh) != "scout" and String(GameData.ship(String(sh)).get("role", "")) != "Éclaireur":
			return "civil"
	return "scout" if not f.ships.is_empty() else "civil"


## État d'une flotte lisible sans cliquer : "battle" (en combat), "idle" (attend vos ordres),
## "patrol" (ordre permanent), "" sinon. Seul le combat se lit sur les flottes des autres.
func fleet_status(f: Fleet) -> String:
	if not f.is_moving() and state.battles.has(f.system_id) and Espionage.battle_sides(state.battles[f.system_id]).has(f.owner):
		return "battle"
	if f.owner != viewer:
		return ""
	if f.is_idle():
		return "idle"
	return "patrol" if f.is_patrolling() or f.is_guarding() else ""


## Palier Galaxie : la flotte n'est qu'un tiret à la couleur de son empire.
func _draw_fleet_dash(f: Fleet, pos: Vector2, px: float) -> void:
	var col := state.get_empire(f.owner).color()
	if f.id == selected_fleet:
		draw_arc(pos, 7.0 * px, 0.0, TAU, 16, SELECT_COLOR, 1.5 * px, true)
	draw_line(pos + Vector2(0, -5.0) * px, pos + Vector2(0, 5.0) * px, Color(0.02, 0.03, 0.05, 0.9), 4.0 * px)
	draw_line(pos + Vector2(0, -4.0) * px, pos + Vector2(0, 4.0) * px, col, 2.4 * px)


func _draw_fleet_icon(f: Fleet, pos: Vector2, px: float, t := TIER_REGION) -> void:
	var col := state.get_empire(f.owner).color()
	# Furtivité : un simple contact est un insigne gris, sans compte ; vos flottes voilées pâlissent.
	var veiled := false
	var contact := false
	if not state.stealth.is_empty() and viewer >= 0:
		if f.owner == viewer:
			veiled = Stealth.veil_up(state, f)
		elif fog and Stealth.full(state) and Stealth.cloak(state, f) > 0 and Stealth.degree(state, viewer, f, _seen) == 1:
			col = Color(0.62, 0.64, 0.68)
			contact = true
	if veiled:
		col = Color(col, 0.45)
	var dir := Vector2.RIGHT
	var moving := f.is_moving()
	if moving:
		dir = (galaxy.systems[f.path[0]].position - galaxy.systems[f.system_id].position).normalized()
	var chosen := f.id == selected_fleet
	# En route : un trait fin jusqu'à la destination et le délai, pour vos flottes.
	if moving and f.owner == viewer and not chosen:
		var from := pos
		for sid in f.path:
			var to := galaxy.systems[sid].position
			draw_line(from, to, Color(col, 0.3), 1.0 * px, true)
			from = to
	if chosen:
		draw_circle(pos, 16.0 * px, Color(SELECT_COLOR, 0.18))
		draw_arc(pos, 16.0 * px, 0.0, TAU, 24, SELECT_COLOR, 1.5 * px, true)
	var status := "" if contact else fleet_status(f)
	var lead := _lead_ship(f) if (t == TIER_SYSTEM or UiSettings.fleet_silhouettes) and not contact else ""
	var dark := Color(0.02, 0.03, 0.05, 0.9)
	if lead != "":
		# Coques de peuple (prop. 38) : la silhouette du plus gros vaisseau, nez dans le sens de la marche.
		var tex := HullArt.icon(SpeciesLook.hull_style(state.get_empire(f.owner).faction_id), lead, col)
		var h := (20.0 if f.ships.size() > 1 else 17.0) * px
		var w := h * float(tex.get_width()) / float(maxi(1, tex.get_height()))
		draw_set_transform(pos, dir.angle() + PI * 0.5, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-w * 0.5, -h * 0.5, w, h), false, Color(1, 1, 1, col.a))
		draw_set_transform(pos, 0.0, Vector2(px, px))
		if f.ships.size() > 1:
			draw_string(_font, Vector2(8, 12), str(f.ships.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))
	else:
		draw_set_transform(pos, 0.0, Vector2(px, px))
		if status == "patrol":
			draw_arc(Vector2.ZERO, 13.5, 0.0, TAU, 24, Color(col, 0.85), 1.0, true)
		var kind := "civil" if contact else fleet_kind(f)
		var mid := Vector2.ZERO
		match kind:
			"war":
				var pts := PackedVector2Array([Vector2(0, -11.5), Vector2(11.5, 8.0), Vector2(-11.5, 8.0)])
				draw_colored_polygon(pts, dark)
				draw_colored_polygon(_shrunk(pts, Vector2(0, 1.5), 0.76), col)
				mid = Vector2(0, 2.0)
			"scout":
				var pts := PackedVector2Array([Vector2(0, -10.5), Vector2(10.5, 0), Vector2(0, 10.5), Vector2(-10.5, 0)])
				draw_colored_polygon(pts, dark)
				draw_colored_polygon(_shrunk(pts, Vector2.ZERO, 0.8), col)
			_:
				draw_circle(Vector2.ZERO, 9.0, dark)
				draw_circle(Vector2.ZERO, 7.4, col)
		var text := "?" if contact else str(f.ships.size())
		var ink := Color(0.03, 0.04, 0.06, col.a) if col.get_luminance() > 0.42 else Color(1, 1, 1, col.a)
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(_font, mid + Vector2(-w * 0.5, 3.6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)
		if moving:
			# Une pointe devant l'insigne : le sens de la marche.
			var tip := dir * 17.0
			var side := dir.orthogonal() * 3.2
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * 5.0 + side, tip - dir * 5.0 - side]), col)
	# État : point rouge en combat, ambre si la flotte attend vos ordres.
	if status == "battle" or status == "idle":
		draw_circle(Vector2(9.5, -9.5), 4.0, dark)
		draw_circle(Vector2(9.5, -9.5), 2.8, BATTLE_COLOR if status == "battle" else Color(0.96, 0.72, 0.3))
	# Médaillon d'or : un héros commande cette flotte.
	if not Heroes.at_post(state, "fleet", f.id, f.owner).is_empty():
		draw_circle(Vector2(-9.5, -9.5), 3.6, dark)
		draw_circle(Vector2(-9.5, -9.5), 2.6, Color(0.95, 0.78, 0.36))
	if moving and f.owner == viewer and not chosen:
		draw_string(_font, Vector2(13, 14), "%d j" % Fleets.eta_days(state, f), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.89, 0.95, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _shrunk(pts: PackedVector2Array, around: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(around + (p - around) * k)
	return out


## Classe de tête d'une flotte : celle qui a le plus de structure.
func _lead_ship(f: Fleet) -> String:
	var best := ""
	var best_hp := -1
	for sh in f.ships:
		var m := Fleet.max_hp_of(String(sh))
		if m > best_hp:
			best_hp = m
			best = String(sh)
	return best


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
func _draw_label(s: StarSystem, px: float, dots := true, dy := 0.0) -> void:
	# On annule le zoom localement pour que le texte reste net et de taille constante.
	draw_set_transform(s.position + Vector2(0.0, dy) * px, 0.0, Vector2(px, px))
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


## Exodiums de Transcendance connues (prop. 39) : un anneau pâle et une flèche vers le haut sur le système
## de l'Exodium (pulsé pendant le Passage), sans lentille.
func _draw_oeuvres(px: float) -> void:
	if state == null or state.transcendence.is_empty():
		return
	for k in state.transcendence.get("oeuvre", {}):
		var eid := int(k)
		var sid := Transcendence.oeuvre_sys(state, eid)
		if sid < 0 or not is_explored(sid):
			continue
		var e := state.get_empire(eid)
		var col := Color(0.88, 0.84, 1.0) if e == null else e.color().lerp(Color(0.9, 0.88, 1.0), 0.5)
		var pulse := 0.0 if not Transcendence.in_passage(state, eid) else 0.35
		draw_set_transform(galaxy.systems[sid].position + Vector2(19.0, -8.0) * px, 0.0, Vector2(px, px))
		draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 20, Color(col, 0.65 + pulse), 1.4, true)
		draw_line(Vector2(0, 4), Vector2(0, -5), col, 1.6, true)
		draw_line(Vector2(-3, -2), Vector2(0, -5), col, 1.6, true)
		draw_line(Vector2(3, -2), Vector2(0, -5), col, 1.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for k in state.transcendence.get("ark", {}):
		var f := Transcendence.ark_fleet(state, int(k))
		var tgt := int(Transcendence.ark(state, int(k)).get("target", -1))
		if f != null and tgt >= 0 and is_explored(tgt):
			draw_set_transform(galaxy.systems[tgt].position + Vector2(19.0, -8.0) * px, 0.0, Vector2(px, px))
			draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(0.9, 0.88, 1.0, 0.8), 1.2, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Mégastructures connues (voir Megastructures, prop. 43), sans lentille : un arc autour de l'étoile, à la
## couleur du maître (pointillé gris pour une ruine), d'autant plus fermé que l'ouvrage est avancé ;
## une pointe rouge pour une superarme.
func _draw_megas(px: float) -> void:
	if state == null or state.megas.is_empty():
		return
	var done := {}
	for m in Megastructures.all_sorted(state):
		var sid := int(m["s"])
		if done.has(sid) or not is_explored(sid):
			continue
		done[sid] = true
		var ruin := Megastructures.is_ruin(m)
		var e := state.get_empire(int(m["o"]))
		var col := Color(0.6, 0.6, 0.62, 0.8) if ruin or e == null else e.color().lerp(Color(1.0, 0.95, 0.8), 0.3)
		var n := maxi(1, Megastructures.stage_count(String(m["k"])))
		var frac := clampf(float(int(m["st"])) / float(n), 0.15, 1.0)
		draw_set_transform(galaxy.systems[sid].position, 0.0, Vector2(px, px))
		if ruin:
			for i in 6:
				var a := TAU * i / 6.0
				draw_arc(Vector2.ZERO, 13.0, a, a + 0.5, 4, col, 1.2, true)
		else:
			draw_arc(Vector2.ZERO, 13.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 24, col, 1.6, true)
			if bool(Megastructures.kind_def(String(m["k"])).get("weapon", false)):
				draw_line(Vector2(9, -9), Vector2(14, -14), Color(1.0, 0.35, 0.3), 1.8, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Forge des mondes (prop. 40) : un petit carré ambré sous les systèmes connus qui portent un chantier
## planétaire (plein) ou un monde façonné (contour), un losange violet sur les mondes-reliquaires
## scellés repérés. Sans lentille.
func _draw_forge(px: float) -> void:
	if state == null or state.forge.is_empty():
		return
	var amber := Color(0.95, 0.72, 0.4, 0.9)
	var marks := {}
	for id in WorldForge.job_ids(state):
		marks[int(WorldForge.get_job(state, id)["s"])] = 2
	for k in WorldForge.sub(state, "worlds"):
		var p := galaxy.get_planet(int(k))
		if p != null and not marks.has(p.system_id):
			marks[p.system_id] = 1
	for k in WorldForge.sub(state, "relics"):
		var p := galaxy.get_planet(int(k))
		if p != null and WorldForgeWorld.is_relic(state, p.id) and not marks.has(p.system_id):
			marks[p.system_id] = 3
	for sid in marks:
		if not is_explored(int(sid)):
			continue
		draw_set_transform(galaxy.systems[int(sid)].position, 0.0, Vector2(px, px))
		var r := Rect2(Vector2(-12, 9), Vector2(5, 5))
		match int(marks[sid]):
			2:
				draw_rect(r, amber, true)
			1:
				draw_rect(r, amber, false, 1.2)
			3:
				draw_colored_polygon(PackedVector2Array([Vector2(-9.5, 8), Vector2(-7, 11.5), Vector2(-9.5, 15), Vector2(-12, 11.5)]), Color(0.72, 0.6, 0.95, 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Mondes vivants (prop. 31) : une petite feuille sous le système d'un monde vivant que le joueur connaît,
## à la couleur de l'humeur qu'il lui porte (grise s'il la cache) ; rouge sombre pour Ego.
func _draw_living(px: float) -> void:
	if state == null or state.living.is_empty():
		return
	for pid in LivingWorlds.ids(state):
		var sid := LivingWorlds.sys_of(state, pid)
		if sid < 0 or not is_explored(sid) or (viewer >= 0 and not LivingWorlds.knows(state, pid, viewer)):
			continue
		var col := Color(0.55, 0.85, 0.5, 0.95)
		if int(LivingWorlds.world(state, pid).get("ego", 0)) == 1:
			col = Color(0.75, 0.1, 0.2, 0.95)
		elif viewer >= 0 and LivingWorlds.mood_known(state, pid, viewer):
			var c: Array = LivingWorlds.tier(state, pid, viewer).get("color", [0.55, 0.85, 0.5])
			col = Color(float(c[0]), float(c[1]), float(c[2]), 0.95)
		elif viewer >= 0:
			col = Color(0.6, 0.6, 0.6, 0.9)
		draw_set_transform(galaxy.systems[sid].position, 0.0, Vector2(px, px))
		draw_colored_polygon(PackedVector2Array([Vector2(9, 8), Vector2(13, 12), Vector2(9, 17), Vector2(5, 12)]), col)
		draw_line(Vector2(9, 9.5), Vector2(9, 16), Color(0.05, 0.12, 0.05, 0.9), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Archéologie (prop. 42) : petit repère en pioche sous les sites connus du joueur (doré s'il y fouille,
## gris une fois fini), et un losange sur les Mondes-berceaux qu'il a trouvés. Sans lentille.
func _draw_archaeo(px: float) -> void:
	if state == null or not Archaeology.full(state):
		return
	var keys := state.digs.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		if not Relics.knows(state, viewer, sid):
			continue
		var d: Dictionary = state.digs[sid]
		var col := Color(0.78, 0.66, 0.42, 0.85)
		if int(d["done"]) >= 0:
			col = Color(0.55, 0.55, 0.55, 0.6)
		elif int(d["by"]) == viewer and int(d["next"]) >= 0:
			col = Color(1.0, 0.84, 0.35, 1.0)
		draw_set_transform(galaxy.systems[sid].position, 0.0, Vector2(px, px))
		draw_line(Vector2(-6, 15), Vector2(0, 9), col, 1.6, true)
		draw_line(Vector2(-3, 9), Vector2(3, 9), col, 1.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for dn in Archaeology.in_game_disparus(state):
		if not ArchaeoWorld.cradle_known(state, viewer, dn):
			continue
		var sid2 := int(ArchaeoWorld.cradle_of(state, dn)["s"])
		draw_set_transform(galaxy.systems[sid2].position, 0.0, Vector2(px, px))
		var c2 := Color.html(String(Archaeology.disparu_def(dn).get("color", "#c8a96a")))
		draw_polyline(PackedVector2Array([Vector2(0, -17), Vector2(5, -12), Vector2(0, -7), Vector2(-5, -12), Vector2(0, -17)]), c2, 1.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Contact (prop. 43) : Échos fossiles explorés (trois arcs pâles), Oreilles du joueur (petite parabole),
## Hérauts qui transmettent (ondes concentriques, pour tous en mode Complet), sans lentille.
func _draw_contact(px: float) -> void:
	if state == null or state.contact.is_empty():
		return
	var pale := Color(0.7, 0.9, 1.0, 0.7)
	for sid in Contact.echo_sites(state):
		if not is_explored(sid):
			continue
		draw_set_transform(galaxy.systems[sid].position + Vector2(-19.0, -8.0) * px, 0.0, Vector2(px, px))
		for k in 3:
			draw_arc(Vector2(-3, 0), 2.0 + k * 2.5, -0.8, 0.8, 8, pale, 1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if viewer >= 0:
		for x in Contact.ears_of(state, viewer):
			var sid := int(x[1])
			var col := Color(0.6, 1.0, 0.85) if int(x[2]) >= int(x[3]) else pale
			draw_set_transform(galaxy.systems[sid].position + Vector2(-19.0, 8.0) * px, 0.0, Vector2(px, px))
			draw_arc(Vector2(0, 2), 5.0, PI + 0.5, TAU - 0.5, 10, col, 1.4, true)
			draw_line(Vector2(0, 2), Vector2(0, -3), col, 1.2, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var shown: Array[int] = Contact.exposed_systems(state)
	if viewer >= 0:
		var own := Contact.heraut_system(state, viewer)
		if own >= 0 and not shown.has(own):
			shown.append(own)
	for sid in shown:
		draw_set_transform(galaxy.systems[sid].position + Vector2(19.0, 8.0) * px, 0.0, Vector2(px, px))
		for k in 3:
			draw_arc(Vector2.ZERO, 3.0 + k * 3.0, 0.0, TAU, 18, Color(0.75, 0.95, 1.0, 0.85 - k * 0.22), 1.2, true)
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
		# Le lien entier ne s'affiche en clair que pour le trou de ver du système choisi ou survolé ;
		# sinon un fil discret, pour ne pas barrer la carte de longues ondulations.
		var focus := selected_id == ia or selected_id == ib or hovered_id == ia or hovered_id == ib
		var lcol := col if focus else Color(col.r, col.g, col.b, 0.16)
		if known and is_explored(ib):
			var pb := g.systems[ib].position
			var pts := PackedVector2Array()
			var dir := pb - pa
			var nrm := Vector2(-dir.y, dir.x).normalized()
			var steps := 40
			for i in steps + 1:
				var t := float(i) / steps
				pts.append(pa + dir * t + nrm * sin(t * TAU * 6.0) * 5.0 * px)
			draw_polyline(pts, lcol, (1.6 if focus else 1.0) * px, true)
			_draw_swirl(pb, px, col)
		_draw_swirl(pa, px, col)
	if not g.relays.is_empty():
		for lane in g.lanes:
			if g.relays.has(lane.x) and g.relays.has(lane.y) and is_explored(lane.x) and is_explored(lane.y):
				draw_line(g.systems[lane.x].position, g.systems[lane.y].position, Color(0.35, 0.95, 0.75, 0.6), 2.6 * px, true)
	for sid in g.portal_gates:
		if not is_explored(int(sid)):
			continue
		# Liens de portail (dans la portée) : pointillés, en clair pour le système choisi ou survolé.
		var links: Dictionary = g.portal_links.get(sid, {})
		for b in links:
			if int(b) <= int(sid) or not is_explored(int(b)) or int(links[b]) > mini(Portals.gate_range(state, int(sid)), Portals.gate_range(state, int(b))):
				continue
			var gf := selected_id == int(sid) or selected_id == int(b) or hovered_id == int(sid) or hovered_id == int(b)
			draw_dashed_line(g.systems[int(sid)].position, g.systems[int(b)].position, Color(0.62, 0.55, 1.0, 0.85 if gf else 0.3), (2.0 if gf else 1.2) * px, 9.0 * px, true)
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


## Lentille Senseurs : un disque d'autant plus vif que la détection est forte, et son niveau.
func _draw_sensors(s: StarSystem, px: float, level: int, post: bool) -> void:
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	if level >= 0:
		var col := Color(0.35, 0.85, 0.95)
		var t := clampf(float(level) / float(maxi(1, Stealth.max_level())), 0.0, 1.0)
		draw_circle(Vector2.ZERO, 16.0, Color(col, 0.12 + 0.3 * t))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 28, Color(col, 0.5 + 0.4 * t), 1.6, true)
		draw_string(_font, Vector2(14, -10), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.3))
	if post:
		draw_arc(Vector2.ZERO, 21.0, 0.0, TAU, 28, Color(1, 1, 1, 0.7), 1.4, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
func _draw_psionics(s: StarSystem, px: float, mine: bool) -> void:
	var col := Color(0.72, 0.6, 0.95)
	draw_set_transform(s.position, 0.0, Vector2(px, px))
	if mine:
		var best := 0
		var marks := ""
		var cb := String(Psionics.cfg("college").get("building", "college_sensitifs"))
		var eb := String(Psionics.cfg("screens").get("building", "ecran_psychique"))
		var pb := String(Psionics.cfg("phare").get("building", "phare_songe"))
		for pid in s.planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c == null or c.owner != viewer:
				continue
			var cnt := Peoples.counts(state, c) if not c.species.is_empty() else {state.get_empire(viewer).faction_id: c.population}
			for fid in cnt:
				if int(cnt[fid]) > 0:
					best = maxi(best, Psionics.level(state, viewer, String(fid)))
			if c.buildings.has(cb):
				marks += "C"
			if c.buildings.has(eb):
				marks += "E"
			if c.buildings.has(pb):
				marks += "P"
		if best > 0:
			draw_arc(Vector2.ZERO, 14.0 + 4.0 * best, 0.0, TAU, 32, Color(col, 0.35 + 0.2 * best), 2.0 + best)
		if marks != "":
			draw_string(_font, Vector2(-12, 30), marks, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		if (Psionics.sub(state, "phz").get(str(s.id), []) as Array).has(viewer):
			draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, 0.35), 1.5)
	for pid in s.planet_ids:
		if Psionics.sub(state, "ambre").has(str(pid)):
			draw_circle(Vector2(18, -18), 5.0, Color(1.0, 0.7, 0.2, 0.9))
			break
	if Psionics.sub(state, "haunted").has(str(s.id)):
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color(0.8, 0.3, 0.9), 3.0)
		draw_line(Vector2(-10, 10), Vector2(10, -10), Color(0.8, 0.3, 0.9), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
