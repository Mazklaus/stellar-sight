class_name Ancients
extends RefCounted
## Puissances anciennes endormies (étude « Puissances anciennes endormies », 2026-11-15 ; data/ancients.json).
## De vieux empires figés, immensément forts, qui dorment dans une poche de 3 à 5 systèmes : chacune est
## une puissance neutre à identifiant réservé (GameState.ANCIENT_BASE + rang), hors de la liste des
## empires. Elles ne colonisent pas et ne construisent pas tant qu'elles dorment ; elles ont une opinion
## de chaque empire rencontré, envoient des requêtes, des missions, des cadeaux et, sous -100, des
## ultimatums (refusés : guerre de Punition). Chacun peut leur verser des contributions ; tous les cinq
## ans, les deux plus gros contributeurs reçoivent leurs postes honorifiques (Endless Space 2, l'Académie).
## L'Éveil, la décadence, la Guerre au ciel et les Gardiennes de la galaxie sont dans AncientsWake (lot 2) ;
## les ponts (guerre sainte, reliques, coffres, talents, Rejeton) dans AncientsBridges (lot 3).
##
## État : state.ancients = {} (aucune) ou {"mode", "wake": bool, "list": {id: ancienne}, "holy": {planète: id},
##  "worlds": {planète: {"a": id, "b": bâtiment}}, "boons": {empire: [{"label", "fx", "until"}]}}.
## ancienne = {"kind", "home", "systems": [poche], "stage" ("sleep" | lot 2), "power", "fleets": [ids],
##  "op": {empire: opinion}, "base": {empire: opinion de départ}, "contact": {empire: jour}, "req": {empire: jour},
##  "mis_next": {empire: jour}, "mission": {empire: {...}}, "dem_cd": {empire: jour}, "war": {empire: {...}},
##  "contrib": {empire: points}, "posts": {poste: empire}, "term": jour, "yes": {empire: 1}, "siege": {système: jours},
##  "lent": [{"e", "ship", "until", "why"}], "heroes": {héros: {"e", "until"}}, "reinf": jour, "angry": {empire: jour}}.

const STAGE_SLEEP := "sleep"


static func data() -> Dictionary:
	return GameData.ancients()


static func kind_def(kind: String) -> Dictionary:
	return (data().get("kinds", {}) as Dictionary).get(kind, {})


static func kind_ids() -> Array[String]:
	var out: Array[String] = []
	for k in data().get("kinds", {}):
		out.append(String(k))
	out.sort()
	return out


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "normal"))


static func _find(list: Array, id: String) -> Dictionary:
	for d: Dictionary in list:
		if String(d["id"]) == id:
			return d
	return {}


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "ancienne"] + parts))


# --- Lecture ----------------------------------------------------------------------------------------

static func enabled(state: GameState) -> bool:
	return not state.ancients.is_empty() and not (state.ancients.get("list", {}) as Dictionary).is_empty()


static func get_a(state: GameState, id: int) -> Dictionary:
	if state.ancients.is_empty():
		return {}
	return (state.ancients.get("list", {}) as Dictionary).get(id, {})


static func ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if state.ancients.is_empty():
		return out
	for k in state.ancients.get("list", {}):
		out.append(int(k))
	out.sort()
	return out


static func kind_of(state: GameState, id: int) -> String:
	return String(get_a(state, id).get("kind", ""))


static func name_of(state: GameState, id: int) -> String:
	return String(kind_def(kind_of(state, id)).get("name", "Une ancienne"))


static func short_of(state: GameState, id: int) -> String:
	return String(kind_def(kind_of(state, id)).get("short", "Ancienne"))


## L'ancienne de cette sorte en jeu (-1 sinon).
static func id_of_kind(state: GameState, kind: String) -> int:
	for id in ids(state):
		if kind_of(state, id) == kind:
			return id
	return -1


static func stage(state: GameState, id: int) -> String:
	return String(get_a(state, id).get("stage", STAGE_SLEEP))


static func asleep(state: GameState, id: int) -> bool:
	return stage(state, id) == STAGE_SLEEP


static func no_opinion(state: GameState, id: int) -> bool:
	return bool(kind_def(kind_of(state, id)).get("no_opinion", false))


static func in_contact(state: GameState, id: int, eid: int) -> bool:
	return (get_a(state, id).get("contact", {}) as Dictionary).has(eid)


## Anciennes rencontrées par un empire.
static func met(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for id in ids(state):
		if in_contact(state, id, eid):
			out.append(id)
	return out


static func opinion(state: GameState, id: int, eid: int) -> int:
	return int((get_a(state, id).get("op", {}) as Dictionary).get(eid, 0))


static func attitude(state: GameState, id: int, eid: int) -> Dictionary:
	var op := opinion(state, id, eid)
	for at: Dictionary in data().get("attitudes", []):
		if op < int(at["below"]):
			return at
	return {}


## Systèmes tenus par l'ancienne (sa poche, et ce qu'elle a pris).
static func systems_of(state: GameState, id: int) -> Array[int]:
	var out: Array[int] = []
	var seen := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != id:
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if not seen.has(sid):
			seen[sid] = true
			out.append(sid)
	out.sort()
	return out


static func fleets_of(state: GameState, id: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for fid in get_a(state, id).get("fleets", []):
		var f: Fleet = state.fleets.get(int(fid))
		if f != null and not f.ships.is_empty():
			out.append(f)
	return out


static func total_power(state: GameState, id: int) -> int:
	var p := 0
	for f in fleets_of(state, id):
		p += Combat.fleet_power(f)
	return p


static func empire_power(state: GameState, eid: int) -> int:
	var p := 0
	for f in Fleets.empire_fleets(state, eid):
		if Combat.is_armed(f):
			p += Combat.fleet_power(f)
	return p


## Rapport de force en phrases (prop. 6), du point de vue de l'empire.
static func force_text(state: GameState, id: int, eid: int) -> String:
	var mine := float(empire_power(state, eid))
	var theirs := float(maxi(1, total_power(state, id)))
	var r := mine / theirs
	for fw: Array in data().get("force_words", []):
		if r < float(fw[0]):
			return String(fw[1])
	return ""


static func at_war_with(state: GameState, id: int, eid: int) -> bool:
	return (get_a(state, id).get("war", {}) as Dictionary).has(eid)


## Hostilité (Combat.at_war) quand l'un des deux est une ancienne.
static func at_war(state: GameState, a: int, b: int) -> bool:
	if GameState.is_ancient(a) and GameState.is_ancient(b):
		return AncientsWake.heaven_pair(state, a, b)
	var anc := a if GameState.is_ancient(a) else b
	var other := b if anc == a else a
	if get_a(state, anc).is_empty():
		return false
	if other == GameState.FAUNA_ID or GameState.is_minor(other):
		return false
	if GameState.is_npc(other):
		return true  # pirates, crise, Sans-Bannière
	return at_war_with(state, anc, other) or AncientsWake.hostile(state, anc, other)


## Nombre de systèmes tenus par des anciennes endormies (hors du total de la domination).
static func sleeping_systems(state: GameState) -> int:
	var n := 0
	for id in ids(state):
		if asleep(state, id):
			n += systems_of(state, id).size()
	return n


static func is_ancient_system(state: GameState, sid: int) -> bool:
	return GameState.is_ancient(state.system_owner(sid))


static func holy_owner(state: GameState, pid: int) -> int:
	if state.ancients.is_empty():
		return -1
	return int((state.ancients.get("holy", {}) as Dictionary).get(pid, -1))


static func world_of(state: GameState, pid: int) -> Dictionary:
	if state.ancients.is_empty():
		return {}
	return (state.ancients.get("worlds", {}) as Dictionary).get(pid, {})


static func building_def(bid: String) -> Dictionary:
	return (data().get("buildings", {}) as Dictionary).get(bid, {})


# --- Mise en place (prop. 1-5) ----------------------------------------------------------------------

static func wanted_count(state: GameState, mode: String) -> int:
	var md := _find(mode_defs(), mode)
	if md.is_empty() or int(md.get("delta", 0)) <= -99:
		return 0
	var c: Dictionary = data()["count"]
	var n := state.galaxy.systems.size()
	@warning_ignore("integer_division")
	var base := clampi((n + int(c["per_systems"]) / 2) / int(c["per_systems"]), int(c["min"]), 4)
	return clampi(base + int(md.get("delta", 0)), int(c["min"]), mini(int(c["max"]), GameState.ANCIENT_MAX))


static func setup(state: GameState, mode: String, wake := true) -> void:
	state.ancients = {}
	var want := wanted_count(state, mode)
	if want <= 0:
		return
	state.ancients = {"mode": mode, "wake": wake, "list": {}, "holy": {}, "worlds": {}, "boons": {}}
	var starts: Array = []
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cap))
	var order: Array = []
	for k in kind_ids():
		order.append([_h(state, ["ordre", k]), k])
	order.sort()
	var homes: Array[int] = []
	for o in order:
		if ids(state).size() >= want:
			break
		var k := String(o[1])
		var pocket := _pick_pocket(state, k, starts, homes)
		if pocket.is_empty():
			continue
		homes.append(pocket[0])
		create(state, k, pocket)
	if ids(state).is_empty():
		state.ancients = {}
		return
	for e in state.empires:
		e.path_cache.clear()


## Poche : [capitale, voisins…] ; [] s'il n'y a pas la place.
static func _pick_pocket(state: GameState, k: String, starts: Array, homes: Array[int]) -> Array[int]:
	var pl: Dictionary = data()["place"]
	var min_j := int(pl["min_jumps"])
	var cands: Array = []
	for s in state.galaxy.systems:
		if s.planet_ids.size() < 2 or not _free(state, s.id):
			continue
		if _near_start(starts, s.id) < min_j:
			continue
		var close := false
		for hsid in homes:
			if int(FactionTraits.jumps_from(state.galaxy, hsid).get(s.id, 999)) < int(pl["apart"]):
				close = true
				break
		if close:
			continue
		cands.append([-s.planet_ids.size() * 1000 + _h(state, ["site", k, s.id]) % 1000, s.id])
	if cands.is_empty():
		return []
	cands.sort()
	var span: Array = pl["pocket"]
	var size := int(span[0]) + _h(state, ["taille", k]) % (int(span[1]) - int(span[0]) + 1)
	for cand in cands.slice(0, 12):
		var home := int(cand[1])
		var pocket: Array[int] = [home]
		var frontier: Array[int] = [home]
		while pocket.size() < size and not frontier.is_empty():
			var cur: int = frontier.pop_front()
			var ns: Array = state.galaxy.systems[cur].neighbors.duplicate()
			ns.sort()
			for n in ns:
				if pocket.size() >= size:
					break
				var nid := int(n)
				if pocket.has(nid) or not _free(state, nid) or _near_start(starts, nid) < min_j - 1:
					continue
				pocket.append(nid)
				frontier.append(nid)
		if pocket.size() >= int(span[0]):
			return pocket
	return []


static func _near_start(starts: Array, sid: int) -> int:
	var near := 999
	for dj: Dictionary in starts:
		near = mini(near, int(dj.get(sid, 999)))
	return near


static func _free(state: GameState, sid: int) -> bool:
	if state.system_owner(sid) >= 0 or state.lairs.has(sid) or state.digs.has(sid):
		return false
	if Fauna.active(state) and Fauna.nests(state).has(sid):
		return false
	for gid in Guardians.ids(state):
		if int((Guardians.list(state)[gid] as Dictionary).get("sid", -1)) == sid:
			return false
	for id in ids(state):
		if (get_a(state, id).get("systems", []) as Array).has(sid):
			return false
	return true


## Crée l'ancienne k sur cette poche : mondes achevés, bâtiments uniques, flottes, Mondes saints.
static func create(state: GameState, k: String, pocket: Array[int]) -> int:
	var id := GameState.ANCIENT_BASE
	while not get_a(state, id).is_empty():
		id += 1
	if id >= GameState.ANCIENT_BASE + GameState.ANCIENT_MAX:
		return -1
	var kd := kind_def(k)
	var a := {"kind": k, "home": pocket[0], "systems": Array(pocket), "stage": STAGE_SLEEP, "power": 0, "fleets": [],
			"op": {}, "base": {}, "contact": {}, "req": {}, "mis_next": {}, "mission": {}, "dem_cd": {}, "war": {},
			"contrib": {}, "posts": {}, "term": state.tick + int(data()["contrib"]["term_days"]), "yes": {}, "siege": {},
			"lent": [], "heroes": {}, "reinf": 0, "angry": {}}
	(state.ancients["list"] as Dictionary)[id] = a
	# Mondes achevés (prop. 4) : chaque planète de la poche est à elle.
	var homeworld := -1
	for sid in pocket:
		for pid in state.galaxy.systems[sid].planet_ids:
			if state.colonies.has(pid):
				continue
			var c := Colony.new()
			c.planet_id = pid
			c.owner = id
			c.kind = Colony.KIND_COLONY
			c.population = 14 if sid == pocket[0] else 6
			state.colonies[pid] = c
			if sid == pocket[0] and (homeworld < 0 or state.galaxy.get_planet(pid).size > state.galaxy.get_planet(homeworld).size):
				homeworld = pid
	state.rebuild_ownership()
	var blds: Array = kd.get("buildings", [])
	if homeworld >= 0 and not blds.is_empty():
		(state.ancients["worlds"] as Dictionary)[homeworld] = {"a": id, "b": String(blds[0])}
		var second := -1
		for sid in pocket.slice(1):
			for pid in state.galaxy.systems[sid].planet_ids:
				if (state.colonies.get(pid) as Colony) != null and state.colonies[pid].owner == id:
					if second < 0 or state.galaxy.get_planet(pid).size > state.galaxy.get_planet(second).size:
						second = pid
		if second >= 0 and blds.size() > 1:
			(state.ancients["worlds"] as Dictionary)[second] = {"a": id, "b": String(blds[1])}
	# Flottes (prop. 3).
	var pw := sleep_power(state)
	a["power"] = pw
	var cfg: Dictionary = data()["power"]
	var n := maxi(1, int(cfg["fleets"]))
	@warning_ignore("integer_division")
	var home_f := spawn_fleet(state, id, pocket[0], pw * int(cfg["home_pct"]) / 100, true)
	home_f.fleet_name = "Garde de %s" % String(kd.get("home_name", "la capitale"))
	for i in n:
		var sid: int = pocket[mini(i + 1, pocket.size() - 1)]
		@warning_ignore("integer_division")
		spawn_fleet(state, id, sid, pw / n, false)
	a["reinf"] = state.tick + int(cfg["reinf_days"])
	for sid in pocket:
		state.garrisons[sid] = Combat.garrison_max(state, sid)
	# Mondes saints (Hiérophantes) : planètes libres et superbes autour de la poche.
	var hw: Array = kd.get("holy_worlds", [])
	if not hw.is_empty():
		_holy_worlds(state, id, pocket, int(hw[0]) + _h(state, ["saints", k]) % (int(hw[1]) - int(hw[0]) + 1))
	return id


static func _holy_worlds(state: GameState, id: int, pocket: Array[int], want: int) -> void:
	var jumps := FactionTraits.jumps_from(state.galaxy, pocket[0])
	var cands: Array = []
	for s in state.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j < 1 or j > 4 or pocket.has(s.id) or state.system_owner(s.id) >= 0:
			continue
		for pid in s.planet_ids:
			if holy_owner(state, pid) < 0:
				cands.append([j * 1000 + _h(state, ["saint", pid]) % 1000, pid])
	cands.sort()
	var used_sys := {}
	var n := 0
	for cand in cands:
		if n >= want:
			break
		var pid := int(cand[1])
		var sid := state.galaxy.get_planet(pid).system_id
		if used_sys.has(sid):
			continue
		used_sys[sid] = true
		(state.ancients["holy"] as Dictionary)[pid] = id
		n += 1


## Puissance totale d'une ancienne endormie : la flotte de départ militaire d'un empire × sleep_x.
static func sleep_power(state: GameState) -> int:
	var cfg: Dictionary = data()["power"]
	var ref := 0
	if not state.empires.is_empty():
		for ship_id in FactionTraits.start_ships(state.empires[0].faction_id):
			if bool(GameData.ship(String(ship_id)).get("military", false)):
				ref += Combat.ship_strength(String(ship_id))
	return maxi(int(cfg["min"]), ref * int(cfg["sleep_x"]))


## Une flotte de l'ancienne (unités de ligne, avec le vaisseau amiral si flag) jusqu'à la puissance voulue.
static func spawn_fleet(state: GameState, id: int, sid: int, power: int, flag: bool) -> Fleet:
	var kd := kind_def(kind_of(state, id))
	var units: Dictionary = kd.get("units", {})
	var line := String(units.get("line", ""))
	var f := state.spawn_ship(id, String(units.get("flag", line)) if flag else line, sid)
	var guard := 0
	while Combat.fleet_power(f) < power and guard < 200:
		guard += 1
		f.add_ship(line, -1, -1)
	f.troops = 0
	var a := get_a(state, id)
	a["fn"] = int(a.get("fn", 0)) + 1
	f.fleet_name = "%s %s" % [String(kd.get("fleet_name", "Flotte")), GameState.ROMAN[mini(int(a["fn"]), GameState.ROMAN.size() - 1)]]
	(a["fleets"] as Array).append(f.id)
	return f


# --- Chaque jour ------------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not enabled(state):
		return added
	if state.tick % 30 == 0:
		_expire_boons(state)
		AncientsBridges.monthly(state, added)
	for id in ids(state):
		var a := get_a(state, id)
		if (state.tick + id) % 30 == 0:
			_month(state, id, a, added)
		AncientsWake.daily(state, id, a, added)
		if not (a["war"] as Dictionary).is_empty() or AncientsWake.marching(state, id):
			_war_day(state, id, a, added)
	return added


static func _month(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	_prune(state, a)
	_contacts(state, id, a, added)
	_angers(state, id, a, added)
	if asleep(state, id):
		_requests(state, id, a, added)
		_missions(state, id, a, added)
		_demands(state, id, a, added)
		_gifts(state, id, a, added)
		_reinforce(state, id, a, added)
	_posts(state, id, a, added)
	_lent(state, id, a, added)
	_war_end(state, id, a, added)


static func _prune(state: GameState, a: Dictionary) -> void:
	var keep: Array = []
	for fid in a["fleets"]:
		var f: Fleet = state.fleets.get(int(fid))
		if f != null and not f.ships.is_empty():
			keep.append(int(fid))
	a["fleets"] = keep


static func _contacts(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var mine := systems_of(state, id)
	for e in state.empires:
		if e.eliminated or (a["contact"] as Dictionary).has(e.id):
			continue
		var seen := false
		for sid in mine:
			if e.explored.has(sid):
				seen = true
				break
		if seen:
			meet(state, id, e.id, added)


## Premier contact : opinion de départ, fenêtre d'événement, calendrier des requêtes.
static func meet(state: GameState, id: int, eid: int, added: Array[Dictionary]) -> void:
	var a := get_a(state, id)
	if a.is_empty() or (a["contact"] as Dictionary).has(eid):
		return
	(a["contact"] as Dictionary)[eid] = state.tick
	var b := base_opinion(state, id, eid)
	(a["base"] as Dictionary)[eid] = b
	(a["op"] as Dictionary)[eid] = b
	var rq: Dictionary = data()["requests"]
	var ms: Dictionary = data()["missions"]
	(a["req"] as Dictionary)[eid] = state.tick + int(rq["first_days"]) + _h(state, ["req0", id, eid]) % 360
	(a["mis_next"] as Dictionary)[eid] = state.tick + int(ms["first_days"]) + _h(state, ["mis0", id, eid]) % 720
	var e := state.get_empire(eid)
	added.append(state.add_chronicle("%s rencontre %s. %s" % [e.display_name(), Crisis.obj_name(name_of(state, id)).trim_prefix(""),
			"Personne n'ose parler trop fort."], Espionage.private_to(state, [eid])))
	Events.push(state, eid, "anc_contact", {"anc": id, "system": int(a["home"])}, added)
	# Prop. 64 de l'arbre : chaque puissance ancienne rencontrée laisse une trouvaille.
	var fd := Research.grant_find(state, eid, "ancients")
	if fd != "":
		added.append(state.add_chronicle("Trouvaille : au contact de %s, %s comprend %s." % [Crisis.obj_name(name_of(state, id)), e.display_name(),
				String(Research.tech(fd).get("label", fd))], Espionage.private_to(state, [eid])))


## Opinion de départ : celle de la sorte, ses colères permanentes (peuple synthétique) et les talents.
static func base_opinion(state: GameState, id: int, eid: int) -> int:
	if no_opinion(state, id):
		return 0
	var kd := kind_def(kind_of(state, id))
	var v := int(kd.get("start_op", 0))
	if (kd.get("angers", []) as Array).has("synthetic") and Events.layer_value(state, eid, "archetype") == "synthetique":
		v -= 50
	v += AncientsBridges.talent_op(state, id, eid)
	return clampi(v, int(data()["opinion"]["min"]), int(data()["opinion"]["max"]))


static func add_op(state: GameState, id: int, eid: int, v: int) -> void:
	var a := get_a(state, id)
	if a.is_empty() or no_opinion(state, id) or not (a["contact"] as Dictionary).has(eid):
		return
	if v < 0 and WondersCatalog.fx(state, eid, "ancient_friend") > 0:
		return  # Miroir des Anciens : elles ne s'irritent plus
	var o: Dictionary = data()["opinion"]
	(a["op"] as Dictionary)[eid] = clampi(int((a["op"] as Dictionary).get(eid, 0)) + v, int(o["min"]), int(o["max"]))


# --- Colères (prop. 12) -----------------------------------------------------------------------------

static func _angers(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var o: Dictionary = data()["opinion"]
	var kd := kind_def(String(a["kind"]))
	var angers: Array = kd.get("angers", [])
	var mine := systems_of(state, id)
	var mine_set := {}
	for sid in mine:
		mine_set[sid] = true
	for eid in (a["contact"] as Dictionary).keys():
		var e := state.get_empire(int(eid))
		if e == null or e.eliminated:
			continue
		# Retour lent vers l'opinion de départ.
		var cur := opinion(state, id, int(eid))
		var base := int((a["base"] as Dictionary).get(eid, 0))
		var dr := int(o["drift_month"])
		if cur < base:
			(a["op"] as Dictionary)[eid] = mini(base, cur + dr)
		elif cur > base:
			(a["op"] as Dictionary)[eid] = maxi(base, cur - dr)
		var hit := 0
		if angers.has("intrusion"):
			var n := 0
			for sid in mine:
				for f in Fleets.fleets_at(state, sid, int(eid)):
					if Combat.is_armed(f) and not f.is_moving():
						n += 1
			hit += int(o["intrusion_month"]) * mini(3, n)
		if angers.has("neighbor"):
			var n2 := 0
			var seen := {}
			for sid in mine:
				for nb in state.galaxy.systems[sid].neighbors:
					if not mine_set.has(int(nb)) and not seen.has(int(nb)) and state.system_owner(int(nb)) == int(eid):
						seen[int(nb)] = true
						n2 += 1
			hit -= 20 * mini(2, n2)
		if angers.has("holy"):
			hit -= 40 * holy_held(state, id, int(eid)).size()
		if hit != 0:
			add_op(state, id, int(eid), hit)
			if not (a["angry"] as Dictionary).has(eid) or state.tick - int(a["angry"][eid]) >= 720:
				(a["angry"] as Dictionary)[eid] = state.tick
				added.append(state.add_chronicle("%s s'agace de %s (%s)." % [name_of(state, id), e.display_name(), String(kd.get("angers_text", "")).to_lower().trim_suffix(".")],
						Espionage.private_to(state, [int(eid)])))


## Mondes saints de l'ancienne colonisés par cet empire.
static func holy_held(state: GameState, id: int, eid: int) -> Array[int]:
	var out: Array[int] = []
	if state.ancients.is_empty():
		return out
	for pid in state.ancients.get("holy", {}):
		if int(state.ancients["holy"][pid]) != id:
			continue
		var c: Colony = state.colonies.get(int(pid))
		if c != null and c.owner == eid:
			out.append(int(pid))
	out.sort()
	return out


## Atrocité (Peoples) : les anciennes qui détestent l'extermination l'apprennent toutes.
static func on_atrocity(state: GameState, killer: int) -> void:
	if not enabled(state) or GameState.is_npc(killer):
		return
	for id in ids(state):
		if (kind_def(kind_of(state, id)).get("angers", []) as Array).has("atrocity"):
			add_op(state, id, killer, int(data()["opinion"]["atrocity"]))


# --- Requêtes, missions, ultimatums, cadeaux (prop. 7-10) -------------------------------------------

static func _requests(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var kd := kind_def(String(a["kind"]))
	var reqs: Array = kd.get("requests", [])
	if reqs.is_empty():
		return
	for eid in _contact_ids(a):
		if state.tick < int((a["req"] as Dictionary).get(eid, 0)) or at_war_with(state, id, eid):
			continue
		(a["req"] as Dictionary)[eid] = state.tick + int(data()["requests"]["every_days"]) + _h(state, ["req", id, eid, state.tick]) % 360
		if not AncientsBridges.hears(state, id, eid):
			continue
		var card := String(reqs[_h(state, ["quelle", id, eid, state.tick]) % reqs.size()])
		var subj := {"anc": id, "system": int(a["home"])}
		if (Events.card(card).get("subjects", {}) as Dictionary).has("hero"):
			var h := _lendable_hero(state, eid)
			if h < 0:
				card = String(reqs[0]) if String(reqs[0]) != card else String(reqs[-1])
			else:
				subj["hero"] = h
		if (Events.card(card).get("subjects", {}) as Dictionary).has("hero") and not subj.has("hero"):
			continue
		Events.push(state, eid, card, subj, added)


static func _contact_ids(a: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for k in (a["contact"] as Dictionary).keys():
		out.append(int(k))
	out.sort()
	return out


## Héros prêtable : le plus expérimenté qui n'est ni blessé, ni prisonnier, ni déjà prêté.
static func _lendable_hero(state: GameState, eid: int) -> int:
	var best := -1
	var best_l := -1
	var hids := state.heroes.keys()
	hids.sort()
	for hid in hids:
		var h: Dictionary = state.heroes[hid]
		if int(h["owner"]) != eid or Heroes.is_prisoner(h) or Heroes.is_wounded(state, h) or h.has("lent"):
			continue
		if int(h["lvl"]) > best_l:
			best_l = int(h["lvl"])
			best = int(hid)
	return best


static func _missions(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var kd := kind_def(String(a["kind"]))
	var md: Dictionary = kd.get("mission", {})
	var o: Dictionary = data()["opinion"]
	for eid in _contact_ids(a):
		var e := state.get_empire(eid)
		if e == null or e.eliminated:
			continue
		var m: Dictionary = (a["mission"] as Dictionary).get(eid, {})
		if not m.is_empty():
			var done := int(e.stats.get(String(m["stat"]), 0)) - int(m["base"])
			if done >= int(m["n"]):
				(a["mission"] as Dictionary).erase(eid)
				add_op(state, id, eid, int(o["mission_ok"]) * AncientsBridges.mission_mult(state, eid) / 100)
				(a["yes"] as Dictionary)[eid] = 1
				e.resources["influence"] = int(e.resources.get("influence", 0)) + 40
				added.append(state.add_chronicle("%s a rempli la mission de %s. L'ancienne hoche la tête : chez elle, c'est une ovation." % [
						e.display_name(), Crisis.de_name(name_of(state, id)).trim_prefix("de ").trim_prefix("du ")], Espionage.private_to(state, [eid])))
			elif state.tick > int(m["until"]):
				(a["mission"] as Dictionary).erase(eid)
				add_op(state, id, eid, int(o["mission_fail"]))
				added.append(state.add_chronicle("%s n'a pas rempli la mission confiée par %s. L'ancienne note, dans un registre qui ne s'efface pas." % [
						e.display_name(), name_of(state, id)], Espionage.private_to(state, [eid])))
			continue
		if md.is_empty() or state.tick < int((a["mis_next"] as Dictionary).get(eid, 0)) or at_war_with(state, id, eid):
			continue
		(a["mis_next"] as Dictionary)[eid] = state.tick + int(data()["missions"]["every_days"]) + _h(state, ["mis", id, eid, state.tick]) % 720
		if AncientsBridges.hears(state, id, eid):
			Events.push(state, eid, "anc_mission", {"anc": id, "system": int(a["home"])}, added)


static func _demands(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var card := String(kind_def(String(a["kind"])).get("demand", ""))
	if card == "" or no_opinion(state, id):
		return
	for eid in _contact_ids(a):
		if at_war_with(state, id, eid) or opinion(state, id, eid) > int(data()["opinion"]["demand_below"]):
			continue
		if state.tick < int((a["dem_cd"] as Dictionary).get(eid, 0)):
			continue
		(a["dem_cd"] as Dictionary)[eid] = state.tick + 1080
		Events.push(state, eid, card, {"anc": id, "system": int(a["home"])}, added)


static func _gifts(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var g: Dictionary = data()["gifts"]
	@warning_ignore("integer_division")
	if (state.tick / 30 + id) % maxi(1, int(g["check_days"]) / 30) != 0:
		return
	for eid in _contact_ids(a):
		if at_war_with(state, id, eid) or (opinion(state, id, eid) < 0 and not no_opinion(state, id)):
			continue
		var pct := int(g["base_pct"])
		if String(attitude(state, id, eid).get("id", "")) == "bienveillante":
			pct += int(g["bonus_pct"])
		if (a["yes"] as Dictionary).has(eid):
			pct += int(g["bonus_pct"])
		if _h(state, ["cadeau", id, eid, state.tick]) % 100 >= pct:
			continue
		(a["yes"] as Dictionary).erase(eid)
		var table: Array = data()["gift_table"]
		var total := 0
		for gd: Dictionary in table:
			total += int(gd["w"])
		var roll := _h(state, ["quel_cadeau", id, eid, state.tick]) % maxi(1, total)
		var idx := 0
		for i in table.size():
			roll -= int(table[i]["w"])
			if roll < 0:
				idx = i
				break
		Events.push(state, eid, "anc_cadeau", {"anc": id, "system": int(a["home"]), "n": idx}, added)


## Renfort annuel (prop. 3), en paix et affaiblie.
static func _reinforce(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var cfg: Dictionary = data()["power"]
	if state.tick < int(a["reinf"]) or not (a["war"] as Dictionary).is_empty():
		return
	a["reinf"] = state.tick + int(cfg["reinf_days"])
	@warning_ignore("integer_division")
	if total_power(state, id) >= int(a["power"]) * int(cfg["reinf_below_pct"]) / 100:
		return
	@warning_ignore("integer_division")
	spawn_fleet(state, id, int(a["home"]), int(a["power"]) / maxi(1, int(cfg["fleets"])), false)
	added.append(state.add_chronicle("Une nouvelle flotte sort des hangars %s. On ne savait même pas qu'ils avaient des hangars." % Crisis.de_name(name_of(state, id))))


# --- Effets des cartes ------------------------------------------------------------------------------

static func card_fx(state: GameState, eid: int, item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	var id := int(item.get("anc", -1))
	var a := get_a(state, id)
	if a.is_empty():
		return
	var e := state.get_empire(eid)
	match String(fx.get("act", "")):
		"op":
			var v := int(fx.get("v", 0))
			if v > 0 and bool(fx.get("yes", false)):
				(a["yes"] as Dictionary)[eid] = 1
			add_op(state, id, eid, v)
		"pop":
			var best: Colony = null
			for pid in state.sorted_colony_ids():
				var c: Colony = state.colonies[pid]
				if c.owner == eid and c.is_colony() and c.is_established() and (best == null or c.population > best.population):
					best = c
			if best != null and best.population > 1:
				best.population += int(fx.get("v", -1))
		"boon":
			add_boon(state, eid, String(fx["label"]), fx.get("fx", {}), int(fx.get("days", 360)))
		"lend_hero":
			var h: Dictionary = state.heroes.get(int(item.get("hero", -1)), {})
			if not h.is_empty() and int(h["owner"]) == eid:
				h["post"] = ""
				h["target"] = -1
				h["lent"] = id
				h["wound"] = state.tick + int(fx.get("days", 1800))
				(a["heroes"] as Dictionary)[int(h["id"])] = {"e": eid, "until": state.tick + int(fx.get("days", 1800))}
		"mission":
			var md: Dictionary = kind_def(String(a["kind"])).get("mission", {})
			if not md.is_empty():
				(a["mission"] as Dictionary)[eid] = {"stat": String(md["stat"]), "n": int(md["n"]), "base": int(e.stats.get(String(md["stat"]), 0)),
						"from": state.tick, "until": state.tick + int(data()["missions"]["days"])}
		"gift":
			_give_gift(state, id, eid, int(item.get("n", 0)), added)
		"submit":
			_submit(state, id, eid, added)
		"defy":
			if AncientsBridges.shield(state, id, eid):
				add_op(state, id, eid, -50)
				added.append(state.add_chronicle("%s refuse l'ultimatum en brandissant sa relique-clé. %s fulmine, mais ne bouge pas." % [e.display_name(), name_of(state, id)]))
			else:
				declare_war(state, id, eid, "punition", added)
		_:
			AncientsWake.card_fx(state, eid, item, fx, added)


static func _give_gift(state: GameState, id: int, eid: int, idx: int, added: Array[Dictionary]) -> void:
	var table: Array = data()["gift_table"]
	var gd: Dictionary = table[clampi(idx, 0, table.size() - 1)]
	var e := state.get_empire(eid)
	add_op(state, id, eid, int(data()["opinion"]["gift_yes"]))
	match String(gd["id"]):
		"res":
			for r in gd["res"]:
				e.resources[r] = int(e.resources.get(r, 0)) + int(gd["res"][r])
		"tech":
			var t := Research.grant_find(state, eid, "ancients")  # trouvaille d'abord (prop. 10 de l'arbre)
			if t == "":
				t = gift_tech(state, eid)
				if t != "":
					Research.grant(state, eid, [t])
			if t != "":
				added.append(state.add_chronicle("%s reçoit de %s une technologie toute faite : %s." % [e.display_name(), Crisis.obj_name(name_of(state, id)),
						String(Research.tech(t).get("label", t))], Espionage.private_to(state, [eid])))
		"boon":
			add_boon(state, eid, String(gd["label"]), gd.get("fx", {}), int(gd.get("days", 1800)))
		"ship":
			lend_ship(state, id, eid, int(gd.get("days", 3600)), "prêt")
		"hero":
			var hid := Quests.give_hero(state, eid, _ancient_hero_name(state, id, eid), "savant")
			var h: Dictionary = state.heroes.get(hid, {})
			if not h.is_empty():
				h["lvl"] = 5
				h["ancient"] = id


static func _ancient_hero_name(state: GameState, id: int, eid: int) -> String:
	var names := ["Ysolde-qui-se-souvient", "Maître Oth l'Ancien", "Archiviste Néhel", "Sœur Aube-Grise", "Le Berger Sans-Nom", "Kha-Mesh le Patient"]
	return String(names[_h(state, ["heros", id, eid, state.tick]) % names.size()])


## Technologie offerte : la moins chère des disponibles.
static func gift_tech(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	var best := ""
	var best_c := 1 << 40
	for tid in Research.visible_ids(e.faction()):
		if e.techs.has(tid) or not Research.is_available(state, eid, tid):
			continue
		var c := Research.cost(state, eid, tid)
		if c < best_c:
			best_c = c
			best = tid
	return best


## Vaisseau amiral de l'ancienne prêté à un empire pour days jours (cadeau, poste honorifique).
static func lend_ship(state: GameState, id: int, eid: int, days: int, why: String, ship_name := "") -> void:
	var a := get_a(state, id)
	var kd := kind_def(String(a["kind"]))
	var ship := String((kd.get("units", {}) as Dictionary).get("flag", ""))
	var cap := FactionTraits.capital_system(state, eid)
	if ship == "" or cap < 0:
		return
	var f := state.spawn_ship(eid, ship, cap)
	f.fleet_name = "%s (%s %s)" % [ship_name if ship_name != "" else String(GameData.ship(ship).get("label", ship)), why, Crisis.de_name(short_of(state, id))]
	(a["lent"] as Array).append({"e": eid, "ship": ship, "until": state.tick + days, "why": why})


## Fin des prêts : vaisseaux rendus, héros revenus (plus savants).
static func _lent(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var keep: Array = []
	for l: Dictionary in a["lent"]:
		if state.tick < int(l["until"]):
			keep.append(l)
			continue
		var eid := int(l["e"])
		for f in Fleets.empire_fleets(state, eid):
			if f.remove_ship(String(l["ship"])):
				if f.ships.is_empty():
					state.fleets.erase(f.id)
				break
		if state.get_empire(eid) != null:
			added.append(state.add_chronicle("%s reprend son vaisseau prêté à %s. Le plein n'a pas été fait." % [name_of(state, id), state.get_empire(eid).display_name()],
					Espionage.private_to(state, [eid])))
	a["lent"] = keep
	for hid in (a["heroes"] as Dictionary).keys():
		var l2: Dictionary = a["heroes"][hid]
		if state.tick < int(l2["until"]):
			continue
		(a["heroes"] as Dictionary).erase(hid)
		var h: Dictionary = state.heroes.get(int(hid), {})
		if not h.is_empty():
			h.erase("lent")
			h["wound"] = 0
			Heroes.gain_xp(state, h, 200)
			added.append(state.add_chronicle("%s revient de %s, plus savant et un peu distrait." % [String(h["name"]), Crisis.de_name(name_of(state, id)).trim_prefix("de ")],
					Espionage.private_to(state, [int(h["owner"])])))


## Ultimatum accepté (prop. 9) : l'effet de la Punition, sans la guerre.
static func _submit(state: GameState, id: int, eid: int, added: Array[Dictionary]) -> void:
	var a := get_a(state, id)
	var e := state.get_empire(eid)
	match String(a["kind"]):
		"kheb":
			var mine := systems_of(state, id)
			var give: Array[int] = []
			for sid in mine:
				for nb in state.galaxy.systems[sid].neighbors:
					if state.system_owner(int(nb)) == eid and not give.has(int(nb)):
						give.append(int(nb))
			give.sort()
			# Un seul système par ultimatum : la Dynastie est patiente.
			for sid in give.slice(0, 1):
				for entry in Combat.capture_system(state, sid, id):
					added.append(entry)
		"hierophantes":
			for pid in holy_held(state, id, eid):
				var c: Colony = state.colonies.get(pid)
				if c != null and c.planet_id != e.capital_planet:
					state.colonies.erase(pid)
			state.rebuild_ownership()
		"bibliotheque":
			var rel := ""
			for rid in Relics.owned(state, eid):
				rel = String(rid)
				break
			if int(e.resources.get("knowledge", 0)) >= 400 or rel == "":
				e.resources["knowledge"] = maxi(0, int(e.resources.get("knowledge", 0)) - 400)
			else:
				state.relics.erase(rel)
				Relics.touch(state)
	var o: Dictionary = data()["opinion"]
	(a["op"] as Dictionary)[eid] = maxi(opinion(state, id, eid) + int(o["demand_yes"]), int(o["demand_below"]) + 40)
	added.append(state.add_chronicle("%s plie devant l'ultimatum %s. Ça ne fait jamais plaisir, mais c'est moins cher qu'une guerre." % [
			e.display_name(), Crisis.de_name(name_of(state, id))], Espionage.private_to(state, [eid])))


# --- Guerre (prop. 9) -------------------------------------------------------------------------------

static func check_war(state: GameState, eid: int, id: int) -> String:
	var a := get_a(state, id)
	if a.is_empty() or not in_contact(state, id, eid):
		return "vous ne connaissez pas cette ancienne"
	if at_war_with(state, id, eid):
		return "déjà en guerre"
	return ""


## Guerre entre une ancienne et un empire : « punition » (elle l'ouvre) ou « empire » (il l'ouvre).
static func declare_war(state: GameState, id: int, eid: int, why: String, added: Array[Dictionary]) -> void:
	var a := get_a(state, id)
	if a.is_empty() or at_war_with(state, id, eid):
		return
	var d: Dictionary = data()["demand"]
	(a["war"] as Dictionary)[eid] = {"since": state.tick, "until": state.tick + (int(d["war_days"]) if why == "punition" else 99999),
			"why": why, "taken": 0, "take": int(d["war_take"]) if why == "punition" else 0}
	var e := state.get_empire(eid)
	for o in state.empires:
		o.path_cache.clear()
	if why == "punition":
		added.append(state.add_chronicle("%s sort de son sommeil pour punir %s. Les étoiles autour de sa poche s'allument une à une." % [name_of(state, id), e.display_name()]))
		Events.push(state, eid, "anc_punition", {"anc": id, "system": int(a["home"])}, added)
	elif why == "dominion":
		added.append(state.add_chronicle("%s refuse de plier : %s lui fait la guerre pour en faire un Dominion de force." % [e.display_name(), name_of(state, id)]))
	else:
		add_op(state, id, eid, -150)
		added.append(state.add_chronicle("%s déclare la guerre à %s. Les historiens prennent des notes ; les assureurs, la fuite." % [e.display_name(), Crisis.obj_name(name_of(state, id))]))
	AncientsWake.on_war(state, id, eid, why, added)


static func check_peace(state: GameState, eid: int, id: int) -> String:
	var a := get_a(state, id)
	if a.is_empty() or not at_war_with(state, id, eid):
		return "pas en guerre avec elle"
	var w: Dictionary = a["war"][eid]
	if not ["empire", "endiguement"].has(String(w["why"])):
		return "elle seule décidera quand la punition est finie"
	if state.tick - int(w["since"]) < 180:
		return "trop tôt : six mois de guerre au moins"
	if not asleep(state, id) and stage(state, id) != "decadent":
		return "éveillée, elle ne traite plus"
	if int(state.get_empire(eid).resources.get("influence", 0)) < 50:
		return "il faut 50 d'influence"
	return ""


static func peace(state: GameState, id: int, eid: int, added: Array[Dictionary]) -> void:
	var a := get_a(state, id)
	if a.is_empty() or not at_war_with(state, id, eid):
		return
	(a["war"] as Dictionary).erase(eid)
	(a["op"] as Dictionary)[eid] = mini(opinion(state, id, eid), -40)
	for o in state.empires:
		o.path_cache.clear()
	var e := state.get_empire(eid)
	if e != null:
		added.append(state.add_chronicle("La paix revient entre %s et %s. L'ancienne retourne à son sommeil, un œil ouvert." % [e.display_name(), Crisis.obj_name(name_of(state, id))]))
	_go_home(state, id)


static func _war_end(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	for eid in (a["war"] as Dictionary).keys():
		var w: Dictionary = a["war"][eid]
		var e := state.get_empire(int(eid))
		if e == null or e.eliminated:
			(a["war"] as Dictionary).erase(eid)
			continue
		if String(w["why"]) == "punition" and (state.tick >= int(w["until"]) or (int(w["take"]) > 0 and int(w["taken"]) >= int(w["take"]))):
			peace(state, id, int(eid), added)


## Les flottes rentrent dans la poche.
static func _go_home(state: GameState, id: int) -> void:
	var a := get_a(state, id)
	for f in fleets_of(state, id):
		if f.system_id == int(a["home"]) and not f.is_moving():
			continue
		var route := Fleets.plan_route(state, f, int(a["home"]))
		if not route.is_empty():
			f.system_id = int(route["system"])
			f.path.assign(route["path"])
			f.progress = int(route["progress"])


## Guerre en cours : les flottes (sauf la garde) vont assiéger les systèmes ennemis les plus proches ;
## un système sans défenseur armé tombe au bout de 45 jours.
static func _war_day(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var fl := fleets_of(state, id)
	var guard := fl[0].id if not fl.is_empty() and asleep(state, id) else -1
	var foes := AncientsWake.foes(state, id)
	if foes.is_empty():
		return
	var sieged := {}
	for f in fl:
		if f.is_moving() or state.battles.has(f.system_id):
			continue
		var owner := state.system_owner(f.system_id)
		if owner >= 0 and foes.has(owner):
			var armed := false
			for g in Fleets.fleets_at(state, f.system_id, owner):
				if Combat.is_armed(g):
					armed = true
					break
			if not armed and not sieged.has(f.system_id):
				sieged[f.system_id] = true
				var n := int((a["siege"] as Dictionary).get(f.system_id, 0)) + 1
				(a["siege"] as Dictionary)[f.system_id] = n
				if n >= 45:
					(a["siege"] as Dictionary).erase(f.system_id)
					for entry in Combat.capture_system(state, f.system_id, id):
						added.append(entry)
					if (a["war"] as Dictionary).has(owner):
						a["war"][owner]["taken"] = int(a["war"][owner]["taken"]) + 1
					AncientsWake.on_take(state, id, f.system_id, owner, added)
			continue
		if f.id == guard and f.system_id == int(a["home"]):
			continue
		var t := _target(state, id, f, foes)
		if t >= 0 and t != f.system_id:
			var route := Fleets.plan_route(state, f, t)
			if not route.is_empty():
				f.system_id = int(route["system"])
				f.path.assign(route["path"])
				f.progress = int(route["progress"])
	# Sièges abandonnés : le compteur retombe.
	for sid in (a["siege"] as Dictionary).keys():
		if not sieged.has(int(sid)):
			(a["siege"] as Dictionary).erase(sid)


static func _target(state: GameState, id: int, f: Fleet, foes: Array[int]) -> int:
	var jumps := FactionTraits.jumps_from(state.galaxy, f.system_id)
	var best := -1
	var best_s := 1 << 40
	var seen := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not foes.has(c.owner):
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if seen.has(sid):
			continue
		seen[sid] = true
		var j := int(jumps.get(sid, 999))
		if j >= 999:
			continue
		var s := j * 1000 + _h(state, ["cible", id, f.id, sid]) % 500
		if s < best_s:
			best_s = s
			best = sid
	return best


## Prise d'un système (Combat.capture_system) : un monde ancien perdu rapporte son butin (prop. 4).
static func on_capture(state: GameState, sid: int, new_owner: int, old: int, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	AncientsBridges.on_capture(state, sid, new_owner, added)
	if GameState.is_ancient(old) and systems_of(state, old).is_empty():
		AncientsBridges.on_destroyed(state, old, added)
	if not GameState.is_ancient(old) or GameState.is_npc(new_owner):
		return
	var e := state.get_empire(new_owner)
	var lt: Dictionary = data()["loot"]
	var parts: Array = []
	for pid in state.galaxy.systems[sid].planet_ids:
		var w := world_of(state, pid)
		if w.is_empty():
			continue
		for r in lt["res"]:
			e.resources[r] = int(e.resources.get(r, 0)) + int(lt["res"][r])
		parts.append(String(building_def(String(w["b"])).get("label", w["b"])))
	add_op(state, old, new_owner, -100)
	if not parts.is_empty():
		Events.apply_fx(state, new_owner, {"id": -1, "card": "", "system": sid, "planet": -1, "rival": -1, "hero": -1},
				[{"k": "stab", "v": int(lt["stab"]), "days": int(lt["stab_days"]), "scope": "capital"}], added)
		added.append(state.add_chronicle("%s s'empare d'un monde %s : %s. Ce que l'on trouve dans les caves dépasse l'entendement, et les inventaires." % [
				e.display_name(), Crisis.de_name(short_of(state, old)).replace("de ", "de ").trim_prefix(""), ", ".join(parts)]))
	AncientsWake.on_lost_world(state, old, new_owner, added)


# --- Faveur et postes (prop. 11) --------------------------------------------------------------------

static func check_give(state: GameState, eid: int, id: int, res: String) -> String:
	var a := get_a(state, id)
	if a.is_empty() or not in_contact(state, id, eid):
		return "vous ne connaissez pas cette ancienne"
	if at_war_with(state, id, eid):
		return "en guerre avec elle"
	var opts: Dictionary = data()["contrib"]["options"]
	if not opts.has(res):
		return "ressource inconnue"
	var cost := give_cost(state, eid, res)
	if int(state.get_empire(eid).resources.get(res, 0)) < cost:
		return "pas assez de %s" % GameData.resource_label(res).to_lower()
	return ""


static func give_cost(state: GameState, eid: int, res: String) -> int:
	var base := int(data()["contrib"]["options"].get(res, 0))
	@warning_ignore("integer_division")
	return maxi(1, base * (100 + AncientsBridges.contrib_pct(state, eid)) / 100)


static func give(state: GameState, eid: int, id: int, res: String) -> void:
	var a := get_a(state, id)
	var e := state.get_empire(eid)
	var c: Dictionary = data()["contrib"]
	e.resources[res] = int(e.resources.get(res, 0)) - give_cost(state, eid, res)
	var pts := int(c["options"][res]) * int(c["points"][res])
	(a["contrib"] as Dictionary)[eid] = int((a["contrib"] as Dictionary).get(eid, 0)) + pts
	@warning_ignore("integer_division")
	add_op(state, id, eid, maxi(1, pts / maxi(1, int(c["op_per"]))))


## Classement des contributions de la période (points, du plus gros au plus petit).
static func ranking(state: GameState, id: int) -> Array:
	var out: Array = []
	var a := get_a(state, id)
	for eid in (a.get("contrib", {}) as Dictionary).keys():
		out.append([-int(a["contrib"][eid]), int(eid)])
	out.sort()
	return out


static func post_holder(state: GameState, id: int, post: String) -> int:
	return int((get_a(state, id).get("posts", {}) as Dictionary).get(post, -1))


static func _posts(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	if state.tick < int(a["term"]):
		return
	var c: Dictionary = data()["contrib"]
	a["term"] = state.tick + int(c["term_days"])
	var posts: Array = kind_def(String(a["kind"])).get("posts", [])
	var rk := ranking(state, id)
	var before: Dictionary = (a["posts"] as Dictionary).duplicate()
	a["posts"] = {}
	var lines: Array = []
	for i in posts.size():
		var pd: Dictionary = posts[i]
		if i >= rk.size() or -int(rk[i][0]) < int(c["min_points"]):
			continue
		var eid := int(rk[i][1])
		var e := state.get_empire(eid)
		if e == null or e.eliminated:
			continue
		(a["posts"] as Dictionary)[String(pd["id"])] = eid
		lines.append("%s : %s (%s)" % [String(pd["label"]), e.display_name(), String(pd.get("text", ""))])
		if String(pd.get("ship", "")) != "" and int(before.get(String(pd["id"]), -1)) != eid:
			lend_ship(state, id, eid, int(c["term_days"]), String(pd["label"]).to_lower(), String(pd.get("ship_name", "")))
		AncientsBridges.on_post(state, id, eid, String(pd["id"]))
	a["contrib"] = {}
	Relics.touch(state)
	if lines.is_empty():
		return
	a["posts_text"] = "%s a choisi ses favoris pour les cinq prochaines années, parmi ceux qui ont le plus donné :\n%s" % [name_of(state, id), "\n".join(lines)]
	added.append(state.add_chronicle("%s distribue ses postes honorifiques. %s" % [name_of(state, id), "; ".join(lines)]))
	for eid in _contact_ids(a):
		Events.push(state, eid, "anc_postes", {"anc": id, "system": int(a["home"])}, added)


## Questions payantes d'un poste « intel » (Bibliothécaire, Naturaliste) : réponse dans la chronique.
static func check_ask(state: GameState, eid: int, id: int, target: int) -> String:
	var post := intel_post(state, id, eid)
	if post.is_empty():
		return "réservé au titulaire d'un poste de renseignement"
	if int(state.get_empire(eid).resources.get("influence", 0)) < 30:
		return "il faut 30 d'influence"
	if String(post["intel"]) == "empire" and (state.get_empire(target) == null or GameState.is_npc(target) or target == eid):
		return "choisissez un autre empire"
	return ""


static func intel_post(state: GameState, id: int, eid: int) -> Dictionary:
	for pd: Dictionary in kind_def(kind_of(state, id)).get("posts", []):
		if pd.has("intel") and post_holder(state, id, String(pd["id"])) == eid:
			return pd
	return {}


static func ask(state: GameState, eid: int, id: int, target: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - 30
	var post := intel_post(state, id, eid)
	var text := ""
	if String(post.get("intel", "")) == "empire":
		var t := state.get_empire(target)
		text = "« %s ? Sa flotte vaut %d, ses colonies sont %d. » " % [t.display_name(), empire_power(state, target), Research.colony_count(state, target)]
		if Crisis.enabled(state):
			text += "« Et la fin de partie commencera vers l'an %d. Je n'ai rien dit. »" % (Crisis.endgame_day(state) / 360 + 1)
	else:
		var spots: Array = []
		for gid in Guardians.ids(state):
			var g: Dictionary = Guardians.list(state)[gid]
			if String(g.get("status", "")) != "dead":
				spots.append("%s à %s" % [String(Guardians.def(gid).get("name", gid)), state.galaxy.systems[int(g["sid"])].system_name])
		text = "« Les gardiens dorment là : %s. »" % (", ".join(spots) if not spots.is_empty() else "nulle part, ils sont tous morts, quelle tristesse")
	added.append(state.add_chronicle("%s répond à %s. %s" % [String(post.get("label", "L'ancienne")), e.display_name(), text], Espionage.private_to(state, [eid], -1)))


# --- Commandes du joueur (SimCommands.anc_act) -----------------------------------------------------

## act : "give" (x = ancienne, s = ressource), "war", "peace" (x = ancienne), "ask" (x = ancienne,
## n = empire visé) ; les actes de l'Éveil passent par AncientsWake.
static func check_act(state: GameState, eid: int, act: String, x: int, s: String, n: int) -> String:
	if not enabled(state):
		return "pas de puissances anciennes dans cette partie"
	if not GameState.is_ancient(x) or get_a(state, x).is_empty():
		return "ancienne inconnue"
	match act:
		"give":
			return check_give(state, eid, x, s)
		"war":
			return check_war(state, eid, x)
		"peace":
			return check_peace(state, eid, x)
		"ask":
			return check_ask(state, eid, x, n)
	return AncientsWake.check_act(state, eid, act, x, s, n)


static func act(state: GameState, eid: int, act_id: String, x: int, s: String, n: int, added: Array[Dictionary]) -> void:
	match act_id:
		"give":
			give(state, eid, x, s)
		"war":
			declare_war(state, x, eid, "empire", added)
		"peace":
			var e := state.get_empire(eid)
			e.resources["influence"] = int(e.resources.get("influence", 0)) - 50
			peace(state, x, eid, added)
		"ask":
			ask(state, eid, x, n, added)
		_:
			AncientsWake.act(state, eid, act_id, x, s, n, added)


# --- Faveurs (effets au format des technologies) ----------------------------------------------------

static func add_boon(state: GameState, eid: int, label: String, fx: Dictionary, days: int) -> void:
	if state.ancients.is_empty():
		return
	var bs: Dictionary = state.ancients["boons"]
	if not bs.has(eid):
		bs[eid] = []
	(bs[eid] as Array).append({"label": label, "fx": fx.duplicate(true), "until": state.tick + days if days > 0 else -1})
	Relics.touch(state)


static func boons(state: GameState, eid: int) -> Array:
	if state.ancients.is_empty():
		return []
	return (state.ancients.get("boons", {}) as Dictionary).get(eid, [])


static func _expire_boons(state: GameState) -> void:
	var bs: Dictionary = state.ancients.get("boons", {})
	var changed := false
	for eid in bs.keys():
		var keep: Array = []
		for b: Dictionary in bs[eid]:
			if int(b["until"]) < 0 or int(b["until"]) > state.tick:
				keep.append(b)
			else:
				changed = true
		bs[eid] = keep
	if changed:
		Relics.touch(state)


## Effets pour un empire : faveurs, postes tenus, mondes anciens conquis (merveilles).
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not enabled(state):
		return out
	for b: Dictionary in boons(state, eid):
		Research._merge(out, b["fx"])
	for id in ids(state):
		for pd: Dictionary in kind_def(kind_of(state, id)).get("posts", []):
			if post_holder(state, id, String(pd["id"])) == eid:
				Research._merge(out, pd.get("fx", {}))
	for pid in state.ancients.get("worlds", {}):
		var c: Colony = state.colonies.get(int(pid))
		if c != null and c.owner == eid:
			Research._merge(out, {"production_pct": {"all": 5}})
	Research._merge(out, AncientsWake.effects(state, eid))
	return out


# --- Cartes : textes, jetons, IA --------------------------------------------------------------------

static func fx_line(state: GameState, item: Dictionary, fx: Dictionary) -> String:
	var id := int(item.get("anc", -1))
	match String(fx.get("act", "")):
		"op":
			if no_opinion(state, id):
				return ""
			return "opinion %s %+d" % [Crisis.de_name(short_of(state, id)), int(fx.get("v", 0))]
		"pop":
			return "population %+d sur votre monde le plus peuplé" % int(fx.get("v", -1))
		"boon":
			var days := int(fx.get("days", 360))
			return "%s : %s%s" % [String(fx["label"]), Relics.fx_text(fx.get("fx", {})), (" pendant %d mois" % (days / 30)) if days > 0 else ", pour toujours"]
		"lend_hero":
			return "le héros part %d ans et revient avec beaucoup d'expérience" % (int(fx.get("days", 1800)) / 360)
		"mission":
			return "mission : %s (opinion +%d si réussie, -%d sinon)" % [String(kind_def(kind_of(state, id)).get("mission", {}).get("text", "")).to_lower().trim_suffix("."),
					int(data()["opinion"]["mission_ok"]), -int(data()["opinion"]["mission_fail"])]
		"gift":
			return String((data()["gift_table"] as Array)[clampi(int(item.get("n", 0)), 0, (data()["gift_table"] as Array).size() - 1)]["text"])
		"submit":
			return "elle se calme (opinion remonte au-dessus de %d)" % (int(data()["opinion"]["demand_below"]) + 40)
		"defy":
			return "guerre de Punition : ses flottes viennent prendre jusqu'à %d systèmes" % int(data()["demand"]["war_take"])
	return AncientsWake.fx_line(state, item, fx)


static func fill(state: GameState, eid: int, item: Dictionary, s: String) -> String:
	if not s.contains("{anc"):
		return s
	var id := int(item.get("anc", -1))
	var kd := kind_def(kind_of(state, id))
	var out := s.replace("{anc_blurb}", String(kd.get("blurb", "")))
	out = out.replace("{anc_angers}", String(kd.get("angers_text", "")))
	out = out.replace("{anc_wants}", String(kd.get("wants_text", "")))
	out = out.replace("{anc_force}", force_text(state, id, eid))
	out = out.replace("{anc_mission}", String(kd.get("mission", {}).get("text", "")))
	out = out.replace("{anc_gift}", String((data()["gift_table"] as Array)[clampi(int(item.get("n", 0)), 0, (data()["gift_table"] as Array).size() - 1)]["text"]))
	out = out.replace("{anc_posts}", String(get_a(state, id).get("posts_text", "")))
	out = AncientsWake.fill(state, eid, item, out)
	out = out.replace("{anc_de}", Crisis.de_name(name_of(state, id)))
	out = out.replace("{anc}", name_of(state, id))
	return out


## Valeur d'un effet « ancient » pour l'IA (AiEvents).
static func ai_value(state: GameState, eid: int, item: Dictionary, fx: Dictionary, temper: int) -> int:
	var v := int(fx.get("ai", 0)) * 25
	var id := int(item.get("anc", -1))
	match String(fx.get("act", "")):
		"submit":
			# Plier si sa flotte vaut moins de la moitié de celle de l'ancienne.
			var mine := empire_power(state, eid)
			@warning_ignore("integer_division")
			v = 600 if mine * 100 < total_power(state, id) * int(data()["ai"]["demand_accept_ratio"]) else -200 - temper * 100
		"defy":
			v = 0
	return v + AncientsWake.ai_value(state, eid, item, fx, temper)


# --- Sauvegarde -------------------------------------------------------------------------------------

const INT_MAPS := ["op", "base", "contact", "req", "mis_next", "mission", "dem_cd", "war", "contrib", "yes", "siege", "heroes", "angry", "side", "dom", "sub_cd"]


static func to_dict(state: GameState) -> Dictionary:
	return _sorted(state.ancients)


static func _sorted(v: Variant) -> Variant:
	if v is Dictionary:
		var keys: Array = (v as Dictionary).keys()
		keys.sort_custom(func(x: Variant, y: Variant) -> bool: return str(x) < str(y))
		var out := {}
		for k in keys:
			out[str(k)] = _sorted(v[k])
		return out
	if v is Array:
		var arr := []
		for x in v:
			arr.append(_sorted(x))
		return arr
	return v


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.ancients = {}
	if d.is_empty():
		return
	var src: Dictionary = GameData._to_ints(d.duplicate(true))
	var out := {"mode": String(src.get("mode", "normal")), "wake": bool(src.get("wake", true)), "list": {}, "holy": {}, "worlds": {}, "boons": {}}
	for k in src.get("holy", {}):
		out["holy"][int(k)] = int(src["holy"][k])
	for k in src.get("worlds", {}):
		var w: Dictionary = src["worlds"][k]
		out["worlds"][int(k)] = {"a": int(w["a"]), "b": String(w["b"])}
	for k in src.get("boons", {}):
		out["boons"][int(k)] = src["boons"][k]
	if src.has("heaven"):
		var h: Dictionary = src["heaven"]
		var sides := {}
		for k in h.get("sides", {}):
			sides[int(k)] = int(h["sides"][k])
		h["sides"] = sides
		out["heaven"] = h
	for k in ["parv"]:
		if src.has(k):
			out[k] = int(src[k])
	if src.has("consecrated"):
		var cs := {}
		for k in src["consecrated"]:
			cs[int(k)] = String(src["consecrated"][k])
		out["consecrated"] = cs
	if src.has("guard_roll"):
		out["guard_roll"] = String(src["guard_roll"])
	for k in src.get("list", {}):
		var a: Dictionary = src["list"][k]
		for m in INT_MAPS:
			if a.has(m):
				var nm := {}
				for kk in a[m]:
					nm[int(kk) if String(kk).is_valid_int() else kk] = a[m][kk]
				a[m] = nm
		if a.has("posts"):
			var np := {}
			for pk in a["posts"]:
				np[String(pk)] = int(a["posts"][pk])
			a["posts"] = np
		a["kind"] = String(a["kind"])
		a["stage"] = String(a.get("stage", STAGE_SLEEP))
		out["list"][int(k)] = a
	state.ancients = out
