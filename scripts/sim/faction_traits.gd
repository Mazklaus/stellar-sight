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
	return n * int(fv["per_colony"]) - int(fv["decay"])


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


## Ajuste le rendement d'une revendication (Economy.colony_yields) selon les traits de son empire.
static func adjust_yields(state: GameState, c: Colony, gross: Dictionary, upkeep: Dictionary) -> void:
	var e := state.get_empire(c.owner)
	if e == null or not is_fief(state, c):
		return
	var fi: Dictionary = e.faction()["fiefs"]
	if c.is_colony():
		gross["influence"] = int(gross.get("influence", 0)) + int(fi["influence"])
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


# --- Colonisation -------------------------------------------------------------------------------

## Population d'une colonie à sa fondation.
static func colony_start_pop(state: GameState, empire_id: int) -> int:
	return int(_faction(state, empire_id).get("colony_start_pop", GameData.rules()["colony_start_pop"]))


## Habitabilité plancher (Vael) : 0 si aucune.
static func hab_floor(faction: Dictionary) -> int:
	return int(faction.get("hab_floor", 0))


## Coût d'une revendication après les traits (Kh'thari : jamais d'influence).
static func adjust_claim_cost(state: GameState, empire_id: int, cost: Dictionary) -> Dictionary:
	if not _faction(state, empire_id).get("claim_influence_free", false):
		return cost
	var out := cost.duplicate()
	out.erase("influence")
	return out


# --- Vaisseaux ----------------------------------------------------------------------------------

## Classes de vaisseaux qu'une faction peut construire, dans l'ordre des données.
static func ship_ids_for(faction_id: String) -> Array[String]:
	var f := GameData.faction(faction_id)
	var excluded: Array = f.get("ships_excluded", [])
	var out: Array[String] = []
	for sid in GameData.ship_ids():
		var only: Array = GameData.ship(sid).get("factions", [])
		if excluded.has(sid) or (not only.is_empty() and not only.has(faction_id)):
			continue
		out.append(sid)
	return out


static func start_ships(faction_id: String) -> Array:
	return GameData.faction(faction_id).get("start_ships", GameData.rules().get("start_ships", []))


## Vitesse des flottes d'un empire, en pourcentage.
static func fleet_speed_pct(state: GameState, empire_id: int) -> int:
	return int(_faction(state, empire_id).get("fleet_speed_pct", 100))


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
					e.fervor, int(fv["max"]), delta, mood, int(fv["sacrifice_gain"])],
				"bad": e.fervor <= 0}
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
