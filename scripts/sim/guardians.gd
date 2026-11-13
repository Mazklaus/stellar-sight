class_name Guardians
extends RefCounted
## Gardiens (lot 2 des créatures, propositions 6 à 9) : dix créatures uniques de la Faune
## (GameState.FAUNA_ID), assises sur les meilleurs systèmes. Règles dans data/guardians.json.
## - Placement (setup) : 6 à 10 par partie s'il y a des créatures, loin des capitales, chacun selon
##   son goût (étoile, planète, nid, site de fouille…). Trois dorment (Nid sous la ceinture, Œuf-monde,
##   Ce qui dort sous les Portes) et ne se montrent qu'après une action des empires.
## - Un gardien éveillé interdit la colonisation de son système ; on traverse sans s'arrêter. L'Horloger
##   est pacifique : il ne se bat que contre qui l'a provoqué.
## - Riposte (Vouivre, Mange-soleil), étoile rongée (Mange-soleil), réveils, récits à choix (cartes
##   d'événement « guardian » traitées par card_fx).
## - Vaincu : trophée (relique), Triomphe automatique, savoirs anciens (technologies hors arbre), butin,
##   récit éventuel.
## État dans state.fauna["guardians"] ; savoirs anciens et déblocages dans la mémoire de chaque empire
## (Fauna._meta : « techs », « unlock »). Aucun aléatoire : hachages de la graine.


static func data() -> Dictionary:
	return GameData.guardians()


static func def(gid: String) -> Dictionary:
	for g: Dictionary in data().get("guardians", []):
		if String(g["id"]) == gid:
			return g
	return {}


static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for g: Dictionary in data().get("guardians", []):
		out.append(String(g["id"]))
	return out


static func tech_def(tid: String) -> Dictionary:
	return (data().get("techs", {}) as Dictionary).get(tid, {})


## Gardiens de la partie : {gid: état}.
static func list(state: GameState) -> Dictionary:
	return state.fauna.get("guardians", {})


## Gardiens de la partie, triés par identifiant.
static func ids(state: GameState) -> Array[String]:
	var out: Array[String] = []
	for k in list(state):
		out.append(String(k))
	out.sort()
	return out


static func _h(state: GameState, parts: Array) -> int:
	return posmod(hash([state.seed_value, "gardien"] + parts), 1000003)


# --- Mise en place --------------------------------------------------------------------------------

static func setup(state: GameState) -> void:
	if not Fauna.active(state):
		return
	var d := data()
	var n := state.galaxy.systems.size()
	@warning_ignore("integer_division")
	var want := clampi((n + int(d["count_per"]) / 2) / int(d["count_per"]), int(d["count_min"]), int(d["count_max"]))
	var starts: Array = []
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cap))
	var order: Array = []
	for gid in all_ids():
		order.append([_h(state, ["ordre", gid]), gid])
	order.sort()
	var used: Array[int] = []
	for o in order:
		if list(state).size() >= want:
			break
		var gid := String(o[1])
		var sid := _pick_site(state, gid, starts, used)
		if sid < 0:
			continue
		used.append(sid)
		_create(state, gid, sid)
	for e in state.empires:
		e.path_cache.clear()


## Meilleur système pour ce gardien (selon son goût), -1 s'il n'y en a pas.
static func _pick_site(state: GameState, gid: String, starts: Array, used: Array[int]) -> int:
	var place: Dictionary = def(gid).get("place", {})
	var min_j := int(data()["min_jumps"])
	var cands: Array = []
	for s in state.galaxy.systems:
		if s.planet_ids.is_empty() and not place.has("isolated"):
			continue
		if state.system_owner(s.id) >= 0 or state.lairs.has(s.id) or used.has(s.id):
			continue
		if Fauna.nests(state).has(s.id) and not place.has("nest"):
			continue
		if state.digs.has(s.id) and not place.has("dig"):
			continue
		var near := 999
		for dj: Dictionary in starts:
			near = mini(near, int(dj.get(s.id, 999)))
		if near < min_j:
			continue
		var close := false
		for u in used:
			if int(FactionTraits.jumps_from(state.galaxy, u).get(s.id, 999)) < 2:
				close = true
				break
		if close or not _fits(state, place, s.id):
			continue
		cands.append([_h(state, ["site", gid, s.id]), s.id])
	if cands.is_empty():
		return -1
	cands.sort()
	return int(cands[0][1])


static func _fits(state: GameState, place: Dictionary, sid: int) -> bool:
	var s := state.galaxy.systems[sid]
	if place.has("star") and not (place["star"] as Array).has(s.star_type):
		return false
	if place.has("planet") and _planet_for(state, place, sid) < 0:
		return false
	if place.has("habitable"):
		var hab := 0
		for pid in s.planet_ids:
			if state.galaxy.get_planet(pid).is_habitable_type():
				hab += 1
		if hab < int(place["habitable"]):
			return false
	if place.has("nest"):
		var nest: Dictionary = Fauna.nests(state).get(sid, {})
		if nest.is_empty() or String(nest["sp"]) != String(place["nest"]):
			return false
	if place.has("isolated") and s.neighbors.size() > 1:
		return false
	if place.has("dig") and (not state.digs.has(sid) or int(state.digs[sid]["done"]) >= 0):
		return false
	return true


## Planète du goût du gardien dans ce système (-1 sinon).
static func _planet_for(state: GameState, place: Dictionary, sid: int) -> int:
	for pid in state.galaxy.systems[sid].planet_ids:
		var p := state.galaxy.get_planet(pid)
		if not (place.get("planet", []) as Array).has(p.type):
			continue
		if bool(place.get("habitable_only", false)) and not p.is_habitable_type():
			continue
		return pid
	return -1


static func _create(state: GameState, gid: String, sid: int) -> void:
	var gd := def(gid)
	var place: Dictionary = gd.get("place", {})
	var g := {"sid": sid, "home": sid, "fleet": -1, "status": "awake", "by": -1, "seen": {}, "hostile": [],
			"wake": 0, "planet": -1, "egg_at": 0, "visited": {}, "next": 0, "b_hp": -1, "b_foes": []}
	if place.has("planet"):
		g["planet"] = _planet_for(state, place, sid)
	# Le trésor de la Vouivre : ses gisements sur sa planète.
	if place.has("deposit") and int(g["planet"]) >= 0:
		var p := state.galaxy.get_planet(int(g["planet"]))
		var deps: Array = Array(p.deposits).duplicate()
		for dep in place["deposit"]:
			if not deps.has(dep):
				deps.append(dep)
		state.override_planet(int(g["planet"]), {"deposits": deps})
	list(state)[gid] = g
	if gd.has("dormant"):
		g["status"] = "dormant"
	else:
		_spawn(state, gid)
	if bool(gd.get("sun_eater", false)):
		g["next"] = state.tick + int(data()["sun_eater_days"])


## Fait paraître (ou reparaître) le gardien dans son système.
static func _spawn(state: GameState, gid: String) -> Fleet:
	var g: Dictionary = list(state)[gid]
	var units: Array = def(gid)["units"]
	var f := state.spawn_ship(GameState.FAUNA_ID, String(units[0][0]), int(g["sid"]))
	for i in units.size():
		for k in int(units[i][1]) - (1 if i == 0 else 0):
			f.add_ship(String(units[i][0]), -1, -1)
	f.troops = 0
	f.fleet_name = String(def(gid)["name"])
	g["fleet"] = f.id
	g["status"] = "awake"
	g["b_hp"] = -1
	for e in state.empires:
		e.path_cache.clear()
	return f


# --- Questions ------------------------------------------------------------------------------------

## Gardien de cette flotte ("" sinon).
static func of_fleet(state: GameState, f: Fleet) -> String:
	if f == null or f.owner != GameState.FAUNA_ID or state.fauna.is_empty():
		return ""
	for gid in list(state):
		if int(list(state)[gid]["fleet"]) == f.id:
			return String(gid)
	return ""


## Système où se tient la flotte du gardien (-1 s'il n'en a plus).
static func fleet_system(state: GameState, gid: String) -> int:
	var f: Fleet = state.fleets.get(int(list(state)[gid]["fleet"]))
	return f.system_id if f != null and not f.is_moving() else -1


## Gardien éveillé dans ce système ("" sinon).
static func awake_at(state: GameState, sid: int) -> String:
	if state.fauna.is_empty():
		return ""
	for gid in ids(state):
		var g: Dictionary = list(state)[gid]
		if String(g["status"]) == "awake" and state.fleets.has(int(g["fleet"])) and (state.fleets[int(g["fleet"])] as Fleet).system_id == sid:
			return gid
	return ""


## Le gardien combat-il cet empire ? L'Horloger seulement qui l'a provoqué ; les autres, tous.
static func hostile(state: GameState, gid: String, empire_id: int) -> bool:
	if empire_id < 0 or GameState.is_npc(empire_id):
		return false
	if parley(state, gid, empire_id):
		return false
	if bool(def(gid).get("pacific", false)):
		return (list(state)[gid]["hostile"] as Array).has(empire_id)
	return true


## Raison pour laquelle on ne peut pas coloniser ce système ("" si rien).
## Un peuple synthétique parlemente avec les gardiens machines (talent « Langage machine »).
static func parley(state: GameState, gid: String, empire_id: int) -> bool:
	return bool(def(gid).get("machine", false)) and bool(Fauna.talent(state, empire_id).get("parley", false))


static func colony_block(state: GameState, sid: int, empire_id := -1) -> String:
	var gid := awake_at(state, sid)
	if gid != "" and empire_id >= 0 and parley(state, gid, empire_id):
		return ""
	return ("%s veille sur ce système : il faut d'abord l'abattre" % String(def(gid)["name"])) if gid != "" else ""


## Gardiens que l'empire a vus, triés.
static func known(state: GameState, empire_id: int) -> Array[String]:
	var out: Array[String] = []
	for gid in ids(state):
		if (list(state)[gid]["seen"] as Dictionary).has(empire_id):
			out.append(gid)
	return out


## Production d'un système, en % (étoile rongée par le Mange-soleil ou étouffée par une opération).
static func production_pct(state: GameState, sid: int) -> int:
	if state.fauna.is_empty():
		return 100
	var choke: Dictionary = state.fauna.get("choke", {})
	if int(choke.get(sid, 0)) > state.tick:
		return 100 - int(data()["choke"]["pct"])
	var gid := awake_at(state, sid)
	if gid != "" and bool(def(gid).get("sun_eater", false)):
		return 100 - int(data()["sun_eater_pct"])
	return 100


static func has_tech(state: GameState, empire_id: int, tid: String) -> bool:
	return (Fauna._meta_r(state, empire_id).get("techs", {}) as Dictionary).has(tid)


static func unlocked(state: GameState, empire_id: int, what: String) -> bool:
	return (Fauna._meta_r(state, empire_id).get("unlock", {}) as Dictionary).has(what)


## La Matriarche abattue : toutes les Nacrelles s'apprivoisent sans étude.
static func tame_freed(state: GameState, sp: String) -> bool:
	var g: Dictionary = list(state).get("matriarche", {})
	return sp == "nacrelles" and not g.is_empty() and String(g["status"]) == "dead"


## Savoirs anciens de l'empire (effets au format des technologies).
static func effects(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	for tid in (Fauna._meta_r(state, empire_id).get("techs", {}) as Dictionary):
		Research._merge(out, (tech_def(String(tid)).get("fx", {}) as Dictionary).duplicate(true))
	return out


static func give_tech(state: GameState, empire_id: int, tid: String) -> void:
	if tech_def(tid).is_empty() or has_tech(state, empire_id, tid):
		return
	var m := Fauna._meta(state, empire_id)
	if not m.has("techs"):
		m["techs"] = {}
	m["techs"][tid] = state.tick
	state.relic_rev += 1


# --- Chaque jour ----------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if list(state).is_empty():
		return
	for gid in ids(state):
		var g: Dictionary = list(state)[gid]
		match String(g["status"]):
			"awake":
				_awake_day(state, gid, g, added)
			"dormant":
				_dormant_day(state, gid, g, added)
	_sightings(state)


static func _awake_day(state: GameState, gid: String, g: Dictionary, added: Array[Dictionary]) -> void:
	var f: Fleet = state.fleets.get(int(g["fleet"]))
	if f == null:
		return
	var gd := def(gid)
	var here := f.system_id
	# Riposte : on note la coque au début de la bataille, on compare à la fin.
	if bool(gd.get("riposte", false)):
		if state.battles.has(here):
			if int(g["b_hp"]) < 0:
				g["b_hp"] = f.total_hp()
				var foes: Array = []
				for o in Fleets.fleets_at(state, here):
					if not GameState.is_npc(o.owner) and not foes.has(o.owner):
						foes.append(o.owner)
				foes.sort()
				g["b_foes"] = foes
		elif int(g["b_hp"]) >= 0:
			var lost := int(g["b_hp"]) - f.total_hp()
			g["b_hp"] = -1
			if lost * 100 >= int(data()["riposte_pct"]) * f.total_max_hp() and not (g["b_foes"] as Array).is_empty():
				_riposte(state, gid, int((g["b_foes"] as Array)[0]), added)
			for i in f.hp.size():
				f.hp[i] = Fleet.max_hp_of(f.ships[i])
	# Le Mange-soleil change d'étoile tous les deux ans.
	if bool(gd.get("sun_eater", false)) and state.tick >= int(g["next"]) and not f.is_moving() and not state.battles.has(here):
		g["next"] = state.tick + int(data()["sun_eater_days"])
		var to := _sun_target(state, gid, g, f)
		if to >= 0:
			var plan := Fleets.plan_route(state, f, to)
			if not plan.is_empty():
				f.system_id = int(plan["system"])
				f.path.assign(plan["path"])
				f.progress = int(plan["progress"])
	# L'Horloger reçoit les visiteurs : une carte pour chaque empire qui s'arrête chez lui.
	if gd.has("visit_card") and not state.battles.has(here):
		for o in Fleets.fleets_at(state, here):
			if GameState.is_npc(o.owner) or o.is_moving() or (g["visited"] as Dictionary).has(o.owner):
				continue
			g["visited"][o.owner] = state.tick
			Events.push(state, o.owner, String(gd["visit_card"]), {"system": here}, added)


static func _sun_target(state: GameState, gid: String, g: Dictionary, f: Fleet) -> int:
	var jumps := FactionTraits.jumps_from(state.galaxy, int(g["home"]))
	var cands: Array[int] = []
	for k in jumps:
		var sid := int(k)
		if int(jumps[k]) <= 2 and sid != f.system_id and awake_at(state, sid) == "" and not state.lairs.has(sid):
			cands.append(sid)
	if cands.is_empty():
		return -1
	cands.sort()
	return cands[posmod(hash([state.seed_value, gid, state.tick]), cands.size())]


static func _riposte(state: GameState, gid: String, foe: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(foe)
	if e == null or e.eliminated:
		return
	var cols: Array = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == foe and c.is_colony():
			cols.append([-c.population, pid])
	cols.sort()
	var names: Array = []
	var d := data()
	for i in mini(2, cols.size()):
		var c: Colony = state.colonies[int(cols[i][1])]
		c.population = maxi(1, c.population - int(d["riposte_pop"]))
		var sid := state.galaxy.get_planet(c.planet_id).system_id
		if Stability.applies(state, foe):
			var en := Stability._entry_w(state, sid)
			en["ev"] = int(d["riposte_stab"])
			en["ev_end"] = state.tick + int(d["riposte_days"])
			en["ev_card"] = "riposte_" + gid
		names.append(state.galaxy.systems[sid].system_name)
	if names.is_empty():
		return
	added.append(state.add_chronicle("%s, blessée, rend coup pour coup : %s brûlent sous son souffle. Puis elle rentre lécher ses plaies, et elles se referment." % [
			String(def(gid)["name"]), " et ".join(names)], Espionage.public_to(state, [foe])))


static func _dormant_day(state: GameState, gid: String, g: Dictionary, added: Array[Dictionary]) -> void:
	var d := data()
	var sid := int(g["sid"])
	match String(def(gid).get("dormant", "")):
		"belt":
			var claims := 0
			for pid in state.galaxy.systems[sid].planet_ids:
				if state.colonies.has(pid):
					claims += 1
			g["wake"] = int(g["wake"]) + 1 + claims * int(d["belt_per_claim"])
			if int(g["wake"]) >= int(d["belt_wake"]) and not state.battles.has(sid):
				_spawn(state, gid)
				_wake_news(state, gid, "Sous la ceinture de %s, les cailloux se mettent à bouger. Puis à mordre." % state.galaxy.systems[sid].system_name, added)
		"egg":
			var pid := int(g["planet"])
			var c: Colony = state.colonies.get(pid)
			if c == null or not c.is_established():
				g["egg_at"] = 0
				return
			if int(g["egg_at"]) == 0:
				g["egg_at"] = state.tick + int(d["egg_days"])
			elif int(g["egg_at"]) > 0 and state.tick >= int(g["egg_at"]):
				g["egg_at"] = -1  # la carte est partie
				Events.push(state, c.owner, "gardien_oeuf_monde", {"system": sid, "planet": pid}, added)


static func _wake_news(state: GameState, gid: String, text: String, added: Array[Dictionary]) -> void:
	var sid := int(list(state)[gid]["sid"])
	var who: Array = []
	for e in state.empires:
		if not e.eliminated and e.explored.has(sid):
			who.append(e.id)
	added.append(state.add_chronicle(text, Espionage.public_to(state, who)))


## Les empires qui voient un gardien éveillé l'inscrivent au Bestiaire.
static func _sightings(state: GameState) -> void:
	if state.seen_tick != state.tick or state.seen_cache.size() < state.empires.size():
		return
	for gid in ids(state):
		var g: Dictionary = list(state)[gid]
		if String(g["status"]) != "awake" or not state.fleets.has(int(g["fleet"])):
			continue
		var at := (state.fleets[int(g["fleet"])] as Fleet).system_id
		for e in state.empires:
			if not e.eliminated and not (g["seen"] as Dictionary).has(e.id) and (state.seen_cache[e.id] as Dictionary).has(at):
				g["seen"][e.id] = state.tick


# --- Fin de bataille ------------------------------------------------------------------------------

## Un gardien abattu : trophée, Triomphe, savoirs anciens, butin et récit pour le vainqueur.
static func on_battle(state: GameState, b: Dictionary, winner: int, added: Array[Dictionary]) -> void:
	if list(state).is_empty():
		return
	for gid in ids(state):
		var g: Dictionary = list(state)[gid]
		if String(g["status"]) != "awake":
			continue
		var f: Fleet = state.fleets.get(int(g["fleet"]))
		if f != null and not f.ships.is_empty():
			continue
		if f != null:
			state.fleets.erase(f.id)
		g["status"] = "dead"
		g["fleet"] = -1
		g["by"] = winner if winner >= 0 and not GameState.is_npc(winner) else -1
		for e in state.empires:
			e.path_cache.clear()
		if int(g["by"]) >= 0:
			_reward(state, gid, int(g["by"]), int(b.get("system", g["sid"])), added)


static func _reward(state: GameState, gid: String, eid: int, sid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var gd := def(gid)
	var d := data()
	var parts: Array = []
	if String(gd.get("trophy", "")) != "":
		parts.append("trophée : %s" % Quests.give_relic(state, eid, String(gd["trophy"])))
	var item := {"id": -1, "card": "", "system": sid, "planet": -1, "rival": -1, "hero": -1}
	# La chute d'un gardien peut révéler une grande foi, avec un monde saint près du lieu (voir Faiths).
	if state.faith_on and Faiths.reveal(state, eid, "gardien", Faiths.colony_in_system(state, eid, sid), added) != "":
		parts.append("une foi est née")
	var t: Dictionary = d["triumph"]
	var tri := triumph_scale(state, eid, int(t["stab"]), int(t["influence"]))
	Events.apply_fx(state, eid, item, [{"k": "stab", "v": int(tri[0]), "days": int(t["days"]), "scope": "capital"},
			{"k": "res", "res": {"influence": int(tri[1])}}], added)
	var loot: Dictionary = gd.get("loot", {})
	for r in loot:
		e.resources[r] = int(e.resources.get(r, 0)) + int(loot[r])
	if not loot.is_empty():
		parts.append(GameData.format_amounts(loot))
	for tid in gd.get("techs", []):
		give_tech(state, eid, String(tid))
		parts.append("savoir ancien : %s" % String(tech_def(String(tid)).get("label", tid)))
	if gd.has("unlock"):
		var m := Fauna._meta(state, eid)
		if not m.has("unlock"):
			m["unlock"] = {}
		m["unlock"][String(gd["unlock"])] = state.tick
		parts.append("opération « Étouffer une étoile »")
	Heroes.act(state, eid, "guardian")
	if not state.heroes.is_empty():
		for f in Fleets.fleets_at(state, sid, eid):
			var adm := Heroes.assigned_to(state, "fleet", f.id, eid)
			if not adm.is_empty():
				Heroes.gain_xp(state, adm, 60)
				monster_slayer(state, adm, added)
	Research.count_stat(state, eid, "guardians")
	if gid == "matriarche":
		for o in state.empires:
			o.path_cache.clear()
	var who: Array = [eid]
	for o in state.empires:
		if not o.eliminated and o.explored.has(sid) and not who.has(o.id):
			who.append(o.id)
	added.append(state.add_chronicle("Triomphe ! %s abat %s à %s. Les foules envahissent les places de la capitale et les poètes cherchent des rimes. %s." % [
			e.display_name(), String(gd["name"]), state.galaxy.systems[sid].system_name,
			("Au tableau : " + ", ".join(parts)) if not parts.is_empty() else "La gloire suffit"], Espionage.public_to(state, who)))
	if String(gd.get("card", "")) != "":
		Events.push(state, eid, String(gd["card"]), {"system": sid}, added)


## Triomphe selon les talents : [stabilité, influence] (honneur : doublé ; profit : +50 % d'influence).
static func triumph_scale(state: GameState, eid: int, stab: int, infl: int) -> Array:
	var tal := Fauna.talent(state, eid)
	@warning_ignore("integer_division")
	var s := stab * (100 + int(tal.get("triumph_pct", 0))) / 100
	@warning_ignore("integer_division")
	var i := infl * (100 + int(tal.get("triumph_pct", 0)) + int(tal.get("trophy_influence_pct", 0))) / 100
	return [s, i]


## L'amiral qui commandait gagne le trait « Tueur de monstres » (une fois).
static func monster_slayer(state: GameState, adm: Dictionary, added: Array[Dictionary]) -> void:
	var h := adm
	if h.is_empty() or (h["traits"] as Array).has("tueur_monstres"):
		return
	(h["traits"] as Array).append("tueur_monstres")
	added.append(state.add_chronicle("%s gagne le trait « Tueur de monstres » : les créatures n'ont qu'à bien se tenir." % String(h["name"]),
			Espionage.private_to(state, [int(h["owner"])])))


# --- Récits (cartes « guardian ») -----------------------------------------------------------------

## Effet « guardian » d'un choix de carte (Events.apply_fx).
static func card_fx(state: GameState, empire_id: int, item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(empire_id)
	var sid := int(item.get("system", -1))
	match String(fx["do"]):
		"tech":
			give_tech(state, empire_id, String(fx["tech"]))
		"ship":
			var cap := FactionTraits.capital_system(state, empire_id)
			if cap >= 0:
				var f := state.spawn_ship(empire_id, String(fx["ship"]), cap)
				f.fleet_name = String(GameData.ship(String(fx["ship"])).get("label", "Vaisseau unique"))
		"citadel_next":
			Events.push(state, empire_id, String(fx["card"]), {"system": sid}, added)
		"citadel_fail":
			var g: Dictionary = list(state).get("citadelle", {})
			if not g.is_empty() and String(g["status"]) != "awake":
				_spawn(state, "citadelle")
				added.append(state.add_chronicle("La Citadelle muette se rallume : mauvaise réponse. Ses plateformes se remettent en place, l'air vexé.", Espionage.private_to(state, [empire_id])))
		"citadel_win":
			give_tech(state, empire_id, "langue_muette")
			give_tech(state, empire_id, "reseau_citadelle")
		"hostile":
			var h: Dictionary = list(state).get("horloger", {})
			if not h.is_empty() and not (h["hostile"] as Array).has(empire_id):
				(h["hostile"] as Array).append(empire_id)
				for o in state.empires:
					o.path_cache.clear()
		"egg_study":
			var g2: Dictionary = list(state).get("oeuf_monde", {})
			if not g2.is_empty():
				g2["status"] = "studied"
				var pid := int(g2["planet"])
				var p := state.galaxy.get_planet(pid)
				var deps: Array = Array(p.deposits).duplicate()
				if not deps.has("crystals"):
					deps.append("crystals")
				state.override_planet(pid, {"deposits": deps})
				Events.give_research(state, empire_id, 100)
		"egg_leave":
			var g3: Dictionary = list(state).get("oeuf_monde", {})
			if not g3.is_empty():
				_destroy_colony(state, int(g3["planet"]))
				g3["egg_at"] = 0
		"egg_hatch":
			var g4: Dictionary = list(state).get("oeuf_monde", {})
			if not g4.is_empty() and String(g4["status"]) == "dormant":
				_destroy_colony(state, int(g4["planet"]))
				_spawn(state, "oeuf_monde")
				_wake_news(state, "oeuf_monde", "L'Œuf-monde éclot à %s. La colonie n'a pas eu le temps de finir ses valises ; ce qui en sort a faim." % state.galaxy.systems[int(g4["sid"])].system_name, added)
		"gates_open":
			var g5: Dictionary = list(state).get("portes", {})
			if not g5.is_empty() and String(g5["status"]) == "dormant":
				var gsid := int(g5["sid"])
				for pid in state.galaxy.systems[gsid].planet_ids:
					_destroy_colony(state, pid)
				_spawn(state, "portes")
				_wake_news(state, "portes", "Les Portes s'ouvrent à %s. Ce qui dormait dessous se lève, et le système n'est plus qu'un souvenir." % state.galaxy.systems[gsid].system_name, added)
				Events.push(state, empire_id, "gardien_pacte", {"system": gsid}, added)
		"pact":
			var g6: Dictionary = list(state).get("portes", {})
			if not g6.is_empty() and String(g6["status"]) == "awake":
				state.fleets.erase(int(g6["fleet"]))
				g6["fleet"] = -1
				g6["status"] = "pact"
				g6["by"] = empire_id
				give_tech(state, empire_id, "pacte_portes")
				for o in state.empires:
					o.path_cache.clear()
				added.append(state.add_chronicle("%s scelle un pacte avec ce qui dormait sous les Portes. La chose s'en va, satisfaite. Personne n'ose demander ce qu'elle a obtenu." % e.display_name(), Espionage.public_to(state, [empire_id])))
		"pact_refuse":
			pass


## Ce que la carte promet, en texte (Events.fx_lines).
static func fx_line(fx: Dictionary) -> String:
	match String(fx["do"]):
		"tech":
			return "Savoir ancien : %s" % String(tech_def(String(fx["tech"])).get("label", fx["tech"]))
		"ship":
			return "Vaisseau unique : %s" % String(GameData.ship(String(fx["ship"])).get("label", fx["ship"]))
		"citadel_next":
			return "La porte suivante s'ouvre"
		"citadel_fail":
			return "La Citadelle se rallume"
		"citadel_win":
			return "Deux savoirs anciens : Langue muette et Réseau de la Citadelle"
		"hostile":
			return "L'Horloger devient votre ennemi"
		"egg_study":
			return "La planète devient un monde fissuré (cristaux), +100 % d'une technologie"
		"egg_leave":
			return "La colonie est perdue, l'œuf se rendort"
		"egg_hatch":
			return "Si elle éclot : colonie détruite, un gardien se lève"
		"gates_open":
			return "Le système est ravagé ; la chose propose un pacte"
		"pact":
			return "Elle s'en va ; savoir ancien : Pacte des Portes"
		"pact_refuse":
			return "Elle reste, et il faudra l'abattre"
	return ""


## Fouilles : au dernier chapitre du site des Portes, la carte remplace la fin normale.
static func on_dig_finished(state: GameState, sid: int, empire_id: int, added: Array[Dictionary]) -> void:
	var g: Dictionary = list(state).get("portes", {}) if not state.fauna.is_empty() else {}
	if g.is_empty() or int(g["sid"]) != sid or String(g["status"]) != "dormant":
		return
	Events.push(state, empire_id, "gardien_portes", {"system": sid}, added)


static func _destroy_colony(state: GameState, pid: int) -> void:
	var c: Colony = state.colonies.get(pid)
	if c == null:
		return
	var e := state.get_empire(c.owner)
	if e != null and e.capital_planet == pid:
		c.population = 1
		return
	state.colonies.erase(pid)
	state.rebuild_ownership()


# --- Opération « Étouffer une étoile » --------------------------------------------------------------

static func choke(state: GameState, sid: int) -> void:
	if not state.fauna.has("choke"):
		state.fauna["choke"] = {}
	state.fauna["choke"][sid] = state.tick + int(data()["choke"]["days"])


# --- Sauvegarde -----------------------------------------------------------------------------------

static func choke_list(state: GameState) -> Array:
	var out := []
	var c: Dictionary = state.fauna.get("choke", {})
	var keys := c.keys()
	keys.sort()
	for k in keys:
		if int(c[k]) > state.tick:
			out.append([int(k), int(c[k])])
	return out


static func choke_from(state: GameState, l: Array) -> void:
	var c := {}
	for p: Array in l:
		c[int(p[0])] = int(p[1])
	state.fauna["choke"] = c


static func to_list(state: GameState) -> Array:
	var out := []
	for gid in ids(state):
		var g: Dictionary = list(state)[gid]
		var seen := []
		var sk: Array = (g["seen"] as Dictionary).keys()
		sk.sort()
		for k in sk:
			seen.append([int(k), int(g["seen"][k])])
		var vis := []
		var vk: Array = (g["visited"] as Dictionary).keys()
		vk.sort()
		for k in vk:
			vis.append([int(k), int(g["visited"][k])])
		var host: Array = (g["hostile"] as Array).duplicate()
		host.sort()
		out.append({"id": gid, "sid": int(g["sid"]), "home": int(g["home"]), "fleet": int(g["fleet"]), "status": String(g["status"]),
				"by": int(g["by"]), "seen": seen, "hostile": host, "wake": int(g["wake"]), "planet": int(g["planet"]),
				"egg_at": int(g["egg_at"]), "visited": vis, "next": int(g["next"]), "b_hp": int(g["b_hp"]), "b_foes": (g["b_foes"] as Array).duplicate()})
	return out


static func from_list(state: GameState, l: Array) -> void:
	var out := {}
	for x: Dictionary in l:
		var g := {"sid": int(x["sid"]), "home": int(x["home"]), "fleet": int(x["fleet"]), "status": String(x["status"]), "by": int(x["by"]),
				"seen": {}, "hostile": [], "wake": int(x["wake"]), "planet": int(x["planet"]), "egg_at": int(x["egg_at"]),
				"visited": {}, "next": int(x["next"]), "b_hp": int(x["b_hp"]), "b_foes": []}
		for p: Array in x.get("seen", []):
			g["seen"][int(p[0])] = int(p[1])
		for p: Array in x.get("visited", []):
			g["visited"][int(p[0])] = int(p[1])
		for v in x.get("hostile", []):
			(g["hostile"] as Array).append(int(v))
		for v in x.get("b_foes", []):
			(g["b_foes"] as Array).append(int(v))
		out[String(x["id"])] = g
	state.fauna["guardians"] = out
