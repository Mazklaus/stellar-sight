class_name Admin
extends RefCounted
## Administration et corruption (étude « Administration et corruption », 2026-11-16 ; data/administration.json).
## Chaque empire a une capacité administrative ; tout ce qu'il possède crée de la charge (systèmes
## peuplés, colonies de plus, population, avant-postes, systèmes occupés). Au-dessus de la capacité,
## par tranche de 10 % : stabilité, recherche, coûts en influence et corruption de base. Chaque système
## a une corruption de 0 à 50 % (distance au siège le plus proche, population, stabilité basse,
## conquête récente…) qui détourne une part de son énergie, de ses matériaux, de son influence et de
## son Savoir. Les Préfectures sont des sièges régionaux (provinces), le Tribunal divise la corruption
## locale, l'effort administratif se règle en quatre crans. Les conquêtes arrivent non intégrées.
## Le pilier remplace la surextension (Stability) et le surcoût de recherche par colonie (Research).
## Ponts (scandales, pirates, espionnage, commerce, politique, haut fait) : AdminBridges.
##
## Réglage « Administration » : Complète (défaut d'une nouvelle partie), Simple (la jauge seule) ou
## Désactivée (rien ne tourne, state.admin reste vide). Sans l'option (tests, bancs) : désactivée.
##
## État : state.admin = {"mode", "e": {"empire": E}, "sys": {"système": propriétaire au dernier bilan},
##  "ni": {"système": 1 (non intégré)}, "integ": {"système": jour de fin}, "cor": {"système": %},
##  "seat": {"système": système siège}, "cd": {"système": jour (scandale)}, "bought": {"système": jour de fin},
##  "clean": {"empire": jour depuis lequel la corruption moyenne est basse}}.
## E = {"effort", "load", "cap", "over" (%), "lp": [[libellé, valeur]], "cp": [[libellé, valeur]],
##  "moved": jour du dernier transfert de capitale, "trans": fin de la transition, "avg": corruption moyenne}.
## Toutes les clés sont des chaînes (la sauvegarde JSON les rend ainsi).

const LAYERS := ["gouvernement", "credo", "archetype", "registre"]

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.administration()


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func d_int(section: String, key: String) -> int:
	return int((data().get(section, {}) as Dictionary).get(key, 0))


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode(state: GameState) -> String:
	return String(state.admin.get("mode", "desactivee"))


static func enabled(state: GameState) -> bool:
	return not state.admin.is_empty()


## Mode complet : corruption locale, intégration, scandales.
static func full(state: GameState) -> bool:
	return mode(state) == "complete"


static func worth_saving(state: GameState) -> bool:
	return not state.admin.is_empty()


static func setup(state: GameState, mode_id: String) -> void:
	state.admin = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactivee":
		return
	state.admin = {"mode": mode_id, "e": {}, "sys": {}, "ni": {}, "integ": {}, "cor": {}, "seat": {}, "cd": {}, "bought": {}, "clean": {}, "purge": {}}
	_scan_owners(state, [])
	refresh(state)


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.admin)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.admin = {}
	if d.is_empty():
		return
	state.admin = GameData._to_ints(d.duplicate(true))


# --- Talents -----------------------------------------------------------------------------------

static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		for k in t:
			if k == "label" or k == "text":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	var e := state.get_empire(eid)
	var out := []
	if e == null or e.is_npc():
		return out
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


static func government(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return ""
	return String(e.faction().get("species", {}).get("gouvernement", ""))


## L'empire a-t-il une corruption ? (ni la ruche, ni la conscience distribuée.)
static func has_corruption(state: GameState, eid: int) -> bool:
	return full(state) and not bool(talent(state, eid).get("no_corruption", false))


# --- Lecture -----------------------------------------------------------------------------------

static func entry(state: GameState, eid: int) -> Dictionary:
	if state.admin.is_empty():
		return {}
	return (state.admin["e"] as Dictionary).get(str(eid), {})


static func applies(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	return enabled(state) and e != null and not e.is_npc() and not e.eliminated


static func _w(state: GameState, eid: int) -> Dictionary:
	var all: Dictionary = state.admin["e"]
	if not all.has(str(eid)):
		all[str(eid)] = {"effort": String(data().get("default_effort", "normal")), "load": 0, "cap": 0, "over": 0, "lp": [], "cp": [], "moved": -100000, "trans": 0, "avg": 0}
	return all[str(eid)]


static func load_of(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("load", 0))


static func capacity(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("cap", 0))


## Dépassement en % de la capacité (0 sous la capacité).
static func over_pct(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("over", 0))


## Tranches de dépassement (10 % chacune), selon le gouvernement (conscience ×2, ruche ÷2).
static func steps(state: GameState, eid: int) -> int:
	if not applies(state, eid):
		return 0
	@warning_ignore("integer_division")
	var n := over_pct(state, eid) / maxi(1, d_int("over", "step_pct"))
	var tal := talent(state, eid)
	if int(tal.get("over_x", 0)) > 1:
		n *= int(tal["over_x"])
	if bool(tal.get("over_half", false)):
		@warning_ignore("integer_division")
		n = n / 2
	return n


static func effort_defs() -> Array:
	return data().get("efforts", [])


static func effort_def(id: String) -> Dictionary:
	for d: Dictionary in effort_defs():
		if String(d["id"]) == id:
			return d
	return {}


static func effort(state: GameState, eid: int) -> String:
	return String(entry(state, eid).get("effort", data().get("default_effort", "normal")))


static func is_integrated(state: GameState, sid: int) -> bool:
	return state.admin.is_empty() or not (state.admin["ni"] as Dictionary).has(str(sid))


static func integrating(state: GameState, sid: int) -> int:
	if state.admin.is_empty():
		return 0
	return int((state.admin["integ"] as Dictionary).get(str(sid), 0))


static func corruption(state: GameState, sid: int) -> int:
	if state.admin.is_empty():
		return 0
	return int((state.admin["cor"] as Dictionary).get(str(sid), 0))


## Siège dont dépend un système (capitale ou Préfecture), -1 s'il n'en a pas.
static func seat_of(state: GameState, sid: int) -> int:
	if state.admin.is_empty():
		return -1
	return int((state.admin["seat"] as Dictionary).get(str(sid), -1))


static func average_corruption(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("avg", 0))


static func in_transition(state: GameState, eid: int) -> bool:
	return int(entry(state, eid).get("trans", 0)) > state.tick


# --- Effets lus par les autres systèmes -------------------------------------------------------

## Surcoût de recherche (remplace celui des grands empires quand le pilier est actif), en %.
static func research_pct(state: GameState, eid: int) -> int:
	return steps(state, eid) * d_int("over", "research_pct")


## Surcoût des coûts en influence (décrets, lois, intégration), en %.
static func influence_pct(state: GameState, eid: int) -> int:
	return steps(state, eid) * d_int("over", "influence_pct")


static func influence_cost(state: GameState, eid: int, cost: Dictionary) -> Dictionary:
	var pct := influence_pct(state, eid)
	if pct == 0 or not cost.has("influence"):
		return cost
	var out := cost.duplicate()
	@warning_ignore("integer_division")
	out["influence"] = int(cost["influence"]) * (100 + pct) / 100
	return out


## Entretien des fonctionnaires (effort administratif), ajouté à l'entretien mensuel.
static func upkeep(state: GameState, eid: int) -> Dictionary:
	if not applies(state, eid):
		return {}
	var div := int(effort_def(effort(state, eid)).get("upkeep_div", 0))
	if div <= 0:
		return {}
	@warning_ignore("integer_division")
	var n := load_of(state, eid) / div
	return {"energy": n} if n > 0 else {}


## Production d'une colonie : système non intégré (production réduite), puis corruption.
static func adjust_yields(state: GameState, colony: Colony, sid: int, gross: Dictionary) -> void:
	if not is_integrated(state, sid):
		var pct := d_int("integration", "prod_pct")
		for r in gross:
			if int(gross[r]) > 0:
				@warning_ignore("integer_division")
				gross[r] = int(gross[r]) * (100 - pct) / 100
	var cor := corruption(state, sid)
	if cor <= 0:
		return
	var energy_half := bool(talent(state, colony.owner).get("energy_half", false))
	for r in (data()["corruption"]["resources"] as Array):
		var k := String(r)
		if int(gross.get(k, 0)) > 0:
			var pct := cor
			if k == "energy" and energy_half:
				@warning_ignore("integer_division")
				pct = cor / 2
			@warning_ignore("integer_division")
			gross[k] = int(gross[k]) * (100 - pct) / 100


## Sources de stabilité d'empire (remplacent la surextension).
static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not applies(state, eid):
		return out
	var n := steps(state, eid)
	if n > 0:
		out.append(["Empire trop vaste (charge %d %% de la capacité)" % (100 + over_pct(state, eid)), maxi(d_int("over", "stability_max"), n * d_int("over", "stability"))])
	var ed := effort_def(effort(state, eid))
	if int(ed.get("stability", 0)) != 0 and not bool(talent(state, eid).get("enquete_free", false)):
		out.append([String(ed["label"]), int(ed["stability"])])
	if in_transition(state, eid):
		out.append(["Transfert de la capitale", int(data()["capital_move"]["stability"])])
	out.append_array(AdminBridges.empire_stability_parts(state, eid))
	return out


## Sources de stabilité d'un système (corruption élevée).
static func system_stability_parts(state: GameState, sid: int) -> Array:
	var out := []
	var cor := corruption(state, sid)
	if cor >= d_int("corruption", "stability_from"):
		out.append(["Corruption (%d %%)" % cor, d_int("corruption", "stability_value")])
	return out


static func decree_block(state: GameState, sid: int) -> String:
	if not is_integrated(state, sid):
		return "système non intégré : pas de décret avant son intégration"
	return ""


# --- Sièges et distances -----------------------------------------------------------------------

## Sièges de l'empire : le système capitale, puis ceux qui ont une Préfecture (ordre croissant).
static func seats(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	var cap := FactionTraits.capital_system(state, eid)
	if cap >= 0:
		out.append(cap)
	var more: Array[int] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_established() and c.buildings.has("prefecture"):
			var sid := state.galaxy.get_planet(pid).system_id
			if not out.has(sid) and not more.has(sid):
				more.append(sid)
	more.sort()
	out.append_array(more)
	return out


static func _traversable(state: GameState, eid: int, sid: int) -> bool:
	var o := state.system_owner(sid)
	if o == eid or o < 0:
		return true
	if GameState.is_npc(o):
		return false
	return Diplomacy.allied(state, eid, o)


## Distance de chaque système de l'empire à son siège : {système: [sauts, siège, enclave]}.
## Comptée par son territoire, les systèmes libres et ceux des alliés ; sinon (enclave) par la galaxie.
static func distances(state: GameState, eid: int, mine: Array[int]) -> Dictionary:
	var out := {}
	var st := seats(state, eid)
	if st.is_empty():
		return out
	var dist := {}
	var seat := {}
	var queue: Array[int] = []
	for s in st:
		dist[s] = 0
		seat[s] = s
		queue.append(s)
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		for n in state.galaxy.systems[cur].neighbors:
			if dist.has(n) or not _traversable(state, eid, n):
				continue
			dist[n] = int(dist[cur]) + 1
			seat[n] = seat[cur]
			queue.append(n)
	var missing := false
	for sid in mine:
		if dist.has(sid):
			out[sid] = [int(dist[sid]), int(seat[sid]), false]
		else:
			missing = true
	if missing:
		var gd := {}
		var gs := {}
		var q: Array[int] = []
		for s in st:
			gd[s] = 0
			gs[s] = s
			q.append(s)
		var j := 0
		while j < q.size():
			var cur := q[j]
			j += 1
			for n in state.galaxy.systems[cur].neighbors:
				if gd.has(n):
					continue
				gd[n] = int(gd[cur]) + 1
				gs[n] = gs[cur]
				q.append(n)
		for sid in mine:
			if not out.has(sid):
				out[sid] = [int(gd.get(sid, 20)), int(gs.get(sid, st[0])), true]
	return out


## Province : le siège retenu pour un système, la capitale si aucune Préfecture n'est assez proche.
static func _province_seat(state: GameState, eid: int, info: Array) -> int:
	var cap := FactionTraits.capital_system(state, eid)
	if info.is_empty():
		return cap
	if int(info[1]) != cap and (int(info[0]) > d_int("provinces", "radius") or bool(info[2])):
		return cap
	return int(info[1])


# --- Bilan mensuel -----------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.admin.is_empty():
		return added
	if state.tick % int(GameData.rules()["month_days"]) != 0:
		return added
	_scan_owners(state, added)
	_finish_integrations(state, added)
	refresh(state)
	AdminBridges.monthly(state, added)
	return added


## Repère les systèmes qui ont changé de mains : une conquête, une cession, une réintégration ou une
## annexion arrive non intégrée (mode complet). Une colonisation (système sans maître) non.
static func _scan_owners(state: GameState, added: Array[Dictionary]) -> void:
	var sys: Dictionary = state.admin["sys"]
	var ni: Dictionary = state.admin["ni"]
	var now := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.is_established():
			var sid := state.galaxy.get_planet(pid).system_id
			now[str(sid)] = state.system_owner(sid)
	for k in sys.keys():
		if not now.has(k):
			sys.erase(k)
			ni.erase(k)
			(state.admin["integ"] as Dictionary).erase(k)
	for k in now:
		var o := int(now[k])
		var was := int(sys.get(k, -1))
		if was == o:
			continue
		sys[k] = o
		ni.erase(k)
		(state.admin["integ"] as Dictionary).erase(k)
		if was >= 0 and full(state) and applies(state, o):
			ni[k] = 1
			var e := state.get_empire(o)
			if not e.is_ai():
				added.append(state.add_chronicle("%s rejoint %s sans y être intégré : ses bureaux attendent nos règlements, et produisent moitié moins en attendant." % [
						state.galaxy.systems[int(k)].system_name, e.short_name()], Espionage.private_to(state, [o], int(k))))


static func _finish_integrations(state: GameState, added: Array[Dictionary]) -> void:
	var integ: Dictionary = state.admin["integ"]
	for k in integ.keys():
		if int(integ[k]) <= state.tick:
			integ.erase(k)
			(state.admin["ni"] as Dictionary).erase(k)
			var o := state.system_owner(int(k))
			var e := state.get_empire(o)
			if e != null and not e.is_ai():
				added.append(state.add_chronicle("%s est intégré à %s : mêmes tampons, mêmes formulaires, même production." % [
						state.galaxy.systems[int(k)].system_name, e.short_name()], Espionage.private_to(state, [o], int(k))))


## Recalcule charge, capacité, dépassement et corruption de chaque empire.
static func refresh(state: GameState) -> void:
	if state.admin.is_empty():
		return
	state.admin["cor"] = {}
	state.admin["seat"] = {}
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		refresh_empire(state, e.id)


static func refresh_empire(state: GameState, eid: int) -> void:
	var en := _w(state, eid)
	var lp := load_parts(state, eid)
	var cp := capacity_parts(state, eid)
	var ld := 0
	for p in lp:
		ld += int(p[1])
	var cpv := 0
	for p in cp:
		cpv += int(p[1])
	cpv = maxi(10, cpv)
	ld = maxi(0, ld)
	en["lp"] = lp
	en["cp"] = cp
	en["load"] = ld
	en["cap"] = cpv
	@warning_ignore("integer_division")
	en["over"] = maxi(0, (ld - cpv) * 100 / cpv)
	var mine := Stability.systems_of(state, eid)
	var info := distances(state, eid, mine)
	var cors: Dictionary = state.admin["cor"]
	var seat: Dictionary = state.admin["seat"]
	var total := 0
	var weight := 0
	for sid in mine:
		var di: Array = info.get(sid, [])
		seat[str(sid)] = _province_seat(state, eid, di)
		if not has_corruption(state, eid):
			continue
		var v := int(corruption_parts(state, eid, sid, di)[0])
		if v > 0:
			cors[str(sid)] = v
		var pop := maxi(1, Stability.system_pop(state, sid, eid))
		total += v * pop
		weight += pop
	@warning_ignore("integer_division")
	en["avg"] = total / weight if weight > 0 else 0


static func load_parts(state: GameState, eid: int) -> Array:
	var ld: Dictionary = data()["load"]
	var tal := talent(state, eid)
	var per_sys := {}  # système -> [colonies, avant-postes, population]
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_established():
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if not per_sys.has(sid):
			per_sys[sid] = [0, 0, 0]
		var a: Array = per_sys[sid]
		if c.is_colony():
			a[0] = int(a[0]) + 1
			a[2] = int(a[2]) + c.population
		else:
			a[1] = int(a[1]) + 1
	var n_sys := 0
	var extra := 0
	var pop := 0
	var outs := 0
	var fief_cut := 0
	var keys := per_sys.keys()
	keys.sort()
	for sid in keys:
		if not is_integrated(state, int(sid)):
			continue
		var a: Array = per_sys[sid]
		var v := 0
		if int(a[0]) > 0:
			n_sys += 1
			v += int(ld["system"])
			extra += (int(a[0]) - 1) * int(ld["extra_colony"])
			v += (int(a[0]) - 1) * int(ld["extra_colony"])
		@warning_ignore("integer_division")
		var pv := int(a[2]) / maxi(1, int(ld["pop_div"]))
		pop += pv
		v += pv
		outs += int(a[1]) * int(ld["outpost"])
		v += int(a[1]) * int(ld["outpost"])
		if bool(tal.get("fiefs_half", false)) and not state.court.is_empty() and not Court.fief_house(state, int(sid), eid).is_empty():
			@warning_ignore("integer_division")
			fief_cut += v * (100 - int(ld["fief_pct"])) / 100
	var out := []
	if n_sys > 0:
		out.append(["Systèmes peuplés (%d)" % n_sys, n_sys * int(ld["system"])])
	if extra > 0:
		out.append(["Colonies de plus dans un même système", extra])
	if pop > 0:
		out.append(["Population (1 par %d habitants)" % int(ld["pop_div"]), pop])
	if outs > 0:
		out.append(["Avant-postes", outs])
	if state.wars_on:
		var occ := WarPeace.occupied_by(state, eid).size()
		if occ > 0:
			out.append(["Systèmes occupés (%d)" % occ, occ * int(ld["occupied"])])
	if fief_cut > 0:
		out.append(["Fiefs délégués aux Grandes Maisons", -fief_cut])
	var lpct := int(tal.get("load_pct", 0))
	if lpct != 0:
		var s := 0
		for p in out:
			s += int(p[1])
		@warning_ignore("integer_division")
		out.append(["Talent du peuple (%+d %%)" % lpct, s * lpct / 100])
	return out


static func capacity_parts(state: GameState, eid: int) -> Array:
	var cd: Dictionary = data()["capacity"]
	var tal := talent(state, eid)
	var out := []
	if FactionTraits.capital_system(state, eid) >= 0:
		out.append(["Capitale", int(cd["capital"])])
	var forum := false
	var pref := 0
	var trib := 0
	var temples := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_established():
			continue
		if c.buildings.has("forum"):
			forum = true
		if c.buildings.has("prefecture"):
			pref += 1
		if c.buildings.has("tribunal"):
			trib += 1
		if c.buildings.has("temple"):
			temples += 1
	if forum:
		out.append(["Forum impérial", int(cd["forum"])])
	if pref > 0:
		out.append(["Préfectures (%d)" % pref, pref * int(cd["prefecture"])])
	if trib > 0:
		out.append(["Tribunaux (%d)" % trib, trib * int(cd["tribunal"])])
	var tv := Research.fx_int(state, eid, "stability_threshold") * int(cd["threshold_x"]) + Research.fx_int(state, eid, "admin_cap")
	if int(tal.get("cap_per_admin_tech", 0)) > 0:
		var e := state.get_empire(eid)
		for t in data().get("admin_techs", []):
			if e.techs.has(String(t)):
				tv += int(tal["cap_per_admin_tech"])
	if tv != 0:
		out.append(["Technologies", tv])
	if not state.rulers.is_empty():
		var g := int(Rulers.apts(state, eid).get("gestion", 0)) * int(cd["gestion"])
		if g > 0:
			out.append(["Souverain (Gestion)", g])
	if not state.court.is_empty() and Court.applies(state, eid):
		var gi := Court.office_apt(state, eid, "intendant") * int(cd["grand_intendant"])
		if gi > 0:
			out.append([Court.office_label(state, eid, "intendant"), gi])
	if not state.heroes.is_empty():
		var hb := 0
		for h in Heroes.council(state, eid):
			hb += Heroes.trait_fx(h, "admin_cap")
		if hb > 0:
			out.append(["Bureaucrates au conseil", hb])
	var base := 0
	for p in out:
		base += int(p[1])
	var pct := int(effort_def(effort(state, eid)).get("cap_pct", 0))
	if pct != 0:
		@warning_ignore("integer_division")
		out.append(["Effort : %s" % String(effort_def(effort(state, eid))["label"]), base * pct / 100])
	var tp := int(tal.get("cap_pct", 0))
	if tp != 0:
		@warning_ignore("integer_division")
		out.append(["Talent du peuple (%+d %%)" % tp, base * tp / 100])
	var lp := Research.fx_int(state, eid, "admin_cap_pct")
	if lp != 0:
		@warning_ignore("integer_division")
		out.append(["Lois (%+d %%)" % lp, base * lp / 100])
	return out


## Corruption d'un système : [valeur, [[libellé, valeur], …]] ; info = [sauts, siège, enclave] (vide : recalculée).
static func corruption_parts(state: GameState, eid: int, sid: int, info := []) -> Array:
	var cd: Dictionary = data()["corruption"]
	var parts := []
	if not has_corruption(state, eid):
		return [0, parts]
	if info.is_empty():
		var one: Array[int] = [sid]
		info = distances(state, eid, one).get(sid, [])
	var tal := talent(state, eid)
	var n := steps(state, eid)
	if n > 0:
		parts.append(["Empire trop vaste", n * d_int("over", "corruption")])
	var ed := effort_def(effort(state, eid))
	if int(ed.get("corruption", 0)) != 0:
		parts.append(["Effort : %s" % String(ed["label"]), int(ed["corruption"])])
	var cap := FactionTraits.capital_system(state, eid)
	if sid == cap:
		parts.append(["Capitale", int(cd["capital"])])
	elif not info.is_empty():
		var j := int(info[0])
		if Research.fx_int(state, eid, "admin_distance_half") > 0:
			@warning_ignore("integer_division")
			j = j / 2
		var dv := maxi(0, j - int(cd["free_jumps"])) * int(cd["per_jump"])
		if bool(info[2]):
			@warning_ignore("integer_division")
			dv = dv * int(cd["enclave_pct"]) / 100
		dv = mini(int(cd["distance_max"]), dv)
		if dv > 0:
			var seat_name := state.galaxy.systems[int(info[1])].system_name
			parts.append([("Enclave, loin de %s (%d sauts)" if bool(info[2]) else "Distance à %s (%d sauts)") % [seat_name, int(info[0])], dv])
	var pop := Stability.system_pop(state, sid, eid)
	if pop > int(cd["pop_from"]):
		@warning_ignore("integer_division")
		parts.append(["Grosse population", (pop - int(cd["pop_from"])) / maxi(1, int(cd["pop_div"]))])
	if Stability.applies(state, eid) and not state.stability.is_empty() and Stability.value(state, sid) < int(cd["low_stability"]):
		parts.append(["Stabilité basse", int(cd["low_stability_value"])])
	var sen := Stability.entry(state, sid)
	if sen.has("conq") and state.tick - int(sen["conq"]) < int(cd["conquered_days"]):
		parts.append(["Monde conquis", int(cd["conquered"])])
	var gov := {}
	if not state.heroes.is_empty():
		gov = Heroes.at_post(state, "system", sid, eid)
		if not gov.is_empty() and String(gov.get("cls", "")) == "intendant":
			@warning_ignore("integer_division")
			parts.append(["Gouverneur : %s" % String(gov["name"]), -(int(cd["governor_base"]) + int(cd["governor_per_level"]) * Heroes.half_levels(gov, "system") / 2)])
		if not gov.is_empty() and Heroes.trait_fx(gov, "admin_cor") != 0:
			parts.append(["%s est vénal" % String(gov["name"]), Heroes.trait_fx(gov, "admin_cor")])
		# Gouverneur de province : la moitié de son effet dans toute la province.
		if gov.is_empty() and not info.is_empty():
			var ps := _province_seat(state, eid, info)
			if ps != sid and ps >= 0:
				var pg := Heroes.at_post(state, "system", ps, eid)
				if not pg.is_empty() and String(pg.get("cls", "")) == "intendant" and _has_building(state, eid, ps, "prefecture"):
					@warning_ignore("integer_division")
					var v := (int(cd["governor_base"]) + int(cd["governor_per_level"]) * Heroes.half_levels(pg, "system") / 2) * int(cd["province_governor_pct"]) / 100
					if v > 0:
						parts.append(["Gouverneur de province : %s" % String(pg["name"]), -v])
	if not state.court.is_empty() and bool(tal.get("fiefs_half", false)):
		var h := Court.fief_house(state, sid, eid)
		if not h.is_empty() and ["furieuse", "mecontente"].has(Court.tier_id(h)):
			parts.append(["Fief de %s (%s)" % [String(h["name"]), String(Court.tier(h)["label"]).to_lower()], int(cd["scorned_house"])])
	var law := Research.fx_int(state, eid, "admin_cor")
	if law != 0:
		parts.append(["Lois", law])
	parts.append_array(AdminBridges.corruption_parts(state, eid, sid))
	parts.append_array(PrivateBridges.corruption_parts(state, eid, sid))  # repaires, comptabilité créative
	var v := 0
	for p in parts:
		v += int(p[1])
	v = maxi(0, v)
	# Multiplicateurs : talents, lois, Tribunal, gouverneur intègre.
	var pct := int(tal.get("cor_pct", 0)) + Research.fx_int(state, eid, "admin_cor_pct")
	if int(tal.get("exalted_cor_pct", 0)) != 0 and FactionTraits.has_fervor(state.get_empire(eid).faction()) and FactionTraits.is_exalted(state, eid):
		pct += int(tal["exalted_cor_pct"])
	if pct != 0 and v > 0:
		@warning_ignore("integer_division")
		var dv := v * pct / 100
		parts.append(["Talents et lois (%+d %%)" % pct, dv])
		v = maxi(0, v + dv)
	if v > 0 and (_has_building(state, eid, sid, "tribunal") or (bool(tal.get("temple_tribunal", false)) and _has_building(state, eid, sid, "temple"))):
		@warning_ignore("integer_division")
		parts.append(["Tribunal (÷2)", -(v - v / 2)])
		@warning_ignore("integer_division")
		v = v / 2
	for bid in _cor_buildings(state, eid, sid):  # Poste ou Bureau de sécurité, Cour de justice
		if v <= 0:
			break
		var bpct := int(GameData.building(bid).get("corruption_pct", 0))
		@warning_ignore("integer_division")
		var bdv := -v * -bpct / 100
		parts.append(["%s (%d %%)" % [String(GameData.building(bid).get("label", bid)), bpct], bdv])
		v = maxi(0, v + bdv)
	if v > 0 and not gov.is_empty() and Heroes.trait_fx(gov, "admin_cor_half") > 0:
		@warning_ignore("integer_division")
		parts.append(["%s est intègre (÷2)" % String(gov["name"]), -(v - v / 2)])
		@warning_ignore("integer_division")
		v = v / 2
	v = clampi(v, 0, int(cd["max"]))
	return [v, parts]


## Bâtiments distincts du système qui réduisent la corruption (corruption_pct), triés par nom.
static func _cor_buildings(state: GameState, eid: int, sid: int) -> Array[String]:
	var out: Array[String] = []
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_established():
			for b in c.buildings:
				if int(GameData.building(b).get("corruption_pct", 0)) < 0 and not out.has(b):
					out.append(b)
	out.sort()
	return out


static func _has_building(state: GameState, eid: int, sid: int, b: String) -> bool:
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_established() and c.buildings.has(b):
			return true
	return false


# --- Ordres ------------------------------------------------------------------------------------

static func check_effort(state: GameState, eid: int, id: String) -> String:
	if not applies(state, eid):
		return "l'administration n'est pas en jeu dans cette partie"
	if effort_def(id).is_empty():
		return "effort inconnu : %s" % id
	if effort(state, eid) == id:
		return "c'est déjà l'effort en vigueur"
	return ""


static func set_effort(state: GameState, eid: int, id: String) -> void:
	_w(state, eid)["effort"] = id
	refresh_empire(state, eid)


static func integrate_cost(state: GameState, eid: int, sid: int) -> Dictionary:
	var it: Dictionary = data()["integration"]
	var n := Stability.colony_systems_in(state, eid, sid)
	var v := int(it["cost_base"]) + int(it["cost_per_colony"]) * maxi(1, n)
	var tp := int(talent(state, eid).get("integrate_pct", 100))
	if tp <= 0:
		tp = 100
	@warning_ignore("integer_division")
	v = v * tp / 100
	return influence_cost(state, eid, {"influence": v})


static func check_integrate(state: GameState, eid: int, sid: int) -> String:
	if not applies(state, eid) or not full(state):
		return "l'intégration n'est pas en jeu dans cette partie"
	if state.system_owner(sid) != eid:
		return "ce système ne vous appartient pas"
	if is_integrated(state, sid):
		return "ce système est déjà intégré"
	if integrating(state, sid) > 0:
		return "l'intégration est déjà en cours"
	if Stability.applies(state, eid) and not state.stability.is_empty() and Stability.value(state, sid) < d_int("integration", "min_stability"):
		return "il faut une stabilité d'au moins %d" % d_int("integration", "min_stability")
	var cost := integrate_cost(state, eid, sid)
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "pas assez d'influence (%s)" % GameData.format_amounts(cost)
	return ""


static func integrate(state: GameState, eid: int, sid: int) -> void:
	Economy.pay(state.get_empire(eid), integrate_cost(state, eid, sid))
	var days := d_int("integration", "days")
	if Finance.has_franchise(state, sid):  # franchise fiscale : la colonie se rallie plus vite
		@warning_ignore("integer_division")
		days = days * 100 / (100 + Finance.d_int("franchises", "integ_pct"))
	(state.admin["integ"] as Dictionary)[str(sid)] = state.tick + days


## Colonies où la capitale peut aller (au moins min_pop habitants, hors capitale actuelle).
static func check_move_capital(state: GameState, eid: int, pid: int) -> String:
	if not applies(state, eid) or not full(state):
		return "le transfert de capitale n'est pas en jeu dans cette partie"
	var e := state.get_empire(eid)
	var g := government(state, eid)
	if g == "horde":
		return "la capitale d'une horde est sa flotte-ville"
	if g == "ruche":
		return "une ruche ne quitte pas son monde-ruche"
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid or not c.is_colony() or not c.is_established():
		return "il faut une de vos colonies"
	if pid == e.capital_planet:
		return "c'est déjà la capitale"
	var cm: Dictionary = data()["capital_move"]
	if c.population < int(cm["min_pop"]):
		return "il faut %d habitants (%d)" % [int(cm["min_pop"]), c.population]
	if not is_integrated(state, state.galaxy.get_planet(pid).system_id):
		return "ce système n'est pas intégré"
	var last := int(entry(state, eid).get("moved", -100000))
	if state.tick - last < int(cm["cooldown_days"]):
		@warning_ignore("integer_division")
		return "un transfert tous les %d ans au plus (encore %d ans)" % [int(cm["cooldown_days"]) / 360, (int(cm["cooldown_days"]) - (state.tick - last)) / 360 + 1]
	if not Economy.can_afford(e, cm["cost"]):
		return "il faut %s" % GameData.format_amounts(cm["cost"])
	return ""


static func move_capital(state: GameState, eid: int, pid: int) -> Dictionary:
	var e := state.get_empire(eid)
	var cm: Dictionary = data()["capital_move"]
	Economy.pay(e, cm["cost"])
	var old: Colony = state.colonies.get(e.capital_planet)
	var nc: Colony = state.colonies[pid]
	if old != null and old.owner == eid and old.buildings.has("capitale"):
		old.buildings.erase("capitale")
		if not nc.buildings.has("capitale"):
			nc.buildings.append("capitale")
	e.capital_planet = pid
	var en := _w(state, eid)
	en["moved"] = state.tick
	en["trans"] = state.tick + int(cm["transition_days"])
	state.relic_rev += 1
	refresh_empire(state, eid)
	return state.add_chronicle("%s transfère sa capitale à %s. Les archives suivent en convoi ; les courtisans, en traînant les pieds." % [
			e.display_name(), state.galaxy.get_planet(pid).display_name(state.galaxy)], Espionage.public_to(state, [eid]))
