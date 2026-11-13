class_name Plagues
extends RefCounted
## Fléaux errants (étude « Créatures spatiales et gardiens », lot 3, proposition 10 ; voir
## data/creatures.json, section "plagues"). 0 à 2 par partie selon la densité de créatures et la taille
## de la galaxie, pas avant l'an 15 : le Spectre des pulsars (affaibli de moitié dans les systèmes dont
## l'étoile a sa couleur) et la Grande Migration (un troupeau de Béliers devenu fou, quatre fois plus
## robuste). Un fléau est une flotte de la Faune qui va de colonie en colonie (jamais une capitale),
## y dévore de la population et la stabilité, puis repart ; au bout d'un an, s'il vit encore, il quitte
## la galaxie. Abattu à plusieurs, son Triomphe se partage selon les dégâts infligés.
## L'opération d'espionnage « Appât » attire un fléau (ou, à défaut, un troupeau hostile proche) sur
## les colonies d'un rival.
## État : state.fauna["plagues"] = {"plan": [[jour, sorte], ...], "list": {id: fléau}, "next": id}.
## Aucun aléatoire : les choix suivent un hachage de la graine, du fléau et du jour.


static func data() -> Dictionary:
	return GameData.creatures().get("plagues", {})


static func kind_def(kind: String) -> Dictionary:
	return (data().get("kinds", {}) as Dictionary).get(kind, {})


## Lecture seule : l'état n'existe que si la partie a prévu des fléaux (setup), pour que lire ne change
## jamais l'empreinte de la partie.
static func _root(state: GameState) -> Dictionary:
	return state.fauna.get("plagues", {}) if not state.fauna.is_empty() else {}


static func list(state: GameState) -> Dictionary:
	return _root(state).get("list", {})


static func ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in list(state):
		out.append(int(k))
	out.sort()
	return out


static func plan(state: GameState) -> Array:
	return _root(state).get("plan", [])


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "fleau"] + parts))


# --- Nouvelle partie --------------------------------------------------------------------------------

## Prévoit les fléaux de la partie (dates et sortes). on = réglage « Fléaux errants » de la Nouvelle partie.
static func setup(state: GameState, on: bool) -> void:
	if state.fauna.is_empty() or not on:
		return
	var d := data()
	var density := String(state.fauna.get("density", "aucune"))
	var n := int((d.get("count", {}) as Dictionary).get(density, 0))
	if n <= 0:
		return
	if density == "rares" and _h(state, ["rares"]) % 2 == 0:
		n = 0
	if n > 0 and state.galaxy.systems.size() >= int(d["big_galaxy"]):
		n += 1
	n = mini(n, 2)
	var kinds: Array = (d["kinds"] as Dictionary).keys()
	kinds.sort()
	if _h(state, ["ordre"]) % 2 == 1:
		kinds.reverse()
	var day := int(d["first_day"]) + _h(state, ["jour", 0]) % maxi(1, int(d["spread_days"]))
	state.fauna["plagues"] = {"plan": [], "list": {}, "next": 1}
	var root := _root(state)
	for i in n:
		(root["plan"] as Array).append([day, String(kinds[i % kinds.size()])])
		day += int(d["gap_days"]) + _h(state, ["jour", i + 1]) % maxi(1, int(d["spread_days"]))


# --- Questions --------------------------------------------------------------------------------------

## Identifiant du fléau de cette flotte (-1 sinon).
static func of_fleet(state: GameState, f: Fleet) -> int:
	if f == null or f.owner != GameState.FAUNA_ID or state.fauna.is_empty():
		return -1
	for pid in ids(state):
		var p: Dictionary = list(state)[pid]
		if String(p["status"]) == "alive" and int(p["fleet"]) == f.id:
			return pid
	return -1


## Fléaux en vie.
static func alive(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for pid in ids(state):
		if String(list(state)[pid]["status"]) == "alive":
			out.append(pid)
	return out


## Fléaux que l'empire a vus (vivants ou non).
static func known(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	for pid in ids(state):
		if (list(state)[pid]["seen"] as Dictionary).has(empire_id):
			out.append(pid)
	return out


static func fleet_of(state: GameState, pid: int) -> Fleet:
	var p: Dictionary = list(state).get(pid, {})
	if p.is_empty() or String(p["status"]) != "alive":
		return null
	return state.fleets.get(int(p["fleet"]))


## Bonus de dégâts (en %) d'une flotte de fléau dans ce système : le Spectre faiblit sous sa couleur.
static func damage_pct(state: GameState, f: Fleet, sid: int) -> int:
	if f.owner != GameState.FAUNA_ID:
		return 0
	var pid := of_fleet(state, f)
	if pid < 0:
		return 0
	var p: Dictionary = list(state)[pid]
	if String(p["star"]) != "" and state.galaxy.systems[sid].star_type == String(p["star"]):
		return int(kind_def(String(p["kind"])).get("weak_pct", 0))
	return 0


static func name_of(state: GameState, pid: int) -> String:
	return String(kind_def(String(list(state)[pid]["kind"])).get("name", "Fléau"))


# --- Chaque jour ------------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	var root := _root(state)
	if root.is_empty():
		return
	var pl: Array = root["plan"]
	while not pl.is_empty() and int(pl[0][0]) <= state.tick:
		var entry: Array = pl.pop_front()
		_spawn(state, String(entry[1]), added)
	for pid in alive(state):
		_day(state, pid, added)
	_sightings(state)


static func _spawn(state: GameState, kind: String, added: Array[Dictionary]) -> int:
	var kd := kind_def(kind)
	if kd.is_empty():
		return -1
	var sid := _birth_site(state, kind)
	if sid < 0:
		return -1
	var root := _root(state)
	var pid := int(root["next"])
	root["next"] = pid + 1
	var units: Array = kd["units"]
	var f := state.spawn_ship(GameState.FAUNA_ID, String(units[0][0]), sid)
	for i in units.size():
		for k in int(units[i][1]) - (1 if i == 0 else 0):
			f.add_ship(String(units[i][0]), -1, -1)
	f.troops = 0
	f.fleet_name = String(kd["name"])
	var star := ""
	if kd.has("weak_pct"):
		var colors := ["yellow", "red", "white", "blue_giant", "neutron"]
		star = String(colors[_h(state, ["couleur", pid]) % colors.size()])
	(root["list"] as Dictionary)[pid] = {"kind": kind, "fleet": f.id, "born": state.tick, "status": "alive", "by": -1,
			"star": star, "target": -1, "stay": 0, "last": [], "dmg": {}, "hp": f.total_hp(), "seen": {}, "eaten": 0, "bait": -1}
	for e in state.empires:
		e.path_cache.clear()
	var text := "Un fléau se lève : %s paraît à %s. Il ne colonise rien, il mange. Les colonies tremblent ; les capitales, elles, n'ont rien à craindre." % [
			String(kd["name"]), state.galaxy.systems[sid].system_name]
	if star != "":
		text += " Les astronomes notent qu'il porte la couleur des %s." % GalaxyGenerator.star_label(star).to_lower()
	added.append(state.add_chronicle(text))
	return pid


## Lieu de naissance : une étoile de son goût, sinon un système libre, loin des capitales.
static func _birth_site(state: GameState, kind: String) -> int:
	var kd := kind_def(kind)
	var stars: Array = kd.get("spawn_star", [])
	var near := {}
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap < 0:
			continue
		var j := FactionTraits.jumps_from(state.galaxy, cap)
		for k in j:
			near[int(k)] = mini(int(near.get(int(k), 99)), int(j[k]))
	var best := -1
	var best_score := -1
	for s in state.galaxy.systems:
		if state.system_owner(s.id) >= 0 or state.lairs.has(s.id) or int(near.get(s.id, 99)) < 4:
			continue
		var score := (1000000 if stars.has(s.star_type) else 0) + _h(state, ["naissance", kind, s.id]) % 1000000
		if kind == "migration" and Fauna.nests(state).has(s.id) and String(Fauna.nests(state)[s.id]["sp"]) == "beliers":
			score += 2000000
		if score > best_score:
			best = s.id
			best_score = score
	return best


static func _day(state: GameState, pid: int, added: Array[Dictionary]) -> void:
	var p: Dictionary = list(state)[pid]
	var f: Fleet = state.fleets.get(int(p["fleet"]))
	if f == null or f.ships.is_empty():
		return  # la fin de bataille s'en charge (on_battle)
	var here := f.system_id
	# Dégâts : la coque perdue pendant la bataille se répartit entre les empires présents, selon leur force.
	if state.battles.has(here) and not f.is_moving():
		var lost := int(p["hp"]) - f.total_hp()
		if lost > 0:
			var pw := {}
			var total := 0
			for o in Fleets.fleets_at(state, here):
				if GameState.is_npc(o.owner) or not Combat.is_armed(o):
					continue
				var v := Combat.fleet_power(o)
				pw[o.owner] = int(pw.get(o.owner, 0)) + v
				total += v
			if total > 0:
				var keys := pw.keys()
				keys.sort()
				for k in keys:
					@warning_ignore("integer_division")
					p["dmg"][int(k)] = int(p["dmg"].get(int(k), 0)) + lost * int(pw[k]) / total
	p["hp"] = f.total_hp()
	if f.is_moving() or state.battles.has(here):
		return
	var d := data()
	if state.tick >= int(p["born"]) + int(d["life_days"]):
		state.fleets.erase(f.id)
		p["status"] = "gone"
		for e in state.empires:
			e.path_cache.clear()
		added.append(state.add_chronicle("%s quitte la galaxie, repu. Il laisse %d colonie%s ravagée%s et personne pour se vanter de l'avoir chassé." % [
				name_of(state, pid), int(p["eaten"]), "s" if int(p["eaten"]) > 1 else "", "s" if int(p["eaten"]) > 1 else ""]))
		return
	var target := int(p["target"])
	if target == here and target >= 0:
		if int(p["stay"]) == 0:
			if eat(state, here, int(d["eat_pop"]), int(d["eat_stab"]), int(d["eat_stab_days"]), name_of(state, pid), added):
				p["eaten"] = int(p["eaten"]) + 1
			p["stay"] = state.tick + int(d["stay_days"])
			var last: Array = p["last"]
			last.append(here)
			while last.size() > 4:
				last.pop_front()
			return
		if state.tick < int(p["stay"]):
			return
	p["stay"] = 0
	p["target"] = _next_target(state, pid, f)
	if int(p["target"]) >= 0 and int(p["target"]) != here:
		if not _go(state, f, int(p["target"])):
			p["target"] = -1


static func _go(state: GameState, f: Fleet, to: int) -> bool:
	var route := Fleets.plan_route(state, f, to)
	if route.is_empty():
		return false
	f.system_id = int(route["system"])
	f.path.assign(route["path"])
	f.progress = int(route["progress"])
	return true


## Prochaine proie : la colonie la plus proche (hors capitale) que le fléau n'a pas visitée récemment,
## celles de l'empire visé par un Appât d'abord.
static func _next_target(state: GameState, pid: int, f: Fleet) -> int:
	var p: Dictionary = list(state)[pid]
	var jumps := FactionTraits.jumps_from(state.galaxy, f.system_id)
	var bait := int(p["bait"])
	var best := -1
	var best_score := 1 << 40
	for sid in _prey_systems(state):
		if (p["last"] as Array).has(sid):
			continue
		var owner := state.system_owner(sid)
		var j := int(jumps.get(sid, 999))
		if j >= 999:
			continue
		var score := j * 1000 + _h(state, ["proie", pid, sid, int(p["eaten"])]) % 1000
		if bait >= 0 and owner != bait:
			score += 100000
		if score < best_score:
			best = sid
			best_score = score
	if bait >= 0 and (best < 0 or state.system_owner(best) != bait):
		p["bait"] = -1
	return best


## Systèmes où se trouve une colonie d'empire, sans capitale.
static func _prey_systems(state: GameState) -> Array[int]:
	var caps := {}
	for e in state.empires:
		if not e.eliminated and e.capital_planet >= 0:
			caps[state.galaxy.get_planet(e.capital_planet).system_id] = true
	var seen := {}
	var out: Array[int] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if GameState.is_npc(c.owner):
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if caps.has(sid) or seen.has(sid):
			continue
		seen[sid] = true
		out.append(sid)
	out.sort()
	return out


## Le fléau (ou un troupeau appâté) dévore un système : chaque colonie (jamais une capitale) perd de la
## population, et disparaît si elle n'en a plus ; la stabilité du système chute. Vrai si quelque chose
## a été mangé.
static func eat(state: GameState, sid: int, pop: int, stab: int, stab_days: int, who: String, added: Array[Dictionary]) -> bool:
	var victims := {}
	var gone := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or GameState.is_npc(c.owner):
			continue
		var e := state.get_empire(c.owner)
		if e != null and e.capital_planet == pid:
			continue
		victims[c.owner] = true
		if c.population > pop:
			c.population -= pop
		else:
			state.colonies.erase(pid)
			gone += 1
	if victims.is_empty():
		return false
	if gone > 0:
		state.rebuild_ownership()
	var owners := victims.keys()
	owners.sort()
	for o in owners:
		if Stability.applies(state, int(o)):
			var en := Stability._entry_w(state, sid)
			en["ev"] = stab
			en["ev_end"] = state.tick + stab_days
			en["ev_card"] = "fleau"
	added.append(state.add_chronicle("%s s'abat sur %s : %s. Les survivants comptent les absents." % [
			who, state.galaxy.systems[sid].system_name,
			("%d colonie%s rayée%s de la carte" % [gone, "s" if gone > 1 else "", "s" if gone > 1 else ""]) if gone > 0 else "la population fond"],
			Espionage.public_to(state, owners)))
	return true


## Les empires qui voient un fléau l'inscrivent au Bestiaire.
static func _sightings(state: GameState) -> void:
	if state.seen_tick != state.tick or state.seen_cache.size() < state.empires.size():
		return
	for pid in alive(state):
		var p: Dictionary = list(state)[pid]
		var f: Fleet = state.fleets.get(int(p["fleet"]))
		if f == null:
			continue
		for e in state.empires:
			if not e.eliminated and not (p["seen"] as Dictionary).has(e.id) and (state.seen_cache[e.id] as Dictionary).has(f.system_id):
				p["seen"][e.id] = state.tick


# --- Fin de bataille --------------------------------------------------------------------------------

## Un fléau abattu : Triomphe partagé selon les dégâts, trophée pour le premier.
static func on_battle(state: GameState, b: Dictionary, winner: int, added: Array[Dictionary]) -> void:
	if state.fauna.is_empty():
		return
	for pid in alive(state):
		var p: Dictionary = list(state)[pid]
		var f: Fleet = state.fleets.get(int(p["fleet"]))
		if f != null and not f.ships.is_empty():
			continue
		# Les derniers coups de la bataille comptent aussi.
		if f != null:
			var lost := int(p["hp"])
			if lost > 0 and winner >= 0 and not GameState.is_npc(winner):
				p["dmg"][winner] = int(p["dmg"].get(winner, 0)) + lost
			state.fleets.erase(f.id)
		p["status"] = "dead"
		p["hp"] = 0
		for e in state.empires:
			e.path_cache.clear()
		_reward(state, pid, winner, int(b.get("system", -1)), added)


static func shares(state: GameState, pid: int) -> Array:
	var p: Dictionary = list(state)[pid]
	var dmg: Dictionary = p["dmg"]
	var total := 0
	for k in dmg:
		total += int(dmg[k])
	var out: Array = []
	if total <= 0:
		return out
	for k in dmg:
		@warning_ignore("integer_division")
		out.append([-int(dmg[k]) * 100 / total, int(k)])
	out.sort()
	return out.map(func(x: Array) -> Array: return [int(x[1]), -int(x[0])])


static func _reward(state: GameState, pid: int, winner: int, sid: int, added: Array[Dictionary]) -> void:
	var p: Dictionary = list(state)[pid]
	var sh := shares(state, pid)
	if sh.is_empty() and winner >= 0 and not GameState.is_npc(winner):
		sh = [[winner, 100]]
	if sh.is_empty():
		return
	var t: Dictionary = data()["triumph"]
	var names: Array = []
	var first := true
	for s: Array in sh:
		var eid := int(s[0])
		var pct := int(s[1])
		if pct < int(t["min_share"]) and not first:
			continue
		var e := state.get_empire(eid)
		if e == null or e.eliminated:
			continue
		var item := {"id": -1, "card": "", "system": sid, "planet": -1, "rival": -1, "hero": -1}
		@warning_ignore("integer_division")
		var tri := Guardians.triumph_scale(state, eid, maxi(3, int(t["stab"]) * pct / 100), int(t["influence"]) * pct / 100)
		var stab := int(tri[0])
		var infl := int(tri[1])
		Events.apply_fx(state, eid, item, [{"k": "stab", "v": stab, "days": int(t["days"]), "scope": "capital"},
				{"k": "res", "res": {"influence": infl}}], added)
		var part := "%s (%d %%)" % [e.short_name(), pct]
		if first:
			p["by"] = eid
			var trophy := String(kind_def(String(p["kind"])).get("trophy", ""))
			if trophy != "":
				part += ", trophée : %s" % Quests.give_relic(state, eid, trophy)
			Heroes.act(state, eid, "guardian")
			if not state.heroes.is_empty() and sid >= 0:
				for f in Fleets.fleets_at(state, sid, eid):
					var adm := Heroes.assigned_to(state, "fleet", f.id, eid)
					if not adm.is_empty():
						Guardians.monster_slayer(state, adm, added)
			first = false
		Research.count_stat(state, eid, "plagues")
		names.append(part)
	added.append(state.add_chronicle("Triomphe ! %s tombe enfin%s. Le partage de la gloire : %s." % [
			name_of(state, pid), (" à %s" % state.galaxy.systems[sid].system_name) if sid >= 0 else "", ", ".join(names)]))


# --- Appât (espionnage) ----------------------------------------------------------------------------

## Ce que l'Appât attirerait sur l'empire visé : [« plague », id] ou [« herd », flotte], [] sinon.
static func bait_pick(state: GameState, victim: int) -> Array:
	if state.fauna.is_empty():
		return []
	var al := alive(state)
	if not al.is_empty():
		return ["plague", al[0]]
	var mine: Array[int] = []
	for sid in _prey_systems(state):
		if state.system_owner(sid) == victim:
			mine.append(sid)
	if mine.is_empty():
		return []
	var best := -1
	var best_j := 6
	for fid in Fauna.herd_ids(state):
		var g: Fleet = state.fleets.get(fid)
		var h: Dictionary = Fauna.herds(state)[fid]
		if g == null or g.is_moving() or int(h.get("bait", -1)) >= 0 or Fauna.temper(String(h["sp"])) == "passive":
			continue
		var j := FactionTraits.jumps_from(state.galaxy, g.system_id)
		for sid in mine:
			if int(j.get(sid, 99)) < best_j:
				best_j = int(j.get(sid, 99))
				best = fid
	return ["herd", best] if best >= 0 else []


## Lance l'Appât : le fléau change de proie, ou le troupeau part vers la colonie la plus proche du rival.
## Renvoie le texte du compte rendu ("" si rien n'a mordu).
static func bait(state: GameState, victim: int) -> String:
	var pick := bait_pick(state, victim)
	if pick.is_empty():
		return ""
	if String(pick[0]) == "plague":
		var pid := int(pick[1])
		var p: Dictionary = list(state)[pid]
		p["bait"] = victim
		p["stay"] = 0
		var f := fleet_of(state, pid)
		if f != null and not f.is_moving() and not state.battles.has(f.system_id):
			p["target"] = _next_target(state, pid, f)
			if int(p["target"]) >= 0:
				_go(state, f, int(p["target"]))
		return "%s change de route : il flaire les colonies de %s." % [name_of(state, pid), state.get_empire(victim).short_name()]
	var fid := int(pick[1])
	var g: Fleet = state.fleets[fid]
	var jumps := FactionTraits.jumps_from(state.galaxy, g.system_id)
	var to := -1
	var to_j := 99
	for sid in _prey_systems(state):
		if state.system_owner(sid) == victim and int(jumps.get(sid, 99)) < to_j:
			to = sid
			to_j = int(jumps.get(sid, 99))
	if to < 0 or not _go(state, g, to):
		return ""
	Fauna.herds(state)[fid]["bait"] = to
	return "Un %s affamé quitte son pâturage, cap sur %s." % [String(g.fleet_name).to_lower(), state.galaxy.systems[to].system_name]


## Un troupeau appâté arrivé à destination : il se sert, puis rentre (FaunaSystem).
static func herd_bait_arrived(state: GameState, fid: int, added: Array[Dictionary]) -> void:
	var h: Dictionary = Fauna.herds(state)[fid]
	var sid := int(h["bait"])
	h["bait"] = -1
	var g: Fleet = state.fleets[fid]
	eat(state, sid, 1, -10, 180, String(g.fleet_name), added)
	h["next"] = state.tick + 10


# --- Sauvegarde -------------------------------------------------------------------------------------

static func to_dict(state: GameState) -> Dictionary:
	var root: Dictionary = state.fauna.get("plagues", {})
	if root.is_empty():
		return {}
	var out := {"plan": [], "list": [], "next": int(root["next"])}
	for e: Array in root["plan"]:
		out["plan"].append([int(e[0]), String(e[1])])
	for pid in ids(state):
		var p: Dictionary = list(state)[pid]
		out["list"].append({"id": pid, "kind": String(p["kind"]), "fleet": int(p["fleet"]), "born": int(p["born"]), "status": String(p["status"]),
				"by": int(p["by"]), "star": String(p["star"]), "target": int(p["target"]), "stay": int(p["stay"]),
				"last": (p["last"] as Array).duplicate(), "dmg": _pairs(p["dmg"]), "hp": int(p["hp"]), "seen": _pairs(p["seen"]),
				"eaten": int(p["eaten"]), "bait": int(p["bait"])})
	return out


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.fauna.erase("plagues")
		return
	var root := {"plan": [], "list": {}, "next": int(d.get("next", 1))}
	for e: Array in d.get("plan", []):
		root["plan"].append([int(e[0]), String(e[1])])
	for x: Dictionary in d.get("list", []):
		var last: Array = []
		for v in x.get("last", []):
			last.append(int(v))
		root["list"][int(x["id"])] = {"kind": String(x["kind"]), "fleet": int(x["fleet"]), "born": int(x["born"]), "status": String(x["status"]),
				"by": int(x["by"]), "star": String(x["star"]), "target": int(x["target"]), "stay": int(x["stay"]), "last": last,
				"dmg": _unpairs(x.get("dmg", [])), "hp": int(x["hp"]), "seen": _unpairs(x.get("seen", [])),
				"eaten": int(x["eaten"]), "bait": int(x["bait"])}
	state.fauna["plagues"] = root


static func _pairs(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys.map(func(k: Variant) -> Array: return [int(k), int(d[k])])


static func _unpairs(a: Array) -> Dictionary:
	var out := {}
	for p: Array in a:
		out[int(p[0])] = int(p[1])
	return out
