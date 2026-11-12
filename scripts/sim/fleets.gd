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
## Un moteur de trame (Nef-monde) entraîne toute la flotte à sa vitesse, plus lents compris.
static func speed(fleet: Fleet, state: GameState = null) -> int:
	var v := 0
	var warp := 0
	for s in fleet.ships:
		var sd := GameData.ship(s)
		var sv := int(sd.get("speed", 1))
		v = sv if v == 0 else mini(v, sv)
		warp = maxi(warp, int(sd.get("fleet_speed", 0)))
	v = maxi(v, warp)
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
## File de priorité (tas binaire) sur la clé distance * 65536 + identifiant : on traite toujours le
## système le plus proche, à égalité le plus petit identifiant, comme un parcours linéaire, mais vite.
##
## Le résultat ne dépend que des systèmes explorés par l'empire (les routes connues) : il est gardé en
## cache sur l'empire tant qu'il n'explore rien de nouveau (explored ne fait que grandir). Le résultat
## est partagé : les appelants le lisent sans le modifier.
static func _dijkstra(state: GameState, empire_id: int, from: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return _dijkstra_raw(state, empire_id, from)
	if e.path_cache_explored != e.explored.size():
		e.path_cache.clear()
		e.path_cache_explored = e.explored.size()
	if not e.path_cache.has(from):
		e.path_cache[from] = _dijkstra_raw(state, empire_id, from)
	return e.path_cache[from]


static func _dijkstra_raw(state: GameState, empire_id: int, from: int) -> Dictionary:
	# Tableaux indexés par système pendant le calcul (plus rapides que des dictionnaires), puis les
	# dictionnaires du résultat, remplis dans l'ordre de découverte, comme avant.
	var g := state.galaxy
	var count := g.systems.size()
	var e := state.get_empire(empire_id)
	var explored: Dictionary = e.explored if e != null else {}
	var dist := PackedInt32Array()
	dist.resize(count)
	dist.fill(-1)
	var prev := PackedInt32Array()
	prev.resize(count)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(count)
	var order: Array[int] = [from]
	dist[from] = 0
	var heap: Array[int] = [from]
	while not heap.is_empty():
		var key := _heap_pop(heap)
		var best := key & 0xFFFF
		var d0 := key >> 16
		if done[best] == 1 or d0 != dist[best]:
			continue
		done[best] = 1
		var best_known := explored.has(best)
		var pos := g.systems[best].position
		for n in g.systems[best].neighbors:
			if done[n] == 1 or not (best_known or explored.has(n)):
				continue
			var d: int = d0 + maxi(1, roundi(pos.distance_to(g.systems[n].position)))
			var old := dist[n]
			if old < 0 or d < old or (d == old and best < prev[n]):
				if old < 0:
					order.append(n)
				dist[n] = d
				prev[n] = best
				if old < 0 or d < old:
					_heap_push(heap, (d << 16) | n)
	var out_dist := {}
	var out_prev := {}
	for n in order:
		out_dist[n] = dist[n]
		if n != from:
			out_prev[n] = prev[n]
	return {"dist": out_dist, "prev": out_prev}


static func _heap_push(heap: Array[int], v: int) -> void:
	heap.append(v)
	var i := heap.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var p := (i - 1) / 2
		if heap[p] <= heap[i]:
			break
		var tmp := heap[p]
		heap[p] = heap[i]
		heap[i] = tmp
		i = p


static func _heap_pop(heap: Array[int]) -> int:
	var top := heap[0]
	var last: int = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and heap[l] < heap[m]:
			m = l
		if r < n and heap[r] < heap[m]:
			m = r
		if m == i:
			break
		var tmp := heap[m]
		heap[m] = heap[i]
		heap[i] = tmp
		i = m
	return top


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
## et de ses flottes (selon leur portée de vision), plus ce que voient ses alliés (vision partagée).
## Dictionnaire id -> true.
static func visible_systems(state: GameState, empire_id: int) -> Dictionary:
	var seen := _own_visible(state, empire_id)
	for ally in allies_of(state, empire_id):
		seen.merge(_own_visible(state, ally))
	return seen


## Alliés encore en jeu d'un empire, triés. Ne crée aucune relation (lecture seule, sûre pour l'affichage).
static func allies_of(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if e.id == empire_id or e.eliminated:
			continue
		if Diplomacy.allied(state, empire_id, e.id):
			out.append(e.id)
	return out


## Ce que l'empire voit par ses propres revendications et flottes.
static func _own_visible(state: GameState, empire_id: int) -> Dictionary:
	var sources := {}
	var claim_vision := int(GameData.rules().get("claim_vision", 1)) + Research.fx_int(state, empire_id, "claim_vision")
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


## visible_systems de tous les empires (par indice d'empire), en un seul parcours des colonies et des
## flottes : mêmes résultats que visible_systems appelée pour chacun (vision des alliés comprise).
static func visible_all(state: GameState) -> Array[Dictionary]:
	var count := state.empires.size()
	var sources: Array[Dictionary] = []
	var claim_vision: Array[int] = []
	var base_vision := int(GameData.rules().get("claim_vision", 1))
	for e in state.empires:
		sources.append({})
		claim_vision.append(base_vision + Research.fx_int(state, e.id, "claim_vision"))
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner < 0 or c.owner >= count:
			continue
		var src := sources[c.owner]
		var sid := state.galaxy.get_planet(pid).system_id
		src[sid] = maxi(int(src.get(sid, -1)), claim_vision[c.owner])
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner < 0 or f.owner >= count:
			continue
		var src := sources[f.owner]
		var sid := vision_center(state, f)
		src[sid] = maxi(int(src.get(sid, -1)), vision(f))
	var own: Array[Dictionary] = []
	for i in count:
		var seen := {}
		for sid in sources[i]:
			_flood(state.galaxy, int(sid), int(sources[i][sid]), seen)
		own.append(seen)
	# Vision partagée : chacun voit aussi ce que voient ses alliés.
	var out: Array[Dictionary] = []
	for i in count:
		var allies := allies_of(state, state.empires[i].id)
		if allies.is_empty():
			out.append(own[i])
			continue
		var seen: Dictionary = own[i].duplicate()
		for ally in allies:
			if ally < count:
				seen.merge(own[ally])
		out.append(seen)
	return out


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
## Archétype Énergétique : une flotte voilée reste cachée (voir Veil).
static func fleet_visible(state: GameState, viewer: int, fleet: Fleet, seen: Dictionary) -> bool:
	if fleet.owner == viewer:
		return true
	if Echoes.foresees(state, viewer, fleet):
		return true
	var sid := vision_center(state, fleet)
	return seen.has(sid) and not Veil.hides(state, fleet.owner, viewer, sid)


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
	return Research.scaled_amounts(out, Research.fx_int(state, empire_id, "upkeep_pct"))


## Coût d'un vaisseau pour un empire (technologies de coques comprises ; pendant l'Exaltation aussi).
static func ship_cost(state: GameState, empire_id: int, ship_id: String) -> Dictionary:
	return Research.scaled_amounts(GameData.ship(ship_id).get("cost", {}), Research.fx_int(state, empire_id, "ship_cost_pct"))


## Durée de construction d'un vaisseau pour un empire, en jours (au moins 1).
static func ship_days(state: GameState, empire_id: int, ship_id: String) -> int:
	return maxi(1, Research.scaled(int(GameData.ship(ship_id).get("days", 1)), Research.fx_int(state, empire_id, "ship_days_pct")))


## Classe de vaisseau débloquée par les technologies de l'empire ?
static func ship_unlocked(state: GameState, empire_id: int, ship_id: String) -> bool:
	return Research.knows_all(state, empire_id, GameData.ship(ship_id).get("requires_tech", []))


## Composition lisible : "2 Éclaireurs, Vaisseau colon".
static func composition(fleet: Fleet) -> String:
	var parts := PackedStringArray()
	var counts := {}
	for sh in fleet.ships:
		counts[sh] = int(counts.get(sh, 0)) + 1
	for sid in GameData.ship_ids():
		var n := int(counts.get(sid, 0))
		if n == 1:
			parts.append(String(GameData.ship(sid)["label"]))
		elif n > 1:
			parts.append("%d %s" % [n, GameData.ship(sid)["plural"]])
	return ", ".join(parts) if not parts.is_empty() else "aucun vaisseau"


# --- Remise à niveau ---------------------------------------------------------------------------

## Vaisseaux de la flotte dont les marques sont en retard sur celles de l'empire.
static func outdated_count(state: GameState, f: Fleet) -> int:
	var n := 0
	for i in f.ships.size():
		if i < f.gen.size() and Research.gen_outdated(state, f.owner, f.gen[i]):
			n += 1
	return n


## Coût de la remise à niveau : cost_pct % (10 %) du prix de chaque vaisseau en retard.
static func refit_cost(state: GameState, f: Fleet) -> Dictionary:
	var out := {}
	var pct := int(Combat.data().get("refit", {}).get("cost_pct", 10))
	for i in f.ships.size():
		if i < f.gen.size() and Research.gen_outdated(state, f.owner, f.gen[i]):
			var c := ship_cost(state, f.owner, f.ships[i])
			for r in c:
				out[r] = int(out.get(r, 0)) + int(c[r])
	for r in out:
		@warning_ignore("integer_division")
		out[r] = maxi(1, int(out[r]) * pct / 100)
	return out


static func refit_days() -> int:
	return int(Combat.data().get("refit", {}).get("days", 5))


## Un chantier ami : une colonie fondée de l'empire dans ce système.
static func has_own_yard(state: GameState, empire_id: int, system_id: int) -> bool:
	for pid in state.galaxy.systems[system_id].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == empire_id and c.is_established() and c.is_colony():
			return true
	return false


static func check_refit(state: GameState, empire_id: int, fleet_id: int) -> String:
	var f: Fleet = state.fleets.get(fleet_id)
	if f == null or f.owner != empire_id:
		return "cette flotte ne vous appartient pas"
	if f.refit_left > 0:
		return "remise à niveau déjà en cours (encore %d jours)" % f.refit_left
	if outdated_count(state, f) == 0:
		return "les vaisseaux ont déjà les dernières marques"
	if f.is_moving() or not has_own_yard(state, empire_id, f.system_id):
		return "il faut être à l'arrêt dans un système où vous avez une colonie (son chantier fait le travail)"
	if state.battles.has(f.system_id):
		return "impossible en pleine bataille"
	var cost := refit_cost(state, f)
	if not Economy.can_afford(state.get_empire(empire_id), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


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
	if not f.is_moving() and anchored(state, f):
		return "une ancre gravitationnelle ennemie retient la flotte tant que la bataille dure"
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
	if not Designs.can_build_id(state, empire_id, ship_id):
		if sd.get("custom", false):
			return "ce modèle n'est pas disponible pour vous (retiré, ou conçu par un autre empire)"
		return "votre peuple ne construit pas de %s" % String(sd["plural"]).to_lower()
	if not ship_unlocked(state, empire_id, ship_id):
		return "technologie requise : %s" % Research.missing_text(state, empire_id, sd.get("requires_tech", []))
	var req: Dictionary = sd.get("requires", {})
	var need := String(req.get("building", ""))
	if need != "" and not c.buildings.has(need):
		return "il faut un bâtiment sur cette colonie : %s" % String(GameData.building(need).get("label", need))
	if req.get("unique_per_empire", false) and count_same_hull(state, empire_id, ship_id) > 0:
		return "un seul %s par empire" % unique_label(ship_id) + (", toutes variantes confondues" if Designs.hull(String(sd.get("hull", ""))).has("echelon") else "")
	if c.ship_build != "":
		return "le chantier spatial est occupé"
	var pop_cost := int(sd.get("pop_cost", 0))
	if pop_cost > 0 and c.population <= pop_cost:
		return "il faut plus de %d population sur cette colonie (le vaisseau emporte %d population)" % [pop_cost, pop_cost]
	var cost := ship_cost(state, empire_id, ship_id)
	if not Economy.can_afford(e, cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


## Vaisseaux de l'empire (en service ou en chantier) qui comptent pour la règle « un seul par empire »
## de ship_id : même coque (un titan conçu au Chantier compte comme le titan d'origine), ou même
## échelon de méga-vaisseau (Titan porteur, Titan bastion et Titan : un seul des trois).
static func count_same_hull(state: GameState, empire_id: int, ship_id: String) -> int:
	var key := unique_key(ship_id)
	if key == "":
		return count_owned_or_building(state, empire_id, ship_id)
	var n := 0
	for fid in state.fleets:
		var f: Fleet = state.fleets[fid]
		if f.owner == empire_id:
			for sh in f.ships:
				if unique_key(sh) == key:
					n += 1
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.ship_build != "" and unique_key(c.ship_build) == key:
			n += 1
	return n


## Une ancre gravitationnelle ennemie (en guerre) retient la flotte dans la bataille de son système.
static func anchored(state: GameState, f: Fleet) -> bool:
	if not state.battles.has(f.system_id):
		return false
	for other in fleets_at(state, f.system_id):
		if other.owner != f.owner and Combat.at_war(state, other.owner, f.owner) and Combat._fleet_has_flag(other, "anchor"):
			return true
	return false


## Clé de la règle « un seul par empire » : "echelon:N" pour un méga-vaisseau, sinon sa coque ("" sans coque).
static func unique_key(ship_id: String) -> String:
	var hid := String(GameData.ship(ship_id).get("hull", ""))
	if hid == "":
		return ""
	var h := Designs.hull(hid)
	return "echelon:%d" % int(h["echelon"]) if h.has("echelon") else hid


## Nom de ce qui est unique pour ship_id, pour les messages (« titan », « léviathan »…).
static func unique_label(ship_id: String) -> String:
	var sd := GameData.ship(ship_id)
	var h := Designs.hull(String(sd.get("hull", "")))
	if h.has("echelon"):
		var names: Array = Designs.data().get("echelons", [])
		var i := int(h["echelon"])
		if i < names.size():
			return String(names[i])
	return String(sd.get("label", ship_id)).to_lower()


## Vaisseaux d'une classe que l'empire possède ou a en chantier (titan : un seul par empire).
static func count_owned_or_building(state: GameState, empire_id: int, ship_id: String) -> int:
	var n := 0
	for fid in state.fleets:
		var f: Fleet = state.fleets[fid]
		if f.owner == empire_id:
			n += f.count(ship_id)
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.ship_build == ship_id:
			n += 1
	return n


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
	if f.refit_left > 0 or into.refit_left > 0:
		return "une des flottes est en remise à niveau au chantier"
	return ""


static func check_split(state: GameState, empire_id: int, fleet_id: int, ship_id: String) -> String:
	var f: Fleet = state.fleets.get(fleet_id)
	if f == null or f.owner != empire_id:
		return "cette flotte ne vous appartient pas"
	if f.is_moving():
		return "impossible en plein trajet"
	if f.ships.size() < 2:
		return "la flotte n'a qu'un vaisseau"
	if f.refit_left > 0:
		return "la flotte est en remise à niveau au chantier"
	if f.count(ship_id) == 0:
		return "aucun vaisseau de cette classe dans la flotte"
	return ""
