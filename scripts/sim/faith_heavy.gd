class_name FaithHeavy
extends RefCounted
## Religion, lot 4 : les 5 natures SF lourdes (étude « Religion », v1 proposition 26, v2 proposition 10).
## - Chronolâtrie : des oracles annoncent de vrais faits à venir (élection, flotte en route), que le
##   moteur déterministe connaît déjà. Accomplie : zèle ; empêchée par un empire : schisme chez lui.
## - Dieu en chantier : un dieu bâti en 5 étages (chacun un pouvoir) ; achevé, il marche sur la carte
##   comme le Dieu présent, et désobéit si le zèle tombe.
## - Entropisme : zèle par la destruction, horloge de la fin visible de tous ; à son terme, la Fin du
##   cycle (deux ans de puissance) puis l'effondrement de la foi.
## - Communion : production mise en commun entre les empires de la foi, stabilité tirée vers la
##   moyenne ; seule nature ouverte aux consciences collectives.
## - Astres vivants : des systèmes sacrés (étoiles remarquables, sites, gardiens) prêchent comme des
##   mondes saints ; y poser un avant-poste ou une mine fâche les fidèles ; un gardien y est un avatar.
## L'état vit dans state.faiths["nat"]["faith"][fid] (voir FaithNatures.fdat). Branché par FaithNatures.

const HEAVY := ["chronolatrie", "dieu_en_chantier", "entropisme", "communion", "astres_vivants"]


static func hd() -> Dictionary:
	return GameData.faiths()["heavy"]


## Talent de peuple du lot 4 (data/faiths.json, bridges.talents), par peuple de départ.
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or GameState.is_npc(eid):
		return {}
	return GameData.faiths()["bridges"]["talents"].get(e.faction_id, {})


static func _fd(state: GameState, fid: String) -> Dictionary:
	return FaithNatures._peek_faith(state, fid)


static func _founder(state: GameState, fid: String) -> int:
	return int(Faiths.faith(state, fid).get("founder", -1))


# --- Mise en place ---------------------------------------------------------------------------------

static func on_chosen(state: GameState, fid: String) -> void:
	var f := Faiths.faith(state, fid)
	var d := FaithNatures.fdat(state, fid)
	match String(f.get("nature", "")):
		"chronolatrie":
			if not d.has("oracle_next"):
				d["oracle_next"] = state.tick + oracle_days(state, fid)
		"dieu_en_chantier":
			if not d.has("stage"):
				d["stage"] = 0
		"entropisme":
			if not d.has("clock"):
				d["clock"] = 0
		"astres_vivants":
			if not d.has("sacred"):
				d["sacred"] = pick_sacred(state, fid)
		"communion":
			var fo := _founder(state, fid)
			if Faiths.is_hive(state, fo) and Faiths.state_faith(state, fo) == fid:
				Faiths.hive_join(state, fo, fid)
	# Culte de la Faim (Kh'thari) : leur foi est toujours un culte caché.
	var force: Dictionary = talent(state, _founder(state, fid)).get("force", {})
	for a in force:
		f["doctrines"][a] = String(force[a])


# --- Effets ----------------------------------------------------------------------------------------

static func fx(state: GameState, eid: int, sf: String, out: Dictionary) -> void:
	var fd := _fd(state, sf)
	match FaithWars.nature(state, sf):
		"dieu_en_chantier":
			var st: Array = hd()["chantier"]["stages"]
			for i in mini(stage(state, sf), st.size()):
				Research._merge(out, st[i].get("fx", {}))
		"entropisme":
			if int(fd.get("glory_end", 0)) > state.tick:
				Research._merge(out, hd()["entropie"]["glory_fx"])


static func stability_parts(state: GameState, sid: int, owner: int, out: Array) -> void:
	var sf := Faiths.state_faith(state, owner)
	match FaithWars.nature(state, sf):
		"communion":
			var v := int(_fd(state, sf).get("pull", {}).get(str(owner), 0))
			if v != 0:
				out.append(["Communion", v])
		"dieu_en_chantier":
			var g := FaithNatures.live_god(state, sf)
			if not g.is_empty() and disobeys(state, sf) and int(FactionTraits.jumps_from(state.galaxy, int(g["sid"])).get(sid, 99)) <= int(GameData.faiths()["classic"]["dieu"]["dominion"]):
				out.append(["Dieu désobéissant", int(hd()["chantier"]["wander_stab"])])


static func opinion_parts(state: GameState, a: int, b: int, out: Array) -> void:
	var fa := Faiths.state_faith(state, a)
	if FaithWars.nature(state, fa) == "astres_vivants" and (_fd(state, fa).get("profaners", []) as Array).has(b) and a != b:
		out.append(["Profane les Astres vivants", int(hd()["astres"]["profane_op"])])


## Pression des systèmes sacrés (Astres vivants), ajoutée à Faiths.pressures.
static func extra_pressures(state: GameState, out: Dictionary, targets_by_sys: Dictionary) -> void:
	var ad: Dictionary = hd()["astres"]
	for fid in Faiths.ids(state):
		if FaithWars.nature(state, fid) != "astres_vivants" or int(Faiths.faith(state, fid).get("pending", 0)) > 0:
			continue
		for s in sacred(state, fid):
			var x := int(ad["avatar_x"]) if Guardians.awake_at(state, int(s)) != "" else 1
			var dist := FactionTraits.jumps_from(state.galaxy, int(s))
			for t in targets_by_sys:
				if int(dist.get(t, 99)) > int(ad["reach"]):
					continue
				for pid in targets_by_sys[t]:
					var pm: Dictionary = out.get(pid, {})
					pm[fid] = int(pm.get(fid, 0)) + int(ad["pressure"]) * 100 * x
					out[pid] = pm


# --- Jauges ----------------------------------------------------------------------------------------

static func stage(state: GameState, fid: String) -> int:
	return int(_fd(state, fid).get("stage", 0))


static func clock(state: GameState, fid: String) -> int:
	return int(_fd(state, fid).get("clock", 0))


static func sacred(state: GameState, fid: String) -> Array:
	return _fd(state, fid).get("sacred", [])


static func oracle(state: GameState, fid: String) -> Dictionary:
	return _fd(state, fid).get("oracle", {})


static func oracle_days(state: GameState, fid: String) -> int:
	return int(talent(state, _founder(state, fid)).get("oracle_days", hd()["chrono"]["oracle_days"]))


## Le dieu du chantier n'obéit plus (zèle trop bas).
static func disobeys(state: GameState, fid: String) -> bool:
	return FaithWars.nature(state, fid) == "dieu_en_chantier" and FaithWars.zeal(state, fid) < int(hd()["chantier"]["obey_zeal"])


## Durée d'une opération d'espionnage (Espionage.launch) : Chronolâtrie, prophéties plus rapides.
static func op_days_pct(state: GameState, eid: int, op_id: String) -> int:
	if op_id == "prophetie" and state.faith_on and FaithWars.nature(state, Faiths.state_faith(state, eid)) == "chronolatrie":
		return int(hd()["chrono"]["planted_pct"])
	return 0


static func stage_cost(state: GameState, fid: String, eid: int) -> Dictionary:
	var st: Array = hd()["chantier"]["stages"]
	var i := stage(state, fid)
	if i >= st.size():
		return {}
	var pct := int(talent(state, eid).get("stage_cost_pct", 0))
	return Research.scaled_amounts(st[i]["cost"], pct)


# --- Astres vivants : choix des systèmes sacrés ------------------------------------------------------

static func pick_sacred(state: GameState, fid: String) -> Array:
	var ad: Dictionary = hd()["astres"]
	var f := Faiths.faith(state, fid)
	var home := state.galaxy.get_planet(int(f["holy"])).system_id
	var out := [home]
	var dist := FactionTraits.jumps_from(state.galaxy, home)
	var guarded := {}
	for gid in Guardians.ids(state):
		var gs := int(Guardians.list(state)[gid].get("sid", -1))
		if gs >= 0:
			guarded[gs] = true
	var cands := []
	for s in dist:
		if int(s) == home or int(dist[s]) > int(ad["range"]):
			continue
		var sc := int(ad["star_score"].get(state.galaxy.systems[int(s)].star_type, 0))
		if state.digs.has(int(s)):
			sc += int(ad["site_score"])
		if guarded.has(int(s)):
			sc += 3
		cands.append([sc, int(s)])
	cands.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	for cnd in cands:
		if out.size() >= int(ad["sacred"]):
			break
		out.append(int(cnd[1]))
	return out


# --- Événements du reste du jeu ---------------------------------------------------------------------

## Fin de bataille : l'Entropisme se nourrit des vaisseaux abattus et des créatures tuées.
static func on_battle(state: GameState, b: Dictionary) -> void:
	var ed: Dictionary = hd()["entropie"]
	var fauna_lost := 0
	for o: Dictionary in b["sides"]:
		if GameState.is_npc(int(o["empire"])):
			fauna_lost += Combat.count_ships(o["lost"])
	for s: Dictionary in b["sides"]:
		var eid := int(s["empire"])
		var sf := Faiths.state_faith(state, eid)
		if GameState.is_npc(eid) or FaithWars.nature(state, sf) != "entropisme":
			continue
		var n := 0
		for o: Dictionary in b["sides"]:
			if int(o["empire"]) != eid and not GameState.is_npc(int(o["empire"])) and Combat.at_war(state, eid, int(o["empire"])):
				n += Combat.count_ships(o["lost"])
		var d := FaithNatures.fdat(state, sf)
		d["kills"] = int(d.get("kills", 0)) + n
		@warning_ignore("integer_division")
		var ticks := int(d["kills"]) / int(ed["ships_per_tick"])
		d["kills"] = int(d["kills"]) % int(ed["ships_per_tick"])
		@warning_ignore("integer_division")
		FaithWars.add_zeal(state, sf, n / int(ed["ship_zeal_per"]) + fauna_lost * int(ed["creature_zeal"]))
		_advance(state, sf, ticks + fauna_lost * int(ed["creature_tick"]))


## Système peuplé conquis par un empire entropiste.
static func on_capture(state: GameState, new_owner: int) -> void:
	var sf := Faiths.state_faith(state, new_owner)
	if FaithWars.nature(state, sf) == "entropisme":
		FaithWars.add_zeal(state, sf, int(hd()["entropie"]["conquest_zeal"]))
		_advance(state, sf, int(hd()["entropie"]["conquest_tick"]))


static func _advance(state: GameState, fid: String, v: int) -> void:
	if v <= 0:
		return
	var d := FaithNatures.fdat(state, fid)
	if int(d.get("glory_end", 0)) > 0:
		return
	d["clock"] = mini(int(hd()["entropie"]["end"]), clock(state, fid) + v)


# --- Mois -------------------------------------------------------------------------------------------

static func monthly(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	match FaithWars.nature(state, fid):
		"chronolatrie":
			_oracle_month(state, fid, added)
		"dieu_en_chantier":
			_chantier_month(state, fid, added)
		"entropisme":
			_entropy_month(state, fid, added)
		"communion":
			_communion_month(state, fid)
		"astres_vivants":
			_astres_month(state, fid, added)


static func _chantier_month(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var d := FaithNatures.fdat(state, fid)
	var bd: Dictionary = d.get("build", {})
	if not bd.is_empty() and int(bd["end"]) <= state.tick:
		d.erase("build")
		d["stage"] = stage(state, fid) + 1
		var st: Array = hd()["chantier"]["stages"]
		var lab := String(st[stage(state, fid) - 1]["label"])
		Relics.touch(state)
		if stage(state, fid) >= st.size():
			var g := FaithNatures._new_god(state, fid)
			g["name"] = "le dieu bâti de %s" % Faiths.name_of(state, fid)
			d["god"] = g
			added.append(state.add_chronicle("Éveil ! Le dernier étage du dieu de %s est posé, et quelque chose ouvre les yeux. Il marche désormais parmi les étoiles ; reste à savoir s'il écoutera." % Faiths.name_of(state, fid)))
		else:
			added.append(state.add_chronicle("Le dieu en chantier de %s gagne un étage : %s (%d sur %d)." % [Faiths.name_of(state, fid), lab, stage(state, fid), st.size()]))
	if stage(state, fid) >= (hd()["chantier"]["stages"] as Array).size():
		FaithNatures._god_month(state, fid, added)
		# Désobéissance : le dieu erre.
		var g := FaithNatures.live_god(state, fid)
		if not g.is_empty() and disobeys(state, fid):
			var nbs: Array = state.galaxy.systems[int(g["sid"])].neighbors.duplicate()
			nbs.sort()
			if not nbs.is_empty():
				g["target"] = int(nbs[FaithWars._h(state, ["wander", fid, state.tick]) % nbs.size()])


static func _entropy_month(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var ed: Dictionary = hd()["entropie"]
	var d := FaithNatures.fdat(state, fid)
	var ge := int(d.get("glory_end", 0))
	if ge > 0:
		if ge <= state.tick:
			_collapse(state, fid, added)
		return
	var before := clock(state, fid)
	_advance(state, fid, int(ed["month"]))
	var now := clock(state, fid)
	for w in ed["warn"]:
		if before < int(w) and now >= int(w):
			added.append(state.add_chronicle("L'horloge de la fin de %s marque %d. Les fidèles chantent plus fort ; les autres vérifient leurs abris." % [Faiths.name_of(state, fid), now]))
	if now >= int(ed["end"]):
		d["glory_end"] = state.tick + int(ed["glory_days"])
		Relics.touch(state)
		added.append(state.add_chronicle("La Fin du cycle ! L'horloge de %s a sonné : pendant deux ans, ses fidèles sont la colère de l'univers. Après, il n'y aura plus rien, et c'était bien le but." % Faiths.name_of(state, fid)))


## Effondrement de la foi entropiste : elle disparaît, ses mondes vacillent.
static func _collapse(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var ed: Dictionary = hd()["entropie"]
	var name := Faiths.name_of(state, fid)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.faith.has(fid):
			c.faith.erase(fid)
			Faiths.normalize(c)
	for k in state.faiths["state"].keys():
		if String(state.faiths["state"][k]) == fid:
			var eid := int(k)
			state.faiths["state"][k] = Faiths.LAICITE
			state.faiths["changed"][k] = state.tick
			for s in Stability.systems_of(state, eid):
				FaithWars.add_stab(state, s, "Effondrement de l'Entropisme", int(ed["collapse_stab"]), int(ed["collapse_days"]))
	state.faiths["list"].erase(fid)
	FaithNatures._nat(state)["faith"].erase(fid)
	Relics.touch(state)
	added.append(state.add_chronicle("Effondrement : %s s'éteint comme elle l'avait promis. Ses temples se taisent, ses fidèles se réveillent un matin sans rien à attendre." % name))


static func _communion_month(state: GameState, fid: String) -> void:
	var cd: Dictionary = hd()["communion"]
	var d := FaithNatures.fdat(state, fid)
	var mem := FaithNatures.members(state, fid)
	var pull := {}
	if mem.size() >= 2:
		# Fonds commun : chacun verse sa part de production brute, partagée à parts égales.
		var pool := {}
		for eid in mem:
			var e := state.get_empire(eid)
			var gross: Dictionary = Economy.empire_income(state, eid)["gross"]
			for r in cd["resources"]:
				@warning_ignore("integer_division")
				var share := mini(int(e.resources.get(r, 0)), maxi(0, int(gross.get(r, 0))) * int(cd["share_pct"]) / 100)
				e.resources[r] = int(e.resources.get(r, 0)) - share
				pool[r] = int(pool.get(r, 0)) + share
		for r in pool:
			@warning_ignore("integer_division")
			var each := int(pool[r]) / mem.size()
			var rest := int(pool[r]) - each * mem.size()
			for i in mem.size():
				var e := state.get_empire(mem[i])
				e.resources[r] = int(e.resources.get(r, 0)) + each + (rest if i == 0 else 0)
		# Stabilité : chacun tire vers la moyenne de la communion (calculée sur le mois écoulé).
		var tot := 0
		var n := 0
		var own := {}
		for eid in mem:
			var s := 0
			var k := 0
			for sid in Stability.systems_of(state, eid):
				s += Stability.value(state, sid)
				k += 1
			if k > 0:
				@warning_ignore("integer_division")
				own[eid] = s / k
				tot += s
				n += k
		if n > 0:
			@warning_ignore("integer_division")
			var avg := tot / n
			for eid in own:
				@warning_ignore("integer_division")
				var v := clampi((avg - int(own[eid])) * int(cd["stab_pull_pct"]) / 100, -int(cd["stab_max"]), int(cd["stab_max"]))
				if v != 0:
					pull[str(eid)] = v
	d["pull"] = pull


static func _astres_month(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var ad: Dictionary = hd()["astres"]
	var d := FaithNatures.fdat(state, fid)
	if not d.has("sacred"):
		d["sacred"] = pick_sacred(state, fid)
	var prof := []
	var avatars := []
	for s in d["sacred"]:
		for pid in state.galaxy.systems[int(s)].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c == null or GameState.is_npc(c.owner):
				continue
			if (c.kind == Colony.KIND_OUTPOST or c.buildings.has("complexe_minier")) and not prof.has(c.owner):
				prof.append(c.owner)
		var gid := Guardians.awake_at(state, int(s))
		if gid != "":
			avatars.append(gid)
	prof.sort()
	if prof != d.get("profaners", []):
		d["profaners"] = prof
	for eid in prof:
		if Faiths.state_faith(state, eid) == fid:
			FaithWars.add_zeal(state, fid, int(ad["profane_zeal"]))
	# Un avatar abattu : profanation, motif de guerre sainte contre son tueur.
	for gid in d.get("avatars", []):
		var g: Dictionary = Guardians.list(state).get(String(gid), {})
		if not avatars.has(gid) and not g.is_empty() and String(g.get("status", "")) == "dead":
			FaithWars.add_zeal(state, fid, int(ad["avatar_kill_zeal"]))
			var by := int(g.get("by", -1))
			if by >= 0:
				if not d.has("profaned"):
					d["profaned"] = {}
				d["profaned"][str(by)] = state.tick + int(ad["avatar_casus_days"])
				added.append(state.add_chronicle("Déicide stellaire : %s abat l'avatar des Astres vivants. Les fidèles de %s lèvent les yeux vers un ciel qui leur semble soudain vide." % [
						state.get_empire(by).display_name(), Faiths.name_of(state, fid)]))
	d["avatars"] = avatars


## Motif de guerre sainte : l'empire qui a abattu un avatar.
static func casus(state: GameState, a: int, b: int) -> String:
	var fa := Faiths.state_faith(state, a)
	if FaithWars.nature(state, fa) == "astres_vivants" and int(_fd(state, fa).get("profaned", {}).get(str(b), 0)) > state.tick:
		return "il a abattu l'avatar de nos Astres"
	return ""


# --- Chronolâtrie ------------------------------------------------------------------------------------

static func _oracle_month(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var cd: Dictionary = hd()["chrono"]
	var d := FaithNatures.fdat(state, fid)
	var o: Dictionary = d.get("oracle", {})
	if not o.is_empty():
		_check_oracle(state, fid, o, added)
		return
	if state.tick < int(d.get("oracle_next", 0)):
		return
	d["oracle_next"] = state.tick + oracle_days(state, fid)
	var cands := []
	if state.politics_on:
		for e in state.empires:
			if e.eliminated or GameState.is_npc(e.id) or not Politics.applies(state, e.id):
				continue
			var ne := Politics.next_election(state, e.id)
			var r: Array = Politics.tally(state, e.id).get("ruling", [])
			if ne > state.tick and ne <= state.tick + int(cd["window_days"]) and not r.is_empty():
				cands.append({"kind": "election", "eid": e.id, "lead": int(r[0]), "deadline": ne})
	var fids := state.fleets.keys()
	fids.sort()
	for flid in fids:
		var fl: Fleet = state.fleets[flid]
		if GameState.is_npc(fl.owner) or not Combat.is_warfleet(fl) or fl.path.is_empty():
			continue
		cands.append({"kind": "flotte", "fleet": int(flid), "eid": fl.owner, "dest": int(fl.path.back()), "deadline": state.tick + int(cd["window_days"]) / 2})
	if cands.is_empty():
		return
	o = cands[FaithWars._h(state, ["oracle", fid, state.tick]) % cands.size()]
	d["oracle"] = o
	added.append(state.add_chronicle("Les oracles de %s ont parlé : %s" % [Faiths.name_of(state, fid), oracle_text(state, o)]))


static func oracle_text(state: GameState, o: Dictionary) -> String:
	var e := state.get_empire(int(o["eid"]))
	var who := e.display_name() if e != null else "?"
	if String(o["kind"]) == "election":
		return "%s portera au pouvoir %s, avant le %s." % [who, Politics.label(state, int(o["eid"]), int(o["lead"])), GameCalendar.date_string(int(o["deadline"]))]
	return "une flotte de %s atteindra %s avant le %s." % [who, state.galaxy.systems[int(o["dest"])].system_name, GameCalendar.date_string(int(o["deadline"]))]


static func _check_oracle(state: GameState, fid: String, o: Dictionary, added: Array[Dictionary]) -> void:
	var cd: Dictionary = hd()["chrono"]
	var verdict := ""  # "ok", "fail", ou "prevented"
	var culprit := -1
	match String(o["kind"]):
		"election":
			var e := state.get_empire(int(o["eid"]))
			if e == null or e.eliminated:
				verdict = "fail"
			elif Politics.next_election(state, int(o["eid"])) != int(o["deadline"]) or state.tick > int(o["deadline"]):
				if Politics.lead(state, int(o["eid"])) == int(o["lead"]):
					verdict = "ok"
				else:
					verdict = "prevented"
					culprit = int(o["eid"])
		"flotte":
			var fl: Fleet = state.fleets.get(int(o["fleet"]))
			if fl == null:
				verdict = "fail"
			elif fl.system_id == int(o["dest"]) and not fl.is_moving():
				verdict = "ok"
			elif fl.is_moving() and int(fl.path.back()) != int(o["dest"]) or (not fl.is_moving() and fl.system_id != int(o["dest"])):
				verdict = "prevented"
				culprit = fl.owner
			elif state.tick > int(o["deadline"]):
				verdict = "fail"
	if verdict == "":
		return
	FaithNatures.fdat(state, fid).erase("oracle")
	var name := Faiths.name_of(state, fid)
	match verdict:
		"ok":
			FaithWars.add_zeal(state, fid, int(cd["fulfilled_zeal"]))
			added.append(state.add_chronicle("Prophétie accomplie : %s. Les fidèles de %s n'en attendaient pas moins ; le temps leur a donné raison, comme toujours." % [oracle_text(state, o), name]))
		"fail":
			FaithWars.add_zeal(state, fid, int(cd["failed_zeal"]))
			added.append(state.add_chronicle("La prophétie de %s reste en suspens : le monde a changé en route. Les oracles parlent d'une erreur de lecture." % name))
		"prevented":
			var pid := _schism_site(state, fid, culprit)
			if pid >= 0:
				var hid := FaithNatures.make_schism(state, fid, pid, added)
				if hid != "":
					added.append(state.add_chronicle("%s a fait mentir les oracles de %s ! Chez lui, des fidèles refusent un temps qui n'obéit plus : %s fait sécession." % [
							state.get_empire(culprit).display_name(), name, Faiths.name_of(state, hid)]))
					return
			FaithWars.add_zeal(state, fid, int(cd["prevented_zeal"]))
			added.append(state.add_chronicle("%s a fait mentir les oracles de %s. Les fidèles doutent, pour la première fois." % [state.get_empire(culprit).display_name(), name]))


## Colonie du coupable qui compte le plus de fidèles de la foi (au moins 2), -1 sinon.
static func _schism_site(state: GameState, fid: String, culprit: int) -> int:
	var best := -1
	var bn := 1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == culprit and int(c.faith.get(fid, 0)) > bn and pid != int(Faiths.faith(state, fid)["holy"]):
			best = pid
			bn = int(c.faith[fid])
	return best


# --- Actions (commande faith_nat) ---------------------------------------------------------------------

static func check(state: GameState, player: int, act: String, args: Dictionary) -> String:
	var sf := Faiths.state_faith(state, player)
	match act:
		"stage":
			if FaithWars.nature(state, sf) != "dieu_en_chantier":
				return "il faut une foi d'État du Dieu en chantier"
			if Faiths.head(state, sf) != player:
				return "seul le chef de foi fait avancer le chantier"
			var st: Array = hd()["chantier"]["stages"]
			if stage(state, sf) >= st.size():
				return "le dieu est achevé"
			if not (_fd(state, sf).get("build", {}) as Dictionary).is_empty():
				return "un étage est déjà en chantier"
			if stage(state, sf) == st.size() - 1 and state.get_empire(player).faction_id == String(hd()["chantier"]["choir_faction"]):
				var has := false
				for pid in state.colonies:
					var c: Colony = state.colonies[pid]
					if c.owner == player and c.buildings.has(String(hd()["chantier"]["choir_building"])):
						has = true
				if not has:
					return "le dernier étage du Chœur est une Cathédrale-chœur : bâtissez-en une"
			return FaithNatures._afford(state, player, stage_cost(state, sf, player))
	return "action inconnue"


static func apply(state: GameState, player: int, act: String, _args: Dictionary) -> void:
	var sf := Faiths.state_faith(state, player)
	match act:
		"stage":
			FaithNatures._pay(state, player, stage_cost(state, sf, player))
			var st: Array = hd()["chantier"]["stages"]
			FaithNatures.fdat(state, sf)["build"] = {"end": state.tick + int(st[stage(state, sf)]["days"])}


# --- IA ------------------------------------------------------------------------------------------------

static func ai(state: GameState, e: Empire) -> void:
	var sf := Faiths.state_faith(state, e.id)
	if FaithWars.nature(state, sf) == "dieu_en_chantier" and check(state, e.id, "stage", {}) == "":
		var reserve := int(GameData.faiths()["ai"]["heavy"]["stage_reserve"])
		var cost := stage_cost(state, sf, e.id)
		var ok := true
		for r in cost:
			if int(e.resources.get(r, 0)) < int(cost[r]) + reserve:
				ok = false
		if ok:
			apply(state, e.id, "stage", {})


# --- Sauvegarde ----------------------------------------------------------------------------------------

static func fix(d: Dictionary) -> void:
	for k in ["stage", "clock", "kills", "glory_end", "oracle_next"]:
		if d.has(k):
			d[k] = int(d[k])
	if d.has("build"):
		d["build"]["end"] = int(d["build"]["end"])
	if d.has("sacred"):
		var s := []
		for x in d["sacred"]:
			s.append(int(x))
		d["sacred"] = s
	if d.has("profaners"):
		var p := []
		for x in d["profaners"]:
			p.append(int(x))
		d["profaners"] = p
	if d.has("pull"):
		for k in d["pull"]:
			d["pull"][k] = int(d["pull"][k])
	if d.has("oracle"):
		for k in d["oracle"]:
			if String(k) != "kind":
				d["oracle"][k] = int(d["oracle"][k])
