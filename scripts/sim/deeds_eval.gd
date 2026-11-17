class_name DeedsEval
extends RefCounted
## Ce que mesure chaque haut fait (voir Deeds) : la clé « k » d'une fiche de data/deeds.json.
## Deux familles de mesures :
## - les compteurs, nourris par Deeds.note() (batailles gagnées, curiosités fouillées, traités…) : ils
##   comptent depuis l'ouverture du haut fait pour l'empire (prop. 3) ;
## - les états, lus en direct (systèmes tenus, technologies connues, monopole…).
## Ajouter une mesure : un nom dans COUNTERS si c'est un compteur, sinon une branche dans value().

## Mesures tenues par Deeds.note() (le reste se lit dans l'état).
const COUNTERS := ["curios", "battles_won", "digs", "conquests", "treaty", "operations", "lair", "guardians",
		"nomos", "koinon", "giant_slain", "steal_up", "crisis_top", "ancient_world", "relics_stolen", "digested",
		"exterminated", "broke", "archives", "crisis_survived", "phoenix", "david", "bankrupt", "repudiated",
		"company_founded", "cargos_lost"]


static func is_counter(k: String) -> bool:
	return COUNTERS.has(k)


## Valeur brute de la mesure k pour l'empire (avant soustraction de la base d'ouverture).
static func value(state: GameState, eid: int, k: String, x: Variant = null) -> int:
	if is_counter(k):
		return Deeds.count(state, eid, k)
	var e := state.get_empire(eid)
	if e == null:
		return 0
	match k:
		"admin_clean":
			return AdminBridges.clean_years(state, eid)
		"finance_balanced":
			return FinanceBridges.balanced_years(state, eid)
		"linked_gates":
			return PortalsBridges.linked_gates(state, eid)
		"inviolate_years":
			return DefensesBridges.inviolate_years(state, eid)
		"gen_traits":
			return Genetics.stat(state, eid, "founder_traits") if Genetics.enabled(state) else 0
		"gen_shaped":
			return Genetics.stat(state, eid, "shaped") if Genetics.enabled(state) else 0
		"psi_elu":
			return Psionics.stat(state, eid, "elu") if Psionics.enabled(state) else 0
		"psi_phare":
			return Psionics.stat(state, eid, "phare") if Psionics.enabled(state) else 0
		"psi_broken":
			return Psionics.stat(state, eid, "broken") if Psionics.enabled(state) else 0
		"gen_transfer":
			return Genetics.stat(state, eid, "founder_transfer") if Genetics.enabled(state) else 0
		"veiled_fleets":
			return StealthBridges.veiled_fleets(state, eid)
		"spectre_systems":
			return StealthBridges.spectre(state, eid)
		"hidden_found":
			return StealthBridges.found(state, eid)
		"branch_empires":
			return int(Private.entry(state, eid).get("brx", 0))
		"tourism":
			return int(Private.entry(state, eid).get("tour", 0))
		"explored_pct":
			@warning_ignore("integer_division")
			return e.explored.size() * 100 / maxi(1, state.galaxy.systems.size())
		"met_all":
			return 1 if _met_all(state, e) else 0
		"ancient_met":
			return Ancients.met(state, eid).size() if Ancients.enabled(state) else 0
		"planet_types":
			var types := {}
			for c in _colonies(state, eid):
				types[state.galaxy.get_planet(c.planet_id).type] = true
			return types.size()
		"species":
			if not Peoples.enabled(state):
				return _species_basic(state, eid)
			var n0 := 0
			var cnt := Peoples.empire_counts(state, eid)
			for fid in cnt:
				if int(cnt[fid]) > 0:
					n0 += 1
			return n0
		"era":
			return Research.current_era(state, eid)
		"builder_title":
			return 1 if WondersBridges.builder_deed(state) == eid and not state.wonders.is_empty() else 0
		"trade_all":
			return 1 if _trade_all(state, e) else 0
		"capital_taken":
			return _capitals_held(state, eid)
		"echelon":
			return _best_echelon(e)
		"peace_all":
			return 1 if Deeds.peace_days(state, eid) >= Deeds.r_int("peace_days") else 0
		"revelation":
			return _faiths_founded(state, eid).size()
		"influent":
			return _influent_on(state, eid)
		"colonies":
			return _colonies(state, eid).size()
		"stock":
			return int(e.resources.get(String(x) if x != null else "materials", 0))
		"systems":
			return _systems_held(state, eid).size()
		"techs":
			return e.techs.size()
		"routes":
			return Trade.routes_of(state, eid).size()
		"holy":
			return _holy_held(state, eid)
		"explored_terrain":
			if not Terrain.active(state):
				return 0
			var n := 0
			for sid in e.explored:
				if Terrain.zone(state, int(sid)) != "":
					n += 1
			return n
		"terrain_held":
			if not Terrain.active(state):
				return 0
			var n2 := 0
			for sid in _systems_held(state, eid):
				if Terrain.zone(state, sid) != "":
					n2 += 1
			return n2
		"eurekas":
			return e.eurekas.size()
		"monopoly":
			if not Goods.active(state):
				return 0
			var m := 0
			for g in Goods.luxury_ids():
				if Goods.monopoly_of(state, g) == eid:
					m += 1
			return m
		"proteges":
			return Minors.proteges_of(state, eid).size() if Minors.enabled(state) else 0
		"museum":
			return 1 if Culture.enabled(state) and Culture.has_museum(state, eid) else 0
		"networks_all":
			return 1 if _networks_all(state, e) else 0
		"studied":
			if not Fauna.active(state):
				return 0
			var s := 0
			for sp in Fauna.species_ids():
				if Fauna.studied(state, eid, sp):
					s += 1
			return s
		"colony_pop":
			var best := 0
			for c in _colonies(state, eid):
				best = maxi(best, c.population)
			return best
		"luxuries":
			return Goods.luxuries_of(state, eid).size() if Goods.active(state) else 0
		"regiments":
			return Ground.regiments_of(state, eid).size()
		"capital_converted":
			return _capitals_converted(state, eid)
		"pop_total":
			var p := 0
			for c in _colonies(state, eid):
				p += c.population
			return p
		"branch_full":
			return _full_domains(e)
		"streak":
			return int((state.deeds.get("streak", {}) as Dictionary).get(str(eid), 0))
		"quest_relics":
			if state.relics.is_empty():
				return 0
			var q := 0
			for rid in Relics.owned(state, eid):
				if Relics.is_quest(rid):
					q += 1
			return q
		"silence":
			return 1 if Deeds.quiet_days(state, eid) >= Deeds.r_int("silence_days") else 0
		"blackhole_colony":
			for c in _colonies(state, eid):
				var sid := state.galaxy.get_planet(c.planet_id).system_id
				if Terrain.zone(state, sid) == "black_hole" or state.galaxy.systems[sid].star_type == "black_hole":
					return 1
			return 0
	return 0


# --- Aides -------------------------------------------------------------------------------------

## Colonies peuplées et fondées de l'empire.
static func _colonies(state: GameState, eid: int) -> Array[Colony]:
	var out: Array[Colony] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.is_established():
			out.append(c)
	return out


static func _systems_held(state: GameState, eid: int) -> Array[int]:
	var seen := {}
	var out: Array[int] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_established():
			var sid := state.galaxy.get_planet(pid).system_id
			if not seen.has(sid):
				seen[sid] = true
				out.append(sid)
	return out


static func _species_basic(state: GameState, eid: int) -> int:
	var sp := {}
	for c in _colonies(state, eid):
		for fid in c.species:
			if int(c.species[fid]) > 0:
				sp[fid] = true
	return sp.size()


## Rivaux encore en vie (hors PNJ).
static func rivals_alive(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for o in state.empires:
		if o.id != eid and not o.eliminated and not o.is_npc():
			out.append(o.id)
	return out


static func _met_all(state: GameState, e: Empire) -> bool:
	var rivals := rivals_alive(state, e.id)
	if rivals.size() < Deeds.r_int("min_rivals"):
		return false
	for r in rivals:
		if not e.contacts.has(r):
			return false
	return true


static func _met_alive(state: GameState, e: Empire) -> Array[int]:
	var out: Array[int] = []
	for r in rivals_alive(state, e.id):
		if e.contacts.has(r):
			out.append(r)
	return out


static func _trade_all(state: GameState, e: Empire) -> bool:
	var met := _met_alive(state, e)
	if met.size() < 4:
		return false
	for r in met:
		if not Diplomacy.has_trade(state, e.id, r):
			return false
	return true


static func _networks_all(state: GameState, e: Empire) -> bool:
	var met := _met_alive(state, e)
	if met.size() < Deeds.r_int("min_rivals"):
		return false
	for r in met:
		if Espionage.tier(state, e.id, r) < 1:
			return false
	return true


## Capitales d'origine rivales que l'empire tient.
static func _capitals_held(state: GameState, eid: int) -> int:
	var n := 0
	for o in state.empires:
		if o.id == eid or o.is_npc() or o.home_planet < 0:
			continue
		var c: Colony = state.colonies.get(o.home_planet)
		if c != null and c.owner == eid:
			n += 1
	return n


static func _best_echelon(e: Empire) -> int:
	var best := 0
	for k in e.ships_built:
		var hull := String(GameData.ship(String(k)).get("hull", k))
		best = maxi(best, int(Designs.hull(hull).get("echelon", 0)))
	return best


static func _faiths_founded(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	if not state.faith_on or not state.faiths.has("list"):
		return out
	var keys: Array = (state.faiths["list"] as Dictionary).keys()
	keys.sort()
	for fid in keys:
		if int(state.faiths["list"][fid].get("founder", -1)) == eid:
			out.append(String(fid))
	return out


static func _holy_held(state: GameState, eid: int) -> int:
	if not state.faith_on or not state.faiths.has("list"):
		return 0
	var n := 0
	for fid in state.faiths["list"]:
		var c: Colony = state.colonies.get(int(state.faiths["list"][fid].get("holy", -1)))
		if c != null and c.owner == eid:
			n += 1
	return n


static func _capitals_converted(state: GameState, eid: int) -> int:
	var mine := _faiths_founded(state, eid)
	if mine.is_empty():
		return 0
	var n := 0
	for o in state.empires:
		if o.id == eid or o.is_npc() or o.home_planet < 0:
			continue
		var c: Colony = state.colonies.get(o.home_planet)
		if c == null or c.owner == eid:
			continue
		var counts := Faiths.counts(c)
		var best := ""
		var best_n := 0
		var keys := counts.keys()
		keys.sort()
		for f in keys:
			if int(counts[f]) > best_n:
				best_n = int(counts[f])
				best = String(f)
		if mine.has(best):
			n += 1
	return n


static func _influent_on(state: GameState, eid: int) -> int:
	if not Culture.enabled(state):
		return 0
	var n := 0
	for r in rivals_alive(state, eid):
		if Culture.tier(state, eid, r) >= 4:
			n += 1
	return n


## Domaines de recherche dont l'empire connaît toutes les technologies communes.
static func _full_domains(e: Empire) -> int:
	var total := {}
	var known := {}
	var techs: Dictionary = Research.data().get("technologies", {})
	for tid in techs:
		var t: Dictionary = techs[tid]
		if t.has("requires") or t.has("replaces") or t.has("exclusive") or t.has("heretic") or t.has("forbidden") or t.has("victory"):
			continue
		var d := String(t["domain"])
		total[d] = int(total.get(d, 0)) + 1
		if e.techs.has(tid):
			known[d] = int(known.get(d, 0)) + 1
	var n := 0
	for d in total:
		if int(known.get(d, 0)) >= int(total[d]):
			n += 1
	return n
