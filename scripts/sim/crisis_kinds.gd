class_name CrisisKinds
extends RefCounted
## Crises de fin de partie, lot 2 (voir Crisis et data/crises.json) : les crises sans flotte (la Nuit
## lente qui éteint les étoiles, le Grand Krach qui suit les routes commerciales), le grand chantier
## commun qui les arrête, le Roi-Corsaire (repaires ralliés, évasion, héritiers), les pactes, les
## convois, les armes du désespoir et les traces que laisse une crise après sa fin.
##
## État ajouté : cur["dark"] {système: jour éteint}, cur["ring"], cur["night_next"] (Nuit) ;
## cur["infected"] {empire: jour}, cur["origin_e"] (Krach) ; cur["need"], cur["fund"] (chantier) ;
## cur["pact"] {empire: jour}, cur["arks"] {empire: jour}, cur["convoys"] {flotte: système visé},
## cur["arms"] {empire: armes obtenues}, cur["escaped"], cur["absorbed"] [repaires] ;
## state.crisis["scars"] {système: {"until", "pct", "label"}}, ["dark_after"] {système: anneau},
## ["remnants"] {flotte: jour de fin}, ["dep"] {"until", "stab", "trade_pct", "who"}.


static func _d() -> Dictionary:
	return Crisis.data()


static func _kd(state: GameState) -> Dictionary:
	return Crisis.kind_def(Crisis.kind(state))


static func _cur(state: GameState) -> Dictionary:
	return Crisis.cur(state)


# --- Arrivée des crises sans flotte -----------------------------------------------------------------

static func arrive_fleetless(state: GameState, k: String, added: Array[Dictionary]) -> void:
	var c := _cur(state)
	var kd := Crisis.kind_def(k)
	var alive := 0
	for e in state.empires:
		if not e.eliminated:
			alive += 1
	var pj: Dictionary = kd.get("project", {})
	c["need"] = int(pj.get("need_per_empire", 1000)) * maxi(1, alive)
	c["fund"] = 0
	match k:
		"nuit":
			c["dark"] = {}
			c["ring"] = 0
			c["arks"] = {}
			_darken(state, int(c["origin"]), added)
			c["night_next"] = state.tick + int(kd["night"]["ring_days"])
			Crisis._push_all(state, "crise_arches", int(c["origin"]), added)
		"krach":
			c["infected"] = {}
			_infect(state, int(c.get("origin_e", -1)), -1, added)
	for e in state.empires:
		e.path_cache.clear()


static func fleetless_day(state: GameState, added: Array[Dictionary]) -> void:
	var c := _cur(state)
	match String(c["kind"]):
		"nuit":
			_night_day(state, added)
		"krach":
			_krach_day(state, added)


# --- La Nuit lente ----------------------------------------------------------------------------------

static func is_dark(state: GameState, sid: int) -> bool:
	if state.crisis.is_empty():
		return false
	return (_cur(state).get("dark", {}) as Dictionary).has(sid) or (state.crisis.get("dark_after", {}) as Dictionary).has(sid)


static func dark_count(state: GameState) -> int:
	return (_cur(state).get("dark", {}) as Dictionary).size()


static func _darken(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var dk: Dictionary = _cur(state)["dark"]
	if dk.has(sid):
		return
	dk[sid] = state.tick
	if state.system_owner(sid) >= 0 and not GameState.is_npc(state.system_owner(sid)):
		added.append(state.add_chronicle(String(Crisis.fate_of(state).get("fall", "%s s'éteint.")) % state.galaxy.systems[sid].system_name))


static func _night_day(state: GameState, added: Array[Dictionary]) -> void:
	var c := _cur(state)
	var kd := _kd(state)
	var nd: Dictionary = kd["night"]
	if state.tick >= int(c["night_next"]):
		c["night_next"] = state.tick + int(nd["ring_days"])
		c["ring"] = int(c["ring"]) + 1
		var j := FactionTraits.jumps_from(state.galaxy, int(c["origin"]))
		var n := 0
		for s in state.galaxy.systems:
			if int(j.get(s.id, -1)) == int(c["ring"]):
				_darken(state, s.id, added)
				n += 1
		if n > 0:
			added.append(state.add_chronicle("La Nuit lente avance : %d étoile%s de plus s'éteigne%s. %d %% de la galaxie est dans le noir." % [
					n, "s" if n > 1 else "", "nt" if n > 1 else "", dark_count(state) * 100 / maxi(1, state.galaxy.systems.size())]))
	# Les habitants fuient les mondes éteints (vers la capitale s'il y a des Arches).
	var fate := Crisis.fate_of(state)
	var every := maxi(1, int(fate.get("flee_days", 90)))
	var dk: Dictionary = c["dark"]
	var ids := dk.keys()
	ids.sort()
	for k in ids:
		var sid := int(k)
		if state.tick == int(dk[k]) or (state.tick - int(dk[k])) % every != 0:
			continue
		for pid in state.galaxy.systems[sid].planet_ids:
			var col: Colony = state.colonies.get(pid)
			if col == null or GameState.is_npc(col.owner) or col.population <= 1:
				continue
			col.population -= int(fate.get("flee_pop", 1))
			col.population = maxi(1, col.population)
			var e := state.get_empire(col.owner)
			if e != null and (c.get("arks", {}) as Dictionary).has(col.owner) and e.capital_planet >= 0 and e.capital_planet != pid:
				var cap: Colony = state.colonies.get(e.capital_planet)
				if cap != null:
					cap.population += 1
	if dark_count(state) * 100 >= int(nd["defeat_pct"]) * state.galaxy.systems.size() and state.winner.is_empty():
		Crisis._finish(state, "defaite", -1, added)


# --- Le Grand Krach ---------------------------------------------------------------------------------

## L'empire le plus dépendant du commerce (plus gros revenu commercial en énergie), -1 sans commerce.
static func krach_origin(state: GameState) -> int:
	var best := -1
	var best_v := 0
	for e in state.empires:
		if e.eliminated:
			continue
		var v := int(Trade.income(state, e.id).get("energy", 0))
		if v > best_v:
			best_v = v
			best = e.id
	return best


static func infected(state: GameState, eid: int) -> bool:
	return String(_cur(state).get("kind", "")) == "krach" and (_cur(state).get("infected", {}) as Dictionary).has(eid)


static func _infect(state: GameState, eid: int, from: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	if e == null or e.eliminated or infected(state, eid):
		return
	(_cur(state)["infected"] as Dictionary)[eid] = state.tick
	Relics.touch(state)
	if from < 0:
		added.append(state.add_chronicle("Le Krach frappe %s : banques fermées, chantiers arrêtés, files d'attente devant les guichets." % e.display_name()))
	else:
		added.append(state.add_chronicle("La panique passe par les routes commerciales : le Krach gagne %s, venu de %s." % [e.display_name(), state.get_empire(from).short_name()]))


static func _krach_day(state: GameState, added: Array[Dictionary]) -> void:
	var c := _cur(state)
	var kr: Dictionary = _kd(state)["krach"]
	var inf: Dictionary = c["infected"]
	var month := int(GameData.rules()["month_days"])
	if state.tick % month == 0:
		var ids := inf.keys()
		ids.sort()
		for k in ids:
			var eid := int(k)
			var e := state.get_empire(eid)
			if e == null or e.eliminated:
				continue
			# Inflation : les réserves d'énergie fondent.
			@warning_ignore("integer_division")
			e.resources["energy"] = maxi(0, int(e.resources.get("energy", 0)) * (100 - CrisisAllies.scaled(int(kr["inflation_pct"]), CrisisAllies.tal(state, eid, "inflation_pct"))) / 100)
			# Contagion par les routes commerciales (couper ses traités protège).
			for o in Trade.partners(state, eid):
				if not inf.has(o) and Crisis._h(state, ["krach", eid, o, state.tick]) % 100 < CrisisAllies.scaled(int(kr["spread_pct"]), CrisisAllies.tal(state, o, "spread_pct")):
					_infect(state, o, eid, added)
	# Les ruinés rejoignent les pirates.
	var pd := maxi(1, int(kr["pirates_days"]))
	if (state.tick - int(c.get("arrived", 0))) % pd == 0 and state.tick > int(c.get("arrived", 0)):
		var ids2 := inf.keys()
		ids2.sort()
		for k in ids2:
			var sid := _least_stable(state, int(k))
			if sid >= 0:
				var f := Curios.spawn_trap(state, sid, 2)
				f.fleet_name = "Ruinés du Krach"
				added.append(state.add_chronicle("Ruinés par le Krach, des équipages de %s passent à la piraterie près de %s." % [state.get_empire(int(k)).short_name(), state.galaxy.systems[sid].system_name]))
	if state.tick - int(c.get("arrived", 0)) >= int(kr["limit_days"]):
		Crisis._finish(state, "depression", -1, added)


static func _least_stable(state: GameState, eid: int) -> int:
	var best := -1
	var best_v := 1 << 30
	for pid in state.sorted_colony_ids():
		var col: Colony = state.colonies[pid]
		if col.owner != eid:
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		var e := state.get_empire(eid)
		if e != null and e.capital_planet == pid:
			continue
		var v := Stability.value(state, sid)
		if v < best_v:
			best_v = v
			best = sid
	return best


## Revenu commercial d'un empire, en % (Krach : divisé par deux ; Grande Dépression : séquelles).
static func trade_pct(state: GameState, eid: int) -> int:
	if state.crisis.is_empty():
		return 100
	if infected(state, eid):
		return 100 - CrisisAllies.scaled(100 - int(_kd(state)["krach"]["trade_pct"]), CrisisAllies.tal(state, eid, "trade_cut_pct"))
	var dep: Dictionary = state.crisis.get("dep", {})
	if not dep.is_empty() and state.tick < int(dep["until"]) and (dep["who"] as Array).has(eid):
		return int(dep["trade_pct"])
	return 100


## Trade.compute : le revenu commercial des empires touchés par le Krach.
static func adjust_trade_income(state: GameState, income: Dictionary) -> void:
	if state.crisis.is_empty():
		return
	for k in income.keys():
		var pct := trade_pct(state, int(k))
		if pct == 100:
			continue
		var inc: Dictionary = income[k]
		for r in inc:
			if int(inc[r]) > 0:
				@warning_ignore("integer_division")
				inc[r] = int(inc[r]) * pct / 100


# --- Le grand chantier commun (Phare des Âges, Banque des Étoiles) ----------------------------------

static func project(state: GameState) -> Dictionary:
	return _kd(state).get("project", {}) if Crisis.active(state) else {}


static func project_pct(state: GameState) -> int:
	var c := _cur(state)
	@warning_ignore("integer_division")
	return mini(100, int(c.get("fund", 0)) * 100 / maxi(1, int(c.get("need", 1))))


static func check_fund(state: GameState, eid: int, res: String) -> String:
	var pj := project(state)
	if pj.is_empty():
		return "aucun grand chantier commun en cours"
	if res != "energy" and res != "materials":
		return "ressource inconnue"
	if Crisis.pacted(state, eid):
		return "vous avez pactisé avec la crise"
	var e := state.get_empire(eid)
	if e == null or int(e.resources.get(res, 0)) < int(pj.get("pack", 100)):
		return "pas assez de %s" % GameData.resource_label(res).to_lower()
	return ""


static func fund(state: GameState, eid: int, res: String, added: Array[Dictionary]) -> void:
	var pj := project(state)
	var pack := int(pj.get("pack", 100))
	var e := state.get_empire(eid)
	e.resources[res] = int(e.resources.get(res, 0)) - pack
	var c := _cur(state)
	var worth := CrisisAllies.scaled(pack, CrisisAllies.tal(state, eid, "fund_pct"))  # Veilleurs du ciel : double
	c["fund"] = int(c.get("fund", 0)) + worth
	Crisis.add_contrib(state, eid, worth)
	if int(c["fund"]) >= int(c["need"]):
		added.append(state.add_chronicle("%s est achevé ! %s" % [String(pj.get("name", "Le grand chantier")),
				"Il s'allume, et la Nuit recule d'un pas, puis d'un autre." if String(c["kind"]) == "nuit" else "Les guichets ouvrent, la confiance revient, les files d'attente se dispersent."]))
		Crisis._finish(state, "victoire", -1, added)


# --- Roi-Corsaire ------------------------------------------------------------------------------------

## Repaires ralliés à la Horde : leurs gardes rejoignent le Roi (elles reviendront à sa mort).
static func lair_sites(state: GameState, n: int) -> Array[int]:
	var c := _cur(state)
	var origin := int(c["origin"])
	var out: Array[int] = []
	var absorbed: Array = []
	for sid in Pirates.lair_ids(state):
		if Pirates.is_port(state, sid):
			continue
		if sid != origin and out.size() < n:
			out.append(sid)
		elif sid != origin:
			continue
		_absorb(state, sid)
		absorbed.append(sid)
	c["absorbed"] = absorbed
	if out.size() < n:
		for sid in Crisis._spread_sites(state, origin, n - out.size(), true):
			if not out.has(sid):
				out.append(sid)
	return out


static func _absorb(state: GameState, sid: int) -> void:
	var g := Pirates.guard_fleet(state, sid)
	if g != null:
		state.fleets.erase(g.id)
	var lair: Dictionary = state.lairs[sid]
	lair["guard"] = -1
	lair["lost"] = state.tick + 1000000  # pas de nouvelle garde tant que la Horde tient le repaire


## Le cœur vient de tomber : le Roi-Corsaire s'échappe une fois vers un de ses repaires.
static func escape(state: GameState, sid: int, by: int, added: Array[Dictionary]) -> bool:
	var c := _cur(state)
	var kd := _kd(state)
	if not bool(kd.get("escape", false)) or bool(c.get("escaped", false)):
		return false
	var to := -1
	for f in Crisis.stations(state):
		if Crisis.role_of(state, f.id) == Crisis.ROLE_STATION:
			to = f.system_id
			break
	if to < 0:
		return false
	c["escaped"] = true
	@warning_ignore("integer_division")
	Crisis._station(state, String(kd["heart"]), to, int(c["power"]) * int(_d()["power"]["heart_pct"]) / 200, Crisis.ROLE_HEART)
	Crisis.add_contrib(state, by, int(_d()["contrib"]["station"]))
	added.append(state.add_chronicle("Le Trône flottant explose... mais le Roi-Corsaire s'est enfui dans une chaloupe vers %s. « On ne tue pas un roi deux fois », dit-il. On va voir." % state.galaxy.systems[to].system_name))
	return true


## Mort du Roi : ses repaires retrouvent des capitaines, et ses lieutenants se partagent la Horde.
static func _successors(state: GameState, added: Array[Dictionary]) -> void:
	var c := _cur(state)
	var sites: Array = []
	for f in Crisis.stations(state):
		if not sites.has(f.system_id) and state.system_owner(f.system_id) < 0:
			sites.append(f.system_id)
	for sid in c.get("absorbed", []):
		if not sites.has(int(sid)):
			sites.append(int(sid))
	var n := 0
	for sid in sites:
		if n >= 3:
			break
		if state.lairs.has(int(sid)):
			var lair: Dictionary = state.lairs[int(sid)]
			lair["lost"] = -1
			Pirates.spawn_guard(state, int(sid))
		else:
			Pirates.create_lair(state, int(sid))
		n += 1
	if n > 0:
		added.append(state.add_chronicle("Le Roi-Corsaire est mort, et la Horde se morcelle : %d de ses lieutenants se taillent chacun un repaire, et se jurent une haine éternelle." % n))


# --- Pactes (prop. 21) ------------------------------------------------------------------------------

static func pact(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var c := _cur(state)
	if not Crisis.active(state) or not _kd(state).has("pact") or Crisis.pacted(state, eid):
		return
	(c["pact"] as Dictionary)[eid] = state.tick
	(c["front"] as Dictionary).erase(eid)
	for e in state.empires:
		if not e.eliminated and e.id != eid and not CrisisAllies.tal_flag(state, eid, "pact_free"):
			Diplomacy.remember(state, e.id, eid, "crisis_pact")
	# La crise rend les systèmes qu'elle tenait chez son nouvel allié.
	for sid in (c["held"] as Dictionary).keys():
		if state.system_owner(int(sid)) == eid:
			(c["held"] as Dictionary).erase(sid)
	Relics.touch(state)
	for e in state.empires:
		e.path_cache.clear()
	added.append(state.add_chronicle("%s pactise avec %s. Les autres empires s'en souviendront." % [state.get_empire(eid).display_name(), Crisis.obj_name(Crisis.name_of(Crisis.kind(state)))]))


## Tribut mensuel des empires soumis (Roi-Corsaire).
static func pacts_day(state: GameState, _added: Array[Dictionary]) -> void:
	var pct := int(_kd(state).get("pact", {}).get("tribute_pct", 0))
	if pct <= 0 or state.tick % int(GameData.rules()["month_days"]) != 0:
		return
	var pc: Dictionary = _cur(state).get("pact", {})
	var ids := pc.keys()
	ids.sort()
	for k in ids:
		var e := state.get_empire(int(k))
		if e != null and not e.eliminated:
			@warning_ignore("integer_division")
			e.resources["energy"] = maxi(0, int(e.resources.get("energy", 0)) * (100 - CrisisAllies.scaled(pct, CrisisAllies.tal(state, e.id, "tribute_pct"))) / 100)


# --- Convois (prop. 20) -----------------------------------------------------------------------------

static func convoys_day(state: GameState, added: Array[Dictionary]) -> void:
	var c := _cur(state)
	var kd := _kd(state)
	var cv: Dictionary = kd.get("convoy", {})
	var cfg: Dictionary = _d().get("convoy", {})
	if cv.is_empty() or cfg.is_empty():
		return
	var conv: Dictionary = c["convoys"]
	# Arrivées : le convoi répare le point faible visé.
	for k in conv.keys():
		var f: Fleet = state.fleets.get(int(k))
		if f == null or f.ships.is_empty():
			continue
		if not f.is_moving() and f.system_id == int(conv[k]) and not state.battles.has(f.system_id):
			for st in Crisis.stations(state):
				if st.system_id == f.system_id:
					for i in st.ships.size():
						st.hp[i] = Fleet.max_hp_of(st.ships[i])
			state.fleets.erase(int(k))
			conv.erase(k)
	var every := maxi(30, int(cfg["every_days"]))
	var since := int(c.get("arrived", 0))
	if state.tick <= since or (state.tick - since) % every != 0:
		return
	var sts := Crisis.stations(state)
	if sts.size() < 2:
		return
	var a: Fleet = sts[Crisis._h(state, ["convoi", state.tick]) % sts.size()]
	var b: Fleet = sts[(Crisis._h(state, ["convoi", state.tick]) + 1) % sts.size()]
	@warning_ignore("integer_division")
	var f := Crisis._build(state, String(cv["unit"]), a.system_id, maxi(150, int(c["power"]) * int(cfg["power_pct"]) / 100))
	f.fleet_name = "%s vers %s" % [String(GameData.ship(String(cv["unit"])).get("label", "Convoi")), state.galaxy.systems[b.system_id].system_name]
	var route := Fleets.plan_route(state, f, b.system_id)
	if route.is_empty():
		state.fleets.erase(f.id)
		return
	f.path.assign(route["path"])
	conv[f.id] = b.system_id
	added.append(state.add_chronicle("Un convoi %s part de %s vers %s : l'intercepter rapporterait gros." % [Crisis.de_name(Crisis.name_of(Crisis.kind(state))),
			state.galaxy.systems[a.system_id].system_name, state.galaxy.systems[b.system_id].system_name]))


## Après une bataille contre la crise : un convoi détruit récompense le meilleur combattant.
static func on_battle_convoys(state: GameState, top: int, added: Array[Dictionary]) -> void:
	var conv: Dictionary = _cur(state).get("convoys", {})
	var cfg: Dictionary = _d().get("convoy", {})
	for k in conv.keys():
		var f: Fleet = state.fleets.get(int(k))
		if f != null and not f.ships.is_empty():
			continue
		conv.erase(k)
		if f != null:
			state.fleets.erase(int(k))
		var e := state.get_empire(top)
		if e == null or GameState.is_npc(top):
			continue
		for r in cfg.get("loot", {}):
			e.resources[r] = int(e.resources.get(r, 0)) + Events.era_scaled(state, top, int(cfg["loot"][r]))
		Crisis.add_contrib(state, top, int(cfg.get("contrib", 80)))
		added.append(state.add_chronicle("%s intercepte un convoi %s et se sert dans ses cales." % [e.display_name(), Crisis.de_name(Crisis.name_of(Crisis.kind(state)))]))


static func is_convoy(state: GameState, fid: int) -> bool:
	return (_cur(state).get("convoys", {}) as Dictionary).has(fid)


# --- Armes du désespoir (prop. 18) ------------------------------------------------------------------

## Assez d'épaves étudiées (points de contribution) : une arme propre à la crise, jusqu'à sa fin.
static func arms_check(state: GameState, added: Array[Dictionary]) -> void:
	var wl: Array = _kd(state).get("weapons", [])
	if wl.is_empty():
		return
	var c := _cur(state)
	var arms: Dictionary = c["arms"]
	var ct: Dictionary = c["contrib"]
	var ids := ct.keys()
	ids.sort()
	for k in ids:
		var eid := int(k)
		var n := int(arms.get(eid, 0))
		while n < wl.size() and int(ct[k]) >= int(wl[n]["at"]):
			Crisis.add_boon(state, eid, String(wl[n]["label"]), wl[n]["fx"], -1)
			added.append(state.add_chronicle("En étudiant les épaves de %s, les ingénieurs de %s mettent au point : %s." % [
					Crisis.name_of(Crisis.kind(state)), state.get_empire(eid).display_name(), String(wl[n]["label"])], Espionage.private_to(state, [eid], -1)))
			n += 1
		arms[eid] = n


# --- Fin de crise et traces durables (prop. 25) -----------------------------------------------------

static func on_finish(state: GameState, result: String, added: Array[Dictionary]) -> void:
	var c := _cur(state)
	var kd := _kd(state)
	var k := String(c["kind"])
	if not state.crisis.has("scars"):
		state.crisis["scars"] = {}
	# Les repaires ralliés retrouvent leurs pirates.
	if k == "corsaire":
		if result == "victoire" and bool(kd.get("successors", false)):
			_successors(state, added)
		else:
			for sid in c.get("absorbed", []):
				if state.lairs.has(int(sid)):
					state.lairs[int(sid)]["lost"] = -1
					Pirates.spawn_guard(state, int(sid))
	if result != "victoire" and result != "depression":
		return
	# Cicatrices : systèmes tombés (et Mondes-Récifs) à reprendre.
	var sc: Dictionary = kd.get("scar", {})
	if not sc.is_empty():
		var sites := (c.get("held", {}) as Dictionary).keys()
		for f in Crisis.stations(state):
			if Crisis.role_of(state, f.id) == Crisis.ROLE_STATION and state.system_owner(f.system_id) >= 0:
				sites.append(f.system_id)
		for sid in sites:
			state.crisis["scars"][int(sid)] = {"until": state.tick + int(sc["days"]), "pct": int(sc["pct"]), "label": String(sc["label"])}
	# La Nuit recule lentement : les étoiles se rallument un anneau par an, des bords vers son origine.
	if k == "nuit":
		var after := {}
		var j := FactionTraits.jumps_from(state.galaxy, int(c["origin"]))
		for sid in c.get("dark", {}):
			after[int(sid)] = int(j.get(int(sid), 0))
		state.crisis["dark_after"] = after
		state.crisis["relight"] = state.tick + int(kd["night"]["ring_days"])
	# Grande Dépression.
	if result == "depression":
		var kr: Dictionary = kd["krach"]
		var who: Array = (c.get("infected", {}) as Dictionary).keys().map(func(x: Variant) -> int: return int(x))
		who.sort()
		state.crisis["dep"] = {"until": state.tick + int(kr["depression_days"]), "stab": int(kr["depression_stab"]), "trade_pct": int(kr["depression_trade_pct"]), "who": who}
	# Restes sauvages : deux flottes de guerre errent encore quinze ans.
	if result == "victoire" and not bool(kd.get("fleetless", false)) and k != "corsaire":
		var rem: Dictionary = state.crisis.get("remnants", {})
		var n := 0
		for f in Crisis.war_fleets(state):
			if n >= int(_d().get("remnants", {}).get("max", 2)):
				break
			rem[f.id] = state.tick + int(_d().get("remnants", {}).get("days", 5400))
			f.fleet_name = "Restes de %s" % String(kd.get("short", "la crise"))
			n += 1
		state.crisis["remnants"] = rem
		if n > 0:
			added.append(state.add_chronicle("Quelques débris %s n'ont pas compris que c'était fini : ils errent encore, sauvages et dangereux." % Crisis.de_name(Crisis.name_of(k))))


static func traces_day(state: GameState, added: Array[Dictionary]) -> void:
	var cr := state.crisis
	# Cicatrices passées.
	var sc: Dictionary = cr.get("scars", {})
	for k in sc.keys():
		if state.tick >= int(sc[k]["until"]):
			sc.erase(k)
	# Étoiles qui se rallument.
	var da: Dictionary = cr.get("dark_after", {})
	if not da.is_empty() and state.tick >= int(cr.get("relight", 0)):
		cr["relight"] = state.tick + 360
		var top := 0
		for k in da:
			top = maxi(top, int(da[k]))
		var n := 0
		for k in da.keys():
			if int(da[k]) == top:
				da.erase(k)
				n += 1
		if n > 0:
			added.append(state.add_chronicle("%d étoile%s éteinte%s par la Nuit lente se rallume%s. Les colons reviennent, avec des lunettes de soleil." % [n, "s" if n > 1 else "", "s" if n > 1 else "", "nt" if n > 1 else ""]))
	# Restes sauvages : ils errent d'un système voisin à l'autre, puis s'éteignent.
	var rem: Dictionary = cr.get("remnants", {})
	if rem.is_empty():
		return
	var keys := rem.keys()
	keys.sort()
	for k in keys:
		var f: Fleet = state.fleets.get(int(k))
		if f == null or f.ships.is_empty() or state.tick >= int(rem[k]):
			if f != null and not state.battles.has(f.system_id):
				state.fleets.erase(int(k))
			rem.erase(k)
			continue
		if f.is_moving() or state.battles.has(f.system_id) or state.tick % 60 != int(k) % 60:
			continue
		var nb: Array = state.galaxy.systems[f.system_id].neighbors
		if nb.is_empty():
			continue
		var to := int(nb[Crisis._h(state, ["erre", int(k), state.tick]) % nb.size()])
		var route := Fleets.plan_route(state, f, to)
		if not route.is_empty():
			f.path.assign(route["path"])


## Production d'un système (en %) hors sort de la crise : cicatrices, étoile éteinte, faillites.
static func trace_pct(state: GameState, sid: int) -> int:
	var pct := 100
	var sc: Dictionary = state.crisis.get("scars", {})
	if sc.has(sid):
		pct = int(sc[sid]["pct"])
	if (_cur(state).get("dark", {}) as Dictionary).has(sid):
		@warning_ignore("integer_division")
		pct = pct * int(Crisis.fate_of(state).get("prod_pct", 25)) / 100
	elif (state.crisis.get("dark_after", {}) as Dictionary).has(sid):
		@warning_ignore("integer_division")
		pct = pct / 2  # elle se rallume
	if String(_cur(state).get("kind", "")) == "krach" and Crisis.active(state):
		var owner := state.system_owner(sid)
		var kr: Dictionary = _kd(state)["krach"]
		if infected(state, owner) and Stability.value(state, sid) < int(kr["bankrupt_below"]):
			@warning_ignore("integer_division")
			pct = pct * int(kr["bankrupt_pct"]) / 100
	return pct


static func stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if infected(state, eid):
		out.append(["Grand Krach : chômage et faillites", int(_kd(state)["krach"]["stab"])])
	var dep: Dictionary = state.crisis.get("dep", {})
	if not dep.is_empty() and state.tick < int(dep["until"]) and (dep["who"] as Array).has(eid):
		out.append(["Grande Dépression", int(dep["stab"])])
	return out


## Grand empire (plus de systèmes que la médiane) : les mesures d'urgence lui coûtent davantage.
static func is_big(state: GameState, eid: int) -> bool:
	var counts: Array[int] = []
	var mine := 0
	for e in state.empires:
		if e.eliminated:
			continue
		var n := 0
		for pid in state.sorted_colony_ids():
			if (state.colonies[pid] as Colony).owner == e.id:
				n += 1
		counts.append(n)
		if e.id == eid:
			mine = n
	if counts.size() < 2:
		return false
	counts.sort()
	return mine > counts[counts.size() / 2]
