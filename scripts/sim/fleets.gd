class_name Fleets
extends RefCounted
## Règles des flottes, des déplacements et du brouillard de guerre : fonctions pures qui LISENT l'état.
## FleetSystem et SimCommands s'en servent pour faire évoluer la partie, l'interface pour afficher
## trajets, délais et refus, avec exactement les mêmes calculs.
##
## Distances et vitesses en entiers (unités de la carte, par jour), comme le reste de la simulation.


# --- Routes et trajets -------------------------------------------------------------------------

## Longueur d'une route de saut, arrondie à l'unité (au moins 1).
static func lane_length(galaxy: Galaxy, a: int, b: int) -> int:
	return maxi(1, roundi(galaxy.systems[a].position.distance_to(galaxy.systems[b].position)))


## Vitesse d'une flotte : celle de son vaisseau le plus lent (unités par jour).
## Avec l'état, le trait de faction de son propriétaire s'applique (navigateurs d'Ossarane).
static func speed(fleet: Fleet, state: GameState = null) -> int:
	var v := 0
	for s in fleet.ships:
		var sv := int(GameData.ship(s).get("speed", 1))
		v = sv if v == 0 else mini(v, sv)
	if state != null:
		@warning_ignore("integer_division")
		v = v * FactionTraits.fleet_speed_pct(state, fleet.owner) / 100
	return maxi(1, v)


## Portée de vision d'une flotte, en sauts : celle de son meilleur vaisseau.
static func vision(fleet: Fleet) -> int:
	var v := 0
	for s in fleet.ships:
		v = maxi(v, int(GameData.ship(s).get("vision", 0)))
	return v


## Plus court chemin de from à to par les routes connues de l'empire (sans from, avec to).
## Vide si to == from ou s'il n'existe aucun chemin connu. Dijkstra à égalités départagées
## par l'identifiant : le même résultat sur toutes les machines.
static func find_path(state: GameState, empire_id: int, from: int, to: int) -> Array[int]:
	var out: Array[int] = []
	var res := _dijkstra(state, empire_id, from)
	if from == to or not res["dist"].has(to):
		return out
	var cur := to
	while cur != from:
		out.push_front(cur)
		cur = int(res["prev"][cur])
	return out


## Distances (en unités) depuis un système vers tous ceux joignables par des routes connues.
static func _dijkstra(state: GameState, empire_id: int, from: int) -> Dictionary:
	var g := state.galaxy
	var dist := {from: 0}
	var prev := {}
	var done := {}
	while true:
		var best := -1
		for k in dist:
			if done.has(k):
				continue
			if best == -1 or dist[k] < dist[best] or (dist[k] == dist[best] and k < best):
				best = k
		if best == -1:
			break
		done[best] = true
		for n in g.systems[best].neighbors:
			if done.has(n) or not lane_known(state, empire_id, best, n):
				continue
			var d: int = dist[best] + lane_length(g, best, n)
			if not dist.has(n) or d < dist[n] or (d == dist[n] and best < int(prev[n])):
				dist[n] = d
				prev[n] = best
	return {"dist": dist, "prev": prev}


## Itinéraire d'une flotte vers un système : {"system", "path", "progress"} prêts à lui être appliqués,
## ou {} si c'est impossible. Une flotte en route peut finir sa route ou faire demi-tour,
## selon ce qui est le plus court (comme dans les 4X en temps réel).
static func plan_route(state: GameState, fleet: Fleet, to: int) -> Dictionary:
	if fleet.is_moving() and fleet.progress == 0 and to == fleet.system_id:
		return {"system": fleet.system_id, "path": [], "progress": 0}  # pas encore parti : on reste
	if not fleet.is_moving() or fleet.progress == 0:
		var p := find_path(state, fleet.owner, fleet.system_id, to)
		if p.is_empty():
			return {}
		return {"system": fleet.system_id, "path": p, "progress": 0}
	var a := fleet.system_id
	var b := fleet.next_system()
	var lane := lane_length(state.galaxy, a, b)
	var options: Array[Dictionary] = []
	# Continuer vers b, puis aller jusqu'à to.
	var res_b := _dijkstra(state, fleet.owner, b)
	if res_b["dist"].has(to):
		var pb: Array[int] = [b]
		pb.append_array(find_path(state, fleet.owner, b, to))
		options.append({"cost": lane - fleet.progress + int(res_b["dist"][to]),
				"plan": {"system": a, "path": pb, "progress": fleet.progress}})
	# Faire demi-tour vers a.
	var res_a := _dijkstra(state, fleet.owner, a)
	if res_a["dist"].has(to):
		var pa: Array[int] = [a]
		pa.append_array(find_path(state, fleet.owner, a, to))
		options.append({"cost": fleet.progress + int(res_a["dist"][to]),
				"plan": {"system": b, "path": pa, "progress": lane - fleet.progress}})
	if options.is_empty():
		return {}
	if options.size() == 2 and int(options[1]["cost"]) < int(options[0]["cost"]):
		return options[1]["plan"]
	return options[0]["plan"]


## Distance restant à parcourir jusqu'à la destination.
static func remaining_distance(state: GameState, fleet: Fleet) -> int:
	if not fleet.is_moving():
		return 0
	var g := state.galaxy
	var d := lane_length(g, fleet.system_id, fleet.path[0]) - fleet.progress
	for i in range(1, fleet.path.size()):
		d += lane_length(g, fleet.path[i - 1], fleet.path[i])
	return d


## Jours avant l'arrivée (0 à l'arrêt).
static func eta_days(state: GameState, fleet: Fleet) -> int:
	var v := speed(fleet, state)
	@warning_ignore("integer_division")
	return (remaining_distance(state, fleet) + v - 1) / v


## Jours de trajet d'un itinéraire calculé par plan_route (pour l'aperçu avant l'ordre).
static func route_days(state: GameState, fleet: Fleet, plan: Dictionary) -> int:
	var f := Fleet.new()
	f.ships = fleet.ships
	f.owner = fleet.owner
	f.system_id = int(plan["system"])
	f.path.assign(plan["path"])
	f.progress = int(plan["progress"])
	return eta_days(state, f)


## Position de la flotte sur la carte. extra : fraction de jour déjà écoulée (0 à 1),
## pour un mouvement fluide à l'écran entre deux ticks.
static func position(state: GameState, fleet: Fleet, extra := 0.0) -> Vector2:
	var g := state.galaxy
	var a := g.systems[fleet.system_id].position
	if not fleet.is_moving():
		return a
	var b := g.systems[fleet.path[0]].position
	var lane := float(lane_length(g, fleet.system_id, fleet.path[0]))
	var t := clampf((fleet.progress + extra * speed(fleet, state)) / lane, 0.0, 1.0)
	return a.lerp(b, t)


## Système d'où la flotte observe : celui qu'elle quitte, puis celui où elle va passé la mi-route.
static func vision_center(state: GameState, fleet: Fleet) -> int:
	if not fleet.is_moving():
		return fleet.system_id
	var lane := lane_length(state.galaxy, fleet.system_id, fleet.path[0])
	return fleet.path[0] if fleet.progress * 2 >= lane else fleet.system_id


# --- Exploration automatique ------------------------------------------------------------------

## Système vers lequel une flotte en exploration automatique doit se diriger : le plus proche
## (en distance de route) des systèmes connus mais inexplorés, en évitant ceux que vise déjà une
## autre flotte du même empire en exploration. -1 s'il n'y en a plus aucun de joignable.
## Déterministe : égalités départagées par l'identifiant.
static func explore_target(state: GameState, fleet: Fleet) -> int:
	var origin := fleet.next_system() if fleet.is_moving() else fleet.system_id
	var res := _dijkstra(state, fleet.owner, origin)
	var taken := {}
	for other in empire_fleets(state, fleet.owner):
		if other.id != fleet.id and other.is_exploring() and other.is_moving():
			taken[other.destination()] = true
	var best := -1
	var best_free := false
	var best_d := 0
	for k in res["dist"]:
		var sid := int(k)
		if is_explored(state, fleet.owner, sid):
			continue
		var d := int(res["dist"][k])
		var free := not taken.has(sid)
		# Un système libre passe avant un système déjà visé ; puis le plus proche ; puis le plus petit id.
		if best == -1 or (free and not best_free) or (free == best_free and (d < best_d or (d == best_d and sid < best))):
			best = sid
			best_free = free
			best_d = d
	return best


## Flottes du joueur qui attendent des ordres (à l'arrêt, sans ordre permanent), triées par id.
static func idle_fleets(state: GameState, empire_id: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f in empire_fleets(state, empire_id):
		if f.is_idle():
			out.append(f)
	return out


# --- Brouillard de guerre ----------------------------------------------------------------------

## Systèmes que l'empire voit en ce moment : autour de ses revendications (1 saut)
## et de ses flottes (selon leur portée de vision). Dictionnaire id -> true.
static func visible_systems(state: GameState, empire_id: int) -> Dictionary:
	var sources := {}
	var claim_vision := int(GameData.rules().get("claim_vision", 1))
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id:
			var sid := state.galaxy.get_planet(pid).system_id
			sources[sid] = maxi(int(sources.get(sid, -1)), claim_vision)
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == empire_id:
			var sid := vision_center(state, f)
			sources[sid] = maxi(int(sources.get(sid, -1)), vision(f))
	var seen := {}
	for sid in sources:
		_flood(state.galaxy, int(sid), int(sources[sid]), seen)
	return seen


static func _flood(g: Galaxy, start: int, radius: int, seen: Dictionary) -> void:
	var frontier: Array[int] = [start]
	var local := {start: true}
	seen[start] = true
	for _r in radius:
		var next: Array[int] = []
		for s in frontier:
			for n in g.systems[s].neighbors:
				if not local.has(n):
					local[n] = true
					seen[n] = true
					next.append(n)
		frontier = next


static func is_explored(state: GameState, empire_id: int, system_id: int) -> bool:
	var e := state.get_empire(empire_id)
	return e != null and e.explored.has(system_id)


## Un système est connu (sa position figure sur la carte) s'il est exploré ou relié à un système exploré.
static func is_known(state: GameState, empire_id: int, system_id: int) -> bool:
	if is_explored(state, empire_id, system_id):
		return true
	for n in state.galaxy.systems[system_id].neighbors:
		if is_explored(state, empire_id, n):
			return true
	return false


## Une route est connue si l'un de ses deux bouts a été exploré.
static func lane_known(state: GameState, empire_id: int, a: int, b: int) -> bool:
	return is_explored(state, empire_id, a) or is_explored(state, empire_id, b)


## Une flotte étrangère est visible si le système d'où elle observerait est vu par l'empire.
static func fleet_visible(state: GameState, viewer: int, fleet: Fleet, seen: Dictionary) -> bool:
	return fleet.owner == viewer or seen.has(vision_center(state, fleet))


# --- Recherches --------------------------------------------------------------------------------

## Flottes présentes (à l'arrêt) dans un système, triées par identifiant. owner = -1 : toutes.
static func fleets_at(state: GameState, system_id: int, owner := -1) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id == system_id and not f.is_moving() and (owner == -1 or f.owner == owner):
			out.append(f)
	return out


## Flottes d'un empire, triées par identifiant.
static func empire_fleets(state: GameState, empire_id: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for fid in state.sorted_fleet_ids():
		if state.fleets[fid].owner == empire_id:
			out.append(state.fleets[fid])
	return out


## Première flotte de l'empire à l'arrêt dans ce système avec un vaisseau colon (null si aucune).
static func colonizer_fleet(state: GameState, empire_id: int, system_id: int) -> Fleet:
	for f in fleets_at(state, system_id, empire_id):
		if colonizer_ship(f) != "":
			return f
	return null


## Classe du premier vaisseau colonisateur de la flotte ("" si aucun).
static func colonizer_ship(fleet: Fleet) -> String:
	for s in fleet.ships:
		if GameData.ship(s).get("colonizer", false):
			return s
	return ""


## Entretien mensuel de toutes les flottes d'un empire.
static func upkeep(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	for f in empire_fleets(state, empire_id):
		for s in f.ships:
			var u: Dictionary = GameData.ship(s).get("upkeep", {})
			for r in u:
				out[r] = int(out.get(r, 0)) + int(u[r])
	return out


## Composition lisible : "2 Éclaireurs, Vaisseau colon".
static func composition(fleet: Fleet) -> String:
	var parts := PackedStringArray()
	for sid in GameData.ship_ids():
		var n := fleet.count(sid)
		if n == 1:
			parts.append(String(GameData.ship(sid)["label"]))
		elif n > 1:
			parts.append("%d %s" % [n, GameData.ship(sid)["plural"]])
	return ", ".join(parts) if not parts.is_empty() else "aucun vaisseau"


# --- Vérification des ordres -------------------------------------------------------------------

static func check_move(state: GameState, empire_id: int, fleet_id: int, system_id: int) -> String:
	var f: Fleet = state.fleets.get(fleet_id)
	if f == null or f.owner != empire_id:
		return "cette flotte ne vous appartient pas"
	if state.galaxy.get_system(system_id) == null:
		return "système inconnu : %d" % system_id
	if not is_known(state, empire_id, system_id):
		return "ce système n'apparaît sur aucune de vos cartes"
	if not f.is_moving() and f.system_id == system_id:
		return "la flotte y est déjà"
	if plan_route(state, f, system_id).is_empty():
		return "aucune route connue jusque-là"
	return ""


static func check_stop(state: GameState, empire_id: int, fleet_id: int) -> String:
	var f: Fleet = state.fleets.get(fleet_id)
	if f == null or f.owner != empire_id:
		return "cette flotte ne vous appartient pas"
	if not f.is_moving():
		return "la flotte est déjà à l'arrêt"
	return ""


static func check_build_ship(state: GameState, empire_id: int, planet_id: int, ship_id: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	var c: Colony = state.colonies.get(planet_id)
	if c == null or c.owner != empire_id:
		return "cette planète ne vous appartient pas"
	if not c.is_established() or not c.is_colony():
		return "il faut une colonie fondée (avec sa population) pour construire des vaisseaux"
	var sd := GameData.ship(ship_id)
	if sd.is_empty():
		return "classe de vaisseau inconnue : %s" % ship_id
	if not FactionTraits.ship_ids_for(e.faction_id).has(ship_id):
		return "votre peuple ne construit pas de %s" % String(sd["plural"]).to_lower()
	if c.ship_build != "":
		return "le chantier spatial est occupé"
	var pop_cost := int(sd.get("pop_cost", 0))
	if pop_cost > 0 and c.population <= pop_cost:
		return "il faut plus de %d population sur cette colonie (le vaisseau emporte %d population)" % [pop_cost, pop_cost]
	var cost: Dictionary = sd.get("cost", {})
	if not Economy.can_afford(e, cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func check_order(state: GameState, empire_id: int, fleet_id: int, order: String) -> String:
	var f: Fleet = state.fleets.get(fleet_id)
	if f == null or f.owner != empire_id:
		return "cette flotte ne vous appartient pas"
	if not Fleet.STANDING_ORDERS.has(order):
		return "ordre inconnu : %s" % order
	if f.standing_order == order:
		return "la flotte a déjà cet ordre" if order != "" else "la flotte n'a pas d'ordre permanent"
	if order == Fleet.ORDER_EXPLORE and explore_target(state, f) == -1:
		return "plus aucun système inexploré joignable par vos routes connues"
	return ""


static func check_merge(state: GameState, empire_id: int, fleet_id: int, into_id: int) -> String:
	var f: Fleet = state.fleets.get(fleet_id)
	var into: Fleet = state.fleets.get(into_id)
	if f == null or into == null or f.owner != empire_id or into.owner != empire_id:
		return "ces flottes ne vous appartiennent pas"
	if fleet_id == into_id:
		return "une flotte ne peut pas fusionner avec elle-même"
	if f.is_moving() or into.is_moving() or f.system_id != into.system_id:
		return "les deux flottes doivent être à l'arrêt dans le même système"
	return ""


static func check_split(state: GameState, empire_id: int, fleet_id: int, ship_id: String) -> String:
	var f: Fleet = state.fleets.get(fleet_id)
	if f == null or f.owner != empire_id:
		return "cette flotte ne vous appartient pas"
	if f.is_moving():
		return "impossible en plein trajet"
	if f.ships.size() < 2:
		return "la flotte n'a qu'un vaisseau"
	if f.count(ship_id) == 0:
		return "aucun vaisseau de cette classe dans la flotte"
	return ""
