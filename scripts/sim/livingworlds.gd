class_name LivingWorlds
extends RefCounted
## Les mondes vivants (étude du 2026-11-18, version complète validée : 33 propositions ; données :
## data/livingworlds.json). Un monde vivant est une planète qui a une humeur envers chaque empire, de
## -100 à +100, lue en cinq paliers (prop. 6) : Hostile, Méfiant, Neutre, Bienveillant, Lié. Elle bouge
## chaque mois selon ce que font les empires (prop. 7) ; elle règle la colonie posée dessus (prop. 8), qui
## peut coloniser (prop. 9), ce que le monde demande (prop. 10), le Rejet puis le départ (prop. 11, 17).
## La défense, les anticorps et le voyage sont dans LivingWorldsWar ; les ponts (foi, psionisme, faune,
## nefs-graines, talents, Monde-Ego, fusion, visiteurs, éveil) dans LivingWorldsBridges.
##
## Réglage « Mondes vivants » (prop. 1) : Aucun, Rares, Fréquents ; Monde-Ego Non / Oui (prop. 26). Sans
## l'option (tests, bancs, anciennes parties) : aucun, et la partie se joue exactement comme avant.
## La version courte de la Forge des mondes (prop. 29 de la Forge) devient l'origine « Reliquaire ».
##
## État : state.living = {"mode", "ego_opt", "woken": éveils en cours de partie, "worlds": {"pid": monde},
##  "moved": {"pid": [système, rang]}, "gone": {"pid": 1}, "slept": {"pid": 1}, "pend": {"pid": eid},
##  "ego": {...}, "st": {"eid": {statistiques}}}.
## Monde : {"o": origine, "t": tempérament, "n": rang du nom, "born", "m": {eid: humeur}, "thr": {eid:
##  tolérance}, "known": {eid: 1}, "deep": {eid: 1}, "unmade": {eid: mondes défaits déjà comptés},
##  "fav": espèce préférée, "nope": espèce rejetée, "hate": jours Hostile envers l'hôte, "rej": {eid: jour
##  du Rejet}, "next_req", "req": demande en attente, "watch": obligation suivie, "repos": {"e", "until"},
##  "lie": {eid: jour où il est devenu Lié}, "fused": eid, "jump", "ab", "seed": {eid: jour}, "inv": {eid:
##  jour}, "listen": {eid: jour}, "visit", "vstab": {"e", "until"}, "dead": 0/1, "ego": 0/1}.

const SUBS := ["worlds", "moved", "gone", "slept", "pend", "ego", "st"]


static func data() -> Dictionary:
	return GameData.livingworlds()


static func cfg(section: String) -> Dictionary:
	var v: Variant = data().get(section, {})
	return v if v is Dictionary else {}


static func r_int(key: String, def := 0) -> int:
	var v: Variant = cfg("rules").get(key, def)
	return int(v) if (v is int or v is float) else def


static func r_dict(key: String) -> Dictionary:
	var v: Variant = cfg("rules").get(key, {})
	return v if v is Dictionary else {}


static func f_int(key: String, def := 0) -> int:
	return int(cfg("factors").get(key, def))


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "rares"))


static func ego_defs() -> Array:
	return data().get("ego_opts", [])


static func default_ego() -> String:
	return String(data().get("default_ego", "non"))


static func mode_def(id: String) -> Dictionary:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == id:
			return m
	return {}


static func enabled(state: GameState) -> bool:
	return state != null and not state.living.is_empty()


static func mode(state: GameState) -> String:
	return String(state.living.get("mode", "aucun"))


static func mode_label(state: GameState) -> String:
	return String(mode_def(mode(state)).get("label", "Aucun"))


static func ego_on(state: GameState) -> bool:
	return enabled(state) and String(state.living.get("ego_opt", "non")) == "oui"


static func setup(state: GameState, mode_id: String, ego_id := "") -> void:
	state.living = {}
	var md := mode_def(mode_id)
	if md.is_empty() or int(md.get("start", 0)) <= 0:
		return
	var eg := ego_id
	var ok := false
	for o: Dictionary in ego_defs():
		if String(o["id"]) == eg:
			ok = true
	if not ok:
		eg = default_ego()
	state.living = {"mode": mode_id, "ego_opt": eg, "woken": 0}
	for k in SUBS:
		state.living[k] = {}
	_place_start(state, md)


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.living.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.living = {}
		return
	state.living = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.living.has(k):
			state.living[k] = {}


## Corps déplacés ou partis (appelé par GameState.from_dict après WorldForge.restore_bodies).
static func restore_bodies(galaxy: Galaxy, d: Dictionary) -> void:
	if d.is_empty() or galaxy == null:
		return
	var touched := {}
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
	if state.living.is_empty():
		return {}
	if not state.living.has(k):
		state.living[k] = {}
	return state.living[k]


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "living"] + parts))


static func stat(state: GameState, eid: int, k: String) -> int:
	return int((sub(state, "st").get(str(eid), {}) as Dictionary).get(k, 0))


static func _stat(state: GameState, eid: int, k: String, n: int) -> void:
	if state.living.is_empty() or eid < 0:
		return
	var st := sub(state, "st")
	var d: Dictionary = st.get(str(eid), {})
	d[k] = int(d.get(k, 0)) + n
	st[str(eid)] = d


static func touch(state: GameState) -> void:
	state.relic_rev += 1
	for x in state.empires:
		x.hab_cache.clear()
		x.path_cache.clear()


# --- Talents des peuples (prop. 25) ------------------------------------------------------------

static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid) if eid >= 0 else null
	if e == null or GameState.is_npc(eid):
		return {}
	var v: Variant = cfg("talents").get(Genetics.root(e.faction_id), null)
	return v if v is Dictionary else {}


static func t_int(state: GameState, eid: int, key: String) -> int:
	var v: Variant = talent(state, eid).get(key, 0)
	return int(v) if (v is int or v is float) else 0


static func t_bool(state: GameState, eid: int, key: String) -> bool:
	return bool(talent(state, eid).get(key, false))


# --- Les mondes --------------------------------------------------------------------------------

static func worlds(state: GameState) -> Dictionary:
	return sub(state, "worlds")


static func world(state: GameState, pid: int) -> Dictionary:
	if state.living.is_empty():
		return {}
	var v: Variant = worlds(state).get(str(pid), null)
	return v if v is Dictionary else {}


static func is_living(state: GameState, pid: int) -> bool:
	var w := world(state, pid)
	return not w.is_empty() and int(w.get("dead", 0)) == 0


## Identifiants des mondes vivants (en vie), triés.
static func ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in worlds(state):
		if int((worlds(state)[k] as Dictionary).get("dead", 0)) == 0:
			out.append(int(k))
	out.sort()
	return out


static func in_system(state: GameState, sid: int) -> Array[int]:
	var out: Array[int] = []
	if state.living.is_empty() or sid < 0 or sid >= state.galaxy.systems.size():
		return out
	for pid in state.galaxy.systems[sid].planet_ids:
		if is_living(state, int(pid)):
			out.append(int(pid))
	return out


static func origin_def(o: String) -> Dictionary:
	var v: Variant = cfg("origins").get(o, {})
	return v if v is Dictionary else {}


static func temper_def(t: String) -> Dictionary:
	var v: Variant = cfg("temperaments").get(t, {})
	return v if v is Dictionary else {}


static func origin_ids() -> Array[String]:
	var out: Array[String] = []
	for k in cfg("origins"):
		if not String(k).begins_with("_"):
			out.append(String(k))
	return out


static func temper_ids() -> Array[String]:
	var out: Array[String] = []
	for k in cfg("temperaments"):
		if not String(k).begins_with("_"):
			out.append(String(k))
	return out


static func name_of(state: GameState, pid: int) -> String:
	var w := world(state, pid)
	if w.is_empty():
		var p := state.galaxy.get_planet(pid)
		return p.display_name(state.galaxy) if p != null else "?"
	if int(w.get("ego", 0)) == 1:
		return String(cfg("ego").get("name", "Ego"))
	var names: Array = origin_def(String(w["o"])).get("names", [])
	if names.is_empty():
		return state.galaxy.get_planet(pid).display_name(state.galaxy)
	var s := String(names[int(w.get("n", 0)) % names.size()])
	return s.substr(0, 1).to_upper() + s.substr(1)


static func sys_of(state: GameState, pid: int) -> int:
	var p := state.galaxy.get_planet(pid)
	return p.system_id if p != null else -1


## L'empire qui a une colonie (ou un avant-poste) sur le monde, -1 sinon.
static func host(state: GameState, pid: int) -> int:
	var c: Colony = state.colonies.get(pid)
	if c == null or GameState.is_npc(c.owner):
		return -1
	return c.owner


## Ajoute un monde vivant sur une planète. Renvoie le monde.
static func add_world(state: GameState, pid: int, origin: String, salt := 0) -> Dictionary:
	if state.living.is_empty() or is_living(state, pid):
		return world(state, pid)
	var tids := temper_ids()
	var names: Array = origin_def(origin).get("names", [""])
	var w := {"o": origin, "t": tids[_h(state, ["temper", pid, salt]) % tids.size()], "n": _h(state, ["name", pid, salt]) % maxi(1, names.size()),
			"born": state.tick, "m": {}, "thr": {}, "known": {}, "deep": {}, "unmade": {}, "rej": {}, "lie": {}, "seed": {}, "inv": {}, "listen": {},
			"hate": 0, "fused": -1, "jump": 0, "ab": 0, "visit": state.tick + r_int("visit_days", 1800), "dead": 0}
	var peoples := _peoples(state)
	if not peoples.is_empty():
		w["fav"] = peoples[_h(state, ["fav", pid, salt]) % peoples.size()]
		if peoples.size() > 1:
			var nope := peoples[_h(state, ["nope", pid, salt]) % peoples.size()]
			if nope == String(w["fav"]):
				nope = peoples[(peoples.find(nope) + 1) % peoples.size()]
			w["nope"] = nope
	w["next_req"] = state.tick + _req_delay(state, w, pid)
	for e in state.empires:
		if e.is_npc():
			continue
		(w["m"] as Dictionary)[str(e.id)] = r_int("start_mood", 0) + t_int(state, e.id, "start_mood")
		(w["unmade"] as Dictionary)[str(e.id)] = _unmade_count(state, e.id)
	worlds(state)[str(pid)] = w
	touch(state)
	return w


## Espèces fondatrices présentes dans la partie (triées).
static func _peoples(state: GameState) -> Array[String]:
	var seen := {}
	for e in state.empires:
		if not e.is_npc() and not e.eliminated:
			seen[Peoples.founder_of(state, e.id)] = true
	var out: Array[String] = []
	for k in seen:
		out.append(String(k))
	out.sort()
	return out


## Prop. 3 : les mondes de départ, sur de belles planètes loin des capitales.
static func _place_start(state: GameState, md: Dictionary) -> void:
	@warning_ignore("integer_division")
	var want := clampi(maxi(int(md.get("start", 1)), state.galaxy.systems.size() / maxi(1, int(md.get("per_systems", 120)))), 0, int(md.get("max_start", 2)))
	var cands := start_candidates(state)
	var picked_sys := {}
	var origins: Array = data().get("start_origins", ["eveille"])
	var n := 0
	for c in cands:
		if n >= want:
			break
		var pid := int(c[1])
		var sid := sys_of(state, pid)
		if picked_sys.has(sid):
			continue
		picked_sys[sid] = true
		add_world(state, pid, String(origins[n % origins.size()]), n)
		n += 1


## Planètes possibles pour un monde vivant : bon type, taille, loin des capitales, sans colonie.
static func start_candidates(state: GameState) -> Array:
	var types: Array = cfg("rules").get("start_types", [])
	var min_j := r_int("min_jumps_from_capital", 4)
	var caps: Array = []
	for e in state.empires:
		if e.is_npc() or e.eliminated:
			continue
		var cap := FactionTraits.capital_system(state, e.id)
		if cap < 0 and e.home_planet >= 0:
			cap = state.galaxy.get_planet(e.home_planet).system_id
		if cap >= 0:
			caps.append(FactionTraits.jumps_from(state.galaxy, cap))
	var out: Array = []
	for p in state.galaxy.planets:
		if not types.has(p.type) or p.size < r_int("min_size", 5) or state.colonies.has(p.id) or is_living(state, p.id):
			continue
		if sub(state, "gone").has(str(p.id)) or sub(state, "slept").has(str(p.id)) or state.lairs.has(p.system_id):
			continue
		if not state.forge.is_empty() and WorldForge.is_made(state, p.id):
			continue
		var near := 999
		for d: Dictionary in caps:
			near = mini(near, int(d.get(p.system_id, 999)))
		if near < min_j:
			continue
		out.append([_h(state, ["start", p.id]), p.id])
	out.sort()
	return out


# --- Humeur (prop. 6-7) ------------------------------------------------------------------------

static func tiers() -> Array:
	return cfg("rules").get("tiers", [])


static func tier_of_value(m: int) -> Dictionary:
	for t: Dictionary in tiers():
		if m <= int(t["max"]):
			return t
	return tiers().back() if not tiers().is_empty() else {}


static func mood(state: GameState, pid: int, eid: int) -> int:
	var w := world(state, pid)
	if w.is_empty() or eid < 0 or GameState.is_npc(eid):
		return 0
	if t_bool(state, eid, "mute"):
		return 0
	return int((w["m"] as Dictionary).get(str(eid), r_int("start_mood", 0) + t_int(state, eid, "start_mood")))


static func tier(state: GameState, pid: int, eid: int) -> Dictionary:
	return tier_of_value(mood(state, pid, eid))


static func tier_id(state: GameState, pid: int, eid: int) -> String:
	return String(tier(state, pid, eid).get("id", "neutre"))


static func tier_index(state: GameState, pid: int, eid: int) -> int:
	var t := tier(state, pid, eid)
	return tiers().find(t)


## Au moins Bienveillant (indice 3).
static func loves(state: GameState, pid: int, eid: int) -> bool:
	return is_living(state, pid) and tier_index(state, pid, eid) >= 3


static func hates(state: GameState, pid: int, eid: int) -> bool:
	return is_living(state, pid) and tier_index(state, pid, eid) == 0


## Méfiant ou Hostile.
static func dislikes(state: GameState, pid: int, eid: int) -> bool:
	return is_living(state, pid) and tier_index(state, pid, eid) <= 1


## Adepte : un empire qui a fait l'Éveil psionique (le monde hanté le tolère, prop. 22).
static func adept(state: GameState, eid: int) -> bool:
	return not state.psionics.is_empty() and Psionics.applies(state, eid) and Psionics.awake(state, eid)


## Change l'humeur d'un monde envers un empire (tempérament, talents, tolérance, plafond).
@warning_ignore("integer_division")
static func add_mood(state: GameState, pid: int, eid: int, delta: int) -> void:
	var w := world(state, pid)
	if w.is_empty() or delta == 0 or eid < 0 or GameState.is_npc(eid) or t_bool(state, eid, "mute"):
		return
	var td := temper_def(String(w["t"]))
	var d := delta
	if d > 0:
		d = d * (int(td.get("gain_pct", 100)) + t_int(state, eid, "gain_pct")) / 100
	else:
		d = d * int(td.get("loss_pct", 100)) / 100
		var thr := int((w["thr"] as Dictionary).get(str(eid), 0))
		d = d * (100 - thr) / 100
		if Research.fx_int(state, eid, "symbiosis") > 0:
			d /= 2  # Symbioses planétaires (lot 3 de l'arbre)
	if d == 0:
		d = 1 if delta > 0 else -1
	var m := clampi(mood(state, pid, eid) + d, -100, 100)
	m = _capped(state, w, eid, m)
	(w["m"] as Dictionary)[str(eid)] = m


static func _capped(state: GameState, w: Dictionary, eid: int, m: int) -> int:
	if int(w.get("ego", 0)) == 1:
		return -100
	var od := origin_def(String(w["o"]))
	if od.has("mood_cap") and not adept(state, eid):
		return mini(m, int(od["mood_cap"]))
	return m


static func set_mood(state: GameState, pid: int, eid: int, m: int) -> void:
	var w := world(state, pid)
	if w.is_empty() or eid < 0 or GameState.is_npc(eid):
		return
	(w["m"] as Dictionary)[str(eid)] = _capped(state, w, eid, clampi(m, -100, 100))


## Après une colère (Rejet, anticorps), le monde se fâche un peu moins vite (seuil d'Alpha Centauri).
static func harden(state: GameState, pid: int, eid: int) -> void:
	var w := world(state, pid)
	if w.is_empty():
		return
	var thr: Dictionary = w["thr"]
	thr[str(eid)] = mini(r_int("tolerance_max", 50), int(thr.get(str(eid), 0)) + r_int("tolerance_step", 10))


## L'humeur est-elle visible pour cet empire ? (Énigme : seulement après une écoute.)
static func mood_known(state: GameState, pid: int, eid: int) -> bool:
	var w := world(state, pid)
	if w.is_empty() or not knows(state, pid, eid):
		return false
	if bool(temper_def(String(w["t"])).get("hidden", false)):
		return (w["deep"] as Dictionary).has(str(eid)) or Research.fx_int(state, eid, "biosemiotics") > 0  # Biosémiotique
	return true


## Prop. 4 : le monde est-il reconnu comme vivant par cet empire ?
static func knows(state: GameState, pid: int, eid: int) -> bool:
	var w := world(state, pid)
	return not w.is_empty() and ((w["known"] as Dictionary).has(str(eid)) or int(w.get("ego", 0)) == 1)


static func _unmade_count(state: GameState, eid: int) -> int:
	var n := stat(state, eid, "murder")
	if not state.forge.is_empty():
		n += WorldForge.stat(state, eid, "dism") + WorldForge.stat(state, eid, "rams")
	return n


# --- Effets sur la colonie (prop. 8) -----------------------------------------------------------

## Bonus de population de la colonie posée sur un monde vivant (Economy.max_pop).
static func pop_bonus(state: GameState, pid: int, eid: int) -> int:
	if not is_living(state, pid) or host(state, pid) != eid:
		return 0
	var n := int(tier(state, pid, eid).get("pop", 0))
	if int(world(state, pid).get("fused", -1)) == eid:
		n += r_int("fuse_pop", 2)
	return n


## Croissance : l'espèce préférée du monde pousse plus vite (prop. 9).
static func growth_pct(state: GameState, pid: int) -> int:
	if not is_living(state, pid):
		return 0
	var c: Colony = state.colonies.get(pid)
	if c == null or GameState.is_npc(c.owner):
		return 0
	var w := world(state, pid)
	var main := c.founder if c.founder != "" else Peoples.founder_of(state, c.owner)
	if String(w.get("fav", "")) == main:
		return 20
	if String(w.get("nope", "")) == main:
		return -20
	return 0


## Production de la colonie (Economy) : sol en repos (demande), monde fusionné.
static func production_pct(state: GameState, pid: int) -> int:
	if state.living.is_empty() or not is_living(state, pid):
		return 100
	var w := world(state, pid)
	var pct := 100
	var rp: Variant = w.get("repos", null)
	if rp is Dictionary and int(rp.get("until", 0)) > state.tick and host(state, pid) == int(rp.get("e", -1)):
		pct += int((cfg("requests").get("repos", {}) as Dictionary).get("prod_pct", -30))
	if int(w.get("fused", -1)) >= 0 and host(state, pid) == int(w["fused"]):
		pct += r_int("fuse_prod_pct", 25)
	return maxi(0, pct)


## Nourriture offerte par les mondes Bienveillants et Liés à leurs hôtes (Economy).
static func income(state: GameState, eid: int) -> Dictionary:
	var gross := {}
	if state.living.is_empty():
		return {"gross": gross, "upkeep": {}}
	for pid in ids(state):
		if host(state, pid) == eid:
			var food := int(tier(state, pid, eid).get("food", 0))
			if food > 0:
				gross["food"] = int(gross.get("food", 0)) + food
	return {"gross": gross, "upkeep": {}}


## Stabilité du système d'un monde vivant pour son hôte (Stability.parts).
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if state.living.is_empty() or owner < 0:
		return out
	for pid in in_system(state, sid):
		if host(state, pid) != owner:
			continue
		var t := tier(state, pid, owner)
		if int(t.get("stab", 0)) != 0:
			out.append(["%s (%s)" % [name_of(state, pid), String(t["label"]).to_lower()], int(t["stab"])])
		var w := world(state, pid)
		if int(w.get("fused", -1)) == owner:
			out.append(["Fusion avec %s" % name_of(state, pid), r_int("fuse_stab", 15)])
		var vs: Variant = w.get("vstab", null)
		if vs is Dictionary and int(vs.get("e", -1)) == owner and int(vs.get("until", 0)) > state.tick:
			out.append(["Un visiteur revenu de %s" % name_of(state, pid), r_int("visit_stab", 5)])
	return out


# --- Choisir ses hôtes (prop. 9) ---------------------------------------------------------------

## Refus de coloniser (Economy.check_colonize).
static func colony_block(state: GameState, pid: int, eid: int) -> String:
	if state.living.is_empty():
		return ""
	if LivingWorldsBridges.ego_holds(state, pid):
		return "Ego tient ce monde : il faut d'abord abattre le Monde affamé"
	if not is_living(state, pid):
		return ""
	if int(world(state, pid).get("ego", 0)) == 1:
		return "on ne s'installe pas sur Ego"
	if hates(state, pid, eid):
		return "le sol rejette les colons : %s vous est Hostile" % name_of(state, pid)
	return ""


## Durée de colonisation (SimCommands « colonize ») : deux fois plus longue chez un monde Méfiant.
@warning_ignore("integer_division")
static func claim_days(state: GameState, eid: int, pid: int, days: int) -> int:
	if not is_living(state, pid) or tier_id(state, pid, eid) != "mefiant":
		return days
	return days * r_int("wary_claim_pct", 200) / 100


# --- Chaque mois -------------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if state.living.is_empty():
		return
	for pid in ids(state):
		var w := world(state, pid)
		_discover(state, pid, w)
		_moods(state, pid, w)
		_people(state, pid, w, added)
		_requests(state, pid, w, added)
		_reject_and_leave(state, pid, w, added)
		if not is_living(state, pid):
			continue
		LivingWorldsWar.monthly(state, pid, added)
		if is_living(state, pid):
			LivingWorldsBridges.monthly(state, pid, added)
	LivingWorldsBridges.wake_check(state, added)
	LivingWorldsBridges.ego_monthly(state, added)


## Prop. 4 : un empire qui colonise le monde, tient son système ou y garde une flotte le reconnaît.
static func _discover(state: GameState, pid: int, w: Dictionary) -> void:
	var sid := sys_of(state, pid)
	var known: Dictionary = w["known"]
	var who := {}
	var h := host(state, pid)
	if h >= 0:
		who[h] = true
	var so := state.system_owner(sid)
	if so >= 0 and not GameState.is_npc(so):
		who[so] = true
	for f in Fleets.fleets_at(state, sid):
		if not GameState.is_npc(f.owner) and not f.is_moving():
			who[f.owner] = true
	for eid in who:
		if not known.has(str(eid)):
			known[str(eid)] = 1
			var e := state.get_empire(int(eid))
			if e != null and not e.is_ai():
				Announce.next(state, "living_wake", {"actor": int(eid), "system": sid})
				state.add_chronicle("À %s, les scientifiques de %s cessent de rire : %s pense. La planète entière est vivante, et elle les regarde. (%s, %s.)" % [
						state.galaxy.systems[sid].system_name, e.short_name(), name_of(state, pid), String(origin_def(String(w["o"])).get("label", "")).to_lower(),
						String(temper_def(String(w["t"])).get("label", "")).to_lower()], Espionage.private_to(state, [int(eid)]))


static func _moods(state: GameState, pid: int, w: Dictionary) -> void:
	var sid := sys_of(state, pid)
	var h := host(state, pid)
	var od := origin_def(String(w["o"]))
	var battle_sides := {}
	if state.battles.has(sid):
		for s: Dictionary in (state.battles[sid] as Dictionary).get("sides", []):
			battle_sides[int(s["empire"])] = true
	var besieger := int((state.sieges.get(sid, {}) as Dictionary).get("by", -1)) if state.sieges.has(sid) else -1
	var eco := _ecology(state, pid) if bool(od.get("ecology", false)) else -1
	for e in state.empires:
		if e.is_npc() or e.eliminated:
			continue
		var eid := e.id
		var m := mood(state, pid, eid)
		var d := 0
		# Les offenses s'effacent lentement.
		if m < 0:
			(w["m"] as Dictionary)[str(eid)] = mini(0, m + r_int("drift", 1))
		# Mondes défaits (démantelés, percutés, tués) depuis la dernière fois.
		var um := _unmade_count(state, eid)
		var seen := int((w["unmade"] as Dictionary).get(str(eid), 0))
		if um > seen:
			d += (um - seen) * f_int("unmade_world", -25) * int(od.get("unmade_x", 1))
			(w["unmade"] as Dictionary)[str(eid)] = um
		var ext := _exterminated(state, eid) * f_int("exterminate", -5) * maxi(1, t_int(state, eid, "exterminate_x"))
		d += maxi(f_int("exterminate_max", -10) * maxi(1, t_int(state, eid, "exterminate_x")), ext)
		if battle_sides.has(eid):
			d += f_int("battle_month", -6)
		if besieger == eid:
			d += f_int("siege_month", -8)
		d += LivingWorldsBridges.faith_mood(state, pid, eid)
		if h == eid:
			if e.wars.is_empty():
				d += f_int("peace_host", 1)
			d += t_int(state, eid, "host_mood")
			var c: Colony = state.colonies.get(pid)
			if w["t"] == "maternel" and c != null and c.population * 2 >= maxi(1, Economy.max_pop(state, state.galaxy.get_planet(pid), eid)):
				d += f_int("maternal_pop", 1)
			if w["t"] == "curieux" and c != null and not c.species.is_empty():
				d += f_int("curious_species", 1)
			if w["t"] == "jaloux":
				for o in ids(state):
					if o != pid and host(state, o) == eid:
						d += f_int("jealous_rival", -2)
						break
			if eco >= 0:
				if eco < 40:
					d += f_int("ecology_low", -4)
				elif eco > 80:
					d += f_int("ecology_high", 2)
		if d != 0:
			add_mood(state, pid, eid, d)
		# Lié : depuis quand (fusion, prop. 27).
		var lie: Dictionary = w["lie"]
		if tier_index(state, pid, eid) >= 4:
			if not lie.has(str(eid)):
				lie[str(eid)] = state.tick
		else:
			lie.erase(str(eid))


static func _exterminated(state: GameState, eid: int) -> int:
	var st: Variant = (state.peoples.get("status", {}) as Dictionary).get(str(eid), {}) if not state.peoples.is_empty() else {}
	var n := 0
	if st is Dictionary:
		for k in st:
			if String(st[k]) == "extermines":
				n += 1
	return n


## Santé de la biosphère (pilier Écologie, s'il est en jeu) : 0-100, -1 sans écologie ni biosphère.
static func _ecology(state: GameState, pid: int) -> int:
	return Ecology.health(state, pid)


## Prop. 9 : la colonie perd peu à peu les habitants de l'espèce que le monde rejette.
static func _people(state: GameState, pid: int, w: Dictionary, added: Array[Dictionary]) -> void:
	var c: Colony = state.colonies.get(pid)
	var nope := String(w.get("nope", ""))
	if c == null or nope == "" or not c.is_colony() or GameState.is_npc(c.owner) or not Movements.migrations_on(state):
		return
	if Movements.count_of(state, c, nope) <= 0 or c.population <= 2:
		return
	if _h(state, ["nope", pid, state.tick]) % 3 != 0:
		return
	if Movements.flee(state, c, nope, 1, [], added) > 0 and not state.get_empire(c.owner).is_ai():
		state.add_chronicle("%s n'aime pas les %s : une famille quitte la colonie, chassée par des rêves trop insistants." % [name_of(state, pid), Peoples.label(nope)],
				Espionage.private_to(state, [c.owner]))


# --- Demandes (prop. 10) -----------------------------------------------------------------------

@warning_ignore("integer_division")
static func _req_delay(state: GameState, w: Dictionary, pid: int) -> int:
	var lo := r_int("request_min_days", 1080)
	var hi := maxi(lo + 1, r_int("request_max_days", 1800))
	var d := lo + _h(state, ["req", pid, state.tick]) % (hi - lo)
	return d * int(temper_def(String(w["t"])).get("req_pct", 100)) / 100


static func _requests(state: GameState, pid: int, w: Dictionary, added: Array[Dictionary]) -> void:
	var h := host(state, pid)
	_watch(state, pid, w, added)
	if h < 0 or state.tick < int(w.get("next_req", 0)) or int(w.get("ego", 0)) == 1:
		return
	w["next_req"] = state.tick + _req_delay(state, w, pid)
	if w.get("req", {}) is Dictionary and not (w.get("req", {}) as Dictionary).is_empty():
		return
	var e := state.get_empire(h)
	var kinds: Array = []
	for k in temper_def(String(w["t"])).get("asks", []):
		var rd: Dictionary = cfg("requests").get(String(k), {})
		if rd.is_empty():
			continue
		if bool(rd.get("needs_war", false)) and e.wars.is_empty():
			continue
		if bool(rd.get("needs_people", false)) and (not Movements.enabled(state) or _guest_people(state, pid, h) == ""):
			continue
		kinds.append(String(k))
	if kinds.is_empty():
		return
	var kind := String(kinds[_h(state, ["kind", pid, state.tick]) % kinds.size()])
	var req := {"k": kind, "e": h, "ev": state.next_event_id}
	if kind == "paix":
		var wars := e.wars.duplicate()
		wars.sort()
		req["r"] = int(wars[0])
	if kind == "peuple":
		req["pp"] = _guest_people(state, pid, h)
	w["req"] = req
	Events.push(state, h, "lw_demande", {"system": sys_of(state, pid), "planet": pid}, added)


## Une espèce autre que celle de l'hôte, rencontrée (préférée du monde si possible).
static func _guest_people(state: GameState, pid: int, eid: int) -> String:
	var mine := Peoples.founder_of(state, eid)
	var w := world(state, pid)
	var fav := String(w.get("fav", ""))
	if fav != "" and fav != mine:
		return fav
	var e := state.get_empire(eid)
	var c := e.contacts.duplicate()
	c.sort()
	for o in c:
		var oe := state.get_empire(int(o))
		if oe != null and not oe.is_npc():
			var f := Peoples.founder_of(state, oe.id)
			if f != mine and f != String(w.get("nope", "")):
				return f
	return ""


## Obligations acceptées (chasser les flottes, faire la paix) : suivies jusqu'à leur échéance.
static func _watch(state: GameState, pid: int, w: Dictionary, added: Array[Dictionary]) -> void:
	var wt: Variant = w.get("watch", null)
	if not (wt is Dictionary) or (wt as Dictionary).is_empty():
		return
	var eid := int(wt["e"])
	var broken := false
	match String(wt["k"]):
		"nofleet":
			for f in Fleets.fleets_at(state, sys_of(state, pid)):
				if f.owner == eid and Combat.is_armed(f) and not f.is_moving():
					broken = true
					break
		"peace":
			var e := state.get_empire(eid)
			if state.tick >= int(wt["until"]) and e != null and e.wars.has(int(wt.get("r", -1))):
				broken = true
	if broken:
		add_mood(state, pid, eid, r_int("request_broken", -20))
		w.erase("watch")
		var e := state.get_empire(eid)
		if e != null and not e.is_ai():
			added.append(state.add_chronicle("%s se sent trahi : %s n'a pas tenu parole. Le ciel de %s gronde toute la nuit." % [
					name_of(state, pid), e.short_name(), state.galaxy.systems[sys_of(state, pid)].system_name], Espionage.private_to(state, [eid])))
	elif state.tick >= int(wt["until"]):
		w.erase("watch")


## Réponse à une demande (carte lw_demande, Events.apply_fx).
static func answer(state: GameState, eid: int, pid: int, yes: bool, added: Array[Dictionary]) -> void:
	var w := world(state, pid)
	if w.is_empty():
		return
	var req: Dictionary = w.get("req", {})
	w["req"] = {}
	if req.is_empty() or int(req.get("e", -1)) != eid:
		return
	var kind := String(req["k"])
	var rd: Dictionary = cfg("requests").get(kind, {})
	var e := state.get_empire(eid)
	if yes:
		var cost: Dictionary = rd.get("cost", {})
		if not cost.is_empty() and not Economy.can_afford(e, cost):
			yes = false
		elif not cost.is_empty():
			Economy.pay(e, cost)
	if not yes:
		var no := r_int("request_no", -15) * int(temper_def(String(w["t"])).get("no_x", 1))
		add_mood(state, pid, eid, no)
		_stat(state, eid, "req_no", 1)
		return
	var gain := r_int("request_yes", 20)
	if kind == "offrande":
		gain *= maxi(1, t_int(state, eid, "offer_x"))
	add_mood(state, pid, eid, gain)
	_stat(state, eid, "req_yes", 1)
	match kind:
		"repos":
			w["repos"] = {"e": eid, "until": state.tick + int(rd.get("days", 360))}
		"chasser":
			w["watch"] = {"k": "nofleet", "e": eid, "until": state.tick + r_int("request_watch_days", 180)}
		"paix":
			w["watch"] = {"k": "peace", "e": eid, "until": state.tick + r_int("request_watch_days", 180), "r": int(req.get("r", -1))}
		"peuple":
			var c: Colony = state.colonies.get(pid)
			var fid := String(req.get("pp", ""))
			if c != null and c.is_colony() and fid != "":
				for i in int(rd.get("pops", 2)):
					Movements.add_one(state, c, fid, 40)


## Texte de la demande en attente ({lw_ask}).
static func ask_text(state: GameState, pid: int) -> String:
	var w := world(state, pid)
	var req: Dictionary = w.get("req", {}) if not w.is_empty() else {}
	if req.is_empty():
		return ""
	var s := String((cfg("requests").get(String(req["k"]), {}) as Dictionary).get("ask", ""))
	var r := state.get_empire(int(req.get("r", -1)))
	s = s.replace("{lw_rival}", r.short_name() if r != null else "vos ennemis")
	s = s.replace("{lw_people}", Peoples.label(String(req.get("pp", ""))) if String(req.get("pp", "")) != "" else "?")
	return s


# --- Rejet et départ (prop. 11, 17) ------------------------------------------------------------

static func _reject_and_leave(state: GameState, pid: int, w: Dictionary, added: Array[Dictionary]) -> void:
	var h := host(state, pid)
	var sid := sys_of(state, pid)
	if h >= 0 and hates(state, pid, h) and int(w.get("ego", 0)) == 0:
		w["hate"] = int(w.get("hate", 0)) + 30
		if int(w["hate"]) >= r_int("reject_days", 1080):
			reject(state, pid, added)
	else:
		w["hate"] = 0
	# Départ : un an après un Rejet, si le système est encore tenu par un empire Hostile.
	var rej: Dictionary = w["rej"]
	for k in rej.keys():
		if state.tick < int(rej[k]) + r_int("leave_days", 360):
			continue
		var so := state.system_owner(sid)
		var still := so >= 0 and not GameState.is_npc(so) and hates(state, pid, so)
		rej.erase(k)
		if still or hates(state, pid, int(k)) and host(state, pid) < 0 and so == int(k):
			depart(state, pid, added)
			return


## Prop. 11 : le monde chasse la colonie d'un hôte Hostile depuis trois ans.
static func reject(state: GameState, pid: int, added: Array[Dictionary]) -> void:
	var w := world(state, pid)
	var c: Colony = state.colonies.get(pid)
	if w.is_empty() or c == null:
		return
	var owner := c.owner
	var sid := sys_of(state, pid)
	var n := c.population
	var fid := c.founder if c.founder != "" else Peoples.founder_of(state, owner)
	state.colonies.erase(pid)
	state.rebuild_ownership()
	if n > 0:
		Movements.flee_from(state, sid, fid, n, owner, added)
	w["hate"] = 0
	(w["rej"] as Dictionary)[str(owner)] = state.tick
	harden(state, pid, owner)
	_stat(state, owner, "rejected", 1)
	touch(state)
	Announce.next(state, "living_anger", {"target": owner, "system": sid})
	added.append(state.add_chronicle("Le Rejet : %s se secoue comme un chien mouillé. Séismes, marées, forêts qui marchent : la colonie de %s est chassée jusqu'au dernier habitant." % [
			name_of(state, pid), state.get_empire(owner).short_name()]))


## Prop. 17 : le monde part s'installer près de l'empire qu'il aime le plus, ou s'en va dans le noir.
static func depart(state: GameState, pid: int, added: Array[Dictionary]) -> void:
	var w := world(state, pid)
	if w.is_empty():
		return
	var from := sys_of(state, pid)
	var best := -1
	var best_m := 24
	for e in state.empires:
		if e.is_npc() or e.eliminated:
			continue
		var m := mood(state, pid, e.id)
		if m > best_m:
			best_m = m
			best = e.id
	var to := -1
	if best >= 0:
		to = free_system_near(state, best, from, r_int("leave_range", 6))
	var c: Colony = state.colonies.get(pid)
	var nm := name_of(state, pid)
	if c != null and not loves(state, pid, c.owner):
		var owner := c.owner
		var n := c.population
		state.colonies.erase(pid)
		state.rebuild_ownership()
		if n > 0:
			Movements.flee_from(state, from, c.founder if c.founder != "" else Peoples.founder_of(state, owner), n, owner, added)
	Announce.next(state, "living_leave", {"system": from})
	if to >= 0:
		move_planet(state, pid, to)
		added.append(state.add_chronicle("%s s'arrache à son orbite et traverse le vide, lentement, comme une baleine. Il s'installe à %s, près de %s qu'il aime bien." % [
				nm, state.galaxy.systems[to].system_name, state.get_empire(best).short_name()]))
	else:
		remove_planet(state, pid)
		w["dead"] = 1
		added.append(state.add_chronicle("%s s'arrache à son orbite et s'en va dans le noir. Personne ne sait où vont les mondes qui ne veulent plus de nous." % nm))


## Un système sans maître, sans repaire, à range sauts au plus d'une colonie de eid, le plus proche de from.
static func free_system_near(state: GameState, eid: int, from: int, range_: int) -> int:
	var dist_from := FactionTraits.jumps_from(state.galaxy, from)
	var homes := {}
	for cpid in state.sorted_colony_ids():
		var c: Colony = state.colonies[cpid]
		if c.owner == eid:
			homes[state.galaxy.get_planet(int(cpid)).system_id] = true
	var best := -1
	var best_d := 999999
	for hs in homes:
		var dist := FactionTraits.jumps_from(state.galaxy, int(hs))
		for k in dist:
			var sid := int(k)
			if int(dist[k]) > range_ or sid == from or state.system_owner(sid) >= 0 or state.lairs.has(sid):
				continue
			if state.galaxy.systems[sid].planet_ids.size() >= 8:
				continue
			var score := int(dist[k]) * 1000 + int(dist_from.get(sid, 99)) * 10 + sid % 10
			if score < best_d:
				best_d = score
				best = sid
	return best


## Déplace la planète (et sa colonie) vers un autre système, en retenant le déplacement.
static func move_planet(state: GameState, pid: int, to_sid: int) -> void:
	var p := state.galaxy.get_planet(pid)
	if p == null or to_sid < 0 or to_sid == p.system_id:
		return
	var from := state.galaxy.systems[p.system_id]
	from.planet_ids.erase(pid)
	from.planet_count = from.planet_ids.size()
	var idx := 0
	for q in state.galaxy.systems[to_sid].planet_ids:
		idx = maxi(idx, state.galaxy.get_planet(q).index + 1)
	p.system_id = to_sid
	p.index = idx
	var s := state.galaxy.systems[to_sid]
	s.planet_ids.append(pid)
	s.planet_count = s.planet_ids.size()
	sub(state, "moved")[str(pid)] = [to_sid, idx]
	if not state.forge.is_empty():
		WorldForge.sub(state, "moved").erase(str(pid))
		WorldForge.sub(state, "moving").erase(str(pid))
	state.rebuild_ownership()
	touch(state)


static func remove_planet(state: GameState, pid: int) -> void:
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return
	if state.colonies.has(pid):
		state.colonies.erase(pid)
		state.rebuild_ownership()
	var s := state.galaxy.systems[p.system_id]
	s.planet_ids.erase(pid)
	s.planet_count = s.planet_ids.size()
	sub(state, "gone")[str(pid)] = 1
	if not state.forge.is_empty():
		WorldForge.sub(state, "moving").erase(str(pid))
	touch(state)


# --- Le meurtre d'un monde (prop. 16) ----------------------------------------------------------

## Un chantier de démantèlement commence sur un monde vivant : il comprend.
static func on_dismantle_start(state: GameState, pid: int, eid: int) -> void:
	if is_living(state, pid):
		add_mood(state, pid, eid, f_int("dismantle_start", -40))


## Un monde vivant est démantelé ou percuté : crime galactique.
static func on_murder(state: GameState, pid: int, eid: int, added: Array[Dictionary]) -> void:
	if not is_living(state, pid):
		return
	var nm := name_of(state, pid)
	var w := world(state, pid)
	w["dead"] = 1
	_stat(state, eid, "murder", 1)
	for x in state.empires:
		if x.id != eid and not x.is_npc() and not x.eliminated:
			Diplomacy.remember(state, x.id, eid, "world_rammed")
	for o in ids(state):
		set_mood(state, o, eid, mini(mood(state, o, eid), -60))
		(world(state, o)["unmade"] as Dictionary)[str(eid)] = _unmade_count(state, eid)
	LivingWorldsBridges.on_murder(state, pid, eid)
	touch(state)
	Announce.next(state, "living_anger", {"actor": eid, "system": sys_of(state, pid)})
	added.append(state.add_chronicle("Meurtre d'un monde : %s abat %s. Il a crié, longtemps, sur toutes les fréquences. Les autres mondes vivants l'ont entendu, et ils n'oublieront pas." % [
			state.get_empire(eid).short_name(), nm]))


# --- Ordres (SimCommands.living_act) -----------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not enabled(state):
		return "les mondes vivants ne sont pas en jeu dans cette partie"
	var e := state.get_empire(eid)
	if e == null or e.is_npc() or e.eliminated:
		return "empire inconnu"
	var pid := int(d.get("p", -1))
	if not is_living(state, pid):
		return "ce n'est pas un monde vivant"
	if not knows(state, pid, eid):
		return "vous ne savez pas encore que ce monde est vivant"
	match act:
		"invite":
			return LivingWorldsWar.check_invite(state, eid, pid)
		"listen":
			return LivingWorldsBridges.check_listen(state, eid, pid)
		"seed":
			return LivingWorldsBridges.check_seed(state, eid, pid)
		"fuse":
			return LivingWorldsBridges.check_fuse(state, eid, pid)
	return "ordre inconnu : %s" % act


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if check(state, eid, act, d) != "":
		return added
	var pid := int(d.get("p", -1))
	match act:
		"invite":
			LivingWorldsWar.invite(state, eid, pid, added)
		"listen":
			LivingWorldsBridges.listen(state, eid, pid, added)
		"seed":
			LivingWorldsBridges.seed(state, eid, pid, added)
		"fuse":
			LivingWorldsBridges.fuse(state, eid, pid, added)
	return added


# --- Cartes d'événement (Events) ---------------------------------------------------------------

static func event_act(state: GameState, eid: int, item: Dictionary, act: String, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	var pid := int(item.get("planet", -1))
	match act:
		"yes":
			answer(state, eid, pid, true, added)
		"no":
			answer(state, eid, pid, false, added)
		_:
			LivingWorldsBridges.event_act(state, eid, pid, act, added)


static func event_line(state: GameState, eid: int, item: Dictionary, act: String) -> String:
	var pid := int(item.get("planet", -1))
	match act:
		"yes":
			var req: Dictionary = world(state, pid).get("req", {}) if is_living(state, pid) else {}
			var cost: Dictionary = (cfg("requests").get(String(req.get("k", "")), {}) as Dictionary).get("cost", {})
			return "Humeur %+d%s" % [r_int("request_yes", 20), (" ; %s" % GameData.format_amounts(cost)) if not cost.is_empty() else ""]
		"no":
			var no := r_int("request_no", -15)
			if is_living(state, pid):
				no *= int(temper_def(String(world(state, pid)["t"])).get("no_x", 1))
			return "Humeur %+d" % no
	return LivingWorldsBridges.event_line(state, eid, pid, act)


## Jetons des cartes : {lw_world}, {lw_ask}, {lw_ghost}.
static func fill(state: GameState, item: Dictionary, s: String) -> String:
	if state.living.is_empty() or not s.contains("{lw_"):
		return s
	var pid := int(item.get("planet", -1))
	var out := s.replace("{lw_world}", name_of(state, pid))
	out = out.replace("{lw_ask}", ask_text(state, pid))
	var gh: Array = data().get("visitors", ["quelqu'un"])
	out = out.replace("{lw_ghost}", String(gh[_h(state, ["ghost", pid, int(item.get("id", 0))]) % gh.size()]))
	return out


## Prop. 27 : la colonie d'un monde fusionné ne laisse partir personne (Movements).
static func fused_colony(state: GameState, c: Colony) -> bool:
	if c == null or not is_living(state, c.planet_id):
		return false
	return int(world(state, c.planet_id).get("fused", -1)) == c.owner


## Prop. 27 : un monde fusionné refuse une guerre contre un empire qu'il aime (Diplomacy.check_war).
static func check_war(state: GameState, a: int, b: int) -> String:
	if state == null or state.living.is_empty():
		return ""
	for pid in ids(state):
		if int(world(state, pid).get("fused", -1)) == a and host(state, pid) == a and loves(state, pid, b):
			return "%s, fusionné à votre peuple, refuse cette guerre contre un empire qu'il aime" % name_of(state, pid)
	return ""
