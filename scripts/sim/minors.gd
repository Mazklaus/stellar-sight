class_name Minors
extends RefCounted
## Peuples mineurs (étude « Peuples mineurs », 2026-11-15 ; data/minors.json).
## De petites civilisations qui ne sont pas des empires : pré-spatiaux (un monde, six âges, pas de
## vaisseaux ; Stellaris) et spatiaux (une cité-État avec une petite flotte, qui ne colonise pas ; Civ VI,
## Endless Space 2). Chacun est une puissance neutre à identifiant réservé (GameState.MINOR_BASE + rang),
## hors de la liste des empires, avec une fiche d'espèce légère (registre, archétype, gouvernement, credo,
## un trait) qui le fait entrer dans la mosaïque des populations.
## Chaque empire a une faveur (0-100) auprès de chaque peuple : émissaires, cadeaux, quêtes. Paliers :
## Contact (20), Amitié (50, bonus d'orientation), Suzerain (au moins 60 et 10 de plus que le deuxième :
## cadeau unique, levée, intégration). Un peuple absorbé (intégré ou conquis) apporte son trait
## d'assimilation, dans la limite des emplacements actifs (prop. 21).
## La vie des mineurs (conscience, hostiles, drames, Avènement, sécessions, pré-conscients, programmes et
## accords, sujets, dispersion) est dans MinorsLife (lot 2) ; les ponts avec le reste du jeu dans
## MinorsBridges (lot 3).
##
## État : state.minors = {} (aucun) ou {"mode", "list": {id: peuple}, "absorbed": {empire: [sortes]},
##  "active": {empire: [sortes]}, "done": {empire: intégrations}, "prot": {empire: {conquérant: jour}},
##  "former": {système: {"kind", "suz", "until"}}, "gone": {sorte: 1}}.
## peuple = {"kind", "fam" ("pre" | "space"), "planet", "sid", "age", "age_days", "aware", "att",
##  "fav": {empire: n}, "contact": {empire: jour}, "post": {empire: "discret" | "ouvert"}, "envoy": {empire: niveau},
##  "suz", "suz_since", "quest": {...}, "quest_next", "levy": {...}, "fleets": [ids], "grudge": {empire: jour},
##  "war": {empire: jour}, "gift_cd": {empire: jour}, "given": {empire: 1}, "eureka": jour, "rebuild": jour,
##  "first": empire} ; une sécession ou un Avènement ajoutent "name", "short", "species" (lot 2).

const FAM_PRE := "pre"
const FAM_SPACE := "space"
const TIERS := ["", "contact", "ami", "suzerain"]
const TIER_LABELS := {"": "Inconnu", "contact": "Contact", "ami": "Amitié", "suzerain": "Suzerain"}


static func data() -> Dictionary:
	return GameData.minors()


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
	return absi(hash([state.seed_value, "mineur"] + parts))


## Fiche d'espèce légère (GameData.faction) : « mineur_<sorte> » ou « pres_<sorte> ».
static func species_fiche(fid: String) -> Dictionary:
	var kd: Dictionary = {}
	if fid.begins_with("mineur_"):
		kd = kind_def(fid.trim_prefix("mineur_"))
	elif fid.begins_with("pres_"):
		kd = (data().get("presapients", {}).get("kinds", {}) as Dictionary).get(fid, {})
	if kd.is_empty():
		return {}
	return {"id": fid, "name": String(kd.get("name", fid)), "short": String(kd.get("short", fid)), "registre": String(kd.get("registre", "")),
			"species": (kd.get("species", {}) as Dictionary).duplicate(true), "preferred": (kd.get("preferred", []) as Array).duplicate(),
			"color": String(kd.get("color", "#b0b0b0")), "lore": String(kd.get("blurb", kd.get("lore", ""))), "minor": true}


# --- Lecture ----------------------------------------------------------------------------------------

static func enabled(state: GameState) -> bool:
	return not state.minors.is_empty()


static func worth_saving(state: GameState) -> bool:
	return not state.minors.is_empty()


static func get_m(state: GameState, id: int) -> Dictionary:
	if state.minors.is_empty():
		return {}
	return (state.minors.get("list", {}) as Dictionary).get(id, {})


static func ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if state.minors.is_empty():
		return out
	for k in state.minors.get("list", {}):
		out.append(int(k))
	out.sort()
	return out


static func kind_of(state: GameState, id: int) -> String:
	return String(get_m(state, id).get("kind", ""))


static func name_of(state: GameState, id: int) -> String:
	var m := get_m(state, id)
	if m.has("name"):
		return String(m["name"])
	return String(kind_def(String(m.get("kind", ""))).get("name", "Un peuple mineur"))


static func short_of(state: GameState, id: int) -> String:
	var m := get_m(state, id)
	if m.has("short"):
		return String(m["short"])
	return String(kind_def(String(m.get("kind", ""))).get("short", "Mineur"))


## Espèce du peuple (fiche GameData.faction) : la sienne, ou celle d'une sécession.
static func species_id(state: GameState, id: int) -> String:
	var m := get_m(state, id)
	if m.has("species"):
		return String(m["species"])
	return "mineur_" + String(m.get("kind", ""))


static func is_pre(state: GameState, id: int) -> bool:
	return String(get_m(state, id).get("fam", FAM_PRE)) == FAM_PRE


static func system_of(state: GameState, id: int) -> int:
	return int(get_m(state, id).get("sid", -1))


## Le peuple qui tient ce système (-1 sinon).
static func at_system(state: GameState, sid: int) -> int:
	var o := state.system_owner(sid)
	return o if GameState.is_minor(o) and not get_m(state, o).is_empty() else -1


static func orientation(state: GameState, id: int) -> Dictionary:
	var m := get_m(state, id)
	var o := String(m.get("orientation", kind_def(String(m.get("kind", ""))).get("orientation", "economique")))
	return (data().get("orientations", {}) as Dictionary).get(o, {})


static func orientation_def(o: String) -> Dictionary:
	return (data().get("orientations", {}) as Dictionary).get(o, {})


static func _res_text(res: Dictionary) -> String:
	var parts: Array = []
	for r in res:
		parts.append("%d %s" % [int(res[r]), GameData.resource_label(String(r)).to_lower()])
	return ", ".join(parts)


static func gift_def(state: GameState, id: int) -> Dictionary:
	var m := get_m(state, id)
	if m.has("gift"):
		return m["gift"]
	return kind_def(String(m.get("kind", ""))).get("gift", {})


static func age_def(i: int) -> Dictionary:
	var ages: Array = data()["ages"]
	return ages[clampi(i, 0, ages.size() - 1)]


static func age_label(state: GameState, id: int) -> String:
	if not is_pre(state, id):
		return "Spatial"
	return String(age_def(int(get_m(state, id).get("age", 0)))["label"])


static func fav(state: GameState, id: int, eid: int) -> int:
	return int((get_m(state, id).get("fav", {}) as Dictionary).get(eid, 0))


static func in_contact(state: GameState, id: int, eid: int) -> bool:
	return (get_m(state, id).get("contact", {}) as Dictionary).has(eid)


## Peuples rencontrés par un empire.
static func met(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for id in ids(state):
		if in_contact(state, id, eid):
			out.append(id)
	return out


static func suzerain(state: GameState, id: int) -> int:
	return int(get_m(state, id).get("suz", -1))


## Peuples dont l'empire est le suzerain.
static func proteges_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for id in ids(state):
		if suzerain(state, id) == eid:
			out.append(id)
	return out


static func tier(state: GameState, id: int, eid: int) -> String:
	if not in_contact(state, id, eid):
		return ""
	if suzerain(state, id) == eid:
		return "suzerain"
	var fd: Dictionary = data()["favor"]
	var v := fav(state, id, eid)
	if v >= int(fd["friend"]):
		return "ami"
	if v >= int(fd["contact"]):
		return "contact"
	return ""


static func tier_at_least(state: GameState, id: int, eid: int, t: String) -> bool:
	return TIERS.find(tier(state, id, eid)) >= TIERS.find(t)


static func has_post(state: GameState, id: int, eid: int) -> bool:
	return (get_m(state, id).get("post", {}) as Dictionary).has(eid)


static func post_mode(state: GameState, id: int, eid: int) -> String:
	return String((get_m(state, id).get("post", {}) as Dictionary).get(eid, ""))


## Un empire peut-il parler à ce peuple ? Spatial : dès le contact ; pré-spatial : avec un poste
## d'observation (ou une infiltration, lot 3).
static func can_talk(state: GameState, id: int, eid: int) -> bool:
	if not in_contact(state, id, eid):
		return false
	if not is_pre(state, id):
		return true
	return has_post(state, id, eid) or MinorsBridges.infiltrated(state, id, eid)


static func at_war_with(state: GameState, id: int, eid: int) -> bool:
	return (get_m(state, id).get("war", {}) as Dictionary).has(eid)


static func grudge(state: GameState, id: int, eid: int) -> bool:
	return state.tick < int((get_m(state, id).get("grudge", {}) as Dictionary).get(eid, -1))


## Hostilité (Combat.at_war) quand l'un des deux est un peuple mineur.
static func at_war(state: GameState, a: int, b: int) -> bool:
	if GameState.is_minor(a) and GameState.is_minor(b):
		return false
	var mid := a if GameState.is_minor(a) else b
	var other := b if mid == a else a
	if get_m(state, mid).is_empty():
		return false
	if other == GameState.FAUNA_ID or GameState.is_ancient(other):
		return false
	if GameState.is_npc(other):
		return true  # pirates, crise, Sans-Bannière
	return at_war_with(state, mid, other) or MinorsLife.hostile_to(state, mid, other)


## Garnison en plus de la population : les régiments de l'âge (prop. 6), ceux de la cité-État.
static func troops(state: GameState, id: int) -> int:
	var m := get_m(state, id)
	if m.is_empty():
		return 0
	if not is_pre(state, id):
		return int(age_def(5)["troops"]) * 2
	if not (m.get("levy", {}) as Dictionary).is_empty():
		return 0  # régiments loués au suzerain
	return int(age_def(int(m.get("age", 0)))["troops"]) * 2


static func fleets_of(state: GameState, id: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for fid in get_m(state, id).get("fleets", []):
		var f: Fleet = state.fleets.get(int(fid))
		if f != null and not f.ships.is_empty():
			out.append(f)
	return out


static func power(state: GameState, id: int) -> int:
	var p := 0
	for f in fleets_of(state, id):
		p += Combat.fleet_power(f)
	return p


# --- Mise en place (prop. 1-5) ----------------------------------------------------------------------

static func wanted_count(state: GameState, mode: String) -> int:
	var md := _find(mode_defs(), mode)
	var per := int(md.get("per_systems", 0))
	if per <= 0:
		return 0
	var n := state.galaxy.systems.size()
	@warning_ignore("integer_division")
	var want := (n + per / 2) / per
	return clampi(want, int(data()["count"]["min"]), mini(GameState.MINOR_MAX, kind_ids().size()))


static func setup(state: GameState, mode: String) -> void:
	state.minors = {}
	var want := wanted_count(state, mode)
	if want <= 0:
		return
	state.minors = {"mode": mode, "list": {}, "absorbed": {}, "active": {}, "done": {}, "prot": {}, "former": {}, "gone": {}}
	var starts: Array = []
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cap))
	# Ordre des sortes : moitié pré-spatiaux, moitié spatiaux, en alternance.
	var pre: Array = []
	var space: Array = []
	for k in kind_ids():
		var entry := [_h(state, ["ordre", k]), k]
		if String(kind_def(k).get("family", FAM_PRE)) == FAM_SPACE:
			space.append(entry)
		else:
			pre.append(entry)
	pre.sort()
	space.sort()
	var order: Array[String] = []
	var first_space := _h(state, ["famille"]) % 2 == 0
	var i := 0
	while order.size() < pre.size() + space.size():
		var a: Array = space if first_space else pre
		var b: Array = pre if first_space else space
		if i < a.size():
			order.append(String(a[i][1]))
		if i < b.size():
			order.append(String(b[i][1]))
		i += 1
	var pl: Dictionary = data()["place"]
	var homes: Array[int] = []
	var ki := 0
	# Plancher équitable : chaque départ en a un à near_jumps sauts ou moins si possible.
	for dj: Dictionary in starts:
		if ki >= order.size() or ids(state).size() >= want:
			break
		var near := false
		for hsid in homes:
			if int(dj.get(hsid, 999)) <= int(pl["near_jumps"]):
				near = true
				break
		if near:
			continue
		var site := _pick_site(state, order[ki], starts, homes, dj)
		if site.is_empty():
			site = _pick_site(state, order[ki], starts, homes, dj, 2)  # pas de place : un peu plus loin
		if site.is_empty():
			continue
		homes.append(int(site[0]))
		create(state, order[ki], int(site[0]), int(site[1]))
		ki += 1
	while ki < order.size() and ids(state).size() < want:
		var site2 := _pick_site(state, order[ki], starts, homes, {})
		ki += 1
		if site2.is_empty():
			continue
		homes.append(int(site2[0]))
		create(state, order[ki - 1], int(site2[0]), int(site2[1]))
	if ids(state).is_empty():
		state.minors = {}
		return
	MinorsLife.setup_pres(state)
	for e in state.empires:
		e.path_cache.clear()


## [système, planète] pour cette sorte ; [] s'il n'y a pas la place. near : sauts depuis un départ à
## rapprocher (plancher équitable), ou {}.
static func _pick_site(state: GameState, k: String, starts: Array, homes: Array[int], near: Dictionary, slack := 0) -> Array:
	var pl: Dictionary = data()["place"]
	var pref: Array = species_fiche("mineur_" + k).get("preferred", [])
	var best: Array = []
	var best_s := 1 << 40
	for s in state.galaxy.systems:
		if not _free(state, s.id) or _near_start(starts, s.id) < int(pl["min_jumps"]):
			continue
		if not near.is_empty() and int(near.get(s.id, 999)) > int(pl["near_jumps"]) + slack:
			continue
		var close := false
		for hsid in homes:
			if int(FactionTraits.jumps_from(state.galaxy, hsid).get(s.id, 999)) < int(pl["apart"]):
				close = true
				break
		if close:
			continue
		var pid := _home_planet(state, s.id, pref)
		if pid < 0:
			continue
		var p := state.galaxy.get_planet(pid)
		var score := (0 if pref.has(p.type) else 5000) + _h(state, ["site", k, s.id]) % 1000
		if score < best_s:
			best_s = score
			best = [s.id, pid]
	return best


## La planète natale : un type préféré si possible, sinon un monde habitable, la plus grande.
static func _home_planet(state: GameState, sid: int, pref: Array) -> int:
	var best := -1
	var best_s := -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var p := state.galaxy.get_planet(pid)
		if state.colonies.has(pid) or (GameData.planet_type(p.type).get("pop_yields", {}) as Dictionary).is_empty():
			continue
		var s := (1000 if pref.has(p.type) else 0) + p.size * 10
		if s > best_s:
			best_s = s
			best = pid
	return best


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
	for aid in Ancients.ids(state):
		if (Ancients.get_a(state, aid).get("systems", []) as Array).has(sid):
			return false
	return true


static func _new_id(state: GameState) -> int:
	var id := GameState.MINOR_BASE
	while not get_m(state, id).is_empty():
		id += 1
	return id if id < GameState.MINOR_BASE + GameState.MINOR_MAX else -1


## Crée le peuple k sur cette planète : monde peuplé, garnison, flotte (spatiaux).
static func create(state: GameState, k: String, sid: int, pid: int, extra := {}) -> int:
	var id := _new_id(state)
	if id < 0:
		return -1
	var kd := kind_def(k)
	var fam := String(extra.get("fam", kd.get("family", FAM_PRE)))
	var ar: Dictionary = data()["age_rules"]
	var age := 5
	if fam == FAM_PRE:
		age = int(kd["start_age"]) if kd.has("start_age") else _h(state, ["age", k]) % (int(ar["start_max"]) + 1)
	var att := _roll_attitude(state, k)
	var m := {"kind": k, "fam": fam, "planet": pid, "sid": sid, "age": age, "age_days": 0, "aware": 0, "att": att,
			"fav": {}, "contact": {}, "post": {}, "envoy": {}, "suz": -1, "suz_since": 0, "quest": {},
			"quest_next": state.tick + int(data()["quests"]["first_days"]) + _h(state, ["quete0", k]) % 360,
			"levy": {}, "fleets": [], "grudge": {}, "war": {}, "gift_cd": {}, "given": {}, "eureka": 0, "rebuild": 0, "first": -1}
	for key in extra:
		m[key] = extra[key]
	(state.minors["list"] as Dictionary)[id] = m
	var c: Colony = state.colonies.get(pid)
	if c == null:
		c = Colony.new()
		c.planet_id = pid
		c.kind = Colony.KIND_COLONY
		state.colonies[pid] = c
	c.owner = id
	c.species.clear()
	c.integ.clear()
	c.population = maxi(c.population, int(data()["space"]["pop"]) if fam == FAM_SPACE else int(age_def(age)["pop"]))
	state.rebuild_ownership()
	if fam == FAM_SPACE:
		spawn_fleet(state, id)
	state.garrisons[sid] = Combat.garrison_max(state, sid)
	return id


static func _roll_attitude(state: GameState, k: String) -> String:
	var w: Dictionary = data()["attitudes"]["weights"]
	var keys := w.keys()
	keys.sort()
	var total := 0
	for key in keys:
		total += int(w[key])
	var roll := _h(state, ["attitude", k]) % maxi(1, total)
	for key in keys:
		roll -= int(w[key])
		if roll < 0:
			return String(key)
	return "neutre"


## Puissance de la flotte d'une cité-État : fleet_pct % de la flotte militaire de départ d'un empire.
static func fleet_power_target(state: GameState) -> int:
	var ref := 0
	if not state.empires.is_empty():
		for ship_id in FactionTraits.start_ships(state.empires[0].faction_id):
			if bool(GameData.ship(String(ship_id)).get("military", false)):
				ref += Combat.ship_strength(String(ship_id))
	@warning_ignore("integer_division")
	return maxi(60, ref * int(data()["space"]["fleet_pct"]) / 100)


static func spawn_fleet(state: GameState, id: int, pct := 100) -> Fleet:
	var m := get_m(state, id)
	var ships: Array = data()["space"]["ships"]
	var f := state.spawn_ship(id, String(ships[0]), int(m["sid"]))
	var guard := 0
	@warning_ignore("integer_division")
	var target := fleet_power_target(state) * pct / 100
	while Combat.fleet_power(f) < target and guard < 40:
		guard += 1
		f.add_ship(String(ships[guard % ships.size()]), -1, -1)
	f.troops = 0
	f.fleet_name = "Garde %s" % Crisis.de_name(short_of(state, id))
	(m["fleets"] as Array).append(f.id)
	return f


# --- Chaque jour ------------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not enabled(state):
		return added
	for id in ids(state):
		var m := get_m(state, id)
		if m.is_empty():
			continue
		if (state.tick + id) % 30 == 0:
			_month(state, id, m, added)
		MinorsLife.daily(state, id, m, added)
	if state.tick % 30 == 0:
		MinorsLife.monthly(state, added)
	return added


static func _month(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	_prune(state, m)
	_contacts(state, id, m, added)
	_favor(state, id, m, added)
	_suzerain(state, id, m, added)
	_friends(state, id, m, added)
	_suz_gifts(state, id, m, added)
	_quests(state, id, m, added)
	_levy_end(state, id, m, added, false)
	_posts(state, id, m, added)
	_ages(state, id, m, added)
	_rebuild(state, id, m, added)
	MinorsLife.month(state, id, m, added)
	MinorsBridges.month(state, id, m, added)


static func _prune(state: GameState, m: Dictionary) -> void:
	var keep: Array = []
	for fid in m["fleets"]:
		var f: Fleet = state.fleets.get(int(fid))
		if f != null and not f.ships.is_empty():
			keep.append(int(fid))
	m["fleets"] = keep
	for eid in (m["contact"] as Dictionary).keys():
		var e := state.get_empire(int(eid))
		if e == null or e.eliminated:
			for key in ["contact", "fav", "post", "envoy", "war"]:
				(m[key] as Dictionary).erase(eid)


static func _contacts(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	for e in state.empires:
		if e.eliminated or (m["contact"] as Dictionary).has(e.id):
			continue
		if e.explored.has(int(m["sid"])):
			meet(state, id, e.id, added)


## Premier contact (prop. 9) : faveur de départ selon l'attitude, fenêtre d'événement.
static func meet(state: GameState, id: int, eid: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	if m.is_empty() or (m["contact"] as Dictionary).has(eid):
		return
	(m["contact"] as Dictionary)[eid] = state.tick
	var start := int(data()["attitudes"]["start_fav"].get(String(m["att"]), 0))
	var kd := kind_def(String(m["kind"]))
	if kd.has("first_fav") and int(m.get("first", -1)) < 0:
		start = maxi(start, int(kd["first_fav"]))
		m["first"] = eid
	(m["fav"] as Dictionary)[eid] = start
	var e := state.get_empire(eid)
	added.append(state.add_chronicle("%s découvre %s (%s)." % [e.display_name(), name_of(state, id), age_label(state, id).to_lower()],
			Espionage.private_to(state, [eid])))
	Events.push(state, eid, "min_contact", {"min": id, "system": int(m["sid"])}, added)


static func add_fav(state: GameState, id: int, eid: int, v: int) -> void:
	var m := get_m(state, id)
	if m.is_empty() or not (m["contact"] as Dictionary).has(eid):
		return
	if v > 0 and (grudge(state, id, eid) or at_war_with(state, id, eid)):
		return
	if v > 0 and Research.fx_int(state, eid, "translators") > 0:
		@warning_ignore("integer_division")
		v = v * 3 / 2  # Traducteurs universels (Vael, lot 4 de l'arbre)
	(m["fav"] as Dictionary)[eid] = clampi(fav(state, id, eid) + v, 0, int(data()["favor"]["max"]))


## Émissaires (ordre mensuel en influence) et usure sans entretien (prop. 10).
static func _favor(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	var fd: Dictionary = data()["favor"]
	var envoys: Array = fd["envoys"]
	@warning_ignore("integer_division")
	var decay_now := (state.tick / 30) % maxi(1, int(fd["decay_months"])) == 0
	for eid in _contact_ids(m):
		var e := state.get_empire(eid)
		var lvl := int((m["envoy"] as Dictionary).get(eid, 0))
		if lvl > 0:
			var ed: Dictionary = envoys[clampi(lvl - 1, 0, envoys.size() - 1)]
			var cost := int(ed["influence"])
			if not can_talk(state, id, eid) or at_war_with(state, id, eid) or int(e.resources.get("influence", 0)) < cost:
				(m["envoy"] as Dictionary).erase(eid)
				added.append(state.add_chronicle("%s rappelle son émissaire auprès %s." % [e.display_name(), Crisis.de_name(name_of(state, id))],
						Espionage.private_to(state, [eid])))
			else:
				e.resources["influence"] = int(e.resources.get("influence", 0)) - cost
				add_fav(state, id, eid, int(ed["fav"]))
				continue
		if decay_now and int((m["contact"] as Dictionary)[eid]) < state.tick:
			var cur := fav(state, id, eid)
			if cur > 0:
				(m["fav"] as Dictionary)[eid] = cur - 1


static func _contact_ids(m: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for k in (m["contact"] as Dictionary).keys():
		out.append(int(k))
	out.sort()
	return out


## Le suzerain (prop. 11) : au moins suz_min de faveur et suz_gap de plus que le deuxième.
static func best_suzerain(state: GameState, id: int) -> int:
	var m := get_m(state, id)
	var fd: Dictionary = data()["favor"]
	var best := -1
	var best_v := -1
	var second := -1
	for eid in _contact_ids(m):
		if at_war_with(state, id, eid):
			continue
		var v := fav(state, id, eid)
		if v > best_v:
			second = best_v
			best_v = v
			best = eid
		elif v > second:
			second = v
	if best < 0 or best_v < int(fd["suz_min"]) or best_v - maxi(0, second) < int(fd["suz_gap"]):
		return -1
	return best


static func _suzerain(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	var now := best_suzerain(state, id)
	var was := int(m["suz"])
	if now == was or MinorsLife.suz_locked(state, id, m):
		return
	set_suzerain(state, id, now, added)


static func set_suzerain(state: GameState, id: int, now: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	var was := int(m["suz"])
	if was >= 0:
		_levy_end(state, id, m, added, true)
		MinorsLife.on_suz_lost(state, id, was, added)
	m["suz"] = now
	m["suz_since"] = state.tick
	Relics.touch(state)
	if now < 0:
		if was >= 0 and state.get_empire(was) != null:
			added.append(state.add_chronicle("%s ne reconnaît plus %s pour suzerain." % [name_of(state, id), state.get_empire(was).display_name()],
					Espionage.private_to(state, [was])))
		return
	var e := state.get_empire(now)
	added.append(state.add_chronicle("%s prête serment à %s : nouveau suzerain%s." % [name_of(state, id), e.display_name(),
			(", au détriment de %s" % state.get_empire(was).display_name()) if was >= 0 and state.get_empire(was) != null else ""]))
	var gd := gift_def(state, id)
	if gd.has("eureka_days"):
		m["eureka"] = state.tick + int(gd["eureka_days"])
	if gd.has("hero") and not (m["given"] as Dictionary).has(now):
		(m["given"] as Dictionary)[now] = 1
		var hd: Dictionary = gd["hero"]
		Quests.give_hero(state, now, String(hd.get("name", "Héros")), String(hd.get("cls", "orateur")))
		added.append(state.add_chronicle("%s offre à %s son %s. Le héros arrive avec une piste d'atterrissage en bambou sous le bras." % [
				name_of(state, id), e.display_name(), String(hd.get("name", "héros"))], Espionage.private_to(state, [now])))
	Events.push(state, now, "min_suzerain", {"min": id, "system": int(m["sid"])}, added)


## Bonus d'amitié (prop. 12) : chaque ami reçoit les ressources de l'orientation du peuple.
static func _friends(state: GameState, id: int, m: Dictionary, _added: Array[Dictionary]) -> void:
	var od := orientation(state, id)
	var res: Dictionary = od.get("friend", {})
	for eid in _contact_ids(m):
		if not tier_at_least(state, id, eid, "ami"):
			continue
		var e := state.get_empire(eid)
		var x := MinorsLife.friend_mult(state, id, eid)
		for r in res:
			e.resources[r] = int(e.resources.get(r, 0)) + int(res[r]) * x


## Cadeaux de suzerain qui ne sont pas des effets permanents : les eurêkas (Lumen, Tharsis).
static func _suz_gifts(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	var s := int(m["suz"])
	if s < 0:
		return
	var gd := gift_def(state, id)
	if gd.has("eureka_days") and state.tick >= int(m.get("eureka", 0)):
		m["eureka"] = state.tick + int(gd["eureka_days"])
		var e := state.get_empire(s)
		if e != null and not e.research_queue.is_empty():
			var tid := String(e.research_queue[0])
			@warning_ignore("integer_division")
			Research.add_progress(state, s, tid, Research.cost(state, s, tid) / 4)
			added.append(state.add_chronicle("Eurêka ! %s souffle à %s une idée pour « %s »." % [name_of(state, id), e.display_name(),
					String(Research.tech(tid).get("label", tid))], Espionage.private_to(state, [s])))
	MinorsBridges.suz_gift(state, id, m, s, added)


# --- Quêtes (prop. 13) ------------------------------------------------------------------------------

static func quest_def(qid: String) -> Dictionary:
	return _find(data()["quests"]["list"], qid)


static func _quests(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	var qd: Dictionary = data()["quests"]
	var q: Dictionary = m["quest"]
	if not q.is_empty():
		var winner := _quest_winner(state, id, m, q)
		if winner >= 0:
			complete_quest(state, id, winner, added)
		elif state.tick > int(q["until"]) or int(q.get("dead", 0)) == 1:
			m["quest"] = {}
			m["quest_next"] = state.tick + int(qd["every_days"])
		return
	if state.tick < int(m["quest_next"]) or (m["contact"] as Dictionary).is_empty():
		return
	var cands: Array = []
	for d: Dictionary in qd["list"]:
		var nq := _make_quest(state, id, m, d)
		if not nq.is_empty():
			cands.append(nq)
	m["quest_next"] = state.tick + int(qd["every_days"])
	if cands.is_empty():
		return
	q = cands[_h(state, ["quete", id, state.tick]) % cands.size()]
	q["until"] = state.tick + int(qd["expire_days"])
	m["quest"] = q
	for eid in _contact_ids(m):
		if can_talk(state, id, eid):
			Events.push(state, eid, "min_quest", {"min": id, "system": int(m["sid"])}, added)


static func _make_quest(state: GameState, id: int, m: Dictionary, d: Dictionary) -> Dictionary:
	var q := {"id": String(d["id"])}
	if d.has("deliver"):
		return q
	if bool(d.get("tech", false)):
		var opts: Array = []
		for tid in Research.data().get("technologies", {}):
			var t: Dictionary = Research.tech(String(tid))
			if int(t.get("era", 1)) > 2 or t.has("faction") or t.has("heretic") or t.has("requires_trait"):
				continue
			var nobody := true
			for eid in _contact_ids(m):
				if state.get_empire(eid).techs.has(String(tid)):
					nobody = false
					break
			if nobody:
				opts.append(String(tid))
		if opts.is_empty():
			return {}
		opts.sort()
		q["tech"] = String(opts[_h(state, ["quete_techno", id, state.tick]) % opts.size()])
		return q
	if d.has("lair_jumps"):
		var jumps := FactionTraits.jumps_from(state.galaxy, int(m["sid"]))
		var best := -1
		var best_j := int(d["lair_jumps"]) + 1
		for sid in Pirates.lair_ids(state):
			var j := int(jumps.get(sid, 999))
			if j < best_j:
				best_j = j
				best = sid
		if best < 0:
			return {}
		q["lair"] = best
		return q
	if d.has("guard_days"):
		q["guard"] = {}
		return q
	if bool(d.get("faith", false)):
		if not state.faith_on:
			return {}
		return q
	return {}


static func _quest_winner(state: GameState, id: int, m: Dictionary, q: Dictionary) -> int:
	var d := quest_def(String(q["id"]))
	if q.has("tech"):
		for eid in _contact_ids(m):
			if state.get_empire(eid).techs.has(String(q["tech"])):
				return eid
	elif q.has("lair"):
		var sid := int(q["lair"])
		if not state.lairs.has(sid):
			var near: Array = [sid] + Array(state.galaxy.systems[sid].neighbors)
			for eid in _contact_ids(m):
				for s2 in near:
					for f in Fleets.fleets_at(state, int(s2), eid):
						if Combat.is_armed(f):
							return eid
			q["dead"] = 1
	elif q.has("guard"):
		var need := maxi(1, int(d.get("guard_days", 30)) / 30)
		var g: Dictionary = q["guard"]
		for eid in _contact_ids(m):
			var here := false
			for f in Fleets.fleets_at(state, int(m["sid"]), eid):
				if Combat.is_armed(f) and not f.is_moving():
					here = true
					break
			if here:
				g[eid] = int(g.get(eid, 0)) + 1
				if int(g[eid]) >= need:
					return eid
			else:
				g.erase(eid)
	elif bool(d.get("faith", false)):
		var c: Colony = state.colonies.get(int(m["planet"]))
		var maj := Faiths.majority(c) if c != null else ""
		if maj != "":
			for eid in _contact_ids(m):
				if Faiths.state_faith(state, eid) == maj:
					return eid
	return -1


static func complete_quest(state: GameState, id: int, eid: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	var qd: Dictionary = data()["quests"]
	var d := quest_def(String((m["quest"] as Dictionary).get("id", "")))
	m["quest"] = {}
	m["quest_next"] = state.tick + int(qd["every_days"])
	add_fav(state, id, eid, int(qd["reward"]))
	var e := state.get_empire(eid)
	added.append(state.add_chronicle("%s remplit la quête %s (« %s ») : faveur +%d." % [e.display_name(), Crisis.de_name(name_of(state, id)),
			String(d.get("label", "")), int(qd["reward"])], Espionage.private_to(state, [eid])))


# --- Levée (prop. 14) -------------------------------------------------------------------------------

static func levy_cost(state: GameState, id: int, eid: int) -> int:
	var ld: Dictionary = data()["levy"]
	var c := int(ld["pre_energy"])
	if not is_pre(state, id):
		@warning_ignore("integer_division")
		c = power(state, id) * int(ld["energy_pct"]) / 100
	var pct := 100
	var gd := gift_def(state, id)
	if gd.has("levy_pct"):
		pct = mini(pct, int(gd["levy_pct"]))
	pct = mini(pct, MinorsBridges.levy_pct(state, eid))
	@warning_ignore("integer_division")
	return maxi(1, c * pct / 100)


static func check_levy(state: GameState, eid: int, id: int) -> String:
	var m := get_m(state, id)
	if suzerain(state, id) != eid:
		return "réservé au suzerain"
	if not (m["levy"] as Dictionary).is_empty():
		return "déjà levés"
	if is_pre(state, id):
		if int(m["age"]) < int(data()["age_rules"]["levy_min_age"]):
			return "il faut l'âge féodal au moins"
	elif fleets_of(state, id).is_empty():
		return "leur flotte n'existe plus"
	var cost := levy_cost(state, id, eid)
	if int(state.get_empire(eid).resources.get("energy", 0)) < cost:
		return "il faut %d énergie" % cost
	return ""


static func levy(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	var e := state.get_empire(eid)
	e.resources["energy"] = int(e.resources.get("energy", 0)) - levy_cost(state, id, eid)
	var lv := {"e": eid, "until": state.tick + int(data()["levy"]["days"]), "fleets": []}
	if not is_pre(state, id):
		for f in fleets_of(state, id):
			f.owner = eid
			(lv["fleets"] as Array).append(f.id)
		m["fleets"] = []
	m["levy"] = lv
	state.garrisons[int(m["sid"])] = mini(int(state.garrisons.get(int(m["sid"]), 0)), Combat.garrison_max(state, int(m["sid"])))
	Relics.touch(state)
	added.append(state.add_chronicle("%s lève %s %s pour deux ans." % [e.display_name(), "la flotte" if not is_pre(state, id) else "les régiments",
			Crisis.de_name(name_of(state, id))], Espionage.private_to(state, [eid])))


## Fin de la levée : au terme, ou dès que la suzeraineté est perdue (now = true).
static func _levy_end(state: GameState, id: int, m: Dictionary, added: Array[Dictionary], now: bool) -> void:
	var lv: Dictionary = m["levy"]
	if lv.is_empty() or (not now and state.tick < int(lv["until"]) and int(m["suz"]) == int(lv["e"])):
		return
	for fid in lv["fleets"]:
		var f: Fleet = state.fleets.get(int(fid))
		if f == null or f.ships.is_empty():
			continue
		f.owner = id
		(m["fleets"] as Array).append(f.id)
		if f.system_id != int(m["sid"]) or f.is_moving():
			var route := Fleets.plan_route(state, f, int(m["sid"]))
			if not route.is_empty():
				f.system_id = int(route["system"])
				f.path.assign(route["path"])
				f.progress = int(route["progress"])
	m["levy"] = {}
	Relics.touch(state)
	var e := state.get_empire(int(lv["e"]))
	if e != null:
		added.append(state.add_chronicle("Les troupes %s rentrent chez elles." % Crisis.de_name(name_of(state, id)), Espionage.private_to(state, [int(lv["e"])])))


# --- Poste d'observation et âges (prop. 6-7) --------------------------------------------------------

static func check_post(state: GameState, eid: int, id: int, mode: String) -> String:
	if not is_pre(state, id):
		return "seulement au-dessus d'un pré-spatial"
	if not in_contact(state, id, eid):
		return "vous ne les connaissez pas"
	var od: Dictionary = data()["observation"]
	if not (od["knowledge"] as Dictionary).has(mode):
		return "mode inconnu"
	if MinorsBridges.post_banned(state, mode):
		return "interdit par la loi de l'Amphictyonie"
	if has_post(state, id, eid):
		return "" if post_mode(state, id, eid) != mode else "déjà en place"
	var e := state.get_empire(eid)
	for r in od["cost"]:
		if int(e.resources.get(r, 0)) < int(od["cost"][r]):
			return "il faut %d %s" % [int(od["cost"][r]), GameData.resource_label(String(r)).to_lower()]
	return ""


static func set_post(state: GameState, eid: int, id: int, mode: String, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	var e := state.get_empire(eid)
	if not has_post(state, id, eid):
		var od: Dictionary = data()["observation"]
		for r in od["cost"]:
			e.resources[r] = int(e.resources.get(r, 0)) - int(od["cost"][r])
		added.append(state.add_chronicle("%s place un poste d'observation au-dessus %s (%s)." % [e.display_name(), Crisis.de_name(name_of(state, id)), mode],
				Espionage.private_to(state, [eid])))
	(m["post"] as Dictionary)[eid] = mode


static func _posts(state: GameState, id: int, m: Dictionary, _added: Array[Dictionary]) -> void:
	var od: Dictionary = data()["observation"]
	for eid in _contact_ids(m):
		var mode := post_mode(state, id, eid)
		if mode == "":
			continue
		var e := state.get_empire(eid)
		var k := int(od["knowledge"].get(mode, 0))
		@warning_ignore("integer_division")
		k = k * (100 + MinorsBridges.post_pct(state)) / 100
		e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + k


## Jours qu'il faut pour achever l'âge en cours.
static func age_need(state: GameState, id: int) -> int:
	var m := get_m(state, id)
	var ar: Dictionary = data()["age_rules"]
	var pcts: Array = ar["aware_pct"]
	var lvl := MinorsLife.aware_level(state, id)
	@warning_ignore("integer_division")
	return maxi(360, int(age_def(int(m["age"]))["years"]) * 360 * int(pcts[clampi(lvl, 0, pcts.size() - 1)]) / 100)


## Les âges avancent seuls (prop. 6), deux fois plus vite après fast_after_years ans.
static func _ages(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	if not is_pre(state, id):
		return
	var ar: Dictionary = data()["age_rules"]
	var step := 30
	if state.tick >= int(ar["fast_after_years"]) * 360:
		step *= 2
	step *= MinorsLife.age_mult(state, id)
	m["age_days"] = int(m["age_days"]) + step
	if int(m["age_days"]) < age_need(state, id):
		return
	var ages: Array = data()["ages"]
	if int(m["age"]) >= ages.size() - 1:
		MinorsLife.rise(state, id, added)  # l'Aube spatiale achevée : l'Avènement (lot 2)
		return
	m["age"] = int(m["age"]) + 1
	m["age_days"] = 0
	var c: Colony = state.colonies.get(int(m["planet"]))
	if c != null:
		c.population = maxi(c.population, int(age_def(int(m["age"]))["pop"]))
	state.garrisons[int(m["sid"])] = Combat.garrison_max(state, int(m["sid"]))
	for eid in _contact_ids(m):
		if has_post(state, id, eid):
			Events.push(state, eid, "min_age", {"min": id, "system": int(m["sid"])}, added)


## Les régiments du peuple se reconstituent : la cité-État reconstruit sa flotte détruite, en paix.
static func _rebuild(state: GameState, id: int, m: Dictionary, _added: Array[Dictionary]) -> void:
	if is_pre(state, id) or not (m["levy"] as Dictionary).is_empty() or not (m["war"] as Dictionary).is_empty():
		return
	if not fleets_of(state, id).is_empty():
		m["rebuild"] = 0
		return
	if int(m["rebuild"]) == 0:
		m["rebuild"] = state.tick + int(data()["space"]["rebuild_days"])
	elif state.tick >= int(m["rebuild"]):
		m["rebuild"] = 0
		spawn_fleet(state, id)


# --- Faveur : émissaires, cadeaux (prop. 10) --------------------------------------------------------

static func check_envoy(state: GameState, eid: int, id: int, lvl: int) -> String:
	if lvl < 0 or lvl > (data()["favor"]["envoys"] as Array).size():
		return "intensité inconnue"
	if lvl == 0:
		return "" if int((get_m(state, id)["envoy"] as Dictionary).get(eid, 0)) > 0 else "pas d'émissaire"
	if not can_talk(state, id, eid):
		return "il faut un poste d'observation" if is_pre(state, id) and in_contact(state, id, eid) else "vous ne les connaissez pas"
	if at_war_with(state, id, eid):
		return "en guerre avec eux"
	var cost := int((data()["favor"]["envoys"] as Array)[lvl - 1]["influence"])
	if int(state.get_empire(eid).resources.get("influence", 0)) < cost:
		return "il faut %d influence par mois" % cost
	return ""


static func set_envoy(state: GameState, eid: int, id: int, lvl: int) -> void:
	var m := get_m(state, id)
	if lvl <= 0:
		(m["envoy"] as Dictionary).erase(eid)
	else:
		(m["envoy"] as Dictionary)[eid] = lvl


static func envoy_level(state: GameState, id: int, eid: int) -> int:
	return int((get_m(state, id).get("envoy", {}) as Dictionary).get(eid, 0))


static func check_gift(state: GameState, eid: int, id: int, res: String) -> String:
	var gd: Dictionary = data()["favor"]["gifts"]
	if not gd.has(res):
		return "cadeau inconnu"
	if not can_talk(state, id, eid):
		return "il faut un poste d'observation" if is_pre(state, id) and in_contact(state, id, eid) else "vous ne les connaissez pas"
	if at_war_with(state, id, eid):
		return "en guerre avec eux"
	if grudge(state, id, eid):
		return "ils n'ont pas oublié votre attaque"
	if state.tick < int((get_m(state, id)["gift_cd"] as Dictionary).get(eid, -1)):
		return "un cadeau par mois"
	if int(state.get_empire(eid).resources.get(res, 0)) < int(gd[res]["cost"]):
		return "il faut %d %s" % [int(gd[res]["cost"]), GameData.resource_label(res).to_lower()]
	return ""


static func gift(state: GameState, eid: int, id: int, res: String) -> void:
	var gd: Dictionary = data()["favor"]["gifts"][res]
	var e := state.get_empire(eid)
	e.resources[res] = int(e.resources.get(res, 0)) - int(gd["cost"])
	(get_m(state, id)["gift_cd"] as Dictionary)[eid] = state.tick + int(data()["favor"]["gift_cd_days"])
	add_fav(state, id, eid, int(gd["fav"]))
	MinorsBridges.on_gift(state, id, eid)


static func check_deliver(state: GameState, eid: int, id: int) -> String:
	var q: Dictionary = get_m(state, id).get("quest", {})
	var d := quest_def(String(q.get("id", "")))
	if q.is_empty() or not d.has("deliver"):
		return "pas de livraison demandée"
	if not can_talk(state, id, eid):
		return "vous ne pouvez pas leur parler"
	var e := state.get_empire(eid)
	for r in d["deliver"]:
		if int(e.resources.get(r, 0)) < int(d["deliver"][r]):
			return "il faut %d %s" % [int(d["deliver"][r]), GameData.resource_label(String(r)).to_lower()]
	return ""


static func deliver(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var d := quest_def(String((get_m(state, id)["quest"] as Dictionary)["id"]))
	var e := state.get_empire(eid)
	for r in d["deliver"]:
		e.resources[r] = int(e.resources.get(r, 0)) - int(d["deliver"][r])
	complete_quest(state, id, eid, added)


# --- Intégration pacifique (prop. 17) ---------------------------------------------------------------

static func integration_cost(state: GameState, id: int, eid: int) -> int:
	var ig: Dictionary = data()["integration"]
	var done := int((state.minors.get("done", {}) as Dictionary).get(eid, 0))
	var c := int(ig["base"]) + int(ig["per_done"]) * done
	var pct := MinorsLife.decline_pct(state, id, eid)
	pct = mini(pct, MinorsBridges.integ_pct(state, id, eid))
	@warning_ignore("integer_division")
	return maxi(1, c * pct / 100)


static func check_integrate(state: GameState, eid: int, id: int) -> String:
	var ig: Dictionary = data()["integration"]
	var m := get_m(state, id)
	var declining := MinorsLife.declining(state, id)
	if not declining:
		if suzerain(state, id) != eid:
			return "réservé au suzerain"
		if state.tick - int(m["suz_since"]) < int(ig["suz_days"]):
			return "suzerain depuis deux ans au moins"
		if fav(state, id, eid) < int(ig["fav"]):
			return "il faut %d de faveur" % int(ig["fav"])
	elif not can_talk(state, id, eid) or at_war_with(state, id, eid):
		return "vous ne pouvez pas leur parler"
	var cost := integration_cost(state, id, eid)
	if int(state.get_empire(eid).resources.get("influence", 0)) < cost:
		return "il faut %d influence" % cost
	return ""


static func integrate(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	var e := state.get_empire(eid)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - integration_cost(state, id, eid)
	var done: Dictionary = state.minors["done"]
	done[eid] = int(done.get(eid, 0)) + 1
	var ig: Dictionary = data()["integration"]
	# « Il m'a volé mon protégé » chez ceux qui l'aimaient.
	for o in _contact_ids(m):
		if o != eid and fav(state, id, o) >= int(ig["stolen_fav"]):
			Diplomacy.remember(state, o, eid, "vol_protege")
	_levy_end(state, id, m, added, true)
	var sid := int(m["sid"])
	var sp := species_id(state, id)
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != id:
			continue
		Peoples.on_owner_change(state, c, id, eid)
		c.owner = eid
		if c.integ.has(sp):
			c.integ[sp] = int(ig["integ"])
	for f in fleets_of(state, id):
		f.owner = eid
	state.rebuild_ownership()
	state.garrisons[sid] = Combat.garrison_max(state, sid)
	added.append(state.add_chronicle("%s rejoint %s de son plein gré. Les drapeaux changent ; les fêtes, elles, durent une semaine." % [name_of(state, id), e.display_name()]))
	Events.push(state, eid, "min_integrated", {"min": id, "system": sid}, added)
	absorb(state, eid, String(m["kind"]))
	_remove(state, id)
	for o in state.empires:
		o.path_cache.clear()


## Le peuple disparaît de la liste (intégré, conquis, dispersé, éteint).
static func _remove(state: GameState, id: int) -> void:
	var m := get_m(state, id)
	if m.is_empty():
		return
	(state.minors["gone"] as Dictionary)[String(m["kind"])] = 1
	(state.minors["list"] as Dictionary).erase(id)
	Relics.touch(state)


# --- Traits d'assimilation (prop. 21) ---------------------------------------------------------------

static func absorbed(state: GameState, eid: int) -> Array:
	if state.minors.is_empty():
		return []
	return (state.minors.get("absorbed", {}) as Dictionary).get(eid, [])


static func active_traits(state: GameState, eid: int) -> Array:
	if state.minors.is_empty():
		return []
	return (state.minors.get("active", {}) as Dictionary).get(eid, [])


static func trait_slots(state: GameState, eid: int) -> int:
	var td: Dictionary = data()["traits"]
	var n := int(td["base_slots"])
	var e := state.get_empire(eid)
	for t in td["slot_techs"]:
		if e != null and e.techs.has(String(t)):
			n += 1
	return n


static func trait_def(kind: String) -> Dictionary:
	return kind_def(kind).get("trait", {})


## Un peuple absorbé : son trait rejoint la liste, actif s'il reste un emplacement.
static func absorb(state: GameState, eid: int, kind: String) -> void:
	if state.minors.is_empty() or GameState.is_npc(eid) or kind_def(kind).is_empty():
		return
	var ab: Dictionary = state.minors["absorbed"]
	if not ab.has(eid):
		ab[eid] = []
	if not (ab[eid] as Array).has(kind):
		(ab[eid] as Array).append(kind)
	var ac: Dictionary = state.minors["active"]
	if not ac.has(eid):
		ac[eid] = []
	if not (ac[eid] as Array).has(kind) and (ac[eid] as Array).size() < trait_slots(state, eid):
		(ac[eid] as Array).append(kind)
	Relics.touch(state)


static func check_trait(state: GameState, eid: int, kind: String) -> String:
	if not absorbed(state, eid).has(kind):
		return "trait inconnu"
	if active_traits(state, eid).has(kind):
		return "déjà actif"
	if active_traits(state, eid).size() >= trait_slots(state, eid):
		var cost := int(data()["traits"]["swap_cost"])
		if int(state.get_empire(eid).resources.get("influence", 0)) < cost:
			return "il faut %d influence pour changer de trait" % cost
	return ""


static func set_trait(state: GameState, eid: int, kind: String) -> void:
	var ac: Dictionary = state.minors["active"]
	if not ac.has(eid):
		ac[eid] = []
	var arr: Array = ac[eid]
	if arr.size() >= trait_slots(state, eid):
		var e := state.get_empire(eid)
		e.resources["influence"] = int(e.resources.get("influence", 0)) - int(data()["traits"]["swap_cost"])
		arr.pop_front()
	arr.append(kind)
	Relics.touch(state)


# --- Guerre et conquête (prop. 18) ------------------------------------------------------------------

static func check_war(state: GameState, eid: int, id: int) -> String:
	if not in_contact(state, id, eid):
		return "vous ne les connaissez pas"
	if at_war_with(state, id, eid):
		return "déjà en guerre"
	if suzerain(state, id) == eid:
		return "vous êtes leur suzerain"
	return MinorsBridges.war_banned(state, eid, id)


static func declare_war(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	(m["war"] as Dictionary)[eid] = state.tick
	(m["fav"] as Dictionary)[eid] = 0
	(m["envoy"] as Dictionary).erase(eid)
	(m["grudge"] as Dictionary)[eid] = state.tick + int(data()["favor"]["grudge_days"])
	for o in state.empires:
		o.path_cache.clear()
	MinorsBridges.on_war(state, eid, id, added)
	added.append(state.add_chronicle("%s attaque %s. Les autres peuples mineurs prennent note." % [state.get_empire(eid).display_name(), name_of(state, id)]))


static func check_peace(state: GameState, eid: int, id: int) -> String:
	var w: Dictionary = data()["war"]
	if not at_war_with(state, id, eid):
		return "pas en guerre avec eux"
	if state.tick - int(get_m(state, id)["war"][eid]) < int(w["peace_days"]):
		return "trop tôt : six mois de guerre au moins"
	if int(state.get_empire(eid).resources.get("influence", 0)) < int(w["peace_cost"]):
		return "il faut %d influence" % int(w["peace_cost"])
	return ""


static func peace(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	var e := state.get_empire(eid)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - int(data()["war"]["peace_cost"])
	(m["war"] as Dictionary).erase(eid)
	for o in state.empires:
		o.path_cache.clear()
	added.append(state.add_chronicle("%s fait la paix avec %s. La rancune, elle, reste." % [e.display_name(), name_of(state, id)], Espionage.private_to(state, [eid])))


## Motif « Protection » (Wars, req « protection ») : a était le suzerain d'un peuple que b a conquis.
static func protection_casus(state: GameState, a: int, b: int) -> bool:
	if state.minors.is_empty():
		return false
	var p: Dictionary = (state.minors.get("prot", {}) as Dictionary).get(a, {})
	return state.tick < int(p.get(b, -1))


## Prise d'un système (Combat.capture_system) : conquête d'un peuple mineur, ou libération (prop. 18).
static func on_capture(state: GameState, sid: int, new_owner: int, old: int, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	if GameState.is_minor(old) and not get_m(state, old).is_empty():
		var c: Colony = state.colonies.get(int(get_m(state, old)["planet"]))
		if c == null or c.owner != old:
			_conquered(state, old, sid, new_owner, added)
		return
	_liberation(state, sid, new_owner, added)


static func _conquered(state: GameState, id: int, sid: int, new_owner: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	var cq: Dictionary = data()["conquest"]
	_levy_end(state, id, m, added, true)
	for f in fleets_of(state, id):
		state.fleets.erase(f.id)
	var conqueror := not GameState.is_npc(new_owner)
	if conqueror:
		var lvl := MinorsLife.aware_level(state, id)
		var years: Array = data()["awareness"]["shock_years"]
		Events.apply_fx(state, new_owner, {"id": -1, "card": "min_conquered", "system": sid, "planet": -1, "rival": -1, "hero": -1},
				[{"k": "stab", "v": int(cq["stab"]), "days": int(years[clampi(lvl, 0, years.size() - 1)]) * 360, "scope": "system"}], added)
		for o in _contact_ids(m):
			if o != new_owner and fav(state, id, o) >= int(cq["memory_fav"]):
				Diplomacy.remember(state, o, new_owner, "conquete_mineur")
		var suz := int(m["suz"])
		if suz >= 0 and suz != new_owner:
			var pr: Dictionary = state.minors["prot"]
			if not pr.has(suz):
				pr[suz] = {}
			pr[suz][new_owner] = state.tick + int(cq["casus_days"])
		(state.minors["former"] as Dictionary)[sid] = {"kind": String(m["kind"]), "suz": suz, "until": state.tick + int(cq["liberate_days"]),
				"fam": String(m["fam"]), "age": int(m["age"]), "conq": new_owner, "name": name_of(state, id),
				"orient": String(m.get("orientation", kind_def(String(m["kind"])).get("orientation", "economique")))}
		absorb(state, new_owner, String(m["kind"]))
		MinorsBridges.on_conquest(state, id, new_owner, added)
		added.append(state.add_chronicle("%s conquiert %s. Choc culturel garanti." % [state.get_empire(new_owner).display_name(), name_of(state, id)]))
		Events.push(state, new_owner, "min_conquered" if is_pre(state, id) else "min_conquered_space", {"min": id, "system": sid}, added)
	else:
		added.append(state.add_chronicle("%s tombe aux mains de %s." % [name_of(state, id), state.get_empire(new_owner).display_name()]))
	_remove(state, id)


## Libérer un peuple conquis fait de vous son suzerain : on reprend son monde dans le délai.
static func _liberation(state: GameState, sid: int, new_owner: int, added: Array[Dictionary]) -> void:
	var fm: Dictionary = state.minors.get("former", {})
	if not fm.has(sid):
		return
	var f: Dictionary = fm[sid]
	fm.erase(sid)
	if GameState.is_npc(new_owner) or new_owner == int(f.get("conq", -1)) or state.tick > int(f["until"]):
		return
	var pid := -1
	for p in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(p)
		if c != null and c.owner == new_owner and c.is_colony():
			pid = p
			break
	if pid < 0:
		return
	(state.minors["gone"] as Dictionary).erase(String(f["kind"]))
	var c2: Colony = state.colonies[pid]
	var id := create(state, String(f["kind"]), sid, pid, {"fam": String(f["fam"]), "age": int(f["age"])})
	if id < 0:
		return
	c2.species.clear()
	c2.integ.clear()
	var m := get_m(state, id)
	(m["contact"] as Dictionary)[new_owner] = state.tick
	(m["fav"] as Dictionary)[new_owner] = int(data()["favor"]["max"])
	set_suzerain(state, id, new_owner, added)
	added.append(state.add_chronicle("%s libère %s, qui le reconnaît aussitôt pour suzerain." % [state.get_empire(new_owner).display_name(), name_of(state, id)]))


# --- Commandes du joueur (SimCommands.min_act) ------------------------------------------------------

## act : "envoy" (n = intensité 0-3), "gift" (s = ressource), "post" (s = discret | ouvert), "levy",
## "integrate", "war", "peace", "deliver", "trait" (s = sorte absorbée, x ignoré) ; les actes du lot 2
## et du lot 3 passent par MinorsLife et MinorsBridges.
static func check_act(state: GameState, eid: int, act: String, x: int, s: String, n: int) -> String:
	if not enabled(state):
		return "pas de peuples mineurs dans cette partie"
	var e := state.get_empire(eid)
	if e == null or GameState.is_npc(eid) or e.eliminated:
		return "empire inconnu"
	if act == "trait":
		return check_trait(state, eid, s)
	if act == "elevate":
		return MinorsLife.check_global(state, eid, act, n)
	if not GameState.is_minor(x) or get_m(state, x).is_empty():
		return "peuple inconnu"
	if not in_contact(state, x, eid):
		return "vous ne les connaissez pas"
	match act:
		"envoy":
			return check_envoy(state, eid, x, n)
		"gift":
			return check_gift(state, eid, x, s)
		"post":
			return check_post(state, eid, x, s)
		"levy":
			return check_levy(state, eid, x)
		"integrate":
			return check_integrate(state, eid, x)
		"war":
			return check_war(state, eid, x)
		"peace":
			return check_peace(state, eid, x)
		"deliver":
			return check_deliver(state, eid, x)
	var r := MinorsLife.check_act(state, eid, act, x, s, n)
	if r != "?":
		return r
	return MinorsBridges.check_act(state, eid, act, x, s, n)


static func act(state: GameState, eid: int, act_id: String, x: int, s: String, n: int, added: Array[Dictionary]) -> void:
	match act_id:
		"trait":
			set_trait(state, eid, s)
		"elevate":
			MinorsLife.elevate(state, eid, n, added)
		"envoy":
			set_envoy(state, eid, x, n)
		"gift":
			gift(state, eid, x, s)
		"post":
			set_post(state, eid, x, s, added)
		"levy":
			levy(state, eid, x, added)
		"integrate":
			integrate(state, eid, x, added)
		"war":
			declare_war(state, eid, x, added)
		"peace":
			peace(state, eid, x, added)
		"deliver":
			deliver(state, eid, x, added)
		_:
			if not MinorsLife.act(state, eid, act_id, x, s, n, added):
				MinorsBridges.act(state, eid, act_id, x, s, n, added)


# --- Effets (format des technologies) ---------------------------------------------------------------

## Effets pour un empire : cadeaux des peuples dont il est suzerain, régiments levés, traits actifs.
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not enabled(state):
		return out
	for id in ids(state):
		var m := get_m(state, id)
		if int(m["suz"]) == eid:
			var gd := gift_def(state, id)
			var fx: Dictionary = gd.get("fx", {})
			for i in MinorsLife.gift_mult(state, id, eid):
				Research._merge(out, fx)
		var lv: Dictionary = m["levy"]
		if not lv.is_empty() and int(lv["e"]) == eid and is_pre(state, id):
			Research._merge(out, data()["levy"]["pre_fx"])
	for k in active_traits(state, eid):
		Research._merge(out, trait_def(String(k)).get("fx", {}))
	Research._merge(out, MinorsLife.effects(state, eid))
	return out


# --- Cartes : textes, jetons, IA --------------------------------------------------------------------

static func card_fx(state: GameState, eid: int, item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	var id := int(item.get("min", -1))
	if String(fx.get("act", "")) == "disperse":
		MinorsLife.disperse(state, eid, int(item.get("system", -1)), added)
		return
	if get_m(state, id).is_empty():
		return
	var e := state.get_empire(eid)
	match String(fx.get("act", "")):
		"gift":
			var r := String(fx.get("res", "energy"))
			var v := int(fx.get("v", 0))
			if int(e.resources.get(r, 0)) >= v:
				e.resources[r] = int(e.resources.get(r, 0)) - v
				add_fav(state, id, eid, int(fx.get("fav", 0)))
		_:
			MinorsLife.card_fx(state, eid, item, fx, added)


static func fx_line(state: GameState, item: Dictionary, fx: Dictionary) -> String:
	var id := int(item.get("min", -1))
	match String(fx.get("act", "")):
		"gift":
			return "faveur %s +%d" % [Crisis.de_name(short_of(state, id)), int(fx.get("fav", 0))]
	return MinorsLife.fx_line(state, item, fx)


## Ligne de fiche : famille, âge, attitude, orientation.
static func line(state: GameState, id: int) -> String:
	var m := get_m(state, id)
	var at := String(data()["attitudes"]["labels"].get(String(m.get("att", "neutre")), ""))
	var fam := "Pré-spatial, âge %s" % age_label(state, id).to_lower() if is_pre(state, id) else "Cité-État spatiale"
	return "%s. Attitude : %s. Orientation : %s." % [fam, at.to_lower(), String(orientation(state, id).get("label", "")).to_lower()]


static func fill(state: GameState, _eid: int, item: Dictionary, s: String) -> String:
	if not s.contains("{min"):
		return s
	var id := int(item.get("min", -1))
	var m := get_m(state, id)
	var fm: Dictionary = (state.minors.get("former", {}) as Dictionary).get(int(item.get("system", -1)), {}) if not state.minors.is_empty() else {}
	var kd := kind_def(String(m.get("kind", fm.get("kind", ""))))
	var gd := gift_def(state, id)
	var q: Dictionary = m.get("quest", {})
	var out := s.replace("{min_blurb}", String(kd.get("blurb", "Un peuple qui ne demandait rien à personne.")))
	out = out.replace("{min_line}", line(state, id) if not m.is_empty() else "")
	out = out.replace("{min_gift}", "%s : %s" % [String(gd.get("label", "")), String(gd.get("text", ""))])
	out = out.replace("{min_age}", age_label(state, id).to_lower())
	out = out.replace("{min_quest}", quest_text(state, id) if not q.is_empty() else "")
	out = out.replace("{min_reward}", str(int(data()["quests"]["reward"])))
	out = out.replace("{min_loot}", _res_text(orientation_def(String(fm.get("orient", "economique"))).get("loot", {})))
	out = out.replace("{min}", name_of(state, id) if not m.is_empty() else String(fm.get("name", kd.get("name", "Un peuple mineur"))))
	return out


static func quest_text(state: GameState, id: int) -> String:
	var q: Dictionary = get_m(state, id).get("quest", {})
	if q.is_empty():
		return ""
	var d := quest_def(String(q["id"]))
	var t := String(d.get("text", ""))
	if q.has("tech"):
		t += " (%s)" % String(Research.tech(String(q["tech"])).get("label", q["tech"]))
	if q.has("lair"):
		t += " (%s)" % state.galaxy.systems[int(q["lair"])].system_name
	return t


static func ai_value(state: GameState, eid: int, item: Dictionary, fx: Dictionary, temper: int) -> int:
	return int(fx.get("ai", 0)) * 25 + MinorsLife.ai_value(state, eid, item, fx, temper)


# --- Sauvegarde -------------------------------------------------------------------------------------

const INT_MAPS := ["fav", "contact", "post", "envoy", "grudge", "war", "gift_cd", "given", "acc", "prog", "decl", "infil", "ops"]


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.minors)


static func _ikeys(d: Variant) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k in d:
			out[int(k) if String(k).is_valid_int() else k] = d[k]
	return out


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.minors = {}
	if d.is_empty():
		return
	var src: Dictionary = GameData._to_ints(d.duplicate(true))
	var out := {"mode": String(src.get("mode", "normal")), "list": {}, "absorbed": _ikeys(src.get("absorbed", {})),
			"active": _ikeys(src.get("active", {})), "done": _ikeys(src.get("done", {})), "prot": {},
			"former": _ikeys(src.get("former", {})), "gone": src.get("gone", {})}
	for k in src.get("prot", {}):
		out["prot"][int(k)] = _ikeys(src["prot"][k])
	for k in ["pres", "elev"]:
		if src.has(k):
			out[k] = _ikeys(src[k])
	for k in src.get("list", {}):
		var m: Dictionary = src["list"][k]
		for key in INT_MAPS:
			if m.has(key):
				m[key] = _ikeys(m[key])
		var q: Dictionary = m.get("quest", {})
		if q.has("guard"):
			q["guard"] = _ikeys(q["guard"])
		m["kind"] = String(m["kind"])
		out["list"][int(k)] = m
	state.minors = out
