class_name GroundOccupation
extends RefCounted
## Combat au sol, lot 3 : après la prise (prop. 24 à 27) et mercenaires (prop. 11).
## Seulement en combat au sol complet (Ground.full).
##
## - Tenir l'occupation : un système occupé sans régiment de l'occupant au sol ne lui rapporte que
##   unheld_income_pct % de sa part, et la résistance y monte chaque mois (elle redescend s'il est tenu).
## - Insurrection : à 100 de résistance, des partisans du propriétaire se lèvent (régiments rebelles) et
##   attaquent l'occupant ; s'ils gagnent, le système est libéré.
## - Sort des civils : une bataille au sol tue des habitants selon la dévastation qu'elle a causée ; les
##   miliciens survivants d'un monde pris retournent à la vie civile.
## - Libération : reprendre un système occupé passe par une bataille au sol contre les régiments de
##   l'occupant (sans milice) — c'est l'ordre ENVAHIR ordinaire, voir Ground.land.
## - Mercenaires : régiments loués tout de suite (sans recrues), chers, au moral fragile, qui coûtent
##   toujours leur entretien et pillent les mondes qu'ils prennent. Le Syndicat Brisecomète touche une
##   part du contrat s'il est en jeu et en paix avec le client.
##
## state.ground : "res" {"<sid>": résistance 0-100}.

static func _cfg(k: String) -> Dictionary:
	return Ground.data().get(k, {})


static func _res(state: GameState) -> Dictionary:
	if not state.ground.has("res"):
		state.ground["res"] = {}
	return state.ground["res"]


# --- Occupation tenue ------------------------------------------------------------------------------

static func held(state: GameState, sid: int) -> bool:
	var occ := WarPeace.occupier(state, sid)
	return occ < 0 or not Ground.on_ground(state, sid, occ).is_empty()


## Part (en %) de la ponction d'occupation que touche l'occupant pour ce système.
static func income_pct(state: GameState, sid: int) -> int:
	if not Ground.full(state) or held(state, sid):
		return 100
	return int(_cfg("occupation").get("unheld_income_pct", 50))


static func resistance(state: GameState, sid: int) -> int:
	return int(_res(state).get(str(sid), 0))


## Chaque mois : résistance des systèmes occupés, insurrections.
static func monthly(state: GameState) -> void:
	var oc := _cfg("occupation")
	var res := _res(state)
	for k in res.keys():
		if WarPeace.occupier(state, int(k)) < 0:
			res.erase(k)
	var occ: Dictionary = state.wars.get("occ", {}) if state.wars_on else {}
	var keys := occ.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var sid := int(k)
		var v := resistance(state, sid)
		if held(state, sid):
			v = maxi(0, v - int(oc.get("held_res_per_month", 10)))
		else:
			v = mini(100, v + int(oc.get("unheld_res_per_month", 25)))
		if v <= 0:
			res.erase(str(sid))
		else:
			res[str(sid)] = v
		if v >= 100 and Ground.battle(state, sid).is_empty():
			_uprising(state, sid)


## Les partisans du propriétaire prennent les armes contre l'occupant.
static func _uprising(state: GameState, sid: int) -> void:
	var owner := state.system_owner(sid)
	var occ := WarPeace.occupier(state, sid)
	if owner < 0 or occ < 0 or state.get_empire(owner) == null or state.get_empire(owner).eliminated:
		return
	var pop := Vassals.system_pop(state, sid, owner)
	@warning_ignore("integer_division")
	var n := clampi(1 + pop / maxi(1, int(_cfg("occupation").get("rebel_per_pop", 4))), 1, int(_cfg("occupation").get("rebel_max", 6)))
	var sp := Ground.default_species(state, owner, sid)
	for i in n:
		var r := Ground._new_regiment(state, owner, "infanterie", sp, sid)
		r["reb"] = 1
	_res(state).erase(str(sid))
	state.add_chronicle("Insurrection sur %s : %d régiment%s de partisans se lève%s contre %s. Les caves cachaient des fusils, et les fusils des rancunes." % [
			state.galaxy.systems[sid].system_name, n, "s" if n > 1 else "", "nt" if n > 1 else "", state.get_empire(occ).display_name()])
	Ground.start_battle(state, sid, owner, occ, [])


# --- Sort des civils -------------------------------------------------------------------------------

## Fin de bataille : habitants tués selon la dévastation gagnée pendant la bataille ; renvoie leur nombre.
static func civilians(state: GameState, b: Dictionary) -> int:
	var sid := int(b["s"])
	var gained := GroundSiege.dev(state, sid) - int(b.get("dev0", 0))
	@warning_ignore("integer_division")
	var lost := maxi(0, gained / maxi(1, int(_cfg("occupation").get("dev_per_civilian", 10))))
	var owner := state.system_owner(sid)
	var killed := 0
	for i in lost:
		var best: Colony = null
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c != null and c.owner == owner and c.is_colony() and c.population > 1 and (best == null or c.population > best.population):
				best = c
		if best == null:
			break
		best.population -= 1
		best.growth = 0
		Peoples.normalize(best)
		Faiths.normalize(best)
		killed += 1
	return killed


# --- Mercenaires -----------------------------------------------------------------------------------

static func merc_def() -> Dictionary:
	return _cfg("mercenaries")


## Le Syndicat Brisecomète en jeu (premier empire de ce peuple encore vivant), -1 sinon.
static func syndicate(state: GameState) -> int:
	for e in state.empires:
		if not e.eliminated and e.faction_id == String(merc_def().get("syndicate", "brisecomete")):
			return e.id
	return -1


static func hire_cost(state: GameState, eid: int) -> Dictionary:
	var cost: Dictionary = (merc_def().get("cost", {}) as Dictionary).duplicate()
	# Le Syndicat loue ses propres troupes moitié prix.
	if state.get_empire(eid) != null and state.get_empire(eid).faction_id == String(merc_def().get("syndicate", "brisecomete")):
		for k in cost:
			@warning_ignore("integer_division")
			cost[k] = int(cost[k]) / 2
	return cost


static func check_hire(state: GameState, eid: int, sid: int) -> String:
	if not Ground.full(state):
		return "les armées ne sont pas en jeu"
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return "empire inconnu"
	if sid < 0 or sid >= state.galaxy.systems.size() or WarPeace.holder(state, sid) != eid:
		return "ce système n'est pas à vous"
	if not Ground.battle(state, sid).is_empty():
		return "on se bat au sol ici"
	if state.lairs.is_empty() and syndicate(state) < 0:
		return "ni pirates ni Syndicat pour vous louer des troupes"
	var mine := 0
	for r in Ground.regiments_of(state, eid):
		if int(r.get("merc", 0)) > 0:
			mine += 1
	if mine >= int(merc_def().get("max", 4)):
		return "pas plus de %d compagnies de mercenaires à la fois" % int(merc_def().get("max", 4))
	if not Economy.can_afford(e, hire_cost(state, eid)):
		return "il faut %s" % GameData.format_amounts(hire_cost(state, eid))
	return ""


static func hire(state: GameState, eid: int, sid: int) -> void:
	var cost := hire_cost(state, eid)
	Economy.pay(state.get_empire(eid), cost)
	var syn := syndicate(state)
	if syn >= 0 and syn != eid and not Combat.at_war(state, syn, eid):
		var se := state.get_empire(syn)
		for k in cost:
			@warning_ignore("integer_division")
			se.resources[k] = int(se.resources.get(k, 0)) + int(cost[k]) * int(merc_def().get("syndicate_pct", 50)) / 100
	var r := Ground._new_regiment(state, eid, "mercenaires", "", sid)
	r["merc"] = 1
	state.add_chronicle("%s loue une compagnie de mercenaires à %s. Ils ont signé ; ils ont surtout compté." % [
			state.get_empire(eid).display_name(), state.galaxy.systems[sid].system_name], [eid])


## Mercenaires vainqueurs : ils pillent le monde pris.
static func loot(state: GameState, b: Dictionary) -> void:
	var sid := int(b["s"])
	var a := int(b["a"])
	var n := 0
	for r in Ground.on_ground(state, sid, a):
		if int(r.get("merc", 0)) > 0:
			n += 1
	if n == 0:
		return
	var md := merc_def()
	var e := state.get_empire(a)
	var got: Dictionary = md.get("loot", {})
	for k in got:
		e.resources[k] = int(e.resources.get(k, 0)) + int(got[k]) * n
	GroundSiege.add_dev(state, sid, int(md.get("loot_dev", 5)) * n)
	state.add_chronicle("Les mercenaires de %s pillent %s : %s par compagnie, et ce qui ne se compte pas." % [
			e.display_name(), state.galaxy.systems[sid].system_name, GameData.format_amounts(got)], [a, int(b["d"])])


# --- Espionnage : saboter les défenses (prop. 31) -------------------------------------------------

## Système visé : celui que a assiège chez b, sinon la capitale de b.
static func spy_target(state: GameState, a: int, b: int) -> int:
	var keys := state.sieges.keys()
	keys.sort()
	for k in keys:
		if state.system_owner(int(k)) == b and int((state.sieges[k] as Dictionary).get("by", -1)) == a:
			return int(k)
	return FactionTraits.capital_system(state, b)


static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if op_id != "saboter_defenses":
		return ""
	if not Ground.full(state):
		return "les armées ne sont pas en jeu dans cette partie"
	var sid := spy_target(state, a, b)
	if sid < 0 or GroundSiege.fort(state, sid) <= 0 and Combat.garrison(state, sid) <= 0:
		return "aucune défense à saboter"
	return ""


static func spy_apply(state: GameState, a: int, b: int, _o: Dictionary) -> String:
	var sid := spy_target(state, a, b)
	if sid < 0:
		return "les plans des remparts étaient faux. Le cartographe a disparu."
	GroundSiege._sub(state, "fort")[str(sid)] = 0
	@warning_ignore("integer_division")
	state.garrisons[sid] = Combat.garrison(state, sid) * 2 / 3
	return "les remparts de %s s'effondrent dans la nuit et un tiers de la milice ne répond plus à l'appel." % state.galaxy.systems[sid].system_name
