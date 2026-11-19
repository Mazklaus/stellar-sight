class_name InsHalcyre
extends RefCounted
## Orbe-Monde Halcyre (props 23 à 28 ; voir Insolites, data/insolites.json "halcyre").
## L'espèce est sa planète : l'Orbe-Monde, un vaisseau-capitale très lent dont la population est la
## Masse. Au repos, il mange les corps morts et libres de son système (Absorber) ; manger une colonie
## demande une guerre, quatre mois sans bataille, et la tue. Il laisse des Lunes-sentinelles (des
## avant-postes), maigrit s'il ne mange rien (la Faim), ne signe de traité qu'avec les empires que son
## Avatar a visités, et gagne en s'allumant en étoile (l'Allumage) si personne ne l'assiège.
##
## État (Insolites.emp) : "pop" (Masse), "sp", "eat": {"p": planète, "left", "col": 0/1}, "fed": jour du
## dernier repas, "visited": {"eid": 1}.

const SHIP := "orbe_monde"


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("halcyre", key, def)


static func found(state: GameState, e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["pop"] = _c("start_mass", 30)
	ed["sp"] = {e.faction_id: int(ed["pop"])}
	ed["eat"] = {}
	ed["fed"] = state.tick
	ed["visited"] = {}


static func mass(state: GameState, eid: int) -> int:
	return int(Insolites.emp(state, eid).get("pop", 0))


static func _add_mass(ed: Dictionary, fid: String, n: int) -> void:
	ed["pop"] = maxi(1, int(ed["pop"]) + n)
	ed["sp"] = {fid: int(ed["pop"])}


static func orbe(state: GameState, eid: int) -> Fleet:
	return FactionTraits.city_fleet(state, eid)


static func income(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if orbe(state, eid) == null:
		return out
	var m := mass(state, eid)
	@warning_ignore("integer_division")
	Insolites.add_to(out, Insolites.cfg("halcyre").get("mass_yields", {}), m / maxi(1, _c("mass_per_yield", 4)))
	@warning_ignore("integer_division")
	out["influence"] = int(out.get("influence", 0)) + m / maxi(1, _c("mass_influence_div", 10))
	return out


static func damage_pct(state: GameState, f: Fleet) -> int:
	if f.count(SHIP) == 0:
		return 0
	@warning_ignore("integer_division")
	return mini(_c("mass_damage_max", 60), mass(state, f.owner) / maxi(1, _c("mass_damage_div", 3)))


static func visited(state: GameState, eid: int, other: int) -> bool:
	return (Insolites.emp(state, eid).get("visited", {}) as Dictionary).has(str(other))


## Corps que l'Orbe peut manger dans ce système : libre, mort (type de eat_types), pas encore mangé.
static func edible(state: GameState, sid: int) -> Array[int]:
	var out: Array[int] = []
	var types: Array = Insolites.cfg("halcyre").get("eat_types", [])
	for pid in state.galaxy.systems[sid].planet_ids:
		var p := state.galaxy.get_planet(pid)
		if state.colonies.has(pid) or Insolites.is_eaten(state, pid) or not types.has(p.type):
			continue
		if LivingWorlds.is_living(state, pid):
			continue  # on ne mange pas un cousin
		out.append(pid)
	out.sort_custom(func(a, b): return state.galaxy.get_planet(a).size > state.galaxy.get_planet(b).size or (state.galaxy.get_planet(a).size == state.galaxy.get_planet(b).size and a < b))
	return out


static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	var o := orbe(state, eid)
	var e := state.get_empire(eid)
	if o != null:
		var owner := state.system_owner(o.system_id)
		if owner >= 0 and owner != eid and owner < state.empires.size():
			(ed["visited"] as Dictionary)[str(owner)] = 1  # l'Avatar descend saluer (prop. 27)
		if not o.is_moving():
			_eat_day(state, eid, ed, o, added)
		else:
			ed["eat"] = {}
	if month:
		if state.tick - int(ed.get("fed", 0)) > _c("hunger_days", 180):
			_add_mass(ed, e.faction_id, _c("hunger_month", -1))
		if o != null and LivingWorlds.enabled(state):
			for pid in LivingWorlds.in_system(state, o.system_id):
				var w := LivingWorlds.world(state, pid)
				LivingWorlds.add_mood(state, pid, eid, _c("ego_mood", -4) if int(w.get("ego", 0)) > 0 else _c("living_mood", 3))


## Absorber (prop. 24) : un corps à la fois ; une colonie seulement sur ordre (Dévorer), en guerre.
static func _eat_day(state: GameState, eid: int, ed: Dictionary, o: Fleet, added: Array[Dictionary]) -> void:
	var eat: Dictionary = ed.get("eat", {})
	var sid := o.system_id
	if not eat.is_empty() and state.galaxy.get_planet(int(eat["p"])).system_id != sid:
		eat = {}
	if eat.is_empty():
		var list := edible(state, sid)
		if list.is_empty():
			ed["eat"] = {}
			return
		eat = {"p": list[0], "left": Insolites.tuned(state, eid, "halcyre", "eat_days", _c("eat_days", 60)), "col": 0}
	var pid := int(eat["p"])
	if int(eat["col"]) > 0:
		var c: Colony = state.colonies.get(pid)
		if c == null or not Combat.at_war(state, eid, c.owner):
			ed["eat"] = {}
			return
		if state.battles.has(sid):
			ed["eat"] = eat
			return  # pas de repas sous le feu
	elif state.colonies.has(pid):
		ed["eat"] = {}
		return
	eat["left"] = int(eat["left"]) - 1
	ed["eat"] = eat
	if int(eat["left"]) > 0:
		return
	ed["eat"] = {}
	ed["fed"] = state.tick
	var e := state.get_empire(eid)
	var p := state.galaxy.get_planet(pid)
	@warning_ignore("integer_division")
	var gain := _c("eat_mass_base", 3) + p.size / maxi(1, _c("eat_mass_size_div", 2))
	var victim := -1
	if int(eat["col"]) > 0:
		var c: Colony = state.colonies[pid]
		victim = c.owner
		gain += c.population * _c("eat_colony_mass_per_pop", 2)
		state.colonies.erase(pid)
		state.rebuild_ownership()
		Research.count_stat(state, eid, "worlds_devoured")
	Insolites.sub(state, "eaten")[str(pid)] = 1
	_add_mass(ed, e.faction_id, gain)
	Insolites.learn(state, eid, "learn_mass", gain)  # Digestion lente
	Research.count_stat(state, eid, "bodies_eaten")
	if victim >= 0:
		added.append(state.add_chronicle("L'Orbe-Monde Halcyre a dévoré %s, colonie de %s : il n'en reste qu'un anneau de poussière, et une Masse de plus (%+d)." % [
				p.display_name(state.galaxy), state.get_empire(victim).short_name(), gain], Espionage.public_to(state, [eid, victim])))
	else:
		added.append(state.add_chronicle("Halcyre a mangé %s (%+d de Masse). Les astronomes du coin corrigent leurs cartes." % [
				p.display_name(state.galaxy), gain], Espionage.private_to(state, [eid], sid)))


# --- Ordres ------------------------------------------------------------------------------------------

static func check_sentinel(state: GameState, eid: int, pid: int) -> String:
	if Insolites.kind(state, eid) != "halcyre":
		return "seul l'Orbe-Monde laisse des Lunes-sentinelles"
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return "planète inconnue"
	var o := orbe(state, eid)
	if o == null or o.is_moving() or o.system_id != p.system_id:
		return "l'Orbe-Monde doit être au repos dans ce système"
	if state.colonies.has(pid) or Insolites.is_eaten(state, pid):
		return "il faut un corps libre"
	var owner := state.system_owner(p.system_id)
	if owner >= 0 and owner != eid:
		return "le système est revendiqué par %s" % state.get_empire(owner).short_name()
	if mass(state, eid) <= Insolites.tuned(state, eid, "halcyre", "sentinel_mass", _c("sentinel_mass", 4)) + 1:
		return "il faut plus de %d de Masse" % (Insolites.tuned(state, eid, "halcyre", "sentinel_mass", _c("sentinel_mass", 4)) + 1)
	if not (Insolites.emp(state, eid).get("eat", {}) as Dictionary).is_empty() and int(Insolites.emp(state, eid)["eat"]["p"]) == pid:
		return "l'Orbe est en train de manger ce corps"
	return ""


static func sentinel(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var ed := Insolites.emp(state, eid)
	var p := state.galaxy.get_planet(pid)
	var c := Colony.new()
	c.planet_id = pid
	c.owner = eid
	c.kind = Colony.KIND_OUTPOST
	state.colonies[pid] = c
	_add_mass(ed, state.get_empire(eid).faction_id, -Insolites.tuned(state, eid, "halcyre", "sentinel_mass", _c("sentinel_mass", 4)))
	state.rebuild_ownership()
	state.garrisons[p.system_id] = Combat.garrison_max(state, p.system_id)
	Research.count_stat(state, eid, "sentinels")
	added.append(state.add_chronicle("Halcyre laisse une Lune-sentinelle sur %s : un éclat de lui-même, armé, qui garde le système." % p.display_name(state.galaxy),
			Espionage.private_to(state, [eid], p.system_id)))


static func check_devour(state: GameState, eid: int, pid: int) -> String:
	if Insolites.kind(state, eid) != "halcyre":
		return "seul l'Orbe-Monde dévore des mondes"
	var c: Colony = state.colonies.get(pid)
	if c == null:
		return "il n'y a pas de colonie sur cette planète (l'Orbe mange seul les corps libres)"
	if not Combat.at_war(state, eid, c.owner):
		return "dévorer un monde habité demande une guerre"
	var o := orbe(state, eid)
	if o == null or o.is_moving() or o.system_id != state.galaxy.get_planet(pid).system_id:
		return "l'Orbe-Monde doit être au repos dans ce système"
	var eat: Dictionary = Insolites.emp(state, eid).get("eat", {})
	if not eat.is_empty() and int(eat["p"]) == pid:
		return "l'Orbe dévore déjà ce monde"
	return ""


static func devour(state: GameState, eid: int, pid: int) -> void:
	Insolites.emp(state, eid)["eat"] = {"p": pid, "left": Insolites.tuned(state, eid, "halcyre", "eat_colony_days", _c("eat_colony_days", 120)), "col": 1}


# --- L'Allumage (prop. 28) -------------------------------------------------------------------------

## Puissance armée ennemie dans le système de l'Orbe, et la sienne : [ennemie, Orbe].
static func siege(state: GameState, eid: int) -> Array[int]:
	var o := orbe(state, eid)
	if o == null:
		return [0, 0]
	var foe := 0
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id == o.system_id and f.owner != eid and Combat.is_armed(f) and Combat.at_war(state, f.owner, eid):
			foe += Combat.fleet_power(f)
	return [foe, Combat.fleet_power(o)]


static func besieged(state: GameState, eid: int) -> bool:
	var s := siege(state, eid)
	@warning_ignore("integer_division")
	return s[0] > 0 and s[0] * 100 >= s[1] * Insolites.tuned(state, eid, "halcyre", "siege_power_pct", _c("siege_power_pct", 100))


static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := int(Insolites.cfg("victories").get("allumage", {}).get("mass", _c("ignition_mass", 120)))
	var m := mass(state, e.id)
	out["lines"].append("Masse : %d / %d" % [m, want])
	if orbe(state, e.id) == null:
		out["lines"].append("L'Orbe-Monde a disparu")
		return
	var sg := besieged(state, e.id)
	out["lines"].append("Assiégé : %s" % ("oui, le compte à rebours s'arrête" if sg else "non"))
	out["cond"] = m >= want and not sg
	Victory._timed(out, mini(m, want), want)


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Masse : %d" % int(ed["pop"]))
	var eat: Dictionary = ed.get("eat", {})
	if not eat.is_empty():
		out.append("%s %s : %d jours" % ["Dévore" if int(eat["col"]) > 0 else "Mange", state.galaxy.get_planet(int(eat["p"])).display_name(state.galaxy), int(eat["left"])])
	var hungry := state.tick - int(ed.get("fed", 0)) - _c("hunger_days", 180)
	if hungry > 0:
		out.append("La Faim : la Masse fond d'un point par mois")
	out.append("Empires visités par l'Avatar : %d" % (ed.get("visited", {}) as Dictionary).size())
	return out
