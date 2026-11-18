class_name LivingWorldsBridges
extends RefCounted
## Les mondes vivants et le reste du jeu (prop. 20-29 ; voir LivingWorlds) : foi (prop. 20), écoute
## psionique et Résonance (prop. 21), monde hanté (prop. 22), faune apprivoisée (prop. 23), nefs-graines
## (prop. 24), Monde-Ego (prop. 26), fusion (prop. 27), visiteurs (prop. 28), éveil (prop. 29), et la
## version courte de la Forge des mondes (monde-reliquaire vivant, origine Reliquaire).


# --- Foi (prop. 20) ----------------------------------------------------------------------------

## Humeur mensuelle venue de la foi : monde sacré d'une foi Astres vivants, précepte Gardiens du monde.
static func faith_mood(state: GameState, pid: int, eid: int) -> int:
	if not state.faith_on:
		return 0
	var fid := Faiths.state_faith(state, eid)
	if fid == "" or Faiths.faith(state, fid).is_empty():
		return 0
	var n := 0
	if FaithWars.nature(state, fid) == "astres_vivants" and FaithHeavy.sacred(state, fid).has(LivingWorlds.sys_of(state, pid)):
		n += LivingWorlds.f_int("faith_sacred", 3)
	if (Faiths.faith(state, fid).get("precepts", []) as Array).has("gardiens_monde"):
		n += LivingWorlds.f_int("precept", 3)
	return n


## Score d'un système pour devenir sacré (FaithHeavy.pick_sacred) : un monde vivant attire les fidèles.
static func sacred_score(state: GameState, sid: int) -> int:
	if state.living.is_empty():
		return 0
	return 8 * LivingWorlds.in_system(state, sid).size()


## Un monde vivant tué : les fois Astres vivants qui le tenaient pour sacré crient au sacrilège.
static func on_murder(state: GameState, pid: int, eid: int) -> void:
	if not state.faith_on:
		return
	var sid := LivingWorlds.sys_of(state, pid)
	for fid in Faiths.ids(state):
		if FaithWars.nature(state, fid) == "astres_vivants" and FaithHeavy.sacred(state, fid).has(sid):
			var fd: Dictionary = FaithHeavy._fd(state, fid)
			var pr: Array = fd.get("profaners", [])
			if not pr.has(eid):
				pr.append(eid)
			fd["profaners"] = pr


# --- Chaque mois -------------------------------------------------------------------------------

static func monthly(state: GameState, pid: int, added: Array[Dictionary]) -> void:
	var w := LivingWorlds.world(state, pid)
	var h := LivingWorlds.host(state, pid)
	if h < 0:
		return
	# Prop. 21 : un monde Lié chante dans le Songe de son hôte.
	if not state.psionics.is_empty() and Psionics.applies(state, h) and LivingWorlds.tier_index(state, pid, h) >= 4:
		Psionics.add_resonance(state, h, LivingWorlds.r_int("lie_resonance", 3))
	# Prop. 28 : un monde Énigme renvoie parfois des visiteurs.
	if bool(LivingWorlds.temper_def(String(w["t"])).get("visitors", false)) and state.tick >= int(w.get("visit", 0)):
		w["visit"] = state.tick + LivingWorlds.r_int("visit_days", 1800)
		Events.push(state, h, "lw_visiteurs", {"system": LivingWorlds.sys_of(state, pid), "planet": pid}, added)


# --- Écoute psionique (prop. 21) ---------------------------------------------------------------

static func check_listen(state: GameState, eid: int, pid: int) -> String:
	var w := LivingWorlds.world(state, pid)
	if state.tick < int((w["listen"] as Dictionary).get(str(eid), 0)):
		return "le monde se tait encore (écouté il y a peu)"
	if LivingWorlds.t_bool(state, eid, "free_listen"):
		return ""
	if state.psionics.is_empty() or not Psionics.applies(state, eid):
		return "il faut des pouvoirs psioniques pour écouter un monde"
	if Psionics.best_level(state, eid) <= 0:
		return "aucune de vos espèces n'entend le Songe"
	if Psionics.resonance(state, eid) < LivingWorlds.r_int("listen_cost", 30):
		return "Résonance insuffisante (%d / %d)" % [Psionics.resonance(state, eid), LivingWorlds.r_int("listen_cost", 30)]
	return ""


static func listen(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var w := LivingWorlds.world(state, pid)
	if not LivingWorlds.t_bool(state, eid, "free_listen"):
		Psionics.add_resonance(state, eid, -LivingWorlds.r_int("listen_cost", 30))
	(w["listen"] as Dictionary)[str(eid)] = state.tick + LivingWorlds.r_int("listen_cd_days", 360)
	(w["deep"] as Dictionary)[str(eid)] = 1
	LivingWorlds.add_mood(state, pid, eid, LivingWorlds.r_int("listen_mood", 10))
	LivingWorlds._stat(state, eid, "listened", 1)
	var likes := Peoples.label(String(w.get("fav", ""))) if String(w.get("fav", "")) != "" else "personne en particulier"
	var nope := Peoples.label(String(w.get("nope", ""))) if String(w.get("nope", "")) != "" else "personne"
	added.append(state.add_chronicle("Les sensitifs de %s écoutent %s : il aime les %s, supporte mal les %s, et vous trouve %s." % [
			state.get_empire(eid).short_name(), LivingWorlds.name_of(state, pid), likes, nope, String(LivingWorlds.tier(state, pid, eid).get("label", "")).to_lower()],
			Espionage.private_to(state, [eid])))


## Prop. 22 : une fêlure près d'un monde vivant peut le corrompre (appelé par Psionics.felure).
static func on_felure(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	if state.living.is_empty():
		return
	for pid in LivingWorlds.ids(state):
		var w := LivingWorlds.world(state, pid)
		if String(w["o"]) == "hante" or int(w.get("ego", 0)) == 1:
			continue
		var sid := LivingWorlds.sys_of(state, pid)
		if LivingWorlds.host(state, pid) != eid and state.system_owner(sid) != eid:
			continue
		if LivingWorlds._h(state, ["haunt", pid, eid, state.tick]) % 4 != 0:
			continue
		w["o"] = "hante"
		var names: Array = LivingWorlds.origin_def("hante").get("names", [""])
		w["n"] = LivingWorlds._h(state, ["hname", pid]) % maxi(1, names.size())
		for e in state.empires:
			if not e.is_npc():
				LivingWorlds.set_mood(state, pid, e.id, LivingWorlds.mood(state, pid, e.id))
		LivingWorlds._stat(state, eid, "haunted", 1)
		Announce.next(state, "living_anger", {"actor": eid, "system": sid})
		added.append(state.add_chronicle("La fêlure a débordé : le Songe s'est engouffré dans %s. Le monde ne rêve plus, il hurle ; on l'appelle désormais %s." % [
				state.galaxy.systems[sid].system_name, LivingWorlds.name_of(state, pid)]))
		return


# --- Faune apprivoisée (prop. 23) --------------------------------------------------------------

## Un monde Bienveillant ou Lié laisse apprivoiser ses anticorps, même sans étude (Fauna).
static func tames(state: GameState, eid: int, sp: String) -> bool:
	if state == null or state.living.is_empty():
		return false
	for pid in LivingWorlds.ids(state):
		var w := LivingWorlds.world(state, pid)
		if String(LivingWorlds.origin_def(String(w["o"])).get("antibody", "")) == sp and LivingWorlds.loves(state, pid, eid):
			return true
	return false


# --- Nefs-graines (prop. 24) -------------------------------------------------------------------

static func seed_count(state: GameState, eid: int) -> int:
	var unit := String(LivingWorlds.cfg("rules").get("seed_unit", "vivant_nef_graine"))
	var n := 0
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == eid:
			n += f.ships.count(unit)
	return n


@warning_ignore("integer_division")
static func check_seed(state: GameState, eid: int, pid: int) -> String:
	var w := LivingWorlds.world(state, pid)
	if LivingWorlds.host(state, pid) != eid:
		return "il faut vivre sur ce monde"
	if LivingWorlds.tier_index(state, pid, eid) < 4:
		return "seul un monde Lié offre des nefs-graines"
	if state.tick < int((w["seed"] as Dictionary).get(str(eid), 0)):
		return "la prochaine graine n'est pas mûre"
	if seed_count(state, eid) >= LivingWorlds.r_int("seed_max", 3):
		return "vous avez déjà %d nefs-graines" % LivingWorlds.r_int("seed_max", 3)
	return ""


@warning_ignore("integer_division")
static func seed(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var w := LivingWorlds.world(state, pid)
	var cd := LivingWorlds.r_int("seed_cd_days", 720) / maxi(1, int(LivingWorlds.origin_def(String(w["o"])).get("seed_x", 1)))
	(w["seed"] as Dictionary)[str(eid)] = state.tick + cd
	var f := state.spawn_ship(eid, String(LivingWorlds.cfg("rules").get("seed_unit", "vivant_nef_graine")), LivingWorlds.sys_of(state, pid))
	f.fleet_name = "Graine de %s" % LivingWorlds.name_of(state, pid)
	LivingWorlds._stat(state, eid, "seeds", 1)
	added.append(state.add_chronicle("%s offre une graine à %s : elle éclot en orbite, et le vaisseau qui en sort reconnaît déjà son pilote." % [
			LivingWorlds.name_of(state, pid), state.get_empire(eid).short_name()], Espionage.private_to(state, [eid])))


# --- Fusion (prop. 27) -------------------------------------------------------------------------

static func check_fuse(state: GameState, eid: int, pid: int) -> String:
	var w := LivingWorlds.world(state, pid)
	if int(w.get("fused", -1)) >= 0:
		return "ce monde a déjà fusionné"
	if LivingWorlds.host(state, pid) != eid:
		return "il faut vivre sur ce monde"
	var c: Colony = state.colonies.get(pid)
	if c == null or not c.is_colony():
		return "il faut une colonie, pas un avant-poste"
	var since := int((w["lie"] as Dictionary).get(str(eid), -1))
	if since < 0:
		return "il faut que le monde vous soit Lié"
	var left := since + LivingWorlds.r_int("fuse_days", 3600) - state.tick
	if left > 0:
		@warning_ignore("integer_division")
		return "encore %d ans de lien avant de pouvoir fusionner" % maxi(1, (left + 359) / 360)
	return ""


static func fuse(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var w := LivingWorlds.world(state, pid)
	w["fused"] = eid
	LivingWorlds._stat(state, eid, "fused", 1)
	LivingWorlds.touch(state)
	Announce.next(state, "living_wake", {"actor": eid, "system": LivingWorlds.sys_of(state, pid)})
	added.append(state.add_chronicle("Fusion : les habitants de %s et le monde ne font plus qu'un. Ils rêvent les mêmes rêves, et aucun d'eux ne voudra plus jamais partir." % LivingWorlds.name_of(state, pid),
			Espionage.private_to(state, [eid])))


# --- Cartes d'événement : éveil, visiteurs ----------------------------------------------------

static func event_act(state: GameState, eid: int, pid: int, act: String, added: Array[Dictionary]) -> void:
	match act:
		"wake":
			(LivingWorlds.sub(state, "pend") as Dictionary).erase(str(pid))
			if not LivingWorlds.is_living(state, pid) and state.galaxy.get_planet(pid) != null:
				LivingWorlds.add_world(state, pid, "eveille", state.tick)
				(LivingWorlds.world(state, pid)["known"] as Dictionary)[str(eid)] = 1
				LivingWorlds.add_mood(state, pid, eid, 20)
				state.living["woken"] = int(state.living.get("woken", 0)) + 1
				Announce.next(state, "living_wake", {"actor": eid, "system": LivingWorlds.sys_of(state, pid)})
				added.append(state.add_chronicle("%s laisse le monde s'éveiller : %s ouvre les yeux, et son premier regard est pour ceux qui l'ont laissé faire." % [
						state.get_empire(eid).short_name(), LivingWorlds.name_of(state, pid)]))
		"sleep":
			(LivingWorlds.sub(state, "pend") as Dictionary).erase(str(pid))
			LivingWorlds.sub(state, "slept")[str(pid)] = 1
			var e := state.get_empire(eid)
			var res := LivingWorlds.r_dict("slept_res")
			for r in res:
				e.resources[r] = int(e.resources.get(r, 0)) + Events.era_scaled(state, eid, int(res[r]))
			state.living["woken"] = int(state.living.get("woken", 0)) + 1
			added.append(state.add_chronicle("%s endort le monde pour toujours. Les sismographes se calment ; les biologistes, eux, ne dorment plus très bien." % e.short_name(),
					Espionage.private_to(state, [eid])))
		"visit_yes":
			if LivingWorlds.is_living(state, pid):
				Events.give_research(state, eid, LivingWorlds.r_int("visit_research_pct", 15))
				LivingWorlds.world(state, pid)["vstab"] = {"e": eid, "until": state.tick + 360}
		"visit_no":
			LivingWorlds.add_mood(state, pid, eid, -5)


static func event_line(state: GameState, eid: int, pid: int, act: String) -> String:
	match act:
		"wake":
			return "Un monde vivant s'éveille (humeur +20 envers vous) ; il choisira ses hôtes"
		"sleep":
			var res := LivingWorlds.r_dict("slept_res")
			var scaled := {}
			for r in res:
				scaled[r] = Events.era_scaled(state, eid, int(res[r]))
			return "+%s ; la planète reste ordinaire pour toujours" % GameData.format_amounts(scaled)
		"visit_yes":
			return "+%d %% de la recherche en cours ; +%d de stabilité dans le système pendant un an" % [LivingWorlds.r_int("visit_research_pct", 15), LivingWorlds.r_int("visit_stab", 5)]
		"visit_no":
			return "Humeur -5"
	return ""


# --- Éveil en cours de partie (prop. 29) -------------------------------------------------------

static func wake_check(state: GameState, added: Array[Dictionary]) -> void:
	var year_days := 12 * int(GameData.rules()["month_days"])
	if state.tick % year_days != 0:
		return
	@warning_ignore("integer_division")
	if state.tick / year_days < LivingWorlds.r_int("wake_year", 20):
		return
	if int(state.living.get("woken", 0)) + LivingWorlds.sub(state, "pend").size() >= int(LivingWorlds.mode_def(LivingWorlds.mode(state)).get("wake_max", 1)):
		return
	if LivingWorlds._h(state, ["wake", state.tick]) % 100 >= LivingWorlds.r_int("wake_pct", 6):
		return
	var types: Array = LivingWorlds.cfg("rules").get("start_types", [])
	var best := -1
	var best_pop := LivingWorlds.r_int("wake_min_pop", 12) - 1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		var p := state.galaxy.get_planet(int(pid))
		if GameState.is_npc(c.owner) or not c.is_colony() or p == null or not types.has(p.type) or p.size < LivingWorlds.r_int("min_size", 5):
			continue
		if LivingWorlds.world(state, int(pid)).size() > 0 or LivingWorlds.sub(state, "slept").has(str(pid)) or LivingWorlds.sub(state, "pend").has(str(pid)):
			continue
		if state.get_empire(c.owner).capital_planet == int(pid):
			continue
		if c.population > best_pop:
			best_pop = c.population
			best = int(pid)
	if best < 0:
		return
	var owner: int = (state.colonies[best] as Colony).owner
	LivingWorlds.sub(state, "pend")[str(best)] = owner
	Events.push(state, owner, "lw_eveil", {"system": LivingWorlds.sys_of(state, best), "planet": best}, added)


# --- Monde-Ego (prop. 26) ----------------------------------------------------------------------

static func ego(state: GameState) -> Dictionary:
	return LivingWorlds.sub(state, "ego")


static func ego_pid(state: GameState) -> int:
	var e := ego(state)
	return int(e.get("pid", -1)) if not e.is_empty() and int(e.get("dead", 0)) == 0 else -1


## Planète ensemencée ou devenue extension d'Ego : on ne peut pas s'y installer.
static func ego_holds(state: GameState, pid: int) -> bool:
	if ego_pid(state) < 0:
		return false
	return (ego(state).get("ext", {}) as Dictionary).has(str(pid)) or (ego(state).get("seeds", {}) as Dictionary).has(str(pid))


static func ego_monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not LivingWorlds.ego_on(state):
		return
	var eg := ego(state)
	var year_days := 12 * int(GameData.rules()["month_days"])
	var ec := LivingWorlds.cfg("ego")
	if eg.is_empty():
		@warning_ignore("integer_division")
		if state.tick / year_days < int(ec.get("start_year", 40)):
			return
		_ego_rise(state, added)
		return
	if int(eg.get("dead", 0)) == 1:
		return
	var pid := int(eg["pid"])
	if not LivingWorlds.is_living(state, pid):
		eg["dead"] = 1
		return
	var sid := LivingWorlds.sys_of(state, pid)
	# Les graines mûrissent : la planète devient une extension (sa colonie meurt).
	var seeds: Dictionary = eg["seeds"]
	for k in seeds.keys():
		if state.tick < int(seeds[k]):
			continue
		seeds.erase(k)
		var tp := int(k)
		var p := state.galaxy.get_planet(tp)
		if p == null:
			continue
		var c: Colony = state.colonies.get(tp)
		var victim := -1
		if c != null:
			victim = c.owner
			var n := c.population
			state.colonies.erase(tp)
			state.rebuild_ownership()
			if n > 0 and not GameState.is_npc(victim):
				Movements.flee_from(state, p.system_id, Peoples.founder_of(state, victim), maxi(1, n / 2), victim, added)
		state.override_planet(tp, {"type": "toxic"})
		(eg["ext"] as Dictionary)[str(tp)] = 1
		LivingWorlds.touch(state)
		Announce.next(state, "living_ego", {"target": victim, "system": p.system_id})
		added.append(state.add_chronicle("La graine d'Ego a germé sur %s : la planète n'est plus qu'une excroissance du Monde affamé, toute en chair et en racines." % p.display_name(state.galaxy)))
	# Une nouvelle graine.
	if state.tick >= int(eg.get("next", 0)):
		eg["next"] = state.tick + int(ec.get("seed_days", 540))
		var tgt := _ego_target(state, sid, int(ec.get("seed_range", 3)))
		if tgt >= 0:
			seeds[str(tgt)] = state.tick + int(ec.get("grow_days", 360))
			var c2: Colony = state.colonies.get(tgt)
			added.append(state.add_chronicle("Ego a lancé une graine vers %s. Elle germera dans un an, sauf si on abat le Monde affamé avant." % state.galaxy.get_planet(tgt).display_name(state.galaxy),
					Espionage.public_to(state, [c2.owner] if c2 != null else [])))
	# Le noyau : une coalition qui tient l'orbite assez longtemps l'abat.
	var power := 0
	var who := []
	for f in Fleets.fleets_at(state, sid):
		if GameState.is_npc(f.owner) or f.is_moving() or not Combat.is_armed(f):
			continue
		power += Combat.fleet_power(f)
		if not who.has(f.owner):
			who.append(f.owner)
	if power >= int(ec.get("kill_power", 600)):
		eg["siege"] = int(eg.get("siege", 0)) + 30
	else:
		eg["siege"] = maxi(0, int(eg.get("siege", 0)) - 30)
	# Le monde frappe toutes les flottes armées dans son orbite.
	if not who.is_empty():
		var fighters: Array = []
		for f in Fleets.fleets_at(state, sid):
			if not GameState.is_npc(f.owner) and Combat.is_armed(f):
				fighters.append(f)
		LivingWorldsWar._strike(state, pid, sid, fighters, added)
	if int(eg["siege"]) >= int(ec.get("kill_days", 30)):
		_ego_fall(state, pid, who, added)


static func _ego_rise(state: GameState, added: Array[Dictionary]) -> void:
	var pid := -1
	for p in LivingWorlds.ids(state):
		if LivingWorlds.host(state, p) < 0:
			pid = p
			break
	if pid < 0:
		var cands := LivingWorlds.start_candidates(state)
		if cands.is_empty():
			LivingWorlds.sub(state, "ego")["dead"] = 1
			return
		pid = int(cands[0][1])
		LivingWorlds.add_world(state, pid, "hante", 7)
	var w := LivingWorlds.world(state, pid)
	w["ego"] = 1
	for e in state.empires:
		if not e.is_npc():
			LivingWorlds.set_mood(state, pid, e.id, -100)
	var eg := ego(state)
	eg["pid"] = pid
	eg["seeds"] = {}
	eg["ext"] = {}
	eg["next"] = state.tick + 60
	eg["siege"] = 0
	eg["dead"] = 0
	var sid := LivingWorlds.sys_of(state, pid)
	Announce.next(state, "living_ego", {"system": sid})
	added.append(state.add_chronicle("À %s, un monde s'est réveillé affamé. Il se nomme lui-même Ego, et il a décidé que l'univers entier serait lui. Il va falloir s'unir pour frapper son noyau." % state.galaxy.systems[sid].system_name))


static func _ego_target(state: GameState, sid: int, range_: int) -> int:
	var dist := FactionTraits.jumps_from(state.galaxy, sid)
	var eg := ego(state)
	var best := -1
	var best_s := 999999
	var keys := dist.keys()
	keys.sort()
	for k in keys:
		if int(dist[k]) > range_:
			continue
		for pid in state.galaxy.systems[int(k)].planet_ids:
			var p := state.galaxy.get_planet(pid)
			if p == null or not p.is_habitable_type() or LivingWorlds.is_living(state, pid):
				continue
			if (eg["ext"] as Dictionary).has(str(pid)) or (eg["seeds"] as Dictionary).has(str(pid)):
				continue
			var cap := false
			for e in state.empires:
				if e.capital_planet == pid or e.home_planet == pid:
					cap = true
			if cap:
				continue
			var s := int(dist[k]) * 100 + pid % 97
			if s < best_s:
				best_s = s
				best = pid
	return best


static func _ego_fall(state: GameState, pid: int, who: Array, added: Array[Dictionary]) -> void:
	var eg := ego(state)
	eg["dead"] = 1
	var w := LivingWorlds.world(state, pid)
	w["dead"] = 1
	state.override_planet(pid, {"type": "barren"})
	(eg["seeds"] as Dictionary).clear()
	var rew: Dictionary = LivingWorlds.cfg("ego").get("reward", {})
	var names := PackedStringArray()
	who.sort()
	for eid in who:
		var e := state.get_empire(int(eid))
		if e == null:
			continue
		for r in rew:
			e.resources[r] = int(e.resources.get(r, 0)) + int(rew[r])
		LivingWorlds._stat(state, int(eid), "ego_slain", 1)
		names.append(e.short_name())
	LivingWorlds.touch(state)
	Announce.next(state, "living_ego", {"system": LivingWorlds.sys_of(state, pid)})
	added.append(state.add_chronicle("Le noyau d'Ego cède sous le feu de %s. Le Monde affamé s'éteint ; il n'en reste qu'un caillou froid, et des planètes qui ne savent plus ce qu'elles sont." % ", ".join(names)))


# --- Forge des mondes : le monde-reliquaire vivant ----------------------------------------------

## Appelé par WorldForgeWorld.opened : si les mondes vivants sont en jeu, le reliquaire vivant devient
## un monde vivant à part entière (origine Reliquaire). Renvoie true s'il a été pris en charge.
static func relic_wakes(state: GameState, pid: int, opener: int) -> bool:
	if state.living.is_empty():
		return false
	LivingWorlds.add_world(state, pid, "reliquaire", 3)
	(LivingWorlds.world(state, pid)["known"] as Dictionary)[str(opener)] = 1
	LivingWorlds.add_mood(state, pid, opener, 10)
	return true
