class_name FactionTraits
extends RefCounted
## Traits de faction qui changent la façon de jouer : fonctions pures qui LISENT l'état.
## Les paramètres viennent de data/factions.json ; une faction sans le champ correspondant
## joue avec les règles communes. Economy, Fleets, EconomySystem et l'interface passent par ici,
## pour que la simulation et les prévisions affichées fassent exactement les mêmes calculs.
##
## - Ossarane : flottes plus rapides (fleet_speed_pct), fiefs qui versent un tribut d'influence,
##   fiefs lointains qui réclament des cristaux et entrent en dissidence s'ils en manquent (fiefs).
## - Chœur Éternel : ferveur nourrie par les colonies et les sacrifices, qui module toute la production
##   (fervor), colonies qui démarrent plus peuplées (colony_start_pop).
## - Vael : habitabilité minimale (hab_floor), vote d'urgence qui achève un chantier contre de
##   l'influence (rush), influence par empire rencontré (contact_influence).
## - Kh'thari : colonisation sans influence (claim_influence_free), vaisseaux-spores à la place des
##   vaisseaux colons (start_ships, ships_excluded, pop_cost des vaisseaux), biomasse (biomass).

const RUSH_BUILDING := "building"
const RUSH_SHIP := "ship"


static func _faction(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	return e.faction() if e else {}


# --- Production --------------------------------------------------------------------------------

## Pourcentage appliqué à la production brute d'une ressource : bonus de faction × ferveur.
static func production_pct(state: GameState, empire_id: int, resource: String) -> int:
	var f := _faction(state, empire_id)
	var pct := int(f.get("production_pct", {}).get(resource, 100))
	if resource == "knowledge" and has_network(f):
		@warning_ignore("integer_division")
		pct = pct * (100 + network_pct(state, empire_id)) / 100
	@warning_ignore("integer_division")
	return pct * fervor_pct(state, empire_id) / 100


## Influence versée chaque mois en plus de la production des planètes (ambassades de Vael).
static func extra_influence(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 0
	return int(e.faction().get("contact_influence", 0)) * e.contacts.size()


# --- Ferveur (Chœur Éternel) -------------------------------------------------------------------

static func has_fervor(faction: Dictionary) -> bool:
	return faction.has("fervor")


## Effet de la ferveur sur la production : 100 sans ferveur, sinon Exaltation ou Silence du dieu.
static func fervor_pct(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null or not has_fervor(e.faction()):
		return 100
	var fv: Dictionary = e.faction()["fervor"]
	if e.fervor <= 0:
		return int(fv["silent_pct"])
	if e.fervor >= int(fv["exalted_at"]):
		return int(fv["exalted_pct"])
	return 100


## L'empire est-il en Exaltation (ferveur au-dessus du seuil) ?
static func is_exalted(state: GameState, empire_id: int) -> bool:
	var e := state.get_empire(empire_id)
	if e == null or not has_fervor(e.faction()):
		return false
	return e.fervor >= int(e.faction()["fervor"]["exalted_at"])


## Variation mensuelle de la ferveur : +per_colony par colonie fondée, -decay.
static func fervor_delta(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null or not has_fervor(e.faction()):
		return 0
	var fv: Dictionary = e.faction()["fervor"]
	var n := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_colony() and c.is_established():
			n += 1
	var delta := n * int(fv["per_colony"]) - int(fv["decay"])
	# Bâtiments qui chantent (Scriptorium) et catéchisme des grandes colonies (technologies).
	var big := Research.fx_int(state, empire_id, "fervor_big_colony")
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id or not c.is_established():
			continue
		for b in c.buildings:
			delta += int(GameData.building(b).get("fervor", 0))
		if big > 0 and c.is_colony() and c.population >= 5:
			delta += big
	return delta


## Ferveur gagnée par une offrande (technologies comprises).
static func sacrifice_gain(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null or not has_fervor(e.faction()):
		return 0
	return int(e.faction()["fervor"]["sacrifice_gain"]) + Research.fx_int(state, empire_id, "sacrifice_gain")


## "" si l'empire peut sacrifier un fidèle sur cette colonie, sinon la raison du refus.
static func check_sacrifice(state: GameState, empire_id: int, planet_id: int) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	if not has_fervor(e.faction()):
		return "votre peuple ne pratique pas l'offrande (et s'en porte très bien)"
	var c: Colony = state.colonies.get(planet_id)
	if c == null or c.owner != empire_id or not c.is_colony() or not c.is_established():
		return "il faut une de vos colonies fondées"
	var fv: Dictionary = e.faction()["fervor"]
	if c.population < int(fv["sacrifice_min_pop"]):
		return "il faut au moins %d population (le dernier fidèle garde la lumière allumée)" % int(fv["sacrifice_min_pop"])
	if e.fervor >= int(fv["max"]):
		return "la ferveur est déjà à son comble"
	return ""


# --- Fiefs (Ossarane) --------------------------------------------------------------------------

static var _jumps_cache := {}


## Distance en sauts depuis un système vers tous les autres (toutes les routes, connues ou non :
## le serment d'un fief ne dépend pas des cartes). Mise en cache par galaxie.
static func jumps_from(galaxy: Galaxy, from: int) -> Dictionary:
	var key := "%d:%d" % [galaxy.get_instance_id(), from]
	if _jumps_cache.has(key):
		return _jumps_cache[key]
	if _jumps_cache.size() > 64:
		_jumps_cache.clear()
	var dist := {from: 0}
	var queue: Array[int] = [from]
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		for n in galaxy.systems[cur].neighbors:
			if not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	_jumps_cache[key] = dist
	return dist


static func has_fiefs(faction: Dictionary) -> bool:
	return faction.has("fiefs")


## Une revendication est un fief si elle est établie hors du système de la capitale.
static func is_fief(state: GameState, c: Colony) -> bool:
	var e := state.get_empire(c.owner)
	if e == null or not has_fiefs(e.faction()) or not c.is_established() or e.capital_planet < 0:
		return false
	var cap_sys := state.galaxy.get_planet(e.capital_planet).system_id
	return state.galaxy.get_planet(c.planet_id).system_id != cap_sys


## Fief lointain : à plus de far_jumps sauts de la capitale.
static func is_far_fief(state: GameState, c: Colony) -> bool:
	if not is_fief(state, c):
		return false
	var e := state.get_empire(c.owner)
	var cap_sys := state.galaxy.get_planet(e.capital_planet).system_id
	var d: Dictionary = jumps_from(state.galaxy, cap_sys)
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	return int(d.get(sid, 9999)) > int(e.faction()["fiefs"]["far_jumps"])


# --- Conscience distribuée (Noosphères de Teyl) ------------------------------------------------

static func has_network(faction: Dictionary) -> bool:
	return faction.has("network")


## Systèmes reliés à la capitale : on y va de proche en proche par des systèmes à soi ou à personne,
## sans traverser un blocus ennemi. Vide sans capitale. Recalculé à chaque appel (pas de cache :
## un cache survivrait mal à un rechargement en cours de journée et casserait le déterminisme).
static func network_systems(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null or e.capital_planet < 0:
		return {}
	var start := state.galaxy.get_planet(e.capital_planet).system_id
	var seen := {start: true}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var sid: int = queue.pop_front()
		for n in state.galaxy.systems[sid].neighbors:
			if seen.has(n):
				continue
			var o := state.system_owner(n)
			if (o == -1 or o == empire_id) and not Combat.blocks(state, empire_id, n):
				seen[n] = true
				queue.append(n)
	return seen


## Une colonie est-elle un nœud relié au réseau ?
static func is_networked(state: GameState, c: Colony) -> bool:
	return network_systems(state, c.owner).has(state.galaxy.get_planet(c.planet_id).system_id)


## Nœuds du réseau : colonies peuplées reliées à la capitale.
static func network_nodes(state: GameState, empire_id: int) -> int:
	var net := network_systems(state, empire_id)
	var n := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_colony() and c.is_established() and net.has(state.galaxy.get_planet(pid).system_id):
			n += 1
	return n


## Revendications fondées coupées du réseau (colonies et avant-postes).
static func network_cut(state: GameState, empire_id: int) -> int:
	var net := network_systems(state, empire_id)
	var n := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_established() and not net.has(state.galaxy.get_planet(pid).system_id):
			n += 1
	return n


## Bonus de Savoir du réseau, en % : knowledge_per_node par nœud relié, max_pct au plus.
static func network_pct(state: GameState, empire_id: int) -> int:
	var net: Dictionary = _faction(state, empire_id).get("network", {})
	if net.is_empty():
		return 0
	return mini(int(net["max_pct"]), int(net["knowledge_per_node"]) * network_nodes(state, empire_id))


# --- Horde (Clans nomades) -----------------------------------------------------------------------
## Pas de planète capitale : la capitale est une flotte-ville (un vaisseau "capital" unique) qui
## rapporte ce que rapporte une capitale, enrichit le système où elle campe, et dont s'éloigner coûte.

static func has_horde(faction: Dictionary) -> bool:
	return faction.has("horde")


## Classe du vaisseau-capitale d'une horde ("" sinon).
static func city_ship(faction: Dictionary) -> String:
	return String(faction.get("horde", {}).get("ship", ""))


## Le vaisseau est-il une capitale mobile (flotte-ville) ?
static func is_capital_ship(ship_id: String) -> bool:
	return bool(GameData.ship(ship_id).get("capital", false))


## Flotte qui porte la flotte-ville de l'empire (null s'il n'en a pas, ou plus).
static func city_fleet(state: GameState, empire_id: int) -> Fleet:
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated:
		return null
	var ship := city_ship(e.faction())
	if ship == "":
		return null
	var best: Fleet = null
	for fid in state.fleets:
		var f: Fleet = state.fleets[fid]
		if f.owner == empire_id and f.ships.has(ship) and (best == null or f.id < best.id):
			best = f
	return best


## La flotte porte-t-elle une flotte-ville ?
static func is_city_fleet(f: Fleet) -> bool:
	for s in f.ships:
		if is_capital_ship(s):
			return true
	return false


## Système de la capitale : celui de la planète capitale, sinon celui de la flotte-ville (horde),
## sinon celui du monde d'origine ; -1 pour un empire disparu.
static func capital_system(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated:
		return -1
	if e.capital_planet >= 0:
		return state.galaxy.get_planet(e.capital_planet).system_id
	var f := city_fleet(state, empire_id)
	if f != null:
		return f.system_id
	if e.home_planet >= 0:
		return state.galaxy.get_planet(e.home_planet).system_id
	return -1


## Campement : système où la flotte-ville est à l'arrêt (-1 en route, sans flotte-ville, ou sans horde).
static func camp_system(state: GameState, empire_id: int) -> int:
	var f := city_fleet(state, empire_id)
	return f.system_id if f != null and not f.is_moving() else -1


## Revendication loin du clan : à plus de far_jumps sauts de la flotte-ville (ou toutes, si la
## flotte-ville est détruite). Faux hors horde.
static func far_from_clan(state: GameState, c: Colony) -> bool:
	var e := state.get_empire(c.owner)
	if e == null or not has_horde(e.faction()):
		return false
	var f := city_fleet(state, c.owner)
	if f == null:
		return true
	var sys := state.galaxy.get_planet(c.planet_id).system_id
	var d: Dictionary = jumps_from(state.galaxy, f.system_id)
	return int(d.get(sys, 999)) > int(e.faction()["horde"]["far_jumps"])


## Ce que rapporte la flotte-ville chaque mois : le rendement du bâtiment « capitale ».
static func city_yields(state: GameState, empire_id: int) -> Dictionary:
	if city_fleet(state, empire_id) == null:
		return {}
	return GameData.building("capitale").get("yields", {})


## Pillage du mois : pour chaque flotte armée à l'arrêt dans un système d'un empire en guerre avec la
## horde, ce qu'elle prend (par vaisseau armé, dans la limite des stocks de la victime).
## [{"fleet", "victim", "system", "amounts": {res: n}}], flottes par identifiant croissant.
static func loot_plan(state: GameState, empire_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated or not has_horde(e.faction()) or e.wars.is_empty():
		return out
	var per: Dictionary = e.faction()["horde"].get("loot", {})
	var left := {}
	for f in Fleets.empire_fleets(state, empire_id):
		if f.is_moving():
			continue
		var victim_id := state.system_owner(f.system_id)
		if victim_id < 0 or not e.wars.has(victim_id):
			continue
		var victim := state.get_empire(victim_id)
		if victim == null or victim.eliminated:
			continue
		var armed := 0
		for s in f.ships:
			if Combat.is_armed_ship(s):
				armed += 1
		if armed == 0:
			continue
		if not left.has(victim_id):
			left[victim_id] = victim.resources.duplicate()
		var stock: Dictionary = left[victim_id]
		var amounts := {}
		for r in per:
			var n := mini(int(per[r]) * armed, maxi(0, int(stock.get(r, 0))))
			if n > 0:
				amounts[r] = n
				stock[r] = int(stock.get(r, 0)) - n
		if not amounts.is_empty():
			out.append({"fleet": f.id, "victim": victim_id, "system": f.system_id, "amounts": amounts})
	return out


## Ajuste le rendement d'une revendication (Economy.colony_yields) selon les traits de son empire.
static func adjust_yields(state: GameState, c: Colony, gross: Dictionary, upkeep: Dictionary) -> void:
	var e := state.get_empire(c.owner)
	if e == null:
		return
	# Conscience distribuée : un nœud coupé du réseau ne pense plus qu'à moitié.
	if has_network(e.faction()) and c.is_established() and not is_networked(state, c):
		var cut := int(e.faction()["network"]["cut_pct"])
		for r in gross:
			@warning_ignore("integer_division")
			gross[r] = int(gross[r]) * cut / 100
	# Horde : le système du campement prospère, les revendications loin du clan s'étiolent.
	if has_horde(e.faction()) and c.is_established():
		var hd: Dictionary = e.faction()["horde"]
		var pct := 100
		if state.galaxy.get_planet(c.planet_id).system_id == camp_system(state, c.owner):
			pct = int(hd["camp_pct"])
		elif far_from_clan(state, c):
			pct = int(hd["far_pct"])
		if pct != 100:
			for r in gross:
				@warning_ignore("integer_division")
				gross[r] = int(gross[r]) * pct / 100
	if not is_fief(state, c):
		return
	var fi: Dictionary = e.faction()["fiefs"]
	if c.is_colony():
		gross["influence"] = int(gross.get("influence", 0)) + int(fi["influence"]) + Research.fx_int(state, c.owner, "fief_influence")
	if is_far_fief(state, c):
		upkeep["crystals"] = int(upkeep.get("crystals", 0)) + int(fi["crystal_upkeep"])
		if e.dissent:
			for r in gross:
				@warning_ignore("integer_division")
				gross[r] = int(gross[r]) * int(fi["dissent_pct"]) / 100


## Nombre de fiefs et de fiefs lointains d'un empire : {"fiefs", "far"}.
static func fief_counts(state: GameState, empire_id: int) -> Dictionary:
	var n := 0
	var far := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id or not is_fief(state, c):
			continue
		n += 1
		if is_far_fief(state, c):
			far += 1
	return {"fiefs": n, "far": far}


## Levée du ban (Ossarane) : vaisseaux que les fiefs lèvent aujourd'hui. Seulement aux échéances
## (levy.every_days) et tant que l'empire est en guerre contre plus fort que lui : un vaisseau par
## fief, levy.max au plus. 0 sinon.
static func levy_count(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated or e.capital_planet < 0:
		return 0
	var f := e.faction()
	if not has_fiefs(f) or not f["fiefs"].has("levy"):
		return 0
	var levy: Dictionary = f["fiefs"]["levy"]
	if state.tick <= 0 or state.tick % int(levy["every_days"]) != 0 or not outmatched(state, empire_id):
		return 0
	return mini(int(fief_counts(state, empire_id)["fiefs"]), int(levy["max"]))


## L'empire est-il en guerre contre un empire vivant dont la flotte de guerre dépasse la sienne ?
static func outmatched(state: GameState, empire_id: int) -> bool:
	var mine := war_power(state, empire_id)
	for w in state.get_empire(empire_id).wars:
		var o := state.get_empire(int(w))
		if o != null and not o.eliminated and war_power(state, o.id) > mine:
			return true
	return false


## Puissance totale des flottes de guerre d'un empire.
static func war_power(state: GameState, empire_id: int) -> int:
	var p := 0
	for fl in Fleets.empire_fleets(state, empire_id):
		if Combat.is_warfleet(fl):
			p += Combat.fleet_power(fl)
	return p


# --- Colonisation -------------------------------------------------------------------------------

## Population d'une colonie à sa fondation.
static func colony_start_pop(state: GameState, empire_id: int) -> int:
	return int(_faction(state, empire_id).get("colony_start_pop", GameData.rules()["colony_start_pop"])) \
			+ Research.fx_int(state, empire_id, "colony_start_pop")


## Ce que mange la population : "food" d'ordinaire, "materials" pour les lithoïdes.
static func diet(faction: Dictionary) -> String:
	return String(faction.get("diet", "food"))


## Matériaux que coûte chaque nouvel habitant d'une population assemblée (synthétiques), 0 sinon.
static func assembly_cost(faction: Dictionary) -> int:
	return int(faction.get("assembly", {}).get("materials", 0))


## Habitabilité propre d'un type que les autres ne peuplent pas (lithoïdes : mondes stériles), 0 sinon.
static func hab_extra(faction: Dictionary, planet_type: String) -> int:
	return int(faction.get("hab_extra", {}).get(planet_type, 0))


## Types de planète inhabitables pour ce corps (reptiliens : mondes glaciaires), même s'ils le sont
## pour les autres. Une technologie qui rend le type habitable (hab_set) passe outre.
static func hab_none(faction: Dictionary) -> Array:
	return faction.get("hab_none", [])


## Transhumance : les naissances d'une colonie pleine partent peupler une autre colonie (trait de
## corps reptilien, ou technologie des Spatioports de transit).
static func migrates(state: GameState, empire_id: int) -> bool:
	return bool(_faction(state, empire_id).get("migration", false)) or Research.fx_int(state, empire_id, "migration") > 0


## Habitabilité plancher (Vael) : 0 si aucune.
static func hab_floor(faction: Dictionary) -> int:
	return int(faction.get("hab_floor", 0))


## Coût d'une revendication après les traits (Kh'thari : jamais d'influence ; syndicats : les vraies
## colonies coûtent plus d'influence, colony_influence_pct).
static func adjust_claim_cost(state: GameState, empire_id: int, cost: Dictionary, kind := "") -> Dictionary:
	var f := _faction(state, empire_id)
	if f.get("claim_influence_free", false):
		var out := cost.duplicate()
		out.erase("influence")
		return out
	if kind == Colony.KIND_COLONY and f.has("colony_influence_pct") and cost.has("influence"):
		var out2 := cost.duplicate()
		@warning_ignore("integer_division")
		out2["influence"] = int(cost["influence"]) * int(f["colony_influence_pct"]) / 100
		return out2
	return cost


# --- Vaisseaux ----------------------------------------------------------------------------------

## Classes de vaisseaux qu'une faction peut construire, dans l'ordre des données.
## Une classe peut demander des couches d'espèce ("requires"."species" : archétype, credo, gouvernement,
## registre, traits) plutôt qu'un peuple précis : une espèce de l'éditeur qui partage la combinaison
## y a droit aussi. Une classe disponible qui en remplace une autre ("replaces") la retire du catalogue.
static func ship_ids_for(faction_id: String) -> Array[String]:
	var f := GameData.faction(faction_id)
	var excluded: Array = f.get("ships_excluded", [])
	var out: Array[String] = []
	var replaced := {}
	for sid in GameData.class_ids():  # les modèles conçus en partie : voir Designs.buildable_ids
		var sd := GameData.ship(sid)
		var only: Array = sd.get("factions", [])
		if excluded.has(sid) or (not only.is_empty() and not only.has(faction_id)):
			continue
		if not species_matches(f, sd.get("requires", {}).get("species", {})):
			continue
		if sd.has("replaces"):
			replaced[String(sd["replaces"])] = true
		out.append(sid)
	var kept: Array[String] = []
	for sid in out:
		if not replaced.has(sid):
			kept.append(sid)
	return kept


## Couches d'espèce d'une faction : {archetype, gouvernement, credo, traits, registre}.
static func species(faction: Dictionary) -> Dictionary:
	var sp: Dictionary = faction.get("species", {}).duplicate()
	sp["registre"] = String(faction.get("registre", ""))
	return sp


## L'espèce remplit-elle les conditions ? Chaque couche citée doit correspondre à l'une des valeurs
## demandées ; pour les traits, il suffit d'en avoir un.
static func species_matches(faction: Dictionary, req: Dictionary) -> bool:
	if req.is_empty():
		return true
	var sp := species(faction)
	for layer in req:
		var wanted: Array = req[layer]
		if layer == "traits":
			var has_one := false
			for t in sp.get("traits", []):
				if wanted.has(t):
					has_one = true
			if not has_one:
				return false
		elif layer == "registre":
			if not wanted.has(String(faction.get("registre", ""))):
				return false
		elif not wanted.has(sp.get(layer, "")):
			return false
	return true


static func start_ships(faction_id: String) -> Array:
	return GameData.faction(faction_id).get("start_ships", GameData.rules().get("start_ships", []))


## Vitesse des flottes d'un empire, en pourcentage.
@warning_ignore("integer_division")
static func fleet_speed_pct(state: GameState, empire_id: int) -> int:
	return int(_faction(state, empire_id).get("fleet_speed_pct", 100)) * (100 + Research.fx_int(state, empire_id, "fleet_speed_pct")) / 100


# --- Recherche ----------------------------------------------------------------------------------

## Académies des Quarante (Vael) : +x % de Savoir par empire en paix ou allié, plafonné.
static func peace_knowledge_pct(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 0
	var rs: Dictionary = e.faction().get("research", {})
	var per := int(rs.get("peace_knowledge_pct", 0))
	if per == 0:
		return 0
	var n := 0
	for c in e.contacts:
		if Diplomacy.has_pact(state, empire_id, c):
			n += 1
	return mini(n * per, int(rs.get("peace_knowledge_max", 100)))


## Matériaux et Savoir d'une population digérée en biomasse (Essaim) : {"materials", "knowledge"}.
static func biomass_gain(state: GameState, empire_id: int) -> Dictionary:
	var f := _faction(state, empire_id)
	if not f.has("biomass"):
		return {}
	return {"materials": int(f["biomass"]["materials"]) + Research.fx_int(state, empire_id, "biomass_bonus"),
			"knowledge": int(f.get("research", {}).get("knowledge_per_biomass", 0))}


# --- Vote d'urgence (Vael) ----------------------------------------------------------------------

static func can_rush(faction: Dictionary) -> bool:
	return faction.has("rush")


## Coût en influence pour achever tout de suite un chantier ("building" ou "ship"), -1 s'il n'y en a pas.
static func rush_cost(state: GameState, empire_id: int, planet_id: int, what: String) -> int:
	var e := state.get_empire(empire_id)
	var c: Colony = state.colonies.get(planet_id)
	if e == null or c == null or not can_rush(e.faction()):
		return -1
	var days := c.construction_days if what == RUSH_BUILDING and c.construction != "" else \
			(c.ship_days if what == RUSH_SHIP and c.ship_build != "" else -1)
	if days < 0:
		return -1
	var ru: Dictionary = e.faction()["rush"]
	var per := maxi(1, int(ru["days_per_influence"]))
	@warning_ignore("integer_division")
	return maxi(int(ru["min"]), (days + per - 1) / per)


static func check_rush(state: GameState, empire_id: int, planet_id: int, what: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	if not can_rush(e.faction()):
		return "votre gouvernement ne vote pas : il ordonne (et ça prend le temps que ça prend)"
	if what != RUSH_BUILDING and what != RUSH_SHIP:
		return "chantier inconnu : %s" % what
	var c: Colony = state.colonies.get(planet_id)
	if c == null or c.owner != empire_id:
		return "cette planète ne vous appartient pas"
	var cost := rush_cost(state, empire_id, planet_id, what)
	if cost < 0:
		return "aucun chantier en cours"
	if int(e.resources.get("influence", 0)) < cost:
		return "influence insuffisante (il faut %d)" % cost
	return ""


# --- Affichage ----------------------------------------------------------------------------------

## Jauge propre à la faction pour le panneau d'empire : {"label", "value", "tip", "bad"} ou {} si aucune.
static func gauge(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	var f := e.faction()
	if has_fervor(f):
		var fv: Dictionary = f["fervor"]
		var delta := fervor_delta(state, empire_id)
		var mood := "Exaltation : +%d %% de production" % (int(fv["exalted_pct"]) - 100) if e.fervor >= int(fv["exalted_at"]) \
				else ("Le dieu se tait : %d %% de production" % (int(fv["silent_pct"]) - 100) if e.fervor <= 0 \
				else "Ferveur ordinaire. Exaltation à %d." % int(fv["exalted_at"]))
		return {"label": "Ferveur", "value": "%d" % e.fervor, "delta": delta,
				"tip": "Ferveur %d / %d (%+d par mois)\n%s\nOffrande : -1 population, +%d ferveur." % [
					e.fervor, int(fv["max"]), delta, mood, sacrifice_gain(state, empire_id)],
				"bad": e.fervor <= 0}
	if has_network(f):
		var nodes := network_nodes(state, empire_id)
		var cut := network_cut(state, empire_id)
		var tip := "%d nœud%s relié%s à la capitale : +%d %% de Savoir (%d %% au plus)" % [nodes, "s" if nodes > 1 else "", "s" if nodes > 1 else "",
				network_pct(state, empire_id), int(f["network"]["max_pct"])]
		if cut > 0:
			tip += "
%d revendication%s coupée%s du réseau : production divisée par deux." % [cut, "s" if cut > 1 else "", "s" if cut > 1 else ""]
		return {"label": "Réseau", "value": "%d" % nodes if cut == 0 else "%d (%d coupé%s)" % [nodes, cut, "s" if cut > 1 else ""],
				"tip": tip, "bad": cut > 0}
	if has_horde(f):
		var hd: Dictionary = f["horde"]
		var cf := city_fleet(state, empire_id)
		if cf == null:
			return {"label": "Flotte-ville", "value": "détruite", "bad": true,
					"tip": "La flotte-ville est détruite : toutes les revendications produisent %d %% de moins, et plus rien ne rapporte ce que rapportait le palais.\nReconstruisez-la dans un chantier." % (100 - int(hd["far_pct"]))}
		var far := 0
		for pid in state.colonies:
			var c: Colony = state.colonies[pid]
			if c.owner == empire_id and c.is_established() and far_from_clan(state, c):
				far += 1
		var where := state.galaxy.systems[cf.system_id].system_name
		var tip := ("En route depuis %s : pas de campement." % where) if cf.is_moving() \
				else ("Campement à %s : les revendications du système produisent +%d %%." % [where, int(hd["camp_pct"]) - 100])
		tip += "\n%d revendication%s à plus de %d sauts : %d %% de production." % [far, "s" if far > 1 else "", int(hd["far_jumps"]), int(hd["far_pct"]) - 100]
		return {"label": "Flotte-ville", "value": ("en route" if cf.is_moving() else where) if far == 0 else "%s (%d loin)" % ["en route" if cf.is_moving() else where, far],
				"tip": tip}
	if Reputation.has(f):
		return Reputation.gauge(state, empire_id)
	if Diplomacy.has_ability(state, empire_id, "mercenary"):
		var c := Diplomacy.contract_of(state, empire_id)
		if c.is_empty():
			return {"label": "Contrat", "value": "aucun", "tip": "Flottes libres : %d vaisseaux armés, %s par mois à la location.\nLouez-les depuis la Diplomatie à un empire en guerre." % [
					Diplomacy.warships(state, empire_id), GameData.format_amounts(Diplomacy.contract_fee(state, empire_id))]}
		@warning_ignore("integer_division")
		var left := maxi(0, int(c["until"]) - state.tick) / 30
		return {"label": "Contrat", "value": state.get_empire(int(c["client"])).short_name(),
				"tip": "Flottes louées à %s contre %s : %s par mois, %d mois au plus." % [state.get_empire(int(c["client"])).short_name(),
						state.get_empire(int(c["target"])).short_name(), GameData.format_amounts(c["fee"]), left]}
	if has_fiefs(f):
		var n := fief_counts(state, empire_id)
		var tip := "%d fief%s (+%d influence chacun s'il est peuplé)\n%d fief%s lointain%s (plus de %d sauts) : %d cristal par mois chacun" % [
				n["fiefs"], "s" if n["fiefs"] > 1 else "", int(f["fiefs"]["influence"]),
				n["far"], "s" if n["far"] > 1 else "", "s" if n["far"] > 1 else "", int(f["fiefs"]["far_jumps"]), int(f["fiefs"]["crystal_upkeep"])]
		if e.dissent:
			tip += "\nDissidence : les fiefs lointains produisent %d %% de moins." % (100 - int(f["fiefs"]["dissent_pct"]))
		return {"label": "Fiefs", "value": "%d" % n["fiefs"] if n["far"] == 0 else "%d (%d loin)" % [n["fiefs"], n["far"]],
				"tip": tip, "bad": e.dissent}
	if f.has("contact_influence"):
		return {"label": "Ambassades", "value": "%d" % e.contacts.size(),
				"tip": "%d empire%s rencontré%s : +%d influence par mois" % [e.contacts.size(), "s" if e.contacts.size() > 1 else "",
					"s" if e.contacts.size() > 1 else "", extra_influence(state, empire_id)], "bad": false}
	if f.has("biomass"):
		return {"label": "Biomasse", "value": "%d" % e.biomass,
				"tip": "Matériaux digérés depuis le début de la partie : %d\nChaque population en trop d'une colonie pleine donne %d matériaux." % [
					e.biomass, int(f["biomass"]["materials"])], "bad": false}
	return {}
