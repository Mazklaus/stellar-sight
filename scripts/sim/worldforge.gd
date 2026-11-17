class_name WorldForge
extends RefCounted
## La Forge des mondes (étude du 2026-11-17, 42 propositions validées ; données : data/worldforge.json).
##
## Créer des mondes (agglomération, compression, habitat-monde et ses modules, coquille, monde creux,
## planète sur mesure), en démanteler (démantèlement, évacuation) et en déplacer (moteurs, rosettes).
## Un chantier planétaire (prop. 2) est un projet posé sur un corps céleste : un Vaisseau-architecte
## présent dans le système le lance (un chantier par système, rules.slots à la fois par empire), il dure
## un nombre de jours puis change le corps. Les ordres passent par SimCommands.forge_act.
##
## Réglage « Forge des mondes » (prop. 1) : Complète, Sans démantèlement, Désactivée (state.forge vide) ;
## mondes anciens Aucun, Peu, Beaucoup (prop. 27). Sans l'option (tests, bancs, anciennes parties) :
## désactivée, et la partie se joue exactement comme avant.
##
## Corps nouveaux (habitat, sur mesure) : ajoutés au bout de galaxy.planets, retenus dans "added" pour
## les reconstruire quand la galaxie est régénérée (restore_bodies, appelé avant planet_overrides) ;
## un corps démantelé quitte son système ("gone"), un corps déplacé en change ("moved").
##
## État : state.forge = {"mode", "anc", "next", "base_n": planètes à la création, "jobs": {"id": chantier},
##  "plans": {"flotte": {"op", "s", "p", "a"}}, "mass": {"eid": Masse}, "worlds": {"pid": {"k": type
##  façonné, "o": créateur, "integ": intégrité, "mods": modules, "eng": moteurs}}, "added": [[système,
##  type, taille, rang]], "gone": {"pid": 1}, "moved": {"pid": [système, rang]}, "moving": {"pid": {"to",
##  "w", "o"}}, "rosettes": {"sid": {"o", "unpaid"}}, "relics": {"pid": {...}}, "carcass": {"sid": {...}},
##  "debris": {"pid": 1}, "void": {"sid": 1}, "st": {"eid": {statistiques}}, "total_dism", "braderie"}.
## Chantier : {"id", "op", "o": empire, "s": système, "p": planète (-1 = orbite vide), "w": jours restants,
##  "tot": durée, "a": argument (type choisi), "for": acheteur d'une commande (-1), "b": bâtisseur}.
## Tout est déterministe : entiers, tirages par hachage de la graine, ordres par SimCommands.

const SUBS := ["jobs", "plans", "mass", "worlds", "gone", "moved", "moving", "rosettes", "relics", "carcass", "debris", "void", "st", "first"]


static func data() -> Dictionary:
	return GameData.worldforge()


static func cfg(section: String) -> Dictionary:
	var v: Variant = data().get(section, {})
	return v if v is Dictionary else {}


static func r_int(key: String, def := 0) -> int:
	var v: Variant = cfg("rules").get(key, def)
	return int(v) if (v is int or v is float) else def


static func r_dict(key: String) -> Dictionary:
	var v: Variant = cfg("rules").get(key, {})
	return v if v is Dictionary else {}


static func op_def(op: String) -> Dictionary:
	var v: Variant = cfg("ops").get(op, {})
	return v if v is Dictionary else {}


static func op_ids() -> Array[String]:
	var out: Array[String] = []
	for k in cfg("ops"):
		out.append(String(k))
	return out


static func op_label(op: String) -> String:
	var d := op_def(op)
	if d.is_empty():
		return String((cfg("instant").get(op, {}) as Dictionary).get("label", op))
	return String(d.get("label", op))


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func ancient_defs() -> Array:
	return data().get("ancient_opts", [])


static func default_ancients() -> String:
	return String(data().get("default_ancients", "peu"))


static func mode(state: GameState) -> String:
	return String(state.forge.get("mode", "desactivee"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.forge.is_empty()


## Démantèlement en jeu (réglage Complète).
static func dismantle_on(state: GameState) -> bool:
	return enabled(state) and mode(state) == "complete"


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode(state):
			return String(m["label"])
	return "Désactivée"


static func applies(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid) if enabled(state) and eid >= 0 else null
	return e != null and not e.is_npc() and not e.eliminated


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func setup(state: GameState, mode_id: String, anc_id := "") -> void:
	state.forge = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactivee":
		return
	var a := anc_id
	var a_ok := false
	for o: Dictionary in ancient_defs():
		if String(o["id"]) == a:
			a_ok = true
	if not a_ok:
		a = default_ancients()
	state.forge = {"mode": mode_id, "anc": a, "next": 1, "base_n": state.galaxy.planets.size(), "added": [], "total_dism": 0, "braderie": 0}
	for k in SUBS:
		state.forge[k] = {}
	WorldForgeWorld.place_relics(state)


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.forge.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.forge = {}
		return
	state.forge = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.forge.has(k):
			state.forge[k] = {}
	if not state.forge.has("added"):
		state.forge["added"] = []


## Reconstruit les corps ajoutés, déplacés ou démantelés (appelé par GameState.from_dict avant les
## modifications de planètes, pour que leurs identifiants existent). Idempotent : une galaxie lue telle
## quelle (instantané) contient déjà les corps ajoutés.
static func restore_bodies(galaxy: Galaxy, d: Dictionary) -> void:
	if d.is_empty() or galaxy == null:
		return
	var base_n := int(d.get("base_n", galaxy.planets.size()))
	var rows: Array = d.get("added", [])
	var touched := {}
	for i in rows.size():
		var row: Array = rows[i]
		var pid := base_n + i
		if pid < galaxy.planets.size():
			continue
		if pid != galaxy.planets.size():
			return  # incohérent : on n'invente rien
		var p := Planet.new()
		p.id = pid
		p.system_id = int(row[0])
		p.type = String(row[1])
		p.size = int(row[2])
		p.index = int(row[3])
		galaxy.planets.append(p)
		if galaxy.get_system(p.system_id) != null and not galaxy.systems[p.system_id].planet_ids.has(pid):
			galaxy.systems[p.system_id].planet_ids.append(pid)
		touched[p.system_id] = true
	var moved: Dictionary = d.get("moved", {})
	for k in moved:
		var pid := int(k)
		var p := galaxy.get_planet(pid)
		var mv: Array = moved[k]
		var to := int(mv[0])
		if p == null or galaxy.get_system(to) == null:
			continue
		for s in galaxy.systems:
			if s.id != to and s.planet_ids.has(pid):
				s.planet_ids.erase(pid)
				touched[s.id] = true
		if not galaxy.systems[to].planet_ids.has(pid):
			galaxy.systems[to].planet_ids.append(pid)
		p.system_id = to
		p.index = int(mv[1])
		touched[to] = true
	var gone: Dictionary = d.get("gone", {})
	for k in gone:
		var p := galaxy.get_planet(int(k))
		if p != null and galaxy.get_system(p.system_id) != null:
			galaxy.systems[p.system_id].planet_ids.erase(p.id)
			touched[p.system_id] = true
	for sid in touched:
		var s := galaxy.get_system(int(sid))
		if s != null:
			s.planet_count = s.planet_ids.size()


static func sub(state: GameState, k: String) -> Dictionary:
	if state.forge.is_empty():
		return {}  # pilier désactivé : ne jamais le rallumer en écrivant
	if not state.forge.has(k):
		state.forge[k] = {}
	return state.forge[k]


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "forge"] + parts))


static func _stat(state: GameState, eid: int, k: String, n: int) -> void:
	if state.forge.is_empty() or eid < 0:
		return
	var st := sub(state, "st")
	var d: Dictionary = st.get(str(eid), {})
	d[k] = int(d.get(k, 0)) + n
	st[str(eid)] = d


static func stat(state: GameState, eid: int, k: String) -> int:
	return int((sub(state, "st").get(str(eid), {}) as Dictionary).get(k, 0))


static func touch(state: GameState) -> void:
	state.relic_rev += 1  # les effets (Research.effects) se recalculent
	for x in state.empires:
		x.hab_cache.clear()


# --- Talents (prop. 35-37) -----------------------------------------------------------------------

static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or GameState.is_npc(eid):
		return {}
	var v: Variant = cfg("talents").get(Genetics.root(e.faction_id), null)
	return v if v is Dictionary else {}


static func t_int(state: GameState, eid: int, key: String) -> int:
	var v: Variant = talent(state, eid).get(key, 0)
	return int(v) if (v is int or v is float) else 0


static func t_bool(state: GameState, eid: int, key: String) -> bool:
	return bool(talent(state, eid).get(key, false))


# --- Masse planétaire (prop. 4) ----------------------------------------------------------------

static func mass(state: GameState, eid: int) -> int:
	return int(sub(state, "mass").get(str(eid), 0))


static func add_mass(state: GameState, eid: int, n: int) -> void:
	if state.forge.is_empty() or eid < 0 or GameState.is_npc(eid):
		return
	sub(state, "mass")[str(eid)] = maxi(0, mass(state, eid) + n)


# --- Corps célestes --------------------------------------------------------------------------------

static func is_gone(state: GameState, pid: int) -> bool:
	return sub(state, "gone").has(str(pid))


static func world(state: GameState, pid: int) -> Dictionary:
	var v: Variant = sub(state, "worlds").get(str(pid), {})
	return v if v is Dictionary else {}


## Le corps est-il un monde façonné (créé ou transformé par la Forge) ?
static func is_made(state: GameState, pid: int) -> bool:
	return enabled(state) and sub(state, "worlds").has(str(pid))


static func is_artificial_type(t: String) -> bool:
	return bool(GameData.planet_type(t).get("artificial", false))


static func _next_index(state: GameState, sid: int) -> int:
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		n = maxi(n, state.galaxy.get_planet(pid).index + 1)
	return n


## Ajoute un corps nouveau au système (habitat, planète sur mesure). Renvoie son identifiant.
static func add_body(state: GameState, sid: int, t: String, size: int) -> int:
	var p := Planet.new()
	p.id = state.galaxy.planets.size()
	p.system_id = sid
	p.type = t
	p.size = size
	p.index = _next_index(state, sid)
	state.galaxy.planets.append(p)
	var s := state.galaxy.systems[sid]
	s.planet_ids.append(p.id)
	s.planet_count = s.planet_ids.size()
	(state.forge["added"] as Array).append([sid, t, size, p.index])
	return p.id


## Retire un corps de son système (démantelé, percuté) : sa colonie et ce qu'il porte disparaissent.
static func remove_body(state: GameState, pid: int) -> void:
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return
	if state.colonies.has(pid):
		state.colonies.erase(pid)
		state.rebuild_ownership()
	for m in Megastructures.in_system(state, p.system_id):
		if int(m["p"]) == pid:
			Megastructures.entries(state).erase(str(int(m["id"])))
	var s := state.galaxy.systems[p.system_id]
	s.planet_ids.erase(pid)
	s.planet_count = s.planet_ids.size()
	sub(state, "gone")[str(pid)] = 1
	sub(state, "worlds").erase(str(pid))
	sub(state, "moving").erase(str(pid))
	sub(state, "debris").erase(str(pid))
	touch(state)


## Déplace un corps vers un autre système (moteurs planétaires), avec sa colonie.
static func move_body(state: GameState, pid: int, to_sid: int) -> void:
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return
	var from := state.galaxy.systems[p.system_id]
	from.planet_ids.erase(pid)
	from.planet_count = from.planet_ids.size()
	var idx := _next_index(state, to_sid)
	p.system_id = to_sid
	p.index = idx
	var s := state.galaxy.systems[to_sid]
	s.planet_ids.append(pid)
	s.planet_count = s.planet_ids.size()
	sub(state, "moved")[str(pid)] = [to_sid, idx]
	state.rebuild_ownership()
	touch(state)


## Change le type (et la taille) d'un corps, en retenant le changement (planet_overrides).
static func reshape(state: GameState, pid: int, t: String, size := -1) -> void:
	var f := {"type": t}
	if size > 0:
		f["size"] = size
	state.override_planet(pid, f)
	touch(state)


static func mark_world(state: GameState, pid: int, k: String, maker: int) -> void:
	var w := world(state, pid)
	if w.is_empty():
		w = {"k": k, "o": maker, "integ": 100, "mods": 0, "eng": 0}
	else:
		w["k"] = k
	sub(state, "worlds")[str(pid)] = w


static func world_name(state: GameState, pid: int) -> String:
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return "?"
	var rel := WorldForgeWorld.relic_name(state, pid)
	return rel if rel != "" else p.display_name(state.galaxy)


static func has_habitable(state: GameState, sid: int) -> bool:
	for pid in state.galaxy.systems[sid].planet_ids:
		if int(GameData.planet_type(state.galaxy.get_planet(pid).type).get("base_hab", 0)) > 0:
			return true
	return false


# --- Chantiers ---------------------------------------------------------------------------------

static func jobs(state: GameState) -> Dictionary:
	return sub(state, "jobs")


static func job_ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in jobs(state):
		out.append(int(k))
	out.sort()
	return out


static func get_job(state: GameState, id: int) -> Dictionary:
	var v: Variant = jobs(state).get(str(id), {})
	return v if v is Dictionary else {}


static func job_in_system(state: GameState, sid: int) -> Dictionary:
	for id in job_ids(state):
		var j := get_job(state, id)
		if int(j["s"]) == sid:
			return j
	return {}


static func job_on(state: GameState, pid: int) -> Dictionary:
	if pid < 0:
		return {}
	for id in job_ids(state):
		var j := get_job(state, id)
		if int(j["p"]) == pid:
			return j
	return {}


static func jobs_of(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in job_ids(state):
		var j := get_job(state, id)
		if int(j.get("b", j["o"])) == eid or int(j["o"]) == eid:
			out.append(j)
	return out


static func busy(state: GameState, eid: int) -> int:
	var n := 0
	for id in job_ids(state):
		var j := get_job(state, id)
		if int(j.get("b", j["o"])) == eid:
			n += 1
	return n


static func slots(state: GameState, eid: int) -> int:
	return r_int("slots", 2) + Research.fx_int(state, eid, "forge_slots")


static func unlocked(state: GameState, eid: int, op: String) -> bool:
	var e := state.get_empire(eid)
	if e == null:
		return false
	var techs: Array = op_def(op).get("tech", (cfg("instant").get(op, {}) as Dictionary).get("tech", []))
	for t in techs:
		if not e.techs.has(String(t)):
			return false
	return true


static func cost_pct(state: GameState, eid: int, op: String, sid := -1) -> int:
	var pct := WorldForgeBridges.cost_pct(state, eid)
	if op == "habitat" and sid >= 0 and sub(state, "carcass").has(str(sid)):
		pct += r_int("carcass_habitat_pct", -50)
	return pct


static func op_cost(state: GameState, eid: int, op: String, sid := -1) -> Dictionary:
	return Research.scaled_amounts(op_def(op).get("cost", {}), cost_pct(state, eid, op, sid))


static func op_mass(op: String) -> int:
	return int(op_def(op).get("mass", 0))


## Durée d'un chantier (talent des Ferrocornes : agglomération et compression plus rapides).
static func op_days(state: GameState, eid: int, op: String, pid := -1) -> int:
	var d := op_def(op)
	var days := int(d.get("days", 360))
	if op == "demanteler" and pid >= 0:
		var p := state.galaxy.get_planet(pid)
		days = int(d.get("days_base", 900)) + int(d.get("days_per_size", 270)) * (p.size if p != null else 1)
	var fast: Array = talent(state, eid).get("fast_ops", [])
	if fast.has(op):
		days = days * 100 / (100 + t_int(state, eid, "fast_pct"))
	return maxi(1, days)


# --- Vaisseau-architecte -----------------------------------------------------------------------

static func architect_busy(state: GameState, f: Fleet) -> bool:
	return Megastructures.architect_busy(state, f) or sub(state, "plans").has(str(f.id))


## L'architecte est-il retenu par un ordre de la Forge ? (lu par Megastructures.architect_busy)
static func holds_architect(state: GameState, f: Fleet) -> bool:
	return enabled(state) and sub(state, "plans").has(str(f.id))


static func free_architect(state: GameState, eid: int, sid: int) -> Fleet:
	for f in Megastructures.architects_at(state, eid, sid):
		if not architect_busy(state, f):
			return f
	return null


static func _plan_fleet(state: GameState, eid: int, sid: int) -> Fleet:
	var best: Fleet = null
	var best_d := 1 << 30
	var j := FactionTraits.jumps_from(state.galaxy, sid)
	for f in Megastructures.architects_of(state, eid):
		if architect_busy(state, f):
			continue
		var dd := int(j.get(f.system_id, 999))
		if dd < best_d:
			best_d = dd
			best = f
	return best


static func needs_architect(op: String) -> bool:
	return op != "evacuer"


# --- Où lancer quoi (prop. 6-18) -------------------------------------------------------------------

static func _holds(state: GameState, eid: int, sid: int) -> bool:
	return Megastructures._holds(state, eid, sid)


## Raison pour laquelle l'empire ne peut pas lancer ce chantier ici ("" = possible). Ne regarde ni
## l'architecte, ni les ressources, ni la capacité (voir check_start).
static func site_reason(state: GameState, eid: int, op: String, sid: int, pid: int, arg := "") -> String:
	var d := op_def(op)
	if d.is_empty():
		return "chantier inconnu"
	if bool(d.get("dismantle", false)) and not dismantle_on(state):
		return "le démantèlement n'est pas en jeu dans cette partie"
	if not unlocked(state, eid, op):
		return "technologie requise : %s" % Research.missing_text(state, eid, d.get("tech", []))
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	var relic := op == "ouvrir"
	if not relic and not _holds(state, eid, sid):
		return "il faut tenir le système (une colonie ou un avant-poste établi, sans occupant)"
	if relic:
		if not Fleets.is_explored(state, eid, sid):
			return "système inexploré"
		var o := state.system_owner(sid)
		if o >= 0 and o != eid:
			return "le système est tenu par un autre"
	if not job_in_system(state, sid).is_empty():
		return "un chantier planétaire est déjà en cours dans ce système"
	var s := state.galaxy.systems[sid]
	if bool(d.get("new_body", false)):
		if pid != -1:
			return "se bâtit sur une orbite vide"
		if s.planet_ids.size() >= 9:
			return "plus aucune orbite libre dans ce système"
		if op == "habitat":
			if has_habitable(state, sid):
				return "seulement dans un système sans planète habitable"
			for opid in s.planet_ids:
				if state.galaxy.get_planet(opid).type == "habitat":
					return "un habitat-monde par système"
			if not Megastructures.at_star(state, sid, "monde_anneau").is_empty():
				return "impossible dans un système qui porte un Monde-anneau"
		if op == "sur_mesure":
			if not (d.get("choices", []) as Array).has(arg):
				return "choisissez le type de monde"
			if custom_count(state, eid) >= r_int("custom_limit", 3):
				return "limite atteinte : %d planètes sur mesure par empire" % r_int("custom_limit", 3)
		return WorldForgeBridges.site_reason(state, eid, op, sid, pid)
	if pid < 0 or not s.planet_ids.has(pid):
		return "choisissez un corps du système"
	var p := state.galaxy.get_planet(pid)
	var c: Colony = state.colonies.get(pid)
	var e := state.get_empire(eid)
	if c != null and c.owner != eid:
		return "ce monde appartient à un autre"
	var from: Array = d.get("from", [])
	if op == "moteurs":
		var ok := from.has(p.type) or (bool(d.get("custom_ok", false)) and String(world(state, pid).get("k", "")) == "custom")
		if not ok:
			return "seulement sur un monde façonné ou stérile"
		if int(world(state, pid).get("eng", 0)) > 0:
			return "ce monde a déjà ses moteurs"
		if e.capital_planet == pid:
			return "jamais la capitale"
	elif not from.is_empty() and not from.has(p.type):
		return "seulement sur : %s" % ", ".join(PackedStringArray(from.map(func(x: Variant) -> String: return Megastructures.planet_label(String(x)))))
	match op:
		"agglomerer", "comprimer":
			if c != null and c.is_colony() and c.population > 0:
				return "pas sur un monde peuplé"
		"module":
			if p.size >= r_int("habitat_max_size", 5):
				return "l'habitat a atteint sa taille maximale"
			if anchors(state, sid) <= int(world(state, pid).get("mods", 0)):
				return "plus d'ancrage libre dans le système (astéroïde, lune ou planète sans colonie)"
		"creuser":
			if c != null and c.is_colony() and not c.is_established():
				return "la colonie n'est pas encore établie"
		"demanteler":
			var why := _dismantle_reason(state, eid, p, c)
			if why != "":
				return why
		"evacuer":
			if c == null or not c.is_colony() or c.population <= 0:
				return "il n'y a personne à évacuer"
			if e.capital_planet == pid:
				return "jamais la capitale"
			if e.home_planet == pid:
				return "le berceau de votre peuple ne s'évacue pas"
			if not c.is_established():
				return "la colonie n'est pas encore établie"
		"ouvrir":
			if not WorldForgeWorld.is_relic(state, pid):
				return "ce n'est pas un monde-reliquaire"
	return WorldForgeBridges.site_reason(state, eid, op, sid, pid)


static func _dismantle_reason(state: GameState, eid: int, p: Planet, c: Colony) -> String:
	var e := state.get_empire(eid)
	if e.capital_planet == p.id:
		return "jamais la capitale"
	if e.home_planet == p.id:
		return "le berceau de votre peuple ne se défait pas"
	if WorldForgeWorld.is_relic(state, p.id):
		return "un monde-reliquaire scellé résiste à tous les outils"
	if c != null and c.is_colony() and c.population > 0:
		if t_bool(state, eid, "digest"):
			if not c.is_established():
				return "la colonie n'est pas encore établie"
			return ""  # Kh'thari : digestion planétaire (prop. 36)
		return "évacuez d'abord la colonie"
	if sub(state, "moving").has(str(p.id)):
		return "ce monde est en marche"
	return ""


## Ancrages libres d'un système pour les modules d'habitat : astéroïdes, lunes, planètes sans colonie.
static func anchors(state: GameState, sid: int) -> int:
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var p := state.galaxy.get_planet(pid)
		if p.type == "habitat":
			continue
		var c: Colony = state.colonies.get(pid)
		if c == null or not c.is_colony() or c.population <= 0:
			n += 1
	return n


static func custom_count(state: GameState, eid: int) -> int:
	var n := 0
	var w := sub(state, "worlds")
	for k in w:
		if String((w[k] as Dictionary).get("k", "")) == "custom" and int((w[k] as Dictionary).get("o", -1)) == eid:
			n += 1
	for j in jobs_of(state, eid):
		if String(j["op"]) == "sur_mesure" and int(j["o"]) == eid:
			n += 1
	return n


## Tous les sites possibles d'une opération pour un empire : [[système, planète], …].
static func sites(state: GameState, eid: int, op: String, max_n := 99, arg := "") -> Array:
	var out: Array = []
	if not unlocked(state, eid, op):
		return out
	var sys_ids: Array[int] = []
	var seen := {}
	if op == "ouvrir":
		for k in sub(state, "relics"):
			var sid := state.galaxy.get_planet(int(k)).system_id
			if not seen.has(sid):
				seen[sid] = true
				sys_ids.append(sid)
	else:
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner != eid:
				continue
			var sid := state.galaxy.get_planet(pid).system_id
			if not seen.has(sid):
				seen[sid] = true
				sys_ids.append(sid)
	sys_ids.sort()
	for sid in sys_ids:
		if bool(op_def(op).get("new_body", false)):
			if site_reason(state, eid, op, sid, -1, arg) == "":
				out.append([sid, -1])
		else:
			for pid in state.galaxy.systems[sid].planet_ids:
				if site_reason(state, eid, op, sid, pid, arg) == "":
					out.append([sid, pid])
		if out.size() >= max_n:
			break
	return out


# --- Ordres ------------------------------------------------------------------------------------

## Ordres (SimCommands.forge_act) : "start" (op, s, p, a) lance avec un architecte présent, "plan" (op,
## s, p, a) envoie l'architecte libre le plus proche, "cancel" (id), "melt" (n), "move" (p, t), "rosette"
## (s), "ram" (p, t), "order" (seller, s, a), "unplan" (f).
static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not applies(state, eid):
		return "la Forge des mondes n'est pas en jeu"
	match act:
		"start":
			return check_start(state, eid, String(d.get("op", "")), int(d.get("s", -1)), int(d.get("p", -1)), String(d.get("a", "")))
		"plan":
			return check_plan(state, eid, String(d.get("op", "")), int(d.get("s", -1)), int(d.get("p", -1)), String(d.get("a", "")))
		"cancel":
			return check_cancel(state, eid, int(d.get("id", -1)))
		"melt":
			return check_melt(state, eid, int(d.get("n", 0)))
		"unplan":
			return "" if sub(state, "plans").has(str(int(d.get("f", -1)))) and state.fleets.has(int(d.get("f", -1))) and (state.fleets[int(d.get("f", -1))] as Fleet).owner == eid else "aucun ordre pour cet architecte"
	return WorldForgeWorld.check(state, eid, act, d)


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"start":
			start(state, eid, String(d["op"]), int(d["s"]), int(d.get("p", -1)), String(d.get("a", "")), free_architect(state, eid, int(d["s"])), added)
		"plan":
			plan(state, eid, String(d["op"]), int(d["s"]), int(d.get("p", -1)), String(d.get("a", "")), added)
		"cancel":
			cancel(state, eid, int(d["id"]), added)
		"melt":
			melt(state, eid, int(d["n"]))
		"unplan":
			sub(state, "plans").erase(str(int(d["f"])))
		_:
			WorldForgeWorld.apply(state, eid, act, d, added)
	return added


static func check_start(state: GameState, eid: int, op: String, sid: int, pid: int, arg := "") -> String:
	var why := site_reason(state, eid, op, sid, pid, arg)
	if why != "":
		return why
	if needs_architect(op) and free_architect(state, eid, sid) == null:
		return "il faut un Vaisseau-architecte libre, à l'arrêt dans le système"
	return _afford_reason(state, eid, op, sid)


static func _afford_reason(state: GameState, eid: int, op: String, sid: int) -> String:
	if busy(state, eid) >= slots(state, eid):
		return "trop de chantiers planétaires à la fois (%d)" % slots(state, eid)
	var cost := op_cost(state, eid, op, sid)
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	if mass(state, eid) < op_mass(op):
		return "il faut %d Masse planétaire" % op_mass(op)
	return ""


static func check_plan(state: GameState, eid: int, op: String, sid: int, pid: int, arg := "") -> String:
	var why := site_reason(state, eid, op, sid, pid, arg)
	if why != "":
		return why
	if not needs_architect(op):
		return _afford_reason(state, eid, op, sid)
	if free_architect(state, eid, sid) != null:
		return _afford_reason(state, eid, op, sid)
	var f := _plan_fleet(state, eid, sid)
	if f == null:
		return "aucun Vaisseau-architecte libre (construisez-en un dans un chantier spatial)"
	if f.system_id != sid and Fleets.plan_route(state, f, sid).is_empty():
		return "aucune route connue jusque-là"
	return ""


static func plan(state: GameState, eid: int, op: String, sid: int, pid: int, arg: String, added: Array[Dictionary]) -> void:
	if not needs_architect(op) or free_architect(state, eid, sid) != null:
		if check_start(state, eid, op, sid, pid, arg) == "":
			start(state, eid, op, sid, pid, arg, free_architect(state, eid, sid), added)
		return
	var f := _plan_fleet(state, eid, sid)
	if f == null:
		return
	sub(state, "plans")[str(f.id)] = {"op": op, "s": sid, "p": pid, "a": arg}
	var r := Fleets.plan_route(state, f, sid)
	if not r.is_empty():
		f.standing_order = ""
		f.system_id = int(r["system"])
		f.path.assign(r["path"])
		f.progress = int(r["progress"])


## Lance le chantier (paiement au lancement). f : l'architecte (null pour l'évacuation).
static func start(state: GameState, eid: int, op: String, sid: int, pid: int, arg: String, f: Fleet, added: Array[Dictionary], buyer := -1) -> void:
	var e := state.get_empire(eid)
	var payer := state.get_empire(buyer) if buyer >= 0 else e
	if buyer < 0:
		Economy.pay(e, op_cost(state, eid, op, sid))
		add_mass(state, eid, -op_mass(op))
	if f != null:
		sub(state, "plans").erase(str(f.id))
	var id := int(state.forge.get("next", 1))
	state.forge["next"] = id + 1
	var owner := buyer if buyer >= 0 else eid
	var days := op_days(state, eid, op, pid)
	var j := {"id": id, "op": op, "o": owner, "s": sid, "p": pid, "w": days, "tot": days, "a": arg, "for": buyer, "b": eid}
	jobs(state)[str(id)] = j
	_stat(state, eid, "started", 1)
	var where := world_name(state, pid) if pid >= 0 else "une orbite vide de %s" % state.galaxy.systems[sid].system_name
	if op == "demanteler":
		WorldForgeBridges.on_dismantle_start(state, eid, pid, added)
	var extra := (" pour %s" % payer.short_name()) if buyer >= 0 else ""
	added.append(state.add_chronicle("%s lance un chantier planétaire sur %s : %s%s (%d jours)." % [e.short_name(), where, op_label(op).to_lower(), extra, days],
			_who(state, eid, sid)))


static func _who(state: GameState, eid: int, sid: int, public := false) -> Variant:
	return null if public else Espionage.private_to(state, [eid], sid)


static func check_cancel(state: GameState, eid: int, id: int) -> String:
	var j := get_job(state, id)
	if j.is_empty() or (int(j["o"]) != eid and int(j.get("b", -1)) != eid):
		return "ce n'est pas votre chantier"
	return ""


static func cancel(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var j := get_job(state, id)
	jobs(state).erase(str(id))
	added.append(state.add_chronicle("%s abandonne un chantier planétaire (%s). Rien n'est remboursé ; les échafaudages restent comme souvenir." % [
			state.get_empire(eid).short_name(), op_label(String(j["op"])).to_lower()], _who(state, eid, int(j["s"]))))


static func check_melt(state: GameState, eid: int, n: int) -> String:
	if n <= 0:
		return "rien à fondre"
	if mass(state, eid) < n:
		return "pas assez de Masse (%d)" % mass(state, eid)
	return ""


static func melt(state: GameState, eid: int, n: int) -> void:
	add_mass(state, eid, -n)
	var e := state.get_empire(eid)
	e.resources["materials"] = int(e.resources.get("materials", 0)) + n * r_int("mass_materials", 10)


# --- Jour après jour -----------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.forge.is_empty():
		return added
	# Architectes arrivés : ils lancent le chantier prévu.
	var pk := sub(state, "plans").keys()
	pk.sort()
	for k in pk:
		var f: Fleet = state.fleets.get(int(k))
		var pl: Dictionary = sub(state, "plans")[k]
		if f == null:
			sub(state, "plans").erase(k)
			continue
		if f.is_moving() or f.system_id != int(pl["s"]):
			if not f.is_moving() and f.system_id != int(pl["s"]):
				sub(state, "plans").erase(k)  # détourné en chemin
			continue
		sub(state, "plans").erase(k)
		var op := String(pl["op"])
		if check_start(state, f.owner, op, int(pl["s"]), int(pl["p"]), String(pl.get("a", ""))) == "":
			start(state, f.owner, op, int(pl["s"]), int(pl["p"]), String(pl.get("a", "")), f, added)
		else:
			added.append(state.add_chronicle("L'architecte de %s arrive à %s, mais le chantier prévu (%s) n'est plus possible." % [
					state.get_empire(f.owner).short_name(), state.galaxy.systems[int(pl["s"])].system_name, op_label(op).to_lower()], [f.owner]))
	for id in job_ids(state):
		var j := get_job(state, id)
		if j.is_empty():
			continue
		var sid := int(j["s"])
		var occ := WarPeace.occupier(state, sid)
		if occ >= 0 and occ != int(j["o"]):
			continue  # prop. 32 : une flotte ennemie qui tient le système suspend le chantier
		if WorldForgeBridges.enemy_present(state, int(j["o"]), sid):
			continue
		j["w"] = int(j["w"]) - 1
		if String(j["op"]) == "demanteler":
			WorldForgeBridges.dismantle_day(state, j, added)
		if int(j["w"]) <= 0:
			jobs(state).erase(str(id))
			finish(state, j, added)
	WorldForgeWorld.daily(state, added)
	return added


static func finish(state: GameState, j: Dictionary, added: Array[Dictionary]) -> void:
	var op := String(j["op"])
	var eid := int(j["o"])
	var builder := int(j.get("b", eid))
	var sid := int(j["s"])
	var pid := int(j["p"])
	var e := state.get_empire(eid)
	if e == null:
		return
	var d := op_def(op)
	var name_before := world_name(state, pid) if pid >= 0 else ""
	var made := ""
	match op:
		"agglomerer", "comprimer":
			reshape(state, pid, String(d["to"]), int(d.get("size", 2)))
			state.galaxy.get_planet(pid).deposits.clear()
			state.override_planet(pid, {"deposits": []})
			mark_world(state, pid, String(d["to"]), builder)
			made = "%s devient %s." % [name_before, Megastructures.planet_label(String(d["to"]))]
		"habitat":
			var size := maxi(int(d.get("size", 2)), t_int(state, eid, "habitat_size"))
			pid = add_body(state, sid, "habitat", size)
			mark_world(state, pid, "habitat", builder)
			if sub(state, "carcass").has(str(sid)):
				sub(state, "carcass").erase(str(sid))  # la carcasse du titan sert d'ossature (prop. 30)
			made = "un habitat-monde s'allume au-dessus de %s : %s." % [state.galaxy.systems[sid].system_name, world_name(state, pid)]
		"module":
			var p := state.galaxy.get_planet(pid)
			reshape(state, pid, p.type, p.size + 1)
			var w := world(state, pid)
			if w.is_empty():
				mark_world(state, pid, "habitat", builder)
				w = world(state, pid)
			w["mods"] = int(w.get("mods", 0)) + 1
			made = "%s gagne un module : taille %d." % [name_before, p.size]
		"coquille":
			reshape(state, pid, "coquille")
			mark_world(state, pid, "coquille", builder)
			made = "%s est désormais enveloppé d'une coquille : on y respire." % name_before
		"creuser":
			var p := state.galaxy.get_planet(pid)
			reshape(state, pid, "creux", mini(r_int("hollow_max_size", 5), p.size + int(d.get("grow", 2))))
			mark_world(state, pid, "creux", builder)
			made = "%s est creusé : un monde sous le monde." % name_before
		"sur_mesure":
			var t := String(j.get("a", "continental"))
			if t == "prefere":
				var pref: Array = e.faction().get("preferred", [])
				t = String(pref[0]) if not pref.is_empty() and GameData.planet_types().has(String(pref[0])) else "continental"
			pid = add_body(state, sid, t, int(d.get("size", 3)))
			mark_world(state, pid, "custom", eid)
			made = "une planète sur mesure (%s) prend place autour de %s : %s." % [Megastructures.planet_label(t), state.galaxy.systems[sid].system_name, world_name(state, pid)]
			if int(j.get("for", -1)) >= 0:
				WorldForgeBridges.on_order_done(state, j, pid, added)
		"demanteler":
			WorldForgeBridges.dismantle_done(state, j, added)
			return
		"evacuer":
			WorldForgeBridges.evacuate(state, eid, pid, added)
			return
		"moteurs":
			if world(state, pid).is_empty():
				mark_world(state, pid, state.galaxy.get_planet(pid).type, builder)
			world(state, pid)["eng"] = 1
			made = "%s est équipé de moteurs planétaires. Il n'attend plus qu'un cap." % name_before
		"ouvrir":
			WorldForgeWorld.opened(state, j, added)
			return
	if made == "":
		return
	_stat(state, eid, "made", 1)
	WorldForgeBridges.on_made(state, eid, pid, op, added)
	Announce.next(state, "forge_made", {"actor": eid, "system": sid})
	added.append(state.add_chronicle("Forge des mondes : %s" % made.substr(0, 1).to_upper() + made.substr(1), _who(state, eid, sid)))


# --- Mois après mois : entretien, intégrité, Masse --------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if state.forge.is_empty():
		return
	for id in job_ids(state):
		var j := get_job(state, id)
		_sync_owner(state, j, added)
	WorldForgeBridges.monthly(state, added)
	WorldForgeWorld.monthly(state, added)


## Prop. 33 : un chantier suit le maître de son système (un chantier conquis peut être repris).
static func _sync_owner(state: GameState, j: Dictionary, added: Array[Dictionary]) -> void:
	var sid := int(j["s"])
	var o := state.system_owner(sid)
	var cur := int(j["o"])
	if o < 0 or o == cur or GameState.is_npc(o) or String(j["op"]) == "ouvrir":
		return
	if cur >= 0 and _holds(state, cur, sid):
		return
	j["o"] = o
	j["b"] = o
	j["for"] = -1
	added.append(state.add_chronicle("Le chantier planétaire de %s (%s) passe aux mains de %s." % [
			state.galaxy.systems[sid].system_name, op_label(String(j["op"])).to_lower(), state.get_empire(o).short_name()], Espionage.private_to(state, [o, cur], sid)))


## Qui tient ce monde (colonie, sinon maître du système).
static func holder(state: GameState, pid: int) -> int:
	var c: Colony = state.colonies.get(pid)
	if c != null:
		return c.owner
	var p := state.galaxy.get_planet(pid)
	return state.system_owner(p.system_id) if p != null else -1


## Rendements et entretien du mois (Economy.income) : entretien des mondes façonnés, rosettes, coquilles
## pensantes des Teyl, carcasses, matériaux et énergie des démantèlements.
static func income(state: GameState, eid: int) -> Dictionary:
	var gross := {}
	var upkeep := {}
	if state.forge.is_empty():
		return {"gross": gross, "upkeep": upkeep}
	var w := sub(state, "worlds")
	var shell_k := t_int(state, eid, "shell_knowledge")
	for k in w:
		var pid := int(k)
		if holder(state, pid) != eid:
			continue
		var wk := String((w[k] as Dictionary).get("k", ""))
		var up := int((cfg("worlds").get(wk, {}) as Dictionary).get("upkeep", 0))
		if up > 0:
			upkeep["energy"] = int(upkeep.get("energy", 0)) + up
		if shell_k > 0 and (wk == "coquille" or wk == "creux"):
			gross["knowledge"] = int(gross.get("knowledge", 0)) + shell_k
	for j in jobs_of(state, eid):
		if String(j["op"]) == "demanteler" and int(j.get("b", j["o"])) == eid:
			var y := WorldForgeBridges.dismantle_monthly(state, j)
			for r in y:
				if r != "mass":
					gross[r] = int(gross.get(r, 0)) + int(y[r])
	var wx := WorldForgeWorld.income(state, eid)
	for r in wx["gross"]:
		gross[r] = int(gross.get(r, 0)) + int(wx["gross"][r])
	for r in wx["upkeep"]:
		upkeep[r] = int(upkeep.get(r, 0)) + int(wx["upkeep"][r])
	return {"gross": gross, "upkeep": upkeep}


## Effets pour Research.effects : Rayonnement des mondes créés (prop. 31).
static func effects(state: GameState, eid: int) -> Dictionary:
	if state.forge.is_empty():
		return {}
	var n := stat(state, eid, "made")
	if n <= 0:
		return {}
	return {"culture_pct": mini(r_int("culture_pct_max", 10), n * r_int("culture_pct_per_world", 2))}


## Bonus de population (Economy.max_pop) : rosettes, mondes vivants.
static func pop_bonus(state: GameState, pid: int, eid: int) -> int:
	if state.forge.is_empty():
		return 0
	return WorldForgeWorld.pop_bonus(state, pid, eid)


## Croissance (Economy.growth_per_day) : la colonie d'un habitat-monde grandit deux fois plus vite.
static func growth_pct(state: GameState, pid: int) -> int:
	if state.forge.is_empty():
		return 0
	var p := state.galaxy.get_planet(pid)
	return 100 if p != null and p.type == "habitat" else 0


## Production d'une colonie (Economy) : moitié pendant la marche d'un monde.
static func production_pct(state: GameState, pid: int) -> int:
	if state.forge.is_empty() or not sub(state, "moving").has(str(pid)):
		return 100
	return r_int("move_output_pct", 50)


## Kardashev (liaison avec le fil Kardashev, prop. 38) : mondes créés achevés + mondes démantelés.
static func kardashev_count(state: GameState, eid: int) -> int:
	if state == null or state.forge.is_empty():
		return 0
	return stat(state, eid, "made") + stat(state, eid, "dism")


## Colonisation impossible (Economy.check_colonize) : monde-reliquaire scellé, monde en marche.
static func colony_block(state: GameState, pid: int) -> String:
	if state.forge.is_empty():
		return ""
	if WorldForgeWorld.is_relic(state, pid):
		return "un monde-reliquaire scellé : il faut d'abord l'ouvrir (Forge des mondes)"
	if sub(state, "moving").has(str(pid)):
		return "ce monde est en marche"
	return ""


## Tendance du marché (Goods.trend_pct) : la Grande Braderie fait chuter les matériaux (prop. 42).
static func trend_pct(state: GameState, res: String) -> int:
	if state.forge.is_empty() or res != "materials":
		return 0
	return r_int("braderie_pct", -30) if int(state.forge.get("braderie", 0)) > state.tick else 0


## Prop. 21 : Sphère ou Essaim de Dyson moins chers autour d'une étoile dépouillée de ses mondes.
static func mega_cost_pct(state: GameState, k: String, sid: int) -> int:
	if state.forge.is_empty() or sid < 0 or not sub(state, "void").has(str(sid)):
		return 0
	return r_int("void_dyson_pct", -25) if k == "sphere_dyson" or k == "essaim_dyson" else 0


## Prop. 20 : le Brise-monde vient de tirer. Un monde creux sauve la moitié de ses habitants, les débris
## donnent de la Masse au tireur et se démantèlent plus vite (+2 Masse par mois).
static func on_world_broken(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	if state.forge.is_empty():
		return
	var p := state.galaxy.get_planet(pid)
	var c: Colony = state.colonies.get(pid)
	if p != null and p.type == "creux" and c != null and c.is_colony() and c.population > 1 and not GameState.is_npc(c.owner):
		var owner := c.owner
		var n := c.population / 2
		state.colonies.erase(pid)
		state.rebuild_ownership()
		Movements.flee_from(state, p.system_id, Peoples.founder_of(state, owner), n, owner, added)
		added.append(state.add_chronicle("%s était creux : la moitié de ses habitants a fui par les galeries avant l'impact." % world_name(state, pid)))
	sub(state, "worlds").erase(str(pid))
	sub(state, "moving").erase(str(pid))
	sub(state, "debris")[str(pid)] = 1
	add_mass(state, eid, r_int("debris_mass", 20))
