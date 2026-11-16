class_name AdminBridges
extends RefCounted
## Ponts du pilier Administration et corruption (étude 2026-11-16, propositions 23 à 28) : scandales
## (marché noir, fonctionnaires achetés, détournement révélé), pirates (raids attirés, repaires qui
## naissent près des systèmes très corrompus), espionnage (« Acheter les fonctionnaires », réseaux qui
## s'installent plus vite chez un empire trop vaste), commerce (routes amputées), politique (doléance
## « Contre la corruption », voix perdues aux élections) et haut fait « Mains propres ».
## État dans state.admin (voir Admin) : "cd", "bought", "clean", "purge" {"système": jour de fin},
## et dans l'entrée d'empire : "grv" (fin de la doléance), "grv_cd", "gfx" {"v", "end"}, "leak" (fin).

const YEAR := 360


static func _cfg(section: String) -> Dictionary:
	return Admin.data().get(section, {})


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "admin"] + parts))


## Bilan mensuel (après le recalcul d'Admin).
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		_clean(state, e.id)
		_grievance(state, e, added)
		if Admin.has_corruption(state, e.id):
			_scandals(state, e, added)
			_lairs(state, e, added)
	_prune(state)


static func _prune(state: GameState) -> void:
	for key in ["bought", "purge"]:
		var d: Dictionary = state.admin.get(key, {})
		for k in d.keys():
			if int(d[k]) <= state.tick:
				d.erase(k)


# --- Corruption ---------------------------------------------------------------------------------

## Sources de corruption venues des ponts : fonctionnaires achetés par un espion, purge récente.
static func corruption_parts(state: GameState, _eid: int, sid: int) -> Array:
	var out := []
	if int((state.admin.get("bought", {}) as Dictionary).get(str(sid), 0)) > state.tick:
		out.append(["Fonctionnaires achetés par des espions", int(_cfg("espionage")["bought_corruption"])])
	if int((state.admin.get("purge", {}) as Dictionary).get(str(sid), 0)) > state.tick:
		out.append(["Purge récente", -10])
	return out


## Stabilité d'empire : suites de la doléance « Contre la corruption ».
static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	var gfx: Dictionary = Admin.entry(state, eid).get("gfx", {})
	if not gfx.is_empty() and int(gfx.get("end", 0)) > state.tick:
		out.append(["Doléance contre la corruption %s" % ("entendue" if int(gfx["v"]) > 0 else "ignorée"), int(gfx["v"])])
	return out


# --- Haut fait « Mains propres » -----------------------------------------------------------------

static func _clean(state: GameState, eid: int) -> void:
	var clean: Dictionary = state.admin["clean"]
	var dc := _cfg("deed")
	var ok := Admin.has_corruption(state, eid) and Stability.systems_of(state, eid).size() >= int(dc["min_systems"]) \
			and Admin.average_corruption(state, eid) <= int(dc["max_corruption"])
	if ok:
		if not clean.has(str(eid)):
			clean[str(eid)] = state.tick
	else:
		clean.erase(str(eid))


## Années d'administration exemplaire (mesure du haut fait).
static func clean_years(state: GameState, eid: int) -> int:
	if state.admin.is_empty():
		return 0
	var since: Variant = (state.admin["clean"] as Dictionary).get(str(eid))
	if since == null:
		return 0
	@warning_ignore("integer_division")
	return (state.tick - int(since)) / YEAR


# --- Politique ----------------------------------------------------------------------------------

static func _grievance(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	if not Admin.has_corruption(state, e.id) or not state.politics_on or not Politics.applies(state, e.id):
		return
	var en := Admin._w(state, e.id)
	var pc := _cfg("politics")
	var avg := Admin.average_corruption(state, e.id)
	var grv := int(en.get("grv", 0))
	if grv > 0:
		if avg < int(pc["grievance_from"]) - 5:
			en.erase("grv")
			en["grv_cd"] = state.tick + YEAR
			en["gfx"] = {"v": 5, "end": state.tick + YEAR}
			if not e.is_ai():
				added.append(state.add_chronicle("La doléance contre la corruption est entendue : %s respire, et les gazettes aussi." % e.short_name(), Espionage.private_to(state, [e.id])))
		elif grv <= state.tick:
			en.erase("grv")
			en["grv_cd"] = state.tick + YEAR
			en["gfx"] = {"v": -5, "end": state.tick + YEAR}
			if not e.is_ai():
				added.append(state.add_chronicle("La doléance contre la corruption est restée lettre morte : %s gronde (-5 stabilité pendant un an)." % e.short_name(), Espionage.private_to(state, [e.id])))
		return
	if avg >= int(pc["grievance_from"]) and int(en.get("grv_cd", 0)) <= state.tick:
		en["grv"] = state.tick + 2 * YEAR
		if not e.is_ai():
			added.append(state.add_chronicle("Doléance « Contre la corruption » à %s : ramenez la corruption moyenne sous %d %% en deux ans, ou la colère montera." % [
					e.short_name(), int(pc["grievance_from"]) - 5], Espionage.private_to(state, [e.id])))


## Doléance en cours : jour de fin (0 si aucune).
static func grievance_end(state: GameState, eid: int) -> int:
	return int(Admin.entry(state, eid).get("grv", 0))


## Élections : une corruption moyenne élevée coûte des voix aux courants au pouvoir.
static func adjust_votes(state: GameState, eid: int, votes: Array) -> void:
	if state.admin.is_empty() or not Admin.has_corruption(state, eid):
		return
	var pc := _cfg("politics")
	if Admin.average_corruption(state, eid) < int(pc["election_from"]):
		return
	for i in votes.size():
		if Politics.in_power(state, eid, i):
			@warning_ignore("integer_division")
			votes[i] = int(votes[i]) * (100 + int(pc["election_pct"])) / 100


# --- Scandales ----------------------------------------------------------------------------------

static func _scandals(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var sc := _cfg("scandals")
	var cd: Dictionary = state.admin["cd"]
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"])
	for sid in Stability.systems_of(state, e.id):
		if posmod(month + sid, 12) != 0:
			continue  # une chance par an et par système
		if Admin.corruption(state, sid) < int(sc["from"]):
			continue
		if int(cd.get(str(sid), -100000)) + int(sc["cooldown_days"]) > state.tick:
			continue
		if _h(state, ["scandale", sid, month]) % 100 >= int(sc["chance_pct"]):
			continue
		cd[str(sid)] = state.tick
		var kinds: Array = Admin.data()["scandal_kinds"]
		_play(state, e, sid, String(kinds[_h(state, ["carte", sid, month]) % kinds.size()]), added)


static func _play(state: GameState, e: Empire, sid: int, id: String, added: Array[Dictionary]) -> void:
	var sc := _cfg("scandals")
	var sname := state.galaxy.systems[sid].system_name
	match id:
		"marche_noir":
			var lost := mini(int(e.resources.get("energy", 0)), int(sc["black_market_energy"]))
			e.resources["energy"] = int(e.resources.get("energy", 0)) - lost
			added.append(state.add_chronicle("Marché noir à %s : %d énergie s'évaporent des entrepôts, et reparaissent au prix fort chez les receleurs." % [sname, lost], Espionage.private_to(state, [e.id], sid)))
		"fonctionnaires_achetes":
			Admin._w(state, e.id)["leak"] = state.tick + int(sc["bought_days"])
			added.append(state.add_chronicle("Fonctionnaires achetés à %s : les douaniers portent des bagues qu'aucun salaire ne paie. Les espions étrangers passent sans attendre pendant un an." % sname, Espionage.private_to(state, [e.id], sid)))
		"detournement":
			var gov := Heroes.at_post(state, "system", sid, e.id) if not state.heroes.is_empty() else {}
			Events.push(state, e.id, "admin_detournement", {"system": sid, "hero": int(gov.get("id", -1))}, added)


## Carte « Détournement révélé » : punir le gouverneur (loyauté), étouffer (influence), ou laisser faire.
static func apply_fx(state: GameState, eid: int, item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	var sid := int(item.get("system", -1))
	match String(fx.get("act", "")):
		"punish":
			if sid >= 0:
				(state.admin["purge"] as Dictionary)[str(sid)] = state.tick + 2 * YEAR
			var hid := int(item.get("hero", -1))
			var h := Heroes.get_hero(state, hid)
			if not h.is_empty() and int(h["owner"]) == eid:
				h["loy"] = maxi(0, int(h.get("loy", 50)) + int(_cfg("scandals")["punish_loyalty"]))
			Admin.refresh_empire(state, eid)


static func fx_lines(_state: GameState, _eid: int, item: Dictionary, fx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if String(fx.get("act", "")) == "punish":
		out.append("Corruption -10 dans le système pendant deux ans")
		if int(item.get("hero", -1)) >= 0:
			out.append("Le gouverneur perd %d de loyauté" % absi(int(_cfg("scandals")["punish_loyalty"])))
	return out


static func fx_problem(state: GameState, _eid: int, _item: Dictionary, _fx: Dictionary) -> String:
	return "" if Admin.enabled(state) else "pas d'administration"


static func ai_value(_state: GameState, _eid: int, _item: Dictionary, fx: Dictionary) -> int:
	return 20 if String(fx.get("act", "")) == "punish" else 0


# --- Pirates ------------------------------------------------------------------------------------

## Raids : parmi les cibles possibles, les systèmes très corrompus d'abord.
static func raid_filter(state: GameState, cands: Array) -> Array:
	if state.admin.is_empty() or not Admin.full(state):
		return cands
	var from := int(_cfg("pirates")["raid_from"])
	var hot := cands.filter(func(c: Dictionary) -> bool: return Admin.corruption(state, int(c["sid"])) >= from)
	return hot if not hot.is_empty() else cands


## Repaires : un système libre voisin d'un système très corrompu peut en abriter un nouveau (une fois par an).
static func _lairs(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	if state.pirate_density == "aucun" or state.pirate_density == "":
		return
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"])
	if posmod(month + e.id, 12) != 6:
		return
	var pc := _cfg("pirates")
	for sid in Stability.systems_of(state, e.id):
		if Admin.corruption(state, sid) < int(pc["lair_from"]):
			continue
		if _h(state, ["repaire", sid, month]) % 100 >= int(pc["lair_chance_pct"]):
			continue
		for n in state.galaxy.systems[sid].neighbors:
			if state.system_owner(n) >= 0 or state.lairs.has(n) or Pirates.is_port(state, n):
				continue
			Pirates.create_lair(state, n)
			added.append(state.add_chronicle("Des contrebandiers chassés de %s ont fait de %s un repaire : la corruption a des enfants, et ils sont armés." % [
					state.galaxy.systems[sid].system_name, state.galaxy.systems[n].system_name], Espionage.private_to(state, [e.id], n)))
			return


# --- Commerce -----------------------------------------------------------------------------------

## Part (en points de %) qu'une route perd à cause de la corruption du système d'où elle part.
static func trade_pct(state: GameState, eid: int, sid: int) -> int:
	if state.admin.is_empty() or bool(Admin.talent(state, eid).get("trade_safe", false)):
		return 0
	return Admin.corruption(state, sid)


# --- Espionnage ---------------------------------------------------------------------------------

## Croissance des réseaux étrangers chez un empire trop vaste ou aux fonctionnaires achetés.
static func growth_parts(state: GameState, b: int) -> Array:
	var out := []
	if state.admin.is_empty() or not Admin.applies(state, b):
		return out
	var n := mini(5, Admin.steps(state, b) * int(_cfg("espionage").get("infiltration_per_step", 1)))
	if n > 0:
		out.append(["Empire trop vaste : ses bureaux débordent", n])
	if int(Admin.entry(state, b).get("leak", 0)) > state.tick:
		out.append(["Fonctionnaires achetés", 3])
	return out


## Système visé par « Acheter les fonctionnaires » : le plus corrompu hors capitale (-1 s'il n'y en a pas).
static func bribe_target(state: GameState, b: int) -> int:
	var cap := FactionTraits.capital_system(state, b)
	var best := -1
	var bv := -1
	for sid in Stability.systems_of(state, b):
		if sid == cap:
			continue
		var v := Admin.corruption(state, sid)
		if v > bv:
			bv = v
			best = sid
	return best


static func spy_check(state: GameState, _a: int, b: int, op_id: String) -> String:
	if op_id == "acheter_fonctionnaires":
		if not Admin.has_corruption(state, b):
			return "l'administration n'est pas en jeu, ou ce peuple ne se corrompt pas"
		if bribe_target(state, b) < 0:
			return "il n'a aucun système hors de sa capitale"
	return ""


static func spy_apply(state: GameState, _a: int, b: int, o: Dictionary) -> String:
	if String(o["id"]) == "acheter_fonctionnaires":
		var sid := bribe_target(state, b)
		if sid < 0:
			return "il n'y avait plus personne à acheter. L'or rentre au coffre."
		(state.admin["bought"] as Dictionary)[str(sid)] = state.tick + int(_cfg("espionage")["bought_days"])
		Admin.refresh_empire(state, b)
		return "les fonctionnaires de %s sont à nous : +%d corruption pendant un an. Ils signent tout, même ce qu'ils ne lisent pas." % [
				state.galaxy.systems[sid].system_name, int(_cfg("espionage")["bought_corruption"])]
	return ""
