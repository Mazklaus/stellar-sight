class_name Faiths
extends RefCounted
## Religion (étude « Religion », 2026-11-13, lot 1 : propositions 1 à 10). Règles : data/faiths.json.
##
## Modèle : Colony.faith compte les fidèles de chaque foi ({identifiant: nombre}) ; le reste de la
## population (population moins la somme) suit les cultes natals de son espèce. La foi ne dépend ni
## de l'espèce ni du propriétaire : une conquête garde les fidèles.
##
## state.faiths :
## - "list" : {identifiant: {"name", "founder", "holy" (planète), "founded", "via", "dogmas": [],
##   "slots", "color"}} les grandes fois fondées ;
## - "state" : {empire (texte): foi d'État} ("laicite" par défaut, "incroyance" ou une grande foi) ;
## - "changed" : {empire: jour du dernier changement de foi d'État} ;
## - "prog" : {planète (texte): {foi: points de conversion}} ;
## - "next" : numéro de la prochaine foi.
##
## Sans l'option de partie « faiths » (tests, bancs, vieilles sauvegardes), rien de tout cela
## n'existe et le jeu se comporte comme avant : ferveur et offrandes comprises.

const LAICITE := "laicite"
const INCROYANCE := "incroyance"
## Foi d'un habitant qui suit les cultes natals (clé utilisée par majority()).
const NATIVE := ""
const KEYS := ["list", "state", "changed", "prog", "missions", "wards", "crusades", "holy_wars", "seen", "prophecies", "je", "stab", "demands"]

## Croyance emportée par le dernier habitant retiré (Movements.remove_one → add_one).
static var carry := ""


static func data() -> Dictionary:
	return GameData.faiths()


static func enabled(state: GameState) -> bool:
	return state.faith_on


# --- Mise en place et sauvegarde -----------------------------------------------------------------

static func setup(state: GameState, mode: String) -> void:
	state.faith_on = mode == "actives"
	state.faiths = {"next": 1}
	for k in KEYS:
		state.faiths[k] = {}
	state.faiths["missions"] = {"list": []}
	state.faiths["holy_wars"] = {"list": []}
	if not state.faith_on:
		return
	for e in state.empires:
		if e.eliminated:
			continue
		state.faiths["state"][str(e.id)] = LAICITE
	# Peuples théocrates ou au credo Foi : leur foi est déjà fondée.
	var st: Dictionary = data()["start"]
	for e in state.empires:
		if e.eliminated or not can_found(state, e.id):
			continue
		var credo := Events.layer_value(state, e.id, "credo")
		var gov := Events.layer_value(state, e.id, "gouvernement")
		if (st["credos"] as Array).has(credo) or (st["governments"] as Array).has(gov):
			var fid := found(state, e.id, "origine", -1, [] as Array[Dictionary])
			var c: Colony = state.colonies.get(int(state.faiths["list"][fid]["holy"]))
			if c != null:
				c.faith.clear()
				c.faith[fid] = c.population


static func to_dict(state: GameState) -> Dictionary:
	var d := {"on": state.faith_on, "next": int(state.faiths.get("next", 1))}
	for k in KEYS:
		d[k] = (state.faiths.get(k, {}) as Dictionary).duplicate(true)
	return d


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.faith_on = bool(d.get("on", false))
	state.faiths = {"next": int(d.get("next", 1))}
	for k in KEYS:
		state.faiths[k] = (d.get(k, {}) as Dictionary).duplicate(true)
	for fid in state.faiths["list"]:
		var f: Dictionary = state.faiths["list"][fid]
		for k in ["founder", "holy", "founded", "slots"]:
			f[k] = int(f.get(k, 0))
		f["zeal"] = int(f.get("zeal", int(data()["zeal"]["start"])))
		f["nature"] = String(f.get("nature", ""))
		if String(f["nature"]) == "":
			f["nature"] = FaithWars.pick_nature(state, int(f["founder"]), String(fid))
		var dg: Array = []
		for x in f.get("dogmas", []):
			dg.append(String(x))
		f["dogmas"] = dg
	for k in state.faiths["changed"]:
		state.faiths["changed"][k] = int(state.faiths["changed"][k])
	for pid in state.faiths["prog"]:
		var m: Dictionary = state.faiths["prog"][pid]
		for fid in m:
			m[fid] = int(m[fid])
	FaithWars.fix_ints(state)


# --- Lecture -------------------------------------------------------------------------------------

static func faith(state: GameState, fid: String) -> Dictionary:
	return state.faiths.get("list", {}).get(fid, {})


static func ids(state: GameState) -> Array:
	var k: Array = (state.faiths.get("list", {}) as Dictionary).keys()
	k.sort()
	return k


static func name_of(state: GameState, fid: String) -> String:
	if fid == NATIVE:
		return "Cultes natals"
	if data()["pseudo"].has(fid):
		return String(data()["pseudo"][fid]["name"])
	return String(faith(state, fid).get("name", fid))


static func color_of(state: GameState, fid: String) -> Color:
	if fid == INCROYANCE:
		return Color(String(data()["pseudo"][INCROYANCE]["color"]))
	var f := faith(state, fid)
	if f.is_empty():
		return Color(0.55, 0.55, 0.5)
	return Color(String(f.get("color", "#cccccc")))


## Foi d'État d'un empire ("laicite" sans l'option ou pour une puissance neutre).
static func state_faith(state: GameState, eid: int) -> String:
	if not state.faith_on:
		return LAICITE
	return String(state.faiths["state"].get(str(eid), LAICITE))


## Vraie foi d'État (grande foi ou incroyance) : la laïcité n'en est pas une.
static func has_state_faith(state: GameState, eid: int) -> bool:
	return state_faith(state, eid) != LAICITE


## Fidèles d'une colonie par foi, cultes natals compris (clé NATIVE).
static func counts(c: Colony) -> Dictionary:
	var out := {}
	if not c.is_colony() or c.population <= 0:
		return out
	var rest := c.population
	for fid in c.faith:
		var n := int(c.faith[fid])
		if n > 0:
			out[fid] = n
			rest -= n
	if rest > 0:
		out[NATIVE] = rest
	return out


## Fidèles vus par un empire (-1 : tout) : un culte caché qu'il n'a pas découvert compte dans les
## cultes natals (voir FaithWars, dogme « Secret »).
static func visible_counts(state: GameState, c: Colony, viewer: int) -> Dictionary:
	var cnt := counts(c)
	if viewer < 0:
		return cnt
	for fid in c.faith:
		if not FaithWars.visible_to(state, fid, viewer):
			cnt[NATIVE] = int(cnt.get(NATIVE, 0)) + int(cnt.get(fid, 0))
			cnt.erase(fid)
	return cnt


## Croyance la plus suivie sur une colonie (NATIVE pour les cultes natals ; à égalité, la grande foi
## d'identifiant le plus petit, les cultes natals en dernier).
static func majority(c: Colony) -> String:
	var cnt := counts(c)
	var best := NATIVE
	var best_n := int(cnt.get(NATIVE, 0))
	for fid in _sorted_keys(c.faith):
		if int(cnt.get(fid, 0)) > best_n:
			best = fid
			best_n = int(cnt[fid])
	return best


## Fidèles d'une foi dans toute la galaxie.
static func followers(state: GameState, fid: String) -> int:
	var n := 0
	for pid in state.colonies:
		n += int((state.colonies[pid] as Colony).faith.get(fid, 0))
	return n


## Fidèles d'une foi par empire propriétaire.
static func followers_by_owner(state: GameState, fid: String) -> Dictionary:
	var out := {}
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		var n := int(c.faith.get(fid, 0))
		if n > 0 and not GameState.is_npc(c.owner):
			out[c.owner] = int(out.get(c.owner, 0)) + n
	return out


## Chef de foi : parmi les empires qui l'ont pour foi d'État, celui qui compte le plus de fidèles (à égalité, le fondateur, puis le plus petit
## identifiant). -1 si personne ne la suit plus.
static func head(state: GameState, fid: String) -> int:
	var f := faith(state, fid)
	if f.is_empty():
		return -1
	var by := followers_by_owner(state, fid)
	var best := -1
	var best_n := 0
	var founder := int(f["founder"])
	var keys := by.keys()
	keys.sort()
	# D'abord parmi les empires qui l'ont pour foi d'État (un conquérant mécréant qui tient le monde
	# saint n'en devient pas le chef), sinon parmi tous.
	for pass_i in 2:
		for eid in keys:
			var n := int(by[eid])
			var e := state.get_empire(int(eid))
			if e == null or e.eliminated or is_hive(state, int(eid)):
				continue
			if pass_i == 0 and state_faith(state, int(eid)) != fid:
				continue
			if n > best_n or (n == best_n and int(eid) == founder):
				best = int(eid)
				best_n = n
		if best >= 0:
			return best
	return best


## Nombre maximal de grandes fois dans la partie.
@warning_ignore("integer_division")
static func limit(state: GameState) -> int:
	var l: Dictionary = data()["limit"]
	return state.empires.size() / int(l["div"]) + int(l["plus"])


## Foi fondée par un empire ("" s'il n'en a pas).
static func founded_by(state: GameState, eid: int) -> String:
	for fid in ids(state):
		var f: Dictionary = state.faiths["list"][fid]
		if int(f["founder"]) == eid and not ["heresie", "schisme"].has(String(f["via"])):
			return fid
	return ""


## Grandes fois révélées (hérésies et schismes à part : un schisme dépasse la limite).
static func revealed_count(state: GameState) -> int:
	var n := 0
	for fid in ids(state):
		if not ["heresie", "schisme"].has(String(state.faiths["list"][fid]["via"])):
			n += 1
	return n


## Une hérésie (foi fille pas encore schismatique) : identifiant de sa foi mère, "" sinon.
static func parent_of(state: GameState, fid: String) -> String:
	return String(faith(state, fid).get("parent", ""))


static func is_hive(state: GameState, eid: int) -> bool:
	if GameState.is_npc(eid):
		return false
	var e := state.get_empire(eid)
	if e == null:
		return false
	return (data()["no_faith_governments"] as Array).has(Events.layer_value(state, eid, "gouvernement"))


## Un empire peut-il encore fonder une grande foi ?
static func can_found(state: GameState, eid: int) -> bool:
	if not state.faith_on or GameState.is_npc(eid):
		return false
	var e := state.get_empire(eid)
	if e == null or e.eliminated or is_hive(state, eid):
		return false
	if founded_by(state, eid) != "":
		return false
	return revealed_count(state) < limit(state)


# --- Révélation et fondation ---------------------------------------------------------------------

## Tente une Révélation par une des cinq voies (relique, gardien, heros, savoir, prophete).
## planet_id : monde saint voulu (-1 = la capitale). Renvoie l'identifiant de la foi fondée, ou "".
static func reveal(state: GameState, eid: int, via: String, planet_id: int, added: Array[Dictionary]) -> String:
	if not can_found(state, eid):
		return ""
	var fid := found(state, eid, via, planet_id, added)
	if fid == "":
		return ""
	# La colonie sainte se convertit à moitié (arrondi au-dessus).
	var c: Colony = state.colonies.get(int(state.faiths["list"][fid]["holy"]))
	if c != null:
		@warning_ignore("integer_division")
		var n := (c.population * int(data()["reveal"]["found_share_pct"]) + 99) / 100
		for _i in n:
			if not _convert_one(c, fid):
				break
	return fid


static func found(state: GameState, eid: int, via: String, planet_id: int, added: Array[Dictionary]) -> String:
	var e := state.get_empire(eid)
	var holy := _holy_planet(state, eid, planet_id)
	if holy < 0:
		return ""
	var fid := "f%d" % int(state.faiths["next"])
	state.faiths["next"] = int(state.faiths["next"]) + 1
	state.faiths["list"][fid] = {
		"name": _pick_name(state, eid), "founder": eid, "holy": holy, "founded": state.tick, "via": via,
		"dogmas": [], "slots": 1, "color": "#" + e.color().to_html(false),
		"zeal": int(data()["zeal"]["start"]), "nature": FaithWars.pick_nature(state, eid, "f%d" % (int(state.faiths["next"]) - 1)),
	}
	if not has_state_faith(state, eid):
		state.faiths["state"][str(eid)] = fid
	Relics.touch(state)
	if via != "origine":
		var p := state.galaxy.get_planet(holy)
		added.append(state.add_chronicle("Révélation ! %s fonde %s, %s. Monde saint : %s. Les autres empires comptent leurs prêtres." % [
				e.display_name(), name_of(state, fid), String(data()["vias"].get(via, "")), p.display_name(state.galaxy)]))
	return fid


## Première colonie fondée d'un empire dans un système (-1 s'il n'en a pas).
static func colony_in_system(state: GameState, eid: int, sid: int) -> int:
	if sid < 0:
		return -1
	var ps: Array = state.galaxy.systems[sid].planet_ids.duplicate()
	ps.sort()
	for pid in ps:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_colony() and c.is_established():
			return pid
	return -1


static func _holy_planet(state: GameState, eid: int, planet_id: int) -> int:
	var c: Colony = state.colonies.get(planet_id)
	if c != null and c.owner == eid and c.is_colony() and c.is_established():
		return planet_id
	var e := state.get_empire(eid)
	c = state.colonies.get(e.capital_planet)
	if c != null and c.owner == eid and c.is_colony():
		return e.capital_planet
	for pid in state.sorted_colony_ids():
		c = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.is_established():
			return pid
	return -1


static func _pick_name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	var forced: Dictionary = data()["forced_names"]
	var used := {}
	for fid in ids(state):
		used[String(state.faiths["list"][fid]["name"])] = true
	if forced.has(e.faction_id) and not used.has(String(forced[e.faction_id])):
		return String(forced[e.faction_id])
	var by: Dictionary = data()["names_by_register"]
	var reg := Events.layer_value(state, eid, "registre")
	var pool: Array = by.get(reg, by["default"])
	var start := absi(hash([state.seed_value, "foi", eid])) % pool.size()
	for i in pool.size():
		var n := String(pool[(start + i) % pool.size()])
		if not used.has(n):
			return n
	return "%s %s" % [String(pool[start]), GameState.ROMAN[mini(ids(state).size(), GameState.ROMAN.size() - 1)]]


## Voie du savoir : trois technologies de Société de l'ère II.
static func _knows_soul_sciences(state: GameState, eid: int) -> bool:
	var rv: Dictionary = data()["reveal"]
	var n := 0
	var e := state.get_empire(eid)
	for tid in e.techs:
		var t := Research.tech(String(tid))
		if String(t.get("domain", "")) == String(rv["tech_domain"]) and int(t.get("era", 0)) == int(rv["tech_era"]):
			n += 1
	return n >= int(rv["tech_n"])


## Héros à l'ambition Foi qui monte de niveau (Heroes.gain_xp).
static func on_hero_level(state: GameState, h: Dictionary) -> void:
	if not state.faith_on:
		return
	var rv: Dictionary = data()["reveal"]
	if String(h.get("amb", "")) == String(rv["hero_amb"]) and int(h["lvl"]) >= int(rv["hero_lvl"]):
		var owner := int(h["owner"])
		if owner >= 0 and not GameState.is_npc(owner):
			reveal(state, owner, "heros", -1, [] as Array[Dictionary])


# --- Population ----------------------------------------------------------------------------------

## Remet les fidèles d'accord avec la population : la plus grande foi perd les siens d'abord.
static func normalize(c: Colony) -> void:
	if c.faith.is_empty():
		return
	var total := 0
	for fid in c.faith.keys():
		if int(c.faith[fid]) <= 0:
			c.faith.erase(fid)
		else:
			total += int(c.faith[fid])
	while total > c.population and not c.faith.is_empty():
		var best := ""
		for fid in _sorted_keys(c.faith):
			if best == "" or int(c.faith[fid]) > int(c.faith[best]):
				best = fid
		var cut := mini(int(c.faith[best]), total - c.population)
		c.faith[best] = int(c.faith[best]) - cut
		total -= cut
		if int(c.faith[best]) <= 0:
			c.faith.erase(best)


## Fondation d'une colonie : les colons suivent la foi d'État.
static func on_founded(state: GameState, c: Colony) -> void:
	if not state.faith_on or not c.is_colony():
		return
	var sf := state_faith(state, c.owner)
	c.faith.clear()
	if sf != LAICITE and not is_hive(state, c.owner):
		c.faith[sf] = c.population


## Naissance (après Peoples.on_birth, population déjà augmentée) : l'enfant suit la foi qui a plus de
## la moitié des habitants, sinon les cultes natals.
static func on_birth(state: GameState, c: Colony) -> void:
	if not state.faith_on or c.faith.is_empty():
		return
	var before := c.population - 1
	for fid in _sorted_keys(c.faith):
		if int(c.faith[fid]) * 2 > before:
			c.faith[fid] = int(c.faith[fid]) + 1
			return


## Un habitant quitte la colonie (Movements.remove_one) : il emporte la croyance majoritaire.
static func on_leave(state: GameState, c: Colony) -> void:
	carry = NATIVE
	if not state.faith_on or c.faith.is_empty():
		return
	var m := majority(c)
	carry = m
	if m != NATIVE:
		c.faith[m] = int(c.faith[m]) - 1
		if int(c.faith[m]) <= 0:
			c.faith.erase(m)
	normalize(c)


## Un habitant arrive (Movements.add_one, population déjà augmentée) avec la croyance emportée.
static func on_arrive(state: GameState, c: Colony) -> void:
	var m := carry
	carry = NATIVE
	if not state.faith_on or m == NATIVE or is_hive(state, c.owner):
		return
	if m != INCROYANCE and faith(state, m).is_empty():
		return
	c.faith[m] = int(c.faith.get(m, 0)) + 1
	normalize(c)


## Convertit un habitant : pris aux cultes natals d'abord, sinon à la plus grande autre foi.
static func _convert_one(c: Colony, fid: String) -> bool:
	var cnt := counts(c)
	if int(cnt.get(NATIVE, 0)) > 0:
		c.faith[fid] = int(c.faith.get(fid, 0)) + 1
		return true
	var best := ""
	for other in _sorted_keys(c.faith):
		if other == fid:
			continue
		if best == "" or int(c.faith[other]) > int(c.faith[best]):
			best = other
	if best == "":
		return false
	c.faith[best] = int(c.faith[best]) - 1
	if int(c.faith[best]) <= 0:
		c.faith.erase(best)
	c.faith[fid] = int(c.faith.get(fid, 0)) + 1
	return true


# --- Propagation (chaque mois) -------------------------------------------------------------------

static var _near_cache := {}


## Systèmes à 3 sauts au plus : {système: sauts}. Mis en cache par galaxie.
static func near(galaxy: Galaxy, from: int) -> Dictionary:
	var key := "%d:%d" % [galaxy.get_instance_id(), from]
	if _near_cache.has(key):
		return _near_cache[key]
	if _near_cache.size() > 4096:
		_near_cache.clear()
	var w: Array = data()["pressure"]["weights"]
	var maxj := w.size() - 1
	var dist := {from: 0}
	var queue: Array[int] = [from]
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		if int(dist[cur]) >= maxj:
			continue
		for n in galaxy.systems[cur].neighbors:
			if not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	_near_cache[key] = dist
	return dist


## Pression mensuelle sur chaque colonie : {planète: {foi: points}}.
@warning_ignore("integer_division")
static func pressures(state: GameState) -> Dictionary:
	var pd: Dictionary = data()["pressure"]
	var w: Array = pd["weights"]
	# Sources, regroupées par système : {système: {foi: fidèles pondérés}}.
	var src := {}
	var targets_by_sys := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.is_colony() or not c.is_established() or c.population <= 0:
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if not GameState.is_npc(c.owner) and not is_hive(state, c.owner):
			if not targets_by_sys.has(sid):
				targets_by_sys[sid] = []
			targets_by_sys[sid].append(pid)
		if c.faith.is_empty():
			continue
		if is_hive(state, c.owner):
			# La conscience collective dissout les croyances des mondes qu'elle absorbe.
			c.faith.clear()
			continue
		var m: Dictionary = src.get(sid, {})
		for fid in c.faith:
			var n := int(c.faith[fid]) * 100
			var f := faith(state, fid)
			if not f.is_empty() and int(f["holy"]) == pid:
				n *= int(pd["holy_x"])
				n = n * (100 + _fx_for_faith(state, fid, "faith_holy_pct") + FaithWars.nature_holy_pct(state, fid)) / 100
			elif not f.is_empty():
				# Précurseurs : la capitale d'un empire de la foi qui tient des reliques prêche comme un monde saint.
				n *= FaithWars.secondary_holy_x(state, fid, c)
			if not GameState.is_npc(c.owner) and state_faith(state, c.owner) == fid:
				n = n * maxi(0, 100 + Research.fx_int(state, c.owner, "faith_pressure_pct")) / 100
			m[fid] = int(m.get(fid, 0)) + n
		src[sid] = m
	var out := {}
	# Prêche de proximité.
	var src_ids := src.keys()
	src_ids.sort()
	for s in src_ids:
		var dist := near(state.galaxy, int(s))
		var sm: Dictionary = src[s]
		for t in dist:
			if not targets_by_sys.has(t):
				continue
			var wt := int(w[int(dist[t])])
			for pid in targets_by_sys[t]:
				var pm: Dictionary = out.get(pid, {})
				for fid in sm:
					# Parasite saint : pas de prêche de voisinage hors de son système.
					if int(dist[t]) > 0 and FaithWars.nature(state, fid) == "parasite":
						continue
					pm[fid] = int(pm.get(fid, 0)) + int(sm[fid]) * wt
				out[pid] = pm
	# Routes commerciales extérieures : les deux bouts se poussent.
	for r: Dictionary in state.trade.get("routes", []):
		if String(r.get("kind", "")) != "ext" or bool(r.get("blocked", false)):
			continue
		var path: Array = r.get("path", [])
		if path.size() < 2:
			continue
		var a := int(path[0])
		var b := int(path[path.size() - 1])
		for pair in [[a, b], [b, a]]:
			if not src.has(pair[0]) or not targets_by_sys.has(pair[1]):
				continue
			var sm: Dictionary = src[pair[0]]
			for pid in targets_by_sys[pair[1]]:
				var pm: Dictionary = out.get(pid, {})
				for fid in sm:
					var v := int(sm[fid]) * int(pd["route"])
					v = v * (100 + _fx_for_faith(state, fid, "faith_route_pct") + FaithWars.nature_route_pct(state, fid)) / 100
					pm[fid] = int(pm.get(fid, 0)) + v
				out[pid] = pm
	# Poussée de la foi d'État sur chaque colonie de l'empire.
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.is_colony() or not c.is_established() or GameState.is_npc(c.owner) or is_hive(state, c.owner):
			continue
		var sf := state_faith(state, c.owner)
		if sf == LAICITE:
			continue
		var pm: Dictionary = out.get(pid, {})
		var v := int(pd["state_push"]) * 100 * maxi(0, 100 + Research.fx_int(state, c.owner, "faith_pressure_pct")) / 100
		pm[sf] = int(pm.get(sf, 0)) + v
		out[pid] = pm
	# Lot 2 : missions, flottes (parasite saint), réseaux d'espionnage (mème).
	FaithWars.extra_pressures(state, out, targets_by_sys)
	# Zèle : la pression varie de (zèle - 50) %. (points en centièmes)
	for pid in out:
		var pm: Dictionary = out[pid]
		for fid in pm:
			pm[fid] = int(pm[fid]) * maxi(0, 50 + FaithWars.zeal(state, fid)) / 100 / 100
	return out


## Valeur d'un effet de dogme pour une foi (dogmes de la foi elle-même, pas de l'empire).
static func _fx_for_faith(state: GameState, fid: String, key: String) -> int:
	var v := 0
	for d in faith(state, fid).get("dogmas", []):
		v += int(dogma_def(String(d)).get("fx", {}).get(key, 0))
	return v


## Points nécessaires pour convertir un habitant.
@warning_ignore("integer_division")
static func threshold(state: GameState, c: Colony, fid: String) -> int:
	var pd: Dictionary = data()["pressure"]
	var t := int(pd["threshold_base"]) + int(pd["threshold_per_pop"]) * c.population
	# Résistance : celle de la foi d'État du propriétaire, contre une autre foi.
	var sf := state_faith(state, c.owner)
	if sf != fid and sf != LAICITE and int(c.faith.get(sf, 0)) > 0:
		t = t * maxi(25, 100 + Research.fx_int(state, c.owner, "faith_resist_pct")) / 100
	return t


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not state.faith_on:
		return
	# Voie du savoir.
	for e in state.empires:
		if not e.eliminated and can_found(state, e.id) and _knows_soul_sciences(state, e.id):
			reveal(state, e.id, "savoir", -1, added)
	_spread(state)
	FaithWars.monthly(state, added)
	_update_slots(state)
	_ai(state)


static func _spread(state: GameState) -> void:
	var press := pressures(state)
	var prog: Dictionary = state.faiths["prog"]
	var keep := {}
	var pids := press.keys()
	pids.sort()
	for pid in pids:
		var c: Colony = state.colonies.get(pid)
		if c == null:
			continue
		var pm: Dictionary = press[pid]
		var key := str(pid)
		var cur: Dictionary = prog.get(key, {})
		var nxt := {}
		for fid in _sorted_keys(pm):
			var v := int(pm[fid])
			if v <= 0:
				continue
			# Colonie déjà toute acquise : rien à gagner.
			if int(c.faith.get(fid, 0)) >= c.population:
				continue
			var pts := int(cur.get(fid, 0)) + v
			var th := threshold(state, c, fid)
			while pts >= th and int(c.faith.get(fid, 0)) < c.population:
				if not _convert_one(c, fid):
					break
				pts -= th
			if int(c.faith.get(fid, 0)) < c.population:
				nxt[fid] = mini(pts, th)
		if not nxt.is_empty():
			keep[key] = nxt
	state.faiths["prog"] = keep


## Dogmes : un de plus à chaque palier de fidèles franchi (jamais repris).
static func _update_slots(state: GameState) -> void:
	for fid in ids(state):
		var f: Dictionary = state.faiths["list"][fid]
		var n := followers(state, fid)
		var slots := 1
		for t in data()["tiers"]:
			if n >= int(t):
				slots += 1
		f["slots"] = maxi(int(f["slots"]), slots)


# --- Dogmes --------------------------------------------------------------------------------------

static func dogma_def(did: String) -> Dictionary:
	return data()["dogmas"].get(did, {})


static func dogma_ids() -> Array:
	var out := []
	for k in data()["dogmas"]:
		out.append(String(k))
	return out


static func free_slots(state: GameState, fid: String) -> int:
	var f := faith(state, fid)
	if f.is_empty():
		return 0
	return maxi(0, int(f["slots"]) - (f["dogmas"] as Array).size())


## "" si le joueur peut ajouter ce dogme à cette foi, sinon la raison du refus.
static func check_dogma(state: GameState, player: int, fid: String, did: String) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	var f := faith(state, fid)
	if f.is_empty():
		return "foi inconnue"
	if head(state, fid) != player:
		return "seul le chef de foi (l'empire qui compte le plus de fidèles) choisit les dogmes"
	var d := dogma_def(did)
	if d.is_empty():
		return "dogme inconnu"
	if free_slots(state, fid) <= 0:
		return "aucun dogme à choisir : il faut plus de fidèles (paliers %s)" % ", ".join(PackedStringArray(Array(data()["tiers"]).map(func(x): return str(x))))
	var have: Array = f["dogmas"]
	if have.has(did):
		return "cette foi suit déjà ce dogme"
	for h in have:
		if (d.get("excl", []) as Array).has(h) or (dogma_def(String(h)).get("excl", []) as Array).has(did):
			return "incompatible avec « %s »" % String(dogma_def(String(h))["label"])
	return ""


static func add_dogma(state: GameState, fid: String, did: String) -> void:
	(state.faiths["list"][fid]["dogmas"] as Array).append(did)
	Relics.touch(state)


# --- Foi d'État ----------------------------------------------------------------------------------

## Part (en %) d'une foi sur la colonie de l'empire où elle est la plus forte.
static func best_share(state: GameState, eid: int, fid: String) -> int:
	var best := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.population > 0:
			@warning_ignore("integer_division")
			best = maxi(best, int(c.faith.get(fid, 0)) * 100 / c.population)
	return best


static func check_state(state: GameState, player: int, fid: String) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	if is_hive(state, player):
		return "une conscience collective n'a pas de foi"
	if fid == state_faith(state, player):
		return "c'est déjà votre foi d'État"
	if fid != LAICITE and fid != INCROYANCE and faith(state, fid).is_empty():
		return "foi inconnue"
	var last := int(state.faiths["changed"].get(str(player), -100000))
	var cd := int(data()["state"]["cooldown_days"])
	if state.tick - last < cd:
		return "le clergé n'a pas digéré le dernier changement (encore %d jours)" % (cd - (state.tick - last))
	if fid != LAICITE and fid != INCROYANCE and founded_by(state, player) != fid:
		var need := int(data()["state"]["adopt_share_pct"])
		if best_share(state, player, fid) < need:
			return "il faut une de vos colonies où cette foi dépasse %d %%" % need
	return ""


static func set_state(state: GameState, player: int, fid: String) -> void:
	state.faiths["state"][str(player)] = fid
	state.faiths["changed"][str(player)] = state.tick
	Relics.touch(state)


# --- Effets --------------------------------------------------------------------------------------

## Effets (mêmes clés que les technologies, voir Research.effects) : culte natal du peuple et
## dogmes de la foi d'État.
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not state.faith_on or GameState.is_npc(eid):
		return out
	var nat := native_def(state, eid)
	if not nat.is_empty():
		Research._merge(out, nat.get("fx", {}))
	var sf := state_faith(state, eid)
	if sf == INCROYANCE:
		Research._merge(out, data()["pseudo"][INCROYANCE].get("fx", {}))
	elif sf != LAICITE:
		for d in faith(state, sf).get("dogmas", []):
			Research._merge(out, dogma_def(String(d)).get("fx", {}))
		Research._merge(out, FaithWars.nature_fx(state, sf))
	return out


static func native_def(state: GameState, eid: int) -> Dictionary:
	if is_hive(state, eid):
		return {}
	return data()["native"].get(Events.layer_value(state, eid, "credo"), {})


## Stabilité d'un système (Stability.parts).
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if not state.faith_on or GameState.is_npc(owner) or is_hive(state, owner):
		return out
	var sd: Dictionary = data()["state"]
	var sf := state_faith(state, owner)
	var last := int(state.faiths["changed"].get(str(owner), -100000))
	if state.tick - last < int(sd["change_days"]):
		out.append(["Changement de foi d'État", int(sd["change_stab"])])
	out.append_array(FaithWars.stability_parts(state, sid, owner))
	if sf == LAICITE:
		return out
	var m := system_majority(state, sid, owner)
	if m == sf:
		out.append(["Foi d'État majoritaire", int(sd["stab_major"]) + Research.fx_int(state, owner, "faith_stab")])
	elif m != NATIVE and Research.fx_int(state, owner, "faith_tolerance") <= 0 and FaithWars.visible_to(state, m, owner):
		var v := mini(0, int(sd["stab_minor"]) + Research.fx_int(state, owner, "faith_minor_stab"))
		if v != 0:
			out.append(["Autre foi majoritaire (%s)" % name_of(state, m), v])
	return out


## Croyance majoritaire parmi les colonies d'un empire dans un système.
static func system_majority(state: GameState, sid: int, owner: int) -> String:
	var cnt := {}
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_colony():
			continue
		var cc := counts(c)
		for fid in cc:
			cnt[fid] = int(cnt.get(fid, 0)) + int(cc[fid])
	var best := NATIVE
	var best_n := int(cnt.get(NATIVE, 0))
	for fid in _sorted_keys(cnt):
		if fid != NATIVE and int(cnt[fid]) > best_n:
			best = fid
			best_n = int(cnt[fid])
	return best


## Opinion de a envers b (Diplomacy.opinion_parts).
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	if not state.faith_on or GameState.is_npc(a) or GameState.is_npc(b):
		return out
	var fa := state_faith(state, a)
	var fb := state_faith(state, b)
	out.append_array(FaithWars.opinion_parts(state, a, b))
	if fa == LAICITE or fb == LAICITE:
		return out
	var od: Dictionary = data()["opinion"]
	if fa == fb:
		out.append(["Même foi (%s)" % name_of(state, fa), int(od["same"]) + Research.fx_int(state, a, "faith_same_op")])
	else:
		out.append(["Fois rivales (%s)" % name_of(state, fb), mini(0, int(od["rival"]) + Research.fx_int(state, a, "faith_rival_op"))])
		var oth := Research.fx_int(state, b, "faith_others_op")
		if oth != 0:
			out.append(["Pratiques de %s" % name_of(state, fb), oth])
	return out


## Ferveur (proposition 9) : une colonie ne chante pour le dieu que si la foi d'État y domine.
static func is_faithful(state: GameState, c: Colony) -> bool:
	if not state.faith_on:
		return true
	var sf := state_faith(state, c.owner)
	if sf == LAICITE:
		return true
	return majority(c) == sf


# --- IA ------------------------------------------------------------------------------------------

static func _ai(state: GameState) -> void:
	for e in state.empires:
		if e.eliminated or not e.is_ai() or is_hive(state, e.id):
			continue
		_ai_state(state, e.id)
	for fid in ids(state):
		var h := head(state, fid)
		if h < 0:
			continue
		var he := state.get_empire(h)
		if he == null or not he.is_ai():
			continue
		while free_slots(state, fid) > 0:
			var did := ai_pick_dogma(state, h, fid)
			if did == "":
				break
			add_dogma(state, fid, did)


static func ai_pick_dogma(state: GameState, eid: int, fid: String) -> String:
	var ai: Dictionary = data()["ai"]
	var pref: Array = ai.get(Events.layer_value(state, eid, "credo"), ai["default"])
	var emp := state.get_empire(eid)
	if emp != null and ai.get("factions", {}).has(emp.faction_id):
		pref = ai["factions"][emp.faction_id]
	# Parmi les trois premiers dogmes possibles de la liste, un tirage haché : deux fois d'un même
	# credo ne finissent pas avec les mêmes dogmes.
	var ok: Array = []
	for did in pref:
		if check_dogma(state, eid, fid, String(did)) == "":
			ok.append(String(did))
			if ok.size() >= 3:
				break
	if not ok.is_empty():
		var n := (faith(state, fid)["dogmas"] as Array).size()
		return String(ok[0 if n == 0 else absi(hash([state.seed_value, fid, n])) % ok.size()])
	for did in dogma_ids():
		if check_dogma(state, eid, fid, did) == "":
			return did
	return ""


## Foi d'État de l'IA : sa propre foi si elle en a fondé une, sinon une grande foi qui tient la moitié
## de sa population.
@warning_ignore("integer_division")
static func _ai_state(state: GameState, eid: int) -> void:
	var sf := state_faith(state, eid)
	var own := founded_by(state, eid)
	var want := sf
	if own != "":
		want = own
	else:
		var total := 0
		var by := {}
		for pid in state.colonies:
			var c: Colony = state.colonies[pid]
			if c.owner != eid or not c.is_colony():
				continue
			total += c.population
			for fid in c.faith:
				by[fid] = int(by.get(fid, 0)) + int(c.faith[fid])
		if total <= 0:
			return
		var best := ""
		for fid in _sorted_keys(by):
			if best == "" or int(by[fid]) > int(by[best]):
				best = fid
		var need := int(data()["ai"]["adopt_share_pct"])
		if best != "" and int(by[best]) * 100 / total >= need:
			want = best
		elif sf != LAICITE and int(by.get(sf, 0)) * 100 / total < 10:
			want = LAICITE
	if want != sf and check_state(state, eid, want) == "":
		set_state(state, eid, want)


# --- Divers --------------------------------------------------------------------------------------

## Libellé court d'une colonie pour les fiches : « Liturgie 4, cultes natals 2 ».
static func colony_text(state: GameState, c: Colony, viewer := -1) -> String:
	var cnt := visible_counts(state, c, viewer)
	var parts: Array[String] = []
	for fid in _sorted_keys(c.faith):
		if cnt.has(fid):
			parts.append("%s %d" % [name_of(state, fid), int(cnt.get(fid, 0))])
	if int(cnt.get(NATIVE, 0)) > 0:
		parts.append("cultes natals %d" % int(cnt[NATIVE]))
	return ", ".join(parts)


static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k
